// Command yimebroker-process-experiment measures the E5-B standalone broker
// over anonymous pipes and verifies restart/replay after exit and hang faults.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const (
	toolVersion          = "yimebroker-e5b-process-experiment-v1"
	batchSize            = 5
	requestTimeout       = 100 * time.Millisecond
	maxWorkflowP95Ratio  = 4.0
	maxMessageP95        = 10 * time.Millisecond
	maxMessageP99        = 20 * time.Millisecond
	maxMessage           = 50 * time.Millisecond
	maxBrokerWorkingSet  = 128 * 1024 * 1024
	maxFaultRecoveryTime = 2 * time.Second
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

type recovery struct {
	Fault             string `json:"fault"`
	Detected          bool   `json:"detected"`
	ProcessTerminated bool   `json:"process_terminated"`
	Restarted         bool   `json:"restarted"`
	ReplayPassed      bool   `json:"replay_passed"`
	ElapsedNS         int64  `json:"elapsed_ns"`
	Passed            bool   `json:"passed"`
}

type report struct {
	ToolVersion         string                 `json:"tool_version"`
	GeneratedAt         string                 `json:"generated_at"`
	Mode                string                 `json:"mode"`
	IndexPath           string                 `json:"index_path"`
	IndexSourceID       string                 `json:"index_source_id"`
	BrokerPath          string                 `json:"broker_path"`
	ProbePath           string                 `json:"probe_path"`
	ProbeCount          int                    `json:"probe_count"`
	Iterations          int                    `json:"iterations"`
	StartupLatencyNS    int64                  `json:"startup_latency_ns"`
	DirectLatency       latency                `json:"direct_latency"`
	ProcessLatency      latency                `json:"process_latency"`
	MessageLatency      latency                `json:"message_latency"`
	WorkflowP95Ratio    float64                `json:"workflow_p95_ratio"`
	BrokerProcessMemory processmemory.Snapshot `json:"broker_process_memory"`
	CrashRecovery       recovery               `json:"crash_recovery"`
	HangRecovery        recovery               `json:"hang_recovery"`
	CorrectnessPassed   bool                   `json:"correctness_passed"`
	LatencyGatePassed   bool                   `json:"latency_gate_passed"`
	MemoryGatePassed    bool                   `json:"memory_gate_passed"`
	CleanShutdownPassed bool                   `json:"clean_shutdown_passed"`
	Passed              bool                   `json:"passed"`
	ComparisonScope     string                 `json:"comparison_scope"`
}

func main() {
	brokerPath := flag.String("broker", "", "E5-B yimebroker executable")
	indexPath := flag.String("index", "", "validated YimeCore index")
	probesPath := flag.String("probes", "", "E2 sentence probe JSON")
	mode := flag.String("mode", "", "full, variable or shorthand")
	outputPath := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 50, "full probe-set iterations")
	flag.Parse()
	if *brokerPath == "" || *indexPath == "" || *probesPath == "" || *mode == "" || *outputPath == "" || *iterations < 10 {
		fail(errors.New("broker, index, probes, mode, output and at least 10 iterations are required"))
	}
	probes := loadProbes(*probesPath, *mode)
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %q does not match %q", index.Mode(), *mode))
	}
	direct, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		fail(err)
	}
	process, startup, err := startBroker(*brokerPath, *indexPath, *mode, 0, 0)
	if err != nil {
		fail(err)
	}
	directTrace, directOK := traceDirect(direct, probes)
	processTrace, processOK := process.trace(probes)
	correct := directOK && processOK && reflect.DeepEqual(directTrace, processTrace)
	for i := 0; i < 5; i++ {
		correct = runDirect(direct, probes) && correct
		correct = process.run(probes) && correct
	}
	process.messageDurations = nil
	directTimes := make([]time.Duration, 0, (*iterations+batchSize-1)/batchSize)
	processTimes := make([]time.Duration, 0, cap(directTimes))
	for start := 0; start < *iterations; start += batchSize {
		count := batchSize
		if remaining := *iterations - start; remaining < count {
			count = remaining
		}
		began := time.Now()
		for i := 0; i < count; i++ {
			correct = runDirect(direct, probes) && correct
		}
		directTimes = append(directTimes, time.Since(began)/time.Duration(count))
		began = time.Now()
		for i := 0; i < count; i++ {
			correct = process.run(probes) && correct
		}
		processTimes = append(processTimes, time.Since(began)/time.Duration(count))
	}
	directLatency := summarize(directTimes, "direct complete probe set", batchSize)
	processLatency := summarize(processTimes, "standalone Broker complete probe set", batchSize)
	messageLatency := summarize(process.messageDurations, "one pipe request and response", 1)
	memory, err := processmemory.PID(process.pid())
	if err != nil {
		fail(err)
	}
	cleanShutdown := process.close()
	crash := exerciseRecovery(*brokerPath, *indexPath, *mode, probes[0], "exit")
	hang := exerciseRecovery(*brokerPath, *indexPath, *mode, probes[0], "hang")
	ratio := ratio(processLatency.P95NS, directLatency.P95NS)
	latencyPassed := ratio <= maxWorkflowP95Ratio && time.Duration(messageLatency.P95NS) <= maxMessageP95 &&
		time.Duration(messageLatency.P99NS) <= maxMessageP99 && time.Duration(messageLatency.MaxNS) <= maxMessage
	memoryPassed := memory.WorkingSetBytes <= maxBrokerWorkingSet
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), BrokerPath: filepath.Clean(*brokerPath),
		ProbePath: filepath.Clean(*probesPath), ProbeCount: len(probes), Iterations: *iterations, StartupLatencyNS: startup.Nanoseconds(),
		DirectLatency: directLatency, ProcessLatency: processLatency, MessageLatency: messageLatency, WorkflowP95Ratio: ratio,
		BrokerProcessMemory: memory, CrashRecovery: crash, HangRecovery: hang, CorrectnessPassed: correct,
		LatencyGatePassed: latencyPassed, MemoryGatePassed: memoryPassed, CleanShutdownPassed: cleanShutdown,
		ComparisonScope: "same full YimeCore index and E2 sentence paths; direct calls versus standalone process over anonymous pipes",
	}
	result.Passed = result.CorrectnessPassed && result.LatencyGatePassed && result.MemoryGatePassed && result.CleanShutdownPassed && result.CrashRecovery.Passed && result.HangRecovery.Passed
	writeJSON(*outputPath, result)
	fmt.Printf("YimeBroker E5-B: mode=%s passed=%t p95_ratio=%.3f message_p99_ns=%d crash_ms=%.1f hang_ms=%.1f\n", *mode, result.Passed, ratio, messageLatency.P99NS, float64(crash.ElapsedNS)/1e6, float64(hang.ElapsedNS)/1e6)
	if !result.Passed {
		os.Exit(1)
	}
}

type brokerProcess struct {
	command          *exec.Cmd
	input            io.WriteCloser
	output           *bufio.Reader
	sequence         uint64
	sessionID        string
	messageDurations []time.Duration
	waitOnce         sync.Once
	waitErr          error
}

func startBroker(binary, index, mode string, exitBefore, hangBefore int) (*brokerProcess, time.Duration, error) {
	args := []string{"-index", index, "-mode", mode, "-trusted-client-id", "e5b-supervisor"}
	if exitBefore > 0 {
		args = append(args, "-experiment-exit-before-request", fmt.Sprint(exitBefore))
	}
	if hangBefore > 0 {
		args = append(args, "-experiment-hang-before-request", fmt.Sprint(hangBefore))
	}
	command := exec.Command(binary, args...)
	configureProcess(command)
	input, err := command.StdinPipe()
	if err != nil {
		return nil, 0, err
	}
	output, err := command.StdoutPipe()
	if err != nil {
		return nil, 0, err
	}
	command.Stderr = os.Stderr
	started := time.Now()
	if err := command.Start(); err != nil {
		return nil, 0, err
	}
	process := &brokerProcess{command: command, input: input, output: bufio.NewReader(output)}
	process.sequence = 1
	response, err := process.send(yimebroker.Request{Version: 1, Sequence: 1, Operation: yimebroker.OpenSession}, requestTimeout)
	if err != nil {
		process.terminate()
		return nil, 0, err
	}
	process.sessionID = response.SessionID
	return process, time.Since(started), nil
}

func (p *brokerProcess) pid() int { return p.command.Process.Pid }

func (p *brokerProcess) request(operation yimebroker.Operation, event engineapi.Event, candidateID string) (engineapi.Result, error) {
	p.sequence++
	response, err := p.send(yimebroker.Request{Version: 1, Sequence: p.sequence, SessionID: p.sessionID, Operation: operation, Event: event, CandidateID: candidateID}, requestTimeout)
	if err != nil {
		return engineapi.Result{}, err
	}
	if response.Result == nil {
		return engineapi.Result{}, errors.New("missing result")
	}
	return *response.Result, nil
}

func (p *brokerProcess) send(request yimebroker.Request, timeout time.Duration) (yimebroker.Response, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	started := time.Now()
	if _, err := p.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	type readResult struct {
		data []byte
		err  error
	}
	completed := make(chan readResult, 1)
	go func() {
		line, err := p.output.ReadBytes('\n')
		completed <- readResult{data: line, err: err}
	}()
	select {
	case result := <-completed:
		p.messageDurations = append(p.messageDurations, time.Since(started))
		if result.err != nil {
			return yimebroker.Response{}, result.err
		}
		var response yimebroker.Response
		if err := json.Unmarshal(result.data, &response); err != nil {
			return response, err
		}
		if response.Error != nil {
			return response, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
		}
		return response, nil
	case <-time.After(timeout):
		p.messageDurations = append(p.messageDurations, time.Since(started))
		p.terminate()
		return yimebroker.Response{}, fmt.Errorf("broker response timeout after %s", timeout)
	}
}

func (p *brokerProcess) trace(probes []probe) ([]traceOutcome, bool) {
	trace := make([]traceOutcome, 0, len(probes))
	for _, item := range probes {
		if _, err := p.request(yimebroker.ResetSession, engineapi.Event{}, ""); err != nil {
			return trace, false
		}
		var result engineapi.Result
		for _, key := range item.Code {
			var err error
			result, err = p.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}, "")
			if err != nil {
				return trace, false
			}
		}
		candidate := measuredCandidate(result, item)
		if candidate == nil {
			return trace, false
		}
		selected, err := p.request(yimebroker.Select, engineapi.Event{}, candidate.ID)
		if err != nil || selected.Commit != candidate.Text {
			return trace, false
		}
		trace = append(trace, traceOutcome{State: result.State, Commit: selected.Commit})
	}
	return trace, true
}

func (p *brokerProcess) run(probes []probe) bool {
	_, ok := p.trace(probes)
	return ok
}

func (p *brokerProcess) wait() error {
	p.waitOnce.Do(func() { p.waitErr = p.command.Wait() })
	return p.waitErr
}

func (p *brokerProcess) terminate() bool {
	_ = p.input.Close()
	_ = p.command.Process.Kill()
	_ = p.wait()
	return p.command.ProcessState != nil && p.command.ProcessState.Exited()
}

func (p *brokerProcess) close() bool {
	_, _ = p.request(yimebroker.CloseSession, engineapi.Event{}, "")
	_ = p.input.Close()
	_ = p.wait()
	return p.command.ProcessState != nil && p.command.ProcessState.Exited()
}

type traceOutcome struct {
	State  engineapi.State
	Commit string
}

func traceDirect(engine engineapi.Engine, probes []probe) ([]traceOutcome, bool) {
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
			return trace, false
		}
		selected, err := engine.Select(candidate.ID)
		if err != nil || selected.Commit != candidate.Text {
			return trace, false
		}
		trace = append(trace, traceOutcome{State: result.State, Commit: selected.Commit})
	}
	return trace, true
}

func runDirect(engine engineapi.Engine, probes []probe) bool {
	_, ok := traceDirect(engine, probes)
	return ok
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

func exerciseRecovery(binary, index, mode string, item probe, fault string) recovery {
	result := recovery{Fault: fault}
	exitBefore, hangBefore := 0, 0
	if fault == "exit" {
		exitBefore = 3
	} else {
		hangBefore = 3
	}
	process, _, err := startBroker(binary, index, mode, exitBefore, hangBefore)
	if err != nil {
		return result
	}
	started := time.Now()
	_, firstErr := process.request(yimebroker.ResetSession, engineapi.Event{}, "")
	_, faultErr := process.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(item.Code[0])}, "")
	result.Detected = firstErr == nil && faultErr != nil
	result.ProcessTerminated = process.terminate()
	restarted, _, restartErr := startBroker(binary, index, mode, 0, 0)
	result.Restarted = restartErr == nil
	if restartErr == nil {
		result.ReplayPassed = restarted.run([]probe{item})
		result.ProcessTerminated = restarted.close() && result.ProcessTerminated
	}
	result.ElapsedNS = time.Since(started).Nanoseconds()
	result.Passed = result.Detected && result.ProcessTerminated && result.Restarted && result.ReplayPassed && time.Duration(result.ElapsedNS) <= maxFaultRecoveryTime
	return result
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
	if file.Version != 1 || file.Source == "" || len(file.Modes[mode]) == 0 {
		fail(errors.New("unsupported or empty probe file"))
	}
	return file.Modes[mode]
}

func summarize(values []time.Duration, measurement string, batch int) latency {
	sorted := append([]time.Duration(nil), values...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	return latency{Measurement: measurement, BatchSize: batch, Samples: len(sorted), P50NS: percentile(sorted, 50).Nanoseconds(),
		P95NS: percentile(sorted, 95).Nanoseconds(), P99NS: percentile(sorted, 99).Nanoseconds(), MaxNS: sorted[len(sorted)-1].Nanoseconds()}
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
