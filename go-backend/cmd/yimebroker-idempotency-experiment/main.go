// Command yimebroker-idempotency-experiment verifies that a durable select
// can be retried after the Broker dies after fsync but before its response.
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
	toolVersion      = "yimebroker-e5f-idempotency-experiment-v1"
	requestTimeout   = 250 * time.Millisecond
	maximumRecovery  = 2 * time.Second
	stableMutationID = "e5f-select-request-00000001"
)

type report struct {
	ToolVersion                  string `json:"tool_version"`
	GeneratedAt                  string `json:"generated_at"`
	Mode                         string `json:"mode"`
	IndexPath                    string `json:"index_path"`
	IndexSourceID                string `json:"index_source_id"`
	MutationID                   string `json:"mutation_id"`
	SelectedText                 string `json:"selected_text"`
	ResponseLostAfterPersistence bool   `json:"response_lost_after_persistence"`
	ProcessExitDetected          bool   `json:"process_exit_detected"`
	RetryCommitPassed            bool   `json:"retry_commit_passed"`
	RetryEchoPassed              bool   `json:"retry_echo_passed"`
	ConflictRejected             bool   `json:"conflict_rejected"`
	RecoveredGeneration          uint64 `json:"recovered_generation"`
	SingleMutationPassed         bool   `json:"single_mutation_passed"`
	RecoveryNS                   int64  `json:"recovery_ns"`
	CleanShutdownPassed          bool   `json:"clean_shutdown_passed"`
	Passed                       bool   `json:"passed"`
}

func main() {
	brokerPath := flag.String("broker", "", "E5-F YimeBroker executable")
	indexPath := flag.String("index", "", "validated YimeCore index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	snapshot := flag.String("snapshot", "", "durable user model snapshot")
	journal := flag.String("journal", "", "durable user model journal")
	output := flag.String("output", "", "evidence JSON")
	flag.Parse()
	if *brokerPath == "" || *indexPath == "" || *mode == "" || *snapshot == "" || *journal == "" || *output == "" {
		fail(errors.New("broker, index, mode, snapshot, journal and output are required"))
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
	staticState := applyDirect(staticEngine, code)
	if len(staticState.State.Candidates) < 2 {
		fail(errors.New("idempotency probe requires two candidates"))
	}
	target := staticState.State.Candidates[1]
	conflictText := staticState.State.Candidates[0].Text
	exitAfter := 3 + len(code)
	first, err := startBroker(*brokerPath, *indexPath, *mode, *snapshot, *journal, exitAfter)
	if err != nil {
		fail(err)
	}
	state, err := first.applyCode(code)
	if err != nil {
		fail(err)
	}
	candidate := findText(state.Candidates, target.Text)
	if candidate == nil {
		fail(errors.New("target candidate disappeared"))
	}
	started := time.Now()
	_, lostErr := first.selectCandidate(candidate.ID, stableMutationID)
	exitDetected := first.wait() != nil
	responseLost := lostErr != nil

	restarted, err := startBroker(*brokerPath, *indexPath, *mode, *snapshot, *journal, 0)
	if err != nil {
		fail(err)
	}
	retryState, err := restarted.applyCode(code)
	if err != nil {
		fail(err)
	}
	retryCandidate := findText(retryState.Candidates, target.Text)
	if retryCandidate == nil {
		fail(errors.New("retry candidate disappeared"))
	}
	retryResponse, retryErr := restarted.selectCandidate(retryCandidate.ID, stableMutationID)
	retryCommit := retryErr == nil && retryResponse.Result != nil && retryResponse.Result.Commit == target.Text
	retryEcho := retryResponse.MutationID == stableMutationID

	conflictState, err := restarted.applyCode(code)
	if err != nil {
		fail(err)
	}
	conflictCandidate := findText(conflictState.Candidates, conflictText)
	if conflictCandidate == nil {
		fail(errors.New("conflict candidate disappeared"))
	}
	conflictResponse, _ := restarted.selectCandidate(conflictCandidate.ID, stableMutationID)
	conflictRejected := conflictResponse.Error != nil && conflictResponse.Error.Code == yimebroker.CodeEngine && conflictResponse.MutationID == stableMutationID
	clean := restarted.close()
	recoveryElapsed := time.Since(started)

	verified, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: *snapshot, JournalPath: *journal, SourceID: index.SourceID(), CheckpointEvery: 1000,
	})
	if err != nil {
		fail(err)
	}
	generation := verified.Model().Generation()
	if err := verified.Close(); err != nil {
		fail(err)
	}
	result := report{ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), MutationID: stableMutationID, SelectedText: target.Text,
		ResponseLostAfterPersistence: responseLost, ProcessExitDetected: exitDetected, RetryCommitPassed: retryCommit, RetryEchoPassed: retryEcho,
		ConflictRejected: conflictRejected, RecoveredGeneration: generation, SingleMutationPassed: generation == 1,
		RecoveryNS: recoveryElapsed.Nanoseconds(), CleanShutdownPassed: clean}
	result.Passed = result.ResponseLostAfterPersistence && result.ProcessExitDetected && result.RetryCommitPassed && result.RetryEchoPassed &&
		result.ConflictRejected && result.SingleMutationPassed && result.RecoveryNS <= maximumRecovery.Nanoseconds() && result.CleanShutdownPassed
	writeJSON(*output, result)
	fmt.Printf("YimeBroker E5-F: mode=%s passed=%t generation=%d recovery_ms=%.1f\n", *mode, result.Passed, generation, float64(result.RecoveryNS)/1e6)
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

func startBroker(binary, index, mode, snapshot, journal string, exitAfter int) (*brokerClient, error) {
	args := []string{"-index", index, "-mode", mode, "-trusted-client-id", "e5f-supervisor", "-user-model-snapshot", snapshot,
		"-user-model-journal", journal, "-user-model-checkpoint-every", "1000"}
	if exitAfter > 0 {
		args = append(args, "-experiment-exit-after-request", fmt.Sprint(exitAfter))
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
		return yimebroker.Response{}, errors.New("Broker response timeout")
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

func applyDirect(engine engineapi.Engine, code string) engineapi.Result {
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		result, _ = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
	}
	return result
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
