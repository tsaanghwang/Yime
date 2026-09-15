// Command yimebroker-compaction-experiment verifies atomic E5-G user-model
// compaction by crashing a live Broker at each ordered publication stage.
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
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	toolVersion     = "yimebroker-e5g-compaction-experiment-v1"
	requestTimeout  = 500 * time.Millisecond
	recoveryTimeout = 2 * time.Second
)

type stageResult struct {
	Stage                  string `json:"stage"`
	CrashDetected          bool   `json:"crash_detected"`
	RecoveredRankingPassed bool   `json:"recovered_ranking_passed"`
	RecoveredRetryPassed   bool   `json:"recovered_retry_passed"`
	FinalGeneration        uint64 `json:"final_generation"`
	FinalJournalBytes      int64  `json:"final_journal_bytes"`
	SnapshotSchema         string `json:"snapshot_schema"`
	RollbackSchema         string `json:"rollback_schema"`
	RollbackGeneration     uint64 `json:"rollback_generation"`
	RecoveryNS             int64  `json:"recovery_ns"`
	CleanShutdownPassed    bool   `json:"clean_shutdown_passed"`
	Passed                 bool   `json:"passed"`
}

type report struct {
	ToolVersion   string        `json:"tool_version"`
	GeneratedAt   string        `json:"generated_at"`
	Mode          string        `json:"mode"`
	IndexPath     string        `json:"index_path"`
	IndexSourceID string        `json:"index_source_id"`
	SelectedText  string        `json:"selected_text"`
	Stages        []stageResult `json:"stages"`
	Passed        bool          `json:"passed"`
}

func main() {
	brokerPath := flag.String("broker", "", "E5-G YimeBroker executable")
	indexPath := flag.String("index", "", "validated YimeCore index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	workRoot := flag.String("work-root", "", "stage data directory")
	output := flag.String("output", "", "evidence JSON")
	flag.Parse()
	if *brokerPath == "" || *indexPath == "" || *mode == "" || *workRoot == "" || *output == "" {
		fail(errors.New("broker, index, mode, work-root and output are required"))
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
	state := applyDirect(staticEngine, code)
	if len(state.Candidates) < 2 {
		fail(errors.New("compaction probe requires two candidates"))
	}
	target := state.Candidates[1]
	stages := []yimebroker.CompactionStage{
		yimebroker.CompactionAfterSnapshot,
		yimebroker.CompactionAfterJournalClose,
		yimebroker.CompactionAfterJournalReplace,
	}
	result := report{ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), SelectedText: target.Text}
	result.Passed = true
	for _, stage := range stages {
		stageEvidence := exerciseStage(*brokerPath, *indexPath, *mode, *workRoot, code, target.Text, index.SourceID(), stage)
		result.Stages = append(result.Stages, stageEvidence)
		result.Passed = result.Passed && stageEvidence.Passed
	}
	writeJSON(*output, result)
	fmt.Printf("YimeBroker E5-G: mode=%s passed=%t stages=%d\n", *mode, result.Passed, len(result.Stages))
	if !result.Passed {
		os.Exit(1)
	}
}

func exerciseStage(binary, index, mode, root, code, targetText, sourceID string, stage yimebroker.CompactionStage) stageResult {
	directory := filepath.Join(root, string(stage))
	if err := os.MkdirAll(directory, 0o755); err != nil {
		fail(err)
	}
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "journal.log")
	rollback := filepath.Join(directory, "model.v1.rollback")
	seed, err := yimecore.OpenUserModel(snapshot, sourceID)
	if err != nil {
		fail(err)
	}
	if err := seed.SaveVersion1To(snapshot); err != nil {
		fail(err)
	}
	client, err := startBroker(binary, index, mode, snapshot, journal, rollback, string(stage))
	if err != nil {
		fail(err)
	}
	for selection := 1; selection <= 2; selection++ {
		current, applyErr := client.applyCode(code)
		if applyErr != nil {
			break
		}
		candidate := findText(current.Candidates, targetText)
		if candidate == nil {
			break
		}
		_, _ = client.selectCandidate(candidate.ID, fmt.Sprintf("%s-initial-%02d", stage, selection))
	}
	crashStarted := time.Now()
	crashed := client.waitWithin(recoveryTimeout)

	restarted, err := startBroker(binary, index, mode, snapshot, journal, rollback, "")
	if err != nil {
		fail(err)
	}
	recoveredState, err := restarted.applyCode(code)
	if err != nil {
		fail(err)
	}
	recoveredCandidate := findText(recoveredState.Candidates, targetText)
	rankingPassed := recoveredCandidate != nil && recoveredCandidate.Score.User > 0
	retryPassed := false
	if recoveredCandidate != nil {
		response, retryErr := restarted.selectCandidate(recoveredCandidate.ID, fmt.Sprintf("%s-initial-02", stage))
		retryPassed = retryErr == nil && response.Result != nil && response.Result.Commit == targetText
	}
	for selection := 3; selection <= 4; selection++ {
		current, applyErr := restarted.applyCode(code)
		if applyErr != nil {
			fail(applyErr)
		}
		candidate := findText(current.Candidates, targetText)
		if candidate == nil {
			fail(errors.New("post-recovery candidate disappeared"))
		}
		if _, selectErr := restarted.selectCandidate(candidate.ID, fmt.Sprintf("%s-final-%02d", stage, selection)); selectErr != nil {
			fail(selectErr)
		}
	}
	deadline := time.Now().Add(recoveryTimeout)
	journalBytes := int64(-1)
	for time.Now().Before(deadline) {
		if info, statErr := os.Stat(journal); statErr == nil {
			journalBytes = info.Size()
			if journalBytes == 0 {
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	clean := restarted.close()
	recoveryElapsed := time.Since(crashStarted)
	verified, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, RollbackSnapshotPath: rollback, SourceID: sourceID, CompactEvery: 2,
	})
	if err != nil {
		fail(err)
	}
	generation := verified.Model().Generation()
	snapshotSchema := verified.Model().LoadedSchemaVersion()
	if err := verified.Close(); err != nil {
		fail(err)
	}
	rollbackModel, err := yimecore.OpenUserModel(rollback, sourceID)
	if err != nil {
		fail(err)
	}
	result := stageResult{Stage: string(stage), CrashDetected: crashed, RecoveredRankingPassed: rankingPassed, RecoveredRetryPassed: retryPassed,
		FinalGeneration: generation, FinalJournalBytes: journalBytes, SnapshotSchema: snapshotSchema,
		RollbackSchema: rollbackModel.LoadedSchemaVersion(), RollbackGeneration: rollbackModel.Generation(), RecoveryNS: recoveryElapsed.Nanoseconds(), CleanShutdownPassed: clean}
	result.Passed = result.CrashDetected && result.RecoveredRankingPassed && result.RecoveredRetryPassed && result.FinalGeneration == 4 &&
		result.FinalJournalBytes == 0 && result.SnapshotSchema == yimecore.UserModelSchemaVersion2 &&
		result.RollbackSchema == yimecore.UserModelSchemaVersion1 && result.RollbackGeneration == 0 && result.RecoveryNS <= recoveryTimeout.Nanoseconds() && result.CleanShutdownPassed
	return result
}

type brokerClient struct {
	command   *exec.Cmd
	input     io.WriteCloser
	output    *bufio.Reader
	sequence  uint64
	sessionID string
	waited    bool
}

func startBroker(binary, index, mode, snapshot, journal, rollback, stage string) (*brokerClient, error) {
	args := []string{"-index", index, "-mode", mode, "-trusted-client-id", "e5g-supervisor", "-user-model-snapshot", snapshot,
		"-user-model-journal", journal, "-user-model-rollback-snapshot", rollback, "-user-model-checkpoint-every", "1000", "-user-model-compact-every", "2"}
	if stage != "" {
		args = append(args, "-experiment-exit-compaction-stage", stage)
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
	if _, err := c.request(yimebroker.ResetSession, engineapi.Event{}, "", ""); err != nil {
		return engineapi.State{}, err
	}
	var response yimebroker.Response
	for _, key := range code {
		var err error
		response, err = c.request(yimebroker.ApplyEvent, engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}, "", "")
		if err != nil {
			return engineapi.State{}, err
		}
	}
	return response.Result.State, nil
}

func (c *brokerClient) selectCandidate(candidateID, mutationID string) (yimebroker.Response, error) {
	return c.request(yimebroker.Select, engineapi.Event{}, candidateID, mutationID)
}

func (c *brokerClient) request(operation yimebroker.Operation, event engineapi.Event, candidateID, mutationID string) (yimebroker.Response, error) {
	c.sequence++
	return c.send(yimebroker.Request{Version: 1, Sequence: c.sequence, SessionID: c.sessionID, Operation: operation,
		Event: event, CandidateID: candidateID, MutationID: mutationID})
}

func (c *brokerClient) send(request yimebroker.Request) (yimebroker.Response, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	if _, err := c.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	line, err := c.output.ReadBytes('\n')
	if err != nil {
		return yimebroker.Response{}, err
	}
	var response yimebroker.Response
	if err := json.Unmarshal(line, &response); err != nil {
		return response, err
	}
	if response.Error != nil {
		return response, fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
	}
	return response, nil
}

func (c *brokerClient) waitWithin(timeout time.Duration) bool {
	done := make(chan error, 1)
	go func() { done <- c.wait() }()
	select {
	case err := <-done:
		return err != nil && c.command.ProcessState != nil && c.command.ProcessState.Exited()
	case <-time.After(timeout):
		c.terminate()
		return false
	}
}

func (c *brokerClient) wait() error {
	if c.waited {
		return nil
	}
	err := c.command.Wait()
	c.waited = true
	return err
}

func (c *brokerClient) close() bool {
	_, _ = c.request(yimebroker.CloseSession, engineapi.Event{}, "", "")
	_ = c.input.Close()
	err := c.wait()
	return err == nil && c.command.ProcessState != nil && c.command.ProcessState.Exited()
}

func (c *brokerClient) terminate() {
	_ = c.input.Close()
	_ = c.command.Process.Kill()
	_ = c.wait()
}

func applyDirect(engine engineapi.Engine, code string) engineapi.State {
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		result, _ = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
	}
	return result.State
}

func findText(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for index := range candidates {
		if candidates[index].Text == text {
			return &candidates[index]
		}
	}
	return nil
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
