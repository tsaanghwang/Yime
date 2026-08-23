// Command yimebroker-stress-experiment runs the E5-E concurrent soak against
// both one shared Dispatcher and multiple live standalone Broker processes.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const (
	toolVersion              = "yimebroker-e5e-concurrent-soak-v1"
	requestTimeout           = 250 * time.Millisecond
	minimumDuration          = 30 * time.Second
	concurrentWarmupDuration = 5 * time.Second
	minimumRequests          = 100000
	maximumP95               = 10 * time.Millisecond
	maximumP99               = 20 * time.Millisecond
	maximumSingle            = 50 * time.Millisecond
	minimumThroughput        = 500.0
	maximumRecovery          = 2 * time.Second
	maximumProcessWorkingSet = 192 * 1024 * 1024
	maximumTotalGrowth       = 96 * 1024 * 1024
	latencyBucketWidth       = 10 * time.Microsecond
	latencyBucketCount       = int(requestTimeout/latencyBucketWidth) + 1
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
	Samples int   `json:"samples"`
	P50NS   int64 `json:"p50_ns"`
	P95NS   int64 `json:"p95_ns"`
	P99NS   int64 `json:"p99_ns"`
	MaxNS   int64 `json:"max_ns"`
}

type latencyHistogram struct {
	Buckets []uint64
	Samples uint64
	MaxNS   int64
}

type memorySample struct {
	AtNS            int64  `json:"at_ns"`
	WorkingSetBytes uint64 `json:"working_set_bytes"`
	PrivateBytes    uint64 `json:"private_bytes"`
	Processes       int    `json:"processes"`
}

type recovery struct {
	Injected             bool  `json:"injected"`
	ProcessTerminated    bool  `json:"process_terminated"`
	Restarted            bool  `json:"restarted"`
	ReplayPassed         bool  `json:"replay_passed"`
	OtherClientsProgress int64 `json:"other_clients_progress"`
	ElapsedNS            int64 `json:"elapsed_ns"`
	Passed               bool  `json:"passed"`
}

type report struct {
	ToolVersion               string       `json:"tool_version"`
	GeneratedAt               string       `json:"generated_at"`
	Mode                      string       `json:"mode"`
	IndexPath                 string       `json:"index_path"`
	IndexSourceID             string       `json:"index_source_id"`
	ProbePath                 string       `json:"probe_path"`
	ProbeCount                int          `json:"probe_count"`
	RequestedDurationSeconds  int          `json:"requested_duration_seconds"`
	ConcurrentWarmupNS        int64        `json:"concurrent_warmup_ns"`
	ActualDurationNS          int64        `json:"actual_duration_ns"`
	StandaloneBrokerProcesses int          `json:"standalone_broker_processes"`
	SharedDispatcherClients   int          `json:"shared_dispatcher_clients"`
	TotalTrustedClients       int          `json:"total_trusted_clients"`
	CompletedRequests         int64        `json:"completed_requests"`
	CompletedTraces           int64        `json:"completed_traces"`
	Errors                    int64        `json:"errors"`
	IncorrectCommits          int64        `json:"incorrect_commits"`
	ThroughputRequestsPerSec  float64      `json:"throughput_requests_per_second"`
	LatencyHistogramBucketNS  int64        `json:"latency_histogram_bucket_ns"`
	PercentileSemantics       string       `json:"percentile_semantics"`
	InProcessLatency          latency      `json:"in_process_latency"`
	PipeLatency               latency      `json:"pipe_latency"`
	BaselineMemory            memorySample `json:"baseline_memory"`
	FinalMemory               memorySample `json:"final_memory"`
	PeakMemory                memorySample `json:"peak_memory"`
	ForcedRecovery            recovery     `json:"forced_recovery"`
	ActiveSessionsAfterClose  int          `json:"active_sessions_after_close"`
	CleanShutdowns            bool         `json:"clean_shutdowns"`
	CorrectnessPassed         bool         `json:"correctness_passed"`
	LatencyGatePassed         bool         `json:"latency_gate_passed"`
	ThroughputGatePassed      bool         `json:"throughput_gate_passed"`
	MemoryGatePassed          bool         `json:"memory_gate_passed"`
	DurationGatePassed        bool         `json:"duration_gate_passed"`
	RecoveryGatePassed        bool         `json:"recovery_gate_passed"`
	Passed                    bool         `json:"passed"`
}

type requestClient interface {
	send(yimebroker.Request) (yimebroker.Response, time.Duration, error)
	close() bool
}

type sessionClient struct {
	transport requestClient
	sessionID string
	sequence  uint64
}

type workerResult struct {
	kind              string
	latencies         latencyHistogram
	completedRequests int64
	completedTraces   int64
	errors            int64
	incorrect         int64
	clean             bool
}

func main() {
	brokerPath := flag.String("broker", "", "E5-E YimeBroker executable")
	indexPath := flag.String("index", "", "validated YimeCore index")
	probesPath := flag.String("probes", "", "E2 sentence probe JSON")
	mode := flag.String("mode", "", "full, variable or shorthand")
	outputPath := flag.String("output", "", "evidence JSON")
	duration := flag.Duration("duration", 2*time.Minute, "concurrent measured soak duration")
	processes := flag.Int("processes", 4, "standalone Broker process count")
	clients := flag.Int("clients", 8, "trusted clients sharing one Dispatcher")
	flag.Parse()
	if *brokerPath == "" || *indexPath == "" || *probesPath == "" || *mode == "" || *outputPath == "" {
		fail(errors.New("broker, index, probes, mode and output are required"))
	}
	if *duration < minimumDuration || *processes < 2 || *clients < 2 || *processes+*clients > 64 {
		fail(fmt.Errorf("duration must be at least %s, process and shared-client counts at least 2, total at most 64", minimumDuration))
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
	dispatcher, err := yimebroker.NewDispatcher(func() (engineapi.Engine, error) {
		return yimecore.NewFileEngine(index, 9)
	}, yimebroker.Config{MaxSessions: *clients + 8, MaxSessionsPerClient: 1})
	if err != nil {
		fail(err)
	}

	allClients := make([]*sessionClient, 0, *clients+*processes)
	children := make([]*pipeClient, 0, *processes)
	var childrenMu sync.RWMutex
	for i := 0; i < *clients; i++ {
		transport := &dispatcherClient{dispatcher: dispatcher, client: yimebroker.TrustedClient{ID: fmt.Sprintf("e5e-shared-%02d", i)}}
		current, openErr := openSession(transport)
		if openErr != nil {
			fail(openErr)
		}
		allClients = append(allClients, current)
	}
	for i := 0; i < *processes; i++ {
		transport, startErr := startPipeClient(*brokerPath, *indexPath, *mode, fmt.Sprintf("e5e-process-%02d", i))
		if startErr != nil {
			fail(startErr)
		}
		current, openErr := openSession(transport)
		if openErr != nil {
			transport.terminate()
			fail(openErr)
		}
		children = append(children, transport)
		allClients = append(allClients, current)
	}

	warmupElapsed, err := concurrentWarmup(allClients, probes, concurrentWarmupDuration)
	if err != nil {
		fail(err)
	}
	time.Sleep(250 * time.Millisecond)
	started := time.Now()
	baseline := sampleMemory(started, children, &childrenMu)
	peak := baseline
	var totalCompleted atomic.Int64
	var recoveryOnce atomic.Bool
	var forcedRecovery recovery
	var recoveryMu sync.Mutex
	deadline := started.Add(*duration)
	injectionAt := started.Add(*duration / 3)
	stopSampler := make(chan struct{})
	samplerDone := make(chan struct{})
	go func() {
		defer close(samplerDone)
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				current := sampleMemory(started, children, &childrenMu)
				if current.WorkingSetBytes > peak.WorkingSetBytes {
					peak = current
				}
			case <-stopSampler:
				return
			}
		}
	}()

	results := make(chan workerResult, len(allClients))
	workloadDone := make(chan struct{}, len(allClients))
	allowClose := make(chan struct{})
	var wait sync.WaitGroup
	for i, current := range allClients {
		wait.Add(1)
		go func(workerIndex int, session *sessionClient) {
			defer wait.Done()
			kind := "dispatcher"
			if workerIndex >= *clients {
				kind = "pipe"
			}
			result := workerResult{kind: kind, latencies: newLatencyHistogram(), clean: true}
			probeIndex := workerIndex % len(probes)
			for time.Now().Before(deadline) {
				if workerIndex == *clients && time.Now().After(injectionAt) && recoveryOnce.CompareAndSwap(false, true) {
					before := totalCompleted.Load()
					recoveryStarted := time.Now()
					oldPipe := session.transport.(*pipeClient)
					terminated := oldPipe.terminate()
					newPipe, restartErr := startPipeClient(*brokerPath, *indexPath, *mode, oldPipe.clientID)
					restarted := restartErr == nil
					replay := false
					if restartErr == nil {
						newSession, openErr := openSession(newPipe)
						if openErr == nil {
							session.transport, session.sessionID, session.sequence = newSession.transport, newSession.sessionID, newSession.sequence
							_, replay, _ = session.runProbe(probes[probeIndex], nil)
						} else {
							newPipe.terminate()
						}
						childrenMu.Lock()
						children[0] = newPipe
						childrenMu.Unlock()
					}
					elapsed := time.Since(recoveryStarted)
					progress := totalCompleted.Load() - before
					recoveryMu.Lock()
					forcedRecovery = recovery{Injected: true, ProcessTerminated: terminated, Restarted: restarted, ReplayPassed: replay,
						OtherClientsProgress: progress, ElapsedNS: elapsed.Nanoseconds()}
					forcedRecovery.Passed = terminated && restarted && replay && progress > 0 && elapsed <= maximumRecovery
					recoveryMu.Unlock()
				}

				requests, ok, wasIncorrect := session.runProbe(probes[probeIndex], &result.latencies)
				result.completedRequests += int64(requests)
				totalCompleted.Add(int64(requests))
				if !ok {
					if wasIncorrect {
						result.incorrect++
					} else {
						result.errors++
					}
					break
				}
				result.completedTraces++
				probeIndex = (probeIndex + 1) % len(probes)
			}
			workloadDone <- struct{}{}
			<-allowClose
			result.clean = session.close()
			results <- result
		}(i, current)
	}
	for range allClients {
		<-workloadDone
	}
	actualDuration := time.Since(started)
	finalMemory := sampleMemory(started, children, &childrenMu)
	close(allowClose)
	wait.Wait()
	close(results)
	close(stopSampler)
	<-samplerDone
	if finalMemory.WorkingSetBytes > peak.WorkingSetBytes {
		peak = finalMemory
	}

	pipeHistogram := newLatencyHistogram()
	dispatcherHistogram := newLatencyHistogram()
	var completedRequests, completedTraces, errorCount, incorrect int64
	clean := true
	for item := range results {
		if item.kind == "pipe" {
			pipeHistogram.merge(item.latencies)
		} else {
			dispatcherHistogram.merge(item.latencies)
		}
		completedRequests += item.completedRequests
		completedTraces += item.completedTraces
		errorCount += item.errors
		incorrect += item.incorrect
		clean = clean && item.clean
	}
	recoveryMu.Lock()
	recoveryResult := forcedRecovery
	recoveryMu.Unlock()
	inProcessLatency := dispatcherHistogram.summary()
	pipeLatency := pipeHistogram.summary()
	throughput := float64(completedRequests) / actualDuration.Seconds()
	latencyPassed := latencyPassed(inProcessLatency) && latencyPassed(pipeLatency)
	correctnessPassed := errorCount == 0 && incorrect == 0 && completedRequests >= minimumRequests
	throughputPassed := throughput >= minimumThroughput
	durationPassed := actualDuration >= *duration
	workingGrowth := uint64(0)
	if finalMemory.WorkingSetBytes > baseline.WorkingSetBytes {
		workingGrowth = finalMemory.WorkingSetBytes - baseline.WorkingSetBytes
	}
	memoryPassed := peak.WorkingSetBytes <= uint64(*processes+1)*maximumProcessWorkingSet && workingGrowth <= maximumTotalGrowth
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), ProbePath: filepath.Clean(*probesPath), ProbeCount: len(probes),
		RequestedDurationSeconds: int(duration.Seconds()), ConcurrentWarmupNS: warmupElapsed.Nanoseconds(), ActualDurationNS: actualDuration.Nanoseconds(), StandaloneBrokerProcesses: *processes,
		SharedDispatcherClients: *clients, TotalTrustedClients: len(allClients), CompletedRequests: completedRequests, CompletedTraces: completedTraces,
		Errors: errorCount, IncorrectCommits: incorrect, ThroughputRequestsPerSec: throughput, LatencyHistogramBucketNS: latencyBucketWidth.Nanoseconds(),
		PercentileSemantics: "p50/p95/p99 are conservative upper bounds of fixed-width histogram buckets; max is the exact observed duration",
		InProcessLatency:    inProcessLatency, PipeLatency: pipeLatency,
		BaselineMemory: baseline, FinalMemory: finalMemory, PeakMemory: peak, ForcedRecovery: recoveryResult,
		ActiveSessionsAfterClose: dispatcher.ActiveSessions(), CleanShutdowns: clean, CorrectnessPassed: correctnessPassed,
		LatencyGatePassed: latencyPassed, ThroughputGatePassed: throughputPassed, MemoryGatePassed: memoryPassed,
		DurationGatePassed: durationPassed, RecoveryGatePassed: recoveryResult.Passed,
	}
	result.Passed = result.CorrectnessPassed && result.LatencyGatePassed && result.ThroughputGatePassed && result.MemoryGatePassed && result.DurationGatePassed &&
		result.RecoveryGatePassed && result.CleanShutdowns && result.ActiveSessionsAfterClose == 0
	writeJSON(*outputPath, result)
	fmt.Printf("YimeBroker E5-E: mode=%s passed=%t requests=%d rps=%.0f pipe_p99_ms=%.3f recovery_ms=%.1f\n", *mode, result.Passed,
		result.CompletedRequests, result.ThroughputRequestsPerSec, float64(result.PipeLatency.P99NS)/1e6, float64(result.ForcedRecovery.ElapsedNS)/1e6)
	if !result.Passed {
		os.Exit(1)
	}
}

func concurrentWarmup(clients []*sessionClient, probes []probe, duration time.Duration) (time.Duration, error) {
	started := time.Now()
	deadline := started.Add(duration)
	errorsFound := make(chan error, len(clients))
	var wait sync.WaitGroup
	for workerIndex, current := range clients {
		wait.Add(1)
		go func(index int, session *sessionClient) {
			defer wait.Done()
			probeIndex := index % len(probes)
			for time.Now().Before(deadline) {
				if _, ok, incorrect := session.runProbe(probes[probeIndex], nil); !ok {
					if incorrect {
						errorsFound <- fmt.Errorf("warm-up client %d produced an incorrect result for probe %d", index, probeIndex)
					} else {
						errorsFound <- fmt.Errorf("warm-up client %d failed transport for probe %d", index, probeIndex)
					}
					return
				}
				probeIndex = (probeIndex + 1) % len(probes)
			}
		}(workerIndex, current)
	}
	wait.Wait()
	close(errorsFound)
	for err := range errorsFound {
		return time.Since(started), err
	}
	return time.Since(started), nil
}

func (c *sessionClient) runProbe(item probe, latencies *latencyHistogram) (int, bool, bool) {
	completed := 0
	response, elapsed, err := c.request(yimebroker.ResetSession, engineapi.Event{}, "")
	if latencies != nil {
		latencies.add(elapsed)
	}
	if err != nil {
		return completed, false, false
	}
	if response.Result == nil {
		return completed, false, true
	}
	completed++
	var state engineapi.Result
	for _, key := range item.Code {
		response, elapsed, err = c.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}, "")
		if latencies != nil {
			latencies.add(elapsed)
		}
		if err != nil {
			return completed, false, false
		}
		if response.Result == nil {
			return completed, false, true
		}
		completed++
		state = *response.Result
	}
	candidateID := ""
	for page := 0; page < 100; page++ {
		for _, candidate := range state.State.Candidates {
			if candidate.Text == item.Text && candidate.Code == item.Code && candidate.Exact {
				candidateID = candidate.ID
				break
			}
		}
		if candidateID != "" || !state.State.HasNext {
			break
		}
		response, elapsed, err = c.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.PageNext}, "")
		if latencies != nil {
			latencies.add(elapsed)
		}
		if err != nil {
			return completed, false, false
		}
		if response.Result == nil {
			return completed, false, true
		}
		completed++
		state = *response.Result
	}
	if candidateID == "" {
		return completed, false, true
	}
	response, elapsed, err = c.request(yimebroker.Select, engineapi.Event{}, candidateID)
	if latencies != nil {
		latencies.add(elapsed)
	}
	if err != nil {
		return completed, false, false
	}
	if response.Result == nil || response.Result.Commit != item.Text {
		return completed, false, true
	}
	return completed + 1, true, false
}

func (c *sessionClient) request(operation yimebroker.Operation, event engineapi.Event, candidateID string) (yimebroker.Response, time.Duration, error) {
	c.sequence++
	return c.transport.send(yimebroker.Request{Version: yimebroker.ProtocolVersion, Sequence: c.sequence, SessionID: c.sessionID,
		Operation: operation, Event: event, CandidateID: candidateID})
}

func (c *sessionClient) close() bool {
	_, _, _ = c.request(yimebroker.CloseSession, engineapi.Event{}, "")
	return c.transport.close()
}

func openSession(transport requestClient) (*sessionClient, error) {
	response, _, err := transport.send(yimebroker.Request{Version: yimebroker.ProtocolVersion, Sequence: 1, Operation: yimebroker.OpenSession})
	if err != nil {
		return nil, err
	}
	if response.SessionID == "" || response.Error != nil {
		return nil, errors.New("Broker returned no session")
	}
	return &sessionClient{transport: transport, sessionID: response.SessionID, sequence: 1}, nil
}

type dispatcherClient struct {
	dispatcher *yimebroker.Dispatcher
	client     yimebroker.TrustedClient
}

func (c *dispatcherClient) send(request yimebroker.Request) (yimebroker.Response, time.Duration, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, 0, err
	}
	started := time.Now()
	encoded := c.dispatcher.HandleJSON(context.Background(), c.client, data)
	elapsed := time.Since(started)
	var response yimebroker.Response
	if err := json.Unmarshal(encoded, &response); err != nil {
		return response, elapsed, err
	}
	if response.Error != nil {
		return response, elapsed, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
	}
	return response, elapsed, nil
}

func (c *dispatcherClient) close() bool { return true }

type pipeClient struct {
	mu       sync.Mutex
	command  *exec.Cmd
	input    io.WriteCloser
	output   *bufio.Reader
	clientID string
	waited   bool
}

func startPipeClient(binary, index, mode, clientID string) (*pipeClient, error) {
	command := exec.Command(binary, "-index", index, "-mode", mode, "-trusted-client-id", clientID)
	configureProcess(command)
	input, err := command.StdinPipe()
	if err != nil {
		return nil, err
	}
	output, err := command.StdoutPipe()
	if err != nil {
		return nil, err
	}
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return nil, err
	}
	return &pipeClient{command: command, input: input, output: bufio.NewReader(output), clientID: clientID}, nil
}

func (c *pipeClient) send(request yimebroker.Request) (yimebroker.Response, time.Duration, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, 0, err
	}
	started := time.Now()
	if _, err := c.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, time.Since(started), err
	}
	type readResult struct {
		data []byte
		err  error
	}
	done := make(chan readResult, 1)
	go func() {
		line, readErr := c.output.ReadBytes('\n')
		done <- readResult{data: line, err: readErr}
	}()
	select {
	case result := <-done:
		elapsed := time.Since(started)
		if result.err != nil {
			return yimebroker.Response{}, elapsed, result.err
		}
		var response yimebroker.Response
		if err := json.Unmarshal(result.data, &response); err != nil {
			return response, elapsed, err
		}
		if response.Error != nil {
			return response, elapsed, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
		}
		return response, elapsed, nil
	case <-time.After(requestTimeout):
		_ = c.input.Close()
		_ = c.command.Process.Kill()
		_ = c.command.Wait()
		c.waited = true
		return yimebroker.Response{}, time.Since(started), fmt.Errorf("Broker response exceeded %s", requestTimeout)
	}
}

func (c *pipeClient) close() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.command == nil || c.waited {
		return true
	}
	_ = c.input.Close()
	err := c.command.Wait()
	c.waited = true
	return err == nil && c.command.ProcessState != nil && c.command.ProcessState.Exited()
}

func (c *pipeClient) terminate() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.command == nil || c.waited {
		return true
	}
	_ = c.input.Close()
	_ = c.command.Process.Kill()
	_ = c.command.Wait()
	c.waited = true
	return c.command.ProcessState != nil && c.command.ProcessState.Exited()
}

func (c *pipeClient) pid() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.command == nil || c.command.Process == nil || c.waited {
		return 0
	}
	return c.command.Process.Pid
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

func newLatencyHistogram() latencyHistogram {
	return latencyHistogram{Buckets: make([]uint64, latencyBucketCount)}
}

func (h *latencyHistogram) add(value time.Duration) {
	if h.Buckets == nil {
		h.Buckets = make([]uint64, latencyBucketCount)
	}
	index := int((value + latencyBucketWidth - 1) / latencyBucketWidth)
	if index >= len(h.Buckets) {
		index = len(h.Buckets) - 1
	}
	if index < 0 {
		index = 0
	}
	h.Buckets[index]++
	h.Samples++
	if value.Nanoseconds() > h.MaxNS {
		h.MaxNS = value.Nanoseconds()
	}
}

func (h *latencyHistogram) merge(other latencyHistogram) {
	if h.Buckets == nil {
		h.Buckets = make([]uint64, latencyBucketCount)
	}
	for index, count := range other.Buckets {
		if index >= len(h.Buckets) {
			break
		}
		h.Buckets[index] += count
	}
	h.Samples += other.Samples
	if other.MaxNS > h.MaxNS {
		h.MaxNS = other.MaxNS
	}
}

func (h latencyHistogram) summary() latency {
	return latency{Samples: int(h.Samples), P50NS: h.percentile(50), P95NS: h.percentile(95), P99NS: h.percentile(99), MaxNS: h.MaxNS}
}

func (h latencyHistogram) percentile(percent uint64) int64 {
	if h.Samples == 0 {
		return 0
	}
	target := (h.Samples*percent + 99) / 100
	var cumulative uint64
	for index, count := range h.Buckets {
		cumulative += count
		if cumulative >= target {
			return int64(time.Duration(index) * latencyBucketWidth)
		}
	}
	return h.MaxNS
}

func latencyPassed(value latency) bool {
	return value.Samples > 0 && time.Duration(value.P95NS) <= maximumP95 && time.Duration(value.P99NS) <= maximumP99 && time.Duration(value.MaxNS) <= maximumSingle
}

func sampleMemory(started time.Time, children []*pipeClient, childrenMu *sync.RWMutex) memorySample {
	result := memorySample{AtNS: time.Since(started).Nanoseconds()}
	current, err := processmemory.Current()
	if err == nil {
		result.WorkingSetBytes += current.WorkingSetBytes
		result.PrivateBytes += current.PrivateBytes
		result.Processes++
	}
	childrenMu.RLock()
	snapshot := append([]*pipeClient(nil), children...)
	childrenMu.RUnlock()
	for _, child := range snapshot {
		if child == nil {
			continue
		}
		pid := child.pid()
		if pid == 0 {
			continue
		}
		memory, memoryErr := processmemory.PID(pid)
		if memoryErr == nil {
			result.WorkingSetBytes += memory.WorkingSetBytes
			result.PrivateBytes += memory.PrivateBytes
			result.Processes++
		}
	}
	return result
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
