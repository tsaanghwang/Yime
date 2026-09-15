// Command yimebroker-experiment replays real YimeCore probe paths through the
// E5-A in-process protocol dispatcher and compares them with direct engine
// calls. It does not connect PIME, TSF, named pipes, or the installed runtime.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const (
	toolVersion                = "yimebroker-e5a-experiment-v1"
	latencyBatchSize           = 5
	maxP95WorkflowRatio        = 2.00
	maxP99WorkflowRatio        = 2.50
	maxP95MessageLatency       = 2 * time.Millisecond
	maxP99MessageLatency       = 5 * time.Millisecond
	maxSingleMessageLatency    = 50 * time.Millisecond
	maxIncrementalBytesMessage = 64 * 1024
)

type probe struct {
	Text string `json:"text"`
	Code string `json:"code"`
}

type probeFile struct {
	Version int                `json:"version"`
	Source  string             `json:"source"`
	Modes   map[string][]probe `json:"modes"`
}

type latency struct {
	Measurement string `json:"measurement"`
	BatchSize   int    `json:"batch_size"`
	Samples     int    `json:"samples"`
	P50NS       int64  `json:"p50_ns"`
	P95NS       int64  `json:"p95_ns"`
	P99NS       int64  `json:"p99_ns"`
	MaxNS       int64  `json:"max_ns"`
}

type allocation struct {
	Operations                   int    `json:"operations"`
	TotalBytes                   uint64 `json:"total_bytes"`
	BytesPerOperation            uint64 `json:"bytes_per_operation"`
	IncrementalBytesPerOperation uint64 `json:"incremental_bytes_per_operation,omitempty"`
}

type robustness struct {
	SessionIsolationPassed bool `json:"session_isolation_passed"`
	ReplayRejected         bool `json:"replay_rejected"`
	QuotaEnforced          bool `json:"quota_enforced"`
	TimeoutEvicted         bool `json:"timeout_evicted"`
	PanicEvicted           bool `json:"panic_evicted"`
	AllPassed              bool `json:"all_passed"`
}

type report struct {
	ToolVersion            string                 `json:"tool_version"`
	GeneratedAt            string                 `json:"generated_at"`
	Mode                   string                 `json:"mode"`
	IndexPath              string                 `json:"index_path"`
	IndexSourceID          string                 `json:"index_source_id"`
	ProbePath              string                 `json:"probe_path"`
	ProbeCount             int                    `json:"probe_count"`
	Iterations             int                    `json:"iterations"`
	DirectLatency          latency                `json:"direct_latency"`
	BrokerLatency          latency                `json:"broker_latency"`
	BrokerMessageLatency   latency                `json:"broker_message_latency"`
	P95WorkflowRatio       float64                `json:"p95_workflow_ratio"`
	P99WorkflowRatio       float64                `json:"p99_workflow_ratio"`
	DirectAllocation       allocation             `json:"direct_allocation"`
	BrokerAllocation       allocation             `json:"broker_allocation"`
	ProcessMemory          processmemory.Snapshot `json:"process_memory"`
	Robustness             robustness             `json:"robustness"`
	CorrectnessPassed      bool                   `json:"correctness_passed"`
	LatencyGatePassed      bool                   `json:"latency_gate_passed"`
	AllocationGatePassed   bool                   `json:"allocation_gate_passed"`
	SessionCleanupPassed   bool                   `json:"session_cleanup_passed"`
	Passed                 bool                   `json:"passed"`
	ComparisonScope        string                 `json:"comparison_scope"`
	ProcessIsolationCaveat string                 `json:"process_isolation_caveat"`
}

func main() {
	indexPath := flag.String("index", "", "compact .yidx file")
	probesPath := flag.String("probes", "", "E1 whole-word probe JSON")
	mode := flag.String("mode", "", "full, variable or shorthand")
	outputPath := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 100, "full probe-set iterations")
	flag.Parse()
	if *indexPath == "" || *probesPath == "" || *mode == "" || *outputPath == "" || *iterations < 10 {
		fail(errors.New("index, probes, mode, output and at least 10 iterations are required"))
	}

	probes := loadProbes(*probesPath, *mode)
	if len(probes) == 0 {
		fail(fmt.Errorf("no probes for mode %q", *mode))
	}
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %q does not match %q", index.Mode(), *mode))
	}
	factory := func() (engineapi.Engine, error) { return yimecore.NewFileEngine(index, 9) }
	direct, err := factory()
	if err != nil {
		fail(err)
	}
	dispatcher, err := yimebroker.NewDispatcher(factory, yimebroker.Config{})
	if err != nil {
		fail(err)
	}
	client := newWireClient(dispatcher, "e5a-measured-client")
	if err := client.open(); err != nil {
		fail(err)
	}

	directTrace, directOK := traceDirectSet(direct, probes)
	brokerTrace, brokerOK := traceBrokerSet(client, probes)
	correct := directOK && brokerOK && reflect.DeepEqual(directTrace, brokerTrace)
	for warmup := 0; warmup < 5; warmup++ {
		correct = runDirectSet(direct, probes) && correct
		correct = runBrokerSet(client, probes) && correct
	}
	directDurations := make([]time.Duration, 0, (*iterations+latencyBatchSize-1)/latencyBatchSize)
	brokerDurations := make([]time.Duration, 0, cap(directDurations))
	client.messageDurations = nil
	for batchStart := 0; batchStart < *iterations; batchStart += latencyBatchSize {
		count := latencyBatchSize
		if remaining := *iterations - batchStart; remaining < count {
			count = remaining
		}
		directStarted := time.Now()
		for i := 0; i < count; i++ {
			correct = runDirectSet(direct, probes) && correct
		}
		directDurations = append(directDurations, time.Since(directStarted)/time.Duration(count))

		brokerStarted := time.Now()
		for i := 0; i < count; i++ {
			correct = runBrokerSet(client, probes) && correct
		}
		brokerDurations = append(brokerDurations, time.Since(brokerStarted)/time.Duration(count))
	}
	directLatency := summarize(directDurations, "direct complete probe set")
	brokerLatency := summarize(brokerDurations, "JSON dispatcher complete probe set")
	messageLatency := summarize(client.messageDurations, "one strict JSON dispatcher request and response")
	messageLatency.BatchSize = 1
	p95Ratio := ratio(brokerLatency.P95NS, directLatency.P95NS)
	p99Ratio := ratio(brokerLatency.P99NS, directLatency.P99NS)

	allocationIterations := 10
	directAllocation := measureAllocation(func() int {
		operations := 0
		for i := 0; i < allocationIterations; i++ {
			correct = runDirectSet(direct, probes) && correct
			operations += directOperationCount(probes)
		}
		return operations
	})
	brokerAllocation := measureAllocation(func() int {
		operations := 0
		for i := 0; i < allocationIterations; i++ {
			correct = runBrokerSet(client, probes) && correct
			operations += directOperationCount(probes)
		}
		return operations
	})
	if brokerAllocation.BytesPerOperation > directAllocation.BytesPerOperation {
		brokerAllocation.IncrementalBytesPerOperation = brokerAllocation.BytesPerOperation - directAllocation.BytesPerOperation
	}
	if err := client.close(); err != nil {
		fail(err)
	}
	robustnessResult := exerciseRobustness()
	memory, err := processmemory.Current()
	if err != nil {
		fail(err)
	}
	latencyPassed := p95Ratio <= maxP95WorkflowRatio && p99Ratio <= maxP99WorkflowRatio &&
		time.Duration(messageLatency.P95NS) <= maxP95MessageLatency &&
		time.Duration(messageLatency.P99NS) <= maxP99MessageLatency &&
		time.Duration(messageLatency.MaxNS) <= maxSingleMessageLatency
	allocationPassed := brokerAllocation.IncrementalBytesPerOperation <= maxIncrementalBytesMessage
	cleanupPassed := dispatcher.ActiveSessions() == 0
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), ProbePath: filepath.Clean(*probesPath),
		ProbeCount: len(probes), Iterations: *iterations, DirectLatency: directLatency, BrokerLatency: brokerLatency,
		BrokerMessageLatency: messageLatency, P95WorkflowRatio: p95Ratio, P99WorkflowRatio: p99Ratio,
		DirectAllocation: directAllocation, BrokerAllocation: brokerAllocation, ProcessMemory: memory,
		Robustness: robustnessResult, CorrectnessPassed: correct, LatencyGatePassed: latencyPassed,
		AllocationGatePassed: allocationPassed, SessionCleanupPassed: cleanupPassed,
		ComparisonScope:        "same full YimeCore index and whole-word probe paths; direct calls versus in-process strict JSON protocol",
		ProcessIsolationCaveat: "an in-process timeout evicts the logical session but cannot terminate a blocked Go call; hard kill and restart require the later Broker process experiment",
	}
	result.Passed = result.CorrectnessPassed && result.LatencyGatePassed && result.AllocationGatePassed && result.SessionCleanupPassed && result.Robustness.AllPassed
	writeJSON(*outputPath, result)
	fmt.Printf("YimeBroker E5-A: mode=%s passed=%t p95_ratio=%.3f p99_ratio=%.3f message_p99_ns=%d\n", *mode, result.Passed, p95Ratio, p99Ratio, messageLatency.P99NS)
	if !result.Passed {
		os.Exit(1)
	}
}

type wireClient struct {
	dispatcher       *yimebroker.Dispatcher
	trusted          yimebroker.TrustedClient
	sessionID        string
	sequence         uint64
	messageDurations []time.Duration
}

func newWireClient(dispatcher *yimebroker.Dispatcher, id string) *wireClient {
	return &wireClient{dispatcher: dispatcher, trusted: yimebroker.TrustedClient{ID: id}}
}

func (c *wireClient) open() error {
	c.sequence = 1
	response, err := c.send(yimebroker.Request{Version: 1, Sequence: c.sequence, Operation: yimebroker.OpenSession})
	if err != nil {
		return err
	}
	c.sessionID = response.SessionID
	return nil
}

func (c *wireClient) request(operation yimebroker.Operation, event engineapi.Event, candidateID string) (engineapi.Result, error) {
	c.sequence++
	response, err := c.send(yimebroker.Request{
		Version: 1, Sequence: c.sequence, SessionID: c.sessionID,
		Operation: operation, Event: event, CandidateID: candidateID,
	})
	if err != nil {
		return engineapi.Result{}, err
	}
	if response.Result == nil {
		return engineapi.Result{}, errors.New("missing engine result")
	}
	return *response.Result, nil
}

func (c *wireClient) close() error {
	_, err := c.request(yimebroker.CloseSession, engineapi.Event{}, "")
	return err
}

func (c *wireClient) send(request yimebroker.Request) (yimebroker.Response, error) {
	encoded, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	started := time.Now()
	responseBytes := c.dispatcher.HandleJSON(context.Background(), c.trusted, encoded)
	c.messageDurations = append(c.messageDurations, time.Since(started))
	var response yimebroker.Response
	if err := json.Unmarshal(responseBytes, &response); err != nil {
		return response, err
	}
	if response.Error != nil {
		return response, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
	}
	return response, nil
}

func runDirectSet(engine engineapi.Engine, probes []probe) bool {
	_, passed := traceDirectSet(engine, probes)
	return passed
}

type traceOutcome struct {
	State  engineapi.State
	Commit string
}

func traceDirectSet(engine engineapi.Engine, probes []probe) ([]traceOutcome, bool) {
	passed := true
	trace := make([]traceOutcome, 0, len(probes))
	for _, item := range probes {
		engine.Reset()
		var result engineapi.Result
		for _, key := range item.Code {
			var err error
			result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
			if err != nil {
				return trace, false
			}
		}
		candidate := measuredCandidate(result, item)
		if candidate == nil {
			passed = false
			continue
		}
		selected, err := engine.Select(candidate.ID)
		passed = err == nil && passed
		if err == nil {
			passed = selected.Commit == candidate.Text && passed
			trace = append(trace, traceOutcome{State: result.State, Commit: selected.Commit})
		}
	}
	return trace, passed
}

func runBrokerSet(client *wireClient, probes []probe) bool {
	_, passed := traceBrokerSet(client, probes)
	return passed
}

func traceBrokerSet(client *wireClient, probes []probe) ([]traceOutcome, bool) {
	passed := true
	trace := make([]traceOutcome, 0, len(probes))
	for _, item := range probes {
		if _, err := client.request(yimebroker.ResetSession, engineapi.Event{}, ""); err != nil {
			return trace, false
		}
		var result engineapi.Result
		for _, key := range item.Code {
			var err error
			result, err = client.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}, "")
			if err != nil {
				return trace, false
			}
		}
		candidate := measuredCandidate(result, item)
		if candidate == nil {
			passed = false
			continue
		}
		selected, err := client.request(yimebroker.Select, engineapi.Event{}, candidate.ID)
		passed = err == nil && selected.Commit == candidate.Text && passed
		if err == nil {
			trace = append(trace, traceOutcome{State: result.State, Commit: selected.Commit})
		}
	}
	return trace, passed
}

func measuredCandidate(result engineapi.Result, item probe) *engineapi.Candidate {
	for i := range result.State.Candidates {
		candidate := &result.State.Candidates[i]
		if candidate.Text == item.Text && candidate.Code == item.Code && candidate.Exact {
			return candidate
		}
	}
	if len(result.State.Candidates) > 0 {
		return &result.State.Candidates[0]
	}
	return nil
}

func directOperationCount(probes []probe) int {
	count := 0
	for _, item := range probes {
		count += len(item.Code) + 2 // reset, per-byte apply, select
	}
	return count
}

func measureAllocation(run func() int) allocation {
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	operations := run()
	runtime.ReadMemStats(&after)
	total := after.TotalAlloc - before.TotalAlloc
	perOperation := uint64(0)
	if operations > 0 {
		perOperation = total / uint64(operations)
	}
	return allocation{Operations: operations, TotalBytes: total, BytesPerOperation: perOperation}
}

func exerciseRobustness() robustness {
	index, err := yimecore.NewIndex([]yimecore.Entry{{Text: "一", Code: "1", Weight: 1}})
	if err != nil {
		fail(err)
	}
	factory := func() (engineapi.Engine, error) { return yimecore.NewEngine(index, 9) }
	dispatcher, err := yimebroker.NewDispatcher(factory, yimebroker.Config{MaxSessions: 2, MaxSessionsPerClient: 1, OperationTimeout: 20 * time.Millisecond})
	if err != nil {
		fail(err)
	}
	a := newWireClient(dispatcher, "robust-a")
	b := newWireClient(dispatcher, "robust-b")
	isolation := a.open() == nil && b.open() == nil
	if isolation {
		_, errA := a.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: "1"}, "")
		_, errB := b.request(yimebroker.ResetSession, engineapi.Event{}, "")
		isolation = errA == nil && errB == nil
	}
	replayRequest := yimebroker.Request{Version: 1, Sequence: a.sequence, SessionID: a.sessionID, Operation: yimebroker.ResetSession}
	replayResponse := dispatcher.Dispatch(context.Background(), a.trusted, replayRequest)
	replay := replayResponse.Error != nil && replayResponse.Error.Code == yimebroker.CodeSequence
	quotaClient := newWireClient(dispatcher, "robust-c")
	quota := quotaClient.open() != nil
	_ = a.close()
	_ = b.close()

	timeout := faultIsolation("block", yimebroker.CodeTimeout)
	panicPassed := faultIsolation("panic", yimebroker.CodeEnginePanic)
	result := robustness{
		SessionIsolationPassed: isolation, ReplayRejected: replay, QuotaEnforced: quota,
		TimeoutEvicted: timeout, PanicEvicted: panicPassed,
	}
	result.AllPassed = result.SessionIsolationPassed && result.ReplayRejected && result.QuotaEnforced && result.TimeoutEvicted && result.PanicEvicted
	return result
}

func faultIsolation(mode string, want yimebroker.ErrorCode) bool {
	engine := &faultEngine{mode: mode, release: make(chan struct{})}
	dispatcher, err := yimebroker.NewDispatcher(func() (engineapi.Engine, error) { return engine, nil }, yimebroker.Config{OperationTimeout: 5 * time.Millisecond})
	if err != nil {
		return false
	}
	client := newWireClient(dispatcher, "fault")
	if client.open() != nil {
		return false
	}
	client.sequence++
	request := yimebroker.Request{Version: 1, Sequence: client.sequence, SessionID: client.sessionID, Operation: yimebroker.ResetSession}
	response := dispatcher.Dispatch(context.Background(), client.trusted, request)
	close(engine.release)
	return response.Error != nil && response.Error.Code == want && dispatcher.ActiveSessions() == 0
}

type faultEngine struct {
	mode    string
	release chan struct{}
}

func (e *faultEngine) Apply(engineapi.Event) (engineapi.Result, error) { return e.Reset(), nil }
func (e *faultEngine) Select(string) (engineapi.Result, error)         { return e.Reset(), nil }
func (e *faultEngine) Reset() engineapi.Result {
	if e.mode == "block" {
		<-e.release
	}
	if e.mode == "panic" {
		panic("forced experiment panic")
	}
	return engineapi.Result{}
}

func loadProbes(path, mode string) []probe {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err)
	}
	var file probeFile
	if err := json.Unmarshal(data, &file); err != nil {
		fail(err)
	}
	if file.Version != 1 || file.Source == "" {
		fail(errors.New("unsupported or unproven probe file"))
	}
	return file.Modes[mode]
}

func summarize(values []time.Duration, measurement string) latency {
	if len(values) == 0 {
		return latency{Measurement: measurement}
	}
	sorted := append([]time.Duration(nil), values...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	return latency{
		Measurement: measurement, BatchSize: latencyBatchSize, Samples: len(sorted),
		P50NS: percentile(sorted, 50).Nanoseconds(), P95NS: percentile(sorted, 95).Nanoseconds(),
		P99NS: percentile(sorted, 99).Nanoseconds(), MaxNS: sorted[len(sorted)-1].Nanoseconds(),
	}
}

func percentile(values []time.Duration, percent int) time.Duration {
	index := (len(values)*percent + 99) / 100
	if index < 1 {
		index = 1
	}
	if index > len(values) {
		index = len(values)
	}
	return values[index-1]
}

func ratio(numerator, denominator int64) float64 {
	if denominator <= 0 {
		return 0
	}
	return float64(numerator) / float64(denominator)
}

func writeJSON(path string, value any) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fail(err)
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
