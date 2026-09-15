// Command yimebroker-user-model-experiment verifies E5-C durable learning
// across a real standalone Broker process crash and torn journal tail.
package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	toolVersion          = "yimebroker-e5c-user-model-experiment-v1"
	requestTimeout       = 100 * time.Millisecond
	maxSelectP99         = 20 * time.Millisecond
	maxSelect            = 50 * time.Millisecond
	maxCrashRecoveryTime = 2 * time.Second
)

type latency struct {
	Samples int   `json:"samples"`
	P50NS   int64 `json:"p50_ns"`
	P95NS   int64 `json:"p95_ns"`
	P99NS   int64 `json:"p99_ns"`
	MaxNS   int64 `json:"max_ns"`
}

type report struct {
	ToolVersion            string                           `json:"tool_version"`
	GeneratedAt            string                           `json:"generated_at"`
	Mode                   string                           `json:"mode"`
	IndexPath              string                           `json:"index_path"`
	IndexSourceID          string                           `json:"index_source_id"`
	LearningCode           string                           `json:"learning_code"`
	SelectedText           string                           `json:"selected_text"`
	Selections             int                              `json:"selections"`
	DurableSelectLatency   latency                          `json:"durable_select_latency"`
	SnapshotAbsentAtCrash  bool                             `json:"snapshot_absent_at_crash"`
	CrashDetected          bool                             `json:"crash_detected"`
	CrashRecoveryNS        int64                            `json:"crash_recovery_ns"`
	TornTailBytes          int64                            `json:"torn_tail_bytes"`
	TornTailTruncated      bool                             `json:"torn_tail_truncated"`
	RecoveredGeneration    uint64                           `json:"recovered_generation"`
	RecoveredRankingPassed bool                             `json:"recovered_ranking_passed"`
	SnapshotSHA256         string                           `json:"snapshot_sha256"`
	JournalSHA256          string                           `json:"journal_sha256"`
	FinalStats             yimebroker.DurableUserModelStats `json:"final_stats"`
	CorruptionRejected     bool                             `json:"corruption_rejected"`
	LatencyGatePassed      bool                             `json:"latency_gate_passed"`
	RecoveryGatePassed     bool                             `json:"recovery_gate_passed"`
	Passed                 bool                             `json:"passed"`
	DurabilitySemantics    string                           `json:"durability_semantics"`
}

func main() {
	brokerPath := flag.String("broker", "", "E5-C YimeBroker executable")
	indexPath := flag.String("index", "", "validated YimeCore index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	snapshotPath := flag.String("snapshot", "", "user model snapshot path")
	journalPath := flag.String("journal", "", "user model journal path")
	outputPath := flag.String("output", "", "evidence JSON")
	selections := flag.Int("selections", 20, "durable selection acknowledgements before crash")
	flag.Parse()
	if *brokerPath == "" || *indexPath == "" || *mode == "" || *snapshotPath == "" || *journalPath == "" || *outputPath == "" || *selections < 10 {
		fail(errors.New("broker, index, mode, snapshot, journal, output and at least 10 selections are required"))
	}
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	code := "bj"
	if *mode == "full" {
		code = "bjjj"
	}
	staticEngine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		fail(err)
	}
	initial := applyDirect(staticEngine, code)
	if len(initial) < 2 {
		fail(errors.New("learning probe has fewer than two candidates"))
	}
	target := initial[1]
	exitBefore := 2 + *selections*(len(code)+2)
	client, err := startBroker(*brokerPath, *indexPath, *mode, *snapshotPath, *journalPath, exitBefore)
	if err != nil {
		fail(err)
	}
	selectTimes := make([]time.Duration, 0, *selections)
	for i := 0; i < *selections; i++ {
		state, err := client.applyCode(code)
		if err != nil {
			fail(err)
		}
		candidate := findText(state.Candidates, target.Text)
		if candidate == nil {
			fail(fmt.Errorf("target %q disappeared", target.Text))
		}
		started := time.Now()
		selected, err := client.request(yimebroker.Select, engineapi.Event{}, candidate.ID)
		selectTimes = append(selectTimes, time.Since(started))
		if err != nil || selected.Commit != target.Text {
			fail(fmt.Errorf("durable selection failed: %v", err))
		}
	}
	snapshotAbsent := !fileExists(*snapshotPath)
	crashStarted := time.Now()
	_, crashErr := client.request(yimebroker.ResetSession, engineapi.Event{}, "")
	client.terminate()
	crashDetected := crashErr != nil
	journalBefore, err := os.Stat(*journalPath)
	if err != nil {
		fail(err)
	}
	torn := []byte(`{"schema_version":"torn-unacknowledged-tail`)
	if err := appendFile(*journalPath, torn); err != nil {
		fail(err)
	}

	restarted, err := startBroker(*brokerPath, *indexPath, *mode, *snapshotPath, *journalPath, 0)
	if err != nil {
		fail(err)
	}
	recoveredState, err := restarted.applyCode(code)
	if err != nil {
		fail(err)
	}
	recovered := findText(recoveredState.Candidates, target.Text)
	rankingPassed := recovered != nil && len(recoveredState.Candidates) > 0 && recoveredState.Candidates[0].Text == target.Text && recovered.Score.User > 0
	recoveryElapsed := time.Since(crashStarted)
	if !restarted.close() {
		fail(errors.New("restarted Broker did not shut down cleanly"))
	}
	journalAfter, err := os.Stat(*journalPath)
	if err != nil {
		fail(err)
	}
	tornTruncated := journalAfter.Size() == journalBefore.Size()

	verified, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: *snapshotPath, JournalPath: *journalPath, SourceID: index.SourceID(), CheckpointEvery: 1000,
	})
	if err != nil {
		fail(err)
	}
	finalStats := verified.Stats()
	recoveredGeneration := verified.Model().Generation()
	if err := verified.Close(); err != nil {
		fail(err)
	}
	corruptionRejected := verifyCorruptionRejected(*snapshotPath, *journalPath, index.SourceID())
	latencyResult := summarize(selectTimes)
	latencyPassed := time.Duration(latencyResult.P99NS) <= maxSelectP99 && time.Duration(latencyResult.MaxNS) <= maxSelect
	recoveryPassed := snapshotAbsent && crashDetected && tornTruncated && recoveredGeneration == uint64(*selections) && rankingPassed && recoveryElapsed <= maxCrashRecoveryTime && corruptionRejected
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), LearningCode: code, SelectedText: target.Text,
		Selections: *selections, DurableSelectLatency: latencyResult, SnapshotAbsentAtCrash: snapshotAbsent,
		CrashDetected: crashDetected, CrashRecoveryNS: recoveryElapsed.Nanoseconds(), TornTailBytes: int64(len(torn)),
		TornTailTruncated: tornTruncated, RecoveredGeneration: recoveredGeneration, RecoveredRankingPassed: rankingPassed,
		SnapshotSHA256: hashFile(*snapshotPath), JournalSHA256: hashFile(*journalPath), FinalStats: finalStats,
		CorruptionRejected: corruptionRejected, LatencyGatePassed: latencyPassed, RecoveryGatePassed: recoveryPassed,
		DurabilitySemantics: "each acknowledged selection is fsynced to a hash-chained journal before the commit response; snapshots are atomic and recovery replays journal generations after the snapshot",
	}
	result.Passed = result.LatencyGatePassed && result.RecoveryGatePassed
	writeJSON(*outputPath, result)
	fmt.Printf("YimeBroker E5-C: mode=%s passed=%t generation=%d select_p99_ns=%d recovery_ms=%.1f\n", *mode, result.Passed, recoveredGeneration, latencyResult.P99NS, float64(result.CrashRecoveryNS)/1e6)
	if !result.Passed {
		os.Exit(1)
	}
}

type brokerClient struct {
	command   *exec.Cmd
	input     io.WriteCloser
	output    *bufio.Reader
	sequence  uint64
	sessionID string
	waited    bool
}

func startBroker(binary, index, mode, snapshot, journal string, exitBefore int) (*brokerClient, error) {
	args := []string{"-index", index, "-mode", mode, "-trusted-client-id", "e5c-supervisor", "-user-model-snapshot", snapshot, "-user-model-journal", journal, "-user-model-checkpoint-every", "1000"}
	if exitBefore > 0 {
		args = append(args, "-experiment-exit-before-request", fmt.Sprint(exitBefore))
	}
	command := exec.Command(binary, args...)
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
	client := &brokerClient{command: command, input: input, output: bufio.NewReader(output), sequence: 1}
	response, err := client.send(yimebroker.Request{Version: 1, Sequence: 1, Operation: yimebroker.OpenSession})
	if err != nil {
		client.terminate()
		return nil, err
	}
	client.sessionID = response.SessionID
	return client, nil
}

func (c *brokerClient) applyCode(code string) (engineapi.State, error) {
	if _, err := c.request(yimebroker.ResetSession, engineapi.Event{}, ""); err != nil {
		return engineapi.State{}, err
	}
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = c.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}, "")
		if err != nil {
			return engineapi.State{}, err
		}
	}
	return result.State, nil
}

func (c *brokerClient) request(operation yimebroker.Operation, event engineapi.Event, candidateID string) (engineapi.Result, error) {
	c.sequence++
	response, err := c.send(yimebroker.Request{Version: 1, Sequence: c.sequence, SessionID: c.sessionID, Operation: operation, Event: event, CandidateID: candidateID})
	if err != nil {
		return engineapi.Result{}, err
	}
	if response.Result == nil {
		return engineapi.Result{}, errors.New("missing result")
	}
	return *response.Result, nil
}

func (c *brokerClient) send(request yimebroker.Request) (yimebroker.Response, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	if _, err := c.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	type readResult struct {
		data []byte
		err  error
	}
	done := make(chan readResult, 1)
	go func() {
		line, err := c.output.ReadBytes('\n')
		done <- readResult{data: line, err: err}
	}()
	select {
	case result := <-done:
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
	case <-time.After(requestTimeout):
		return yimebroker.Response{}, errors.New("broker response timeout")
	}
}

func (c *brokerClient) close() bool {
	_, _ = c.request(yimebroker.CloseSession, engineapi.Event{}, "")
	_ = c.input.Close()
	err := c.command.Wait()
	c.waited = true
	return err == nil && c.command.ProcessState != nil && c.command.ProcessState.Exited()
}

func (c *brokerClient) terminate() {
	_ = c.input.Close()
	_ = c.command.Process.Kill()
	if !c.waited {
		_ = c.command.Wait()
		c.waited = true
	}
}

func applyDirect(engine engineapi.Engine, code string) []engineapi.Candidate {
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			fail(err)
		}
	}
	return result.State.Candidates
}

func findText(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for i := range candidates {
		if candidates[i].Text == text {
			return &candidates[i]
		}
	}
	return nil
}

func verifyCorruptionRejected(snapshot, journal, sourceID string) bool {
	directory, err := os.MkdirTemp(filepath.Dir(snapshot), "corruption-check-")
	if err != nil {
		return false
	}
	defer os.RemoveAll(directory)
	copySnapshot := filepath.Join(directory, "snapshot.json")
	copyJournal := filepath.Join(directory, "journal.log")
	if copyFile(snapshot, copySnapshot) != nil || copyFile(journal, copyJournal) != nil {
		return false
	}
	data, err := os.ReadFile(copyJournal)
	if err != nil || len(data) == 0 {
		return false
	}
	data[len(data)/2] ^= 1
	if os.WriteFile(copyJournal, data, 0o600) != nil {
		return false
	}
	_, err = yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{SnapshotPath: copySnapshot, JournalPath: copyJournal, SourceID: sourceID})
	return errors.Is(err, yimebroker.ErrCorruptUserJournal)
}

func copyFile(source, target string) error {
	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	return os.WriteFile(target, data, 0o600)
}

func appendFile(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	return file.Sync()
}

func summarize(values []time.Duration) latency {
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return latency{Samples: len(values), P50NS: percentile(values, 50).Nanoseconds(), P95NS: percentile(values, 95).Nanoseconds(), P99NS: percentile(values, 99).Nanoseconds(), MaxNS: values[len(values)-1].Nanoseconds()}
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

func hashFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err)
	}
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
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
