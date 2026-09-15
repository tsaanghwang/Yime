// Command yimebroker-index-switch-experiment verifies E5-D transactional
// index switching and rollback in a live standalone Broker process.
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
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

const (
	toolVersion       = "yimebroker-e5d-index-switch-experiment-v1"
	requestTimeout    = 100 * time.Millisecond
	controlTimeout    = 2 * time.Second
	maxControlLatency = time.Second
)

type controlResult struct {
	RequestID string                        `json:"request_id"`
	ElapsedNS int64                         `json:"elapsed_ns"`
	Status    yimebroker.IndexControlStatus `json:"status"`
	Passed    bool                          `json:"passed"`
}

type report struct {
	ToolVersion                      string        `json:"tool_version"`
	GeneratedAt                      string        `json:"generated_at"`
	Mode                             string        `json:"mode"`
	InitialIndexPath                 string        `json:"initial_index_path"`
	CandidateIndexPath               string        `json:"candidate_index_path"`
	InitialIndexSHA256               string        `json:"initial_index_sha256"`
	CandidateIndexSHA256             string        `json:"candidate_index_sha256"`
	CandidateProbeCode               string        `json:"candidate_probe_code"`
	CandidateProbeText               string        `json:"candidate_probe_text"`
	InitialSessionVersion            string        `json:"initial_session_version"`
	RejectedSwitch                   controlResult `json:"rejected_switch"`
	ValidSwitch                      controlResult `json:"valid_switch"`
	Rollback                         controlResult `json:"rollback"`
	OldSessionSurvivedSwitch         bool          `json:"old_session_survived_switch"`
	NewSessionUsedCandidate          bool          `json:"new_session_used_candidate"`
	CandidateProbePassed             bool          `json:"candidate_probe_passed"`
	CandidateSessionSurvivedRollback bool          `json:"candidate_session_survived_rollback"`
	PostRollbackSessionUsedInitial   bool          `json:"post_rollback_session_used_initial"`
	CleanShutdownPassed              bool          `json:"clean_shutdown_passed"`
	Passed                           bool          `json:"passed"`
}

func main() {
	brokerPath := flag.String("broker", "", "E5-D YimeBroker executable")
	initialIndex := flag.String("initial-index", "", "initial validated index")
	candidateIndex := flag.String("candidate-index", "", "candidate validated index")
	initialHash := flag.String("initial-sha256", "", "expected initial index SHA-256")
	candidateHash := flag.String("candidate-sha256", "", "expected candidate index SHA-256")
	probeCode := flag.String("probe-code", "", "candidate-generation exact probe code")
	probeText := flag.String("probe-text", "", "candidate-generation expected text")
	mode := flag.String("mode", "", "full, variable or shorthand")
	manifest := flag.String("manifest", "", "index control manifest")
	status := flag.String("status", "", "index control status")
	output := flag.String("output", "", "evidence JSON")
	flag.Parse()
	if *brokerPath == "" || *initialIndex == "" || *candidateIndex == "" || len(*initialHash) != 64 || len(*candidateHash) != 64 || *probeCode == "" || *probeText == "" || *mode == "" || *manifest == "" || *status == "" || *output == "" {
		fail(errors.New("broker, two indexes and hashes, candidate probe, mode, manifest, status and output are required"))
	}
	process, err := startBroker(*brokerPath, *initialIndex, *initialHash, *mode, *manifest, *status)
	if err != nil {
		fail(err)
	}
	if _, err := waitStatus(*status, "startup", controlTimeout); err != nil {
		process.terminate()
		fail(err)
	}
	oldSession, oldOpen, err := process.openSession()
	if err != nil {
		fail(err)
	}

	rejected := runControl(*manifest, *status, yimebroker.IndexControlRequest{
		SchemaVersion: yimebroker.IndexControlSchema, RequestID: "reject-bad-hash", Action: "swap",
		Index: &yimebroker.IndexSpec{Version: "v-bad", Mode: *mode, Path: *candidateIndex, ExpectedSHA256: strings.Repeat("0", 64)},
	}, false, "v1")
	oldAfterReject, err := process.reset(oldSession)
	if err != nil {
		fail(err)
	}

	valid := runControl(*manifest, *status, yimebroker.IndexControlRequest{
		SchemaVersion: yimebroker.IndexControlSchema, RequestID: "switch-v2", Action: "swap",
		Index: &yimebroker.IndexSpec{Version: "v2", Mode: *mode, Path: *candidateIndex, ExpectedSHA256: *candidateHash},
	}, true, "v2")
	oldAfterSwitch, err := process.reset(oldSession)
	if err != nil {
		fail(err)
	}
	newSession, newOpen, err := process.openSession()
	if err != nil {
		fail(err)
	}
	candidateState, err := process.applyCode(newSession, *probeCode)
	if err != nil {
		fail(err)
	}
	candidateProbePassed := false
	if candidateState.Result != nil {
		for _, candidate := range candidateState.Result.State.Candidates {
			if candidate.Text == *probeText && candidate.Code == *probeCode && candidate.Exact {
				candidateProbePassed = true
			}
		}
	}

	rollback := runControl(*manifest, *status, yimebroker.IndexControlRequest{
		SchemaVersion: yimebroker.IndexControlSchema, RequestID: "rollback-v1", Action: "rollback",
	}, true, "v1")
	newAfterRollback, err := process.reset(newSession)
	if err != nil {
		fail(err)
	}
	postRollback, rollbackOpen, err := process.openSession()
	if err != nil {
		fail(err)
	}
	clean := process.closeSessions(oldSession, newSession, postRollback)
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		InitialIndexPath: filepath.Clean(*initialIndex), CandidateIndexPath: filepath.Clean(*candidateIndex),
		InitialIndexSHA256: strings.ToLower(*initialHash), CandidateIndexSHA256: strings.ToLower(*candidateHash),
		CandidateProbeCode: *probeCode, CandidateProbeText: *probeText,
		InitialSessionVersion: oldOpen.EngineVersion, RejectedSwitch: rejected, ValidSwitch: valid, Rollback: rollback,
		OldSessionSurvivedSwitch:         oldAfterReject.EngineVersion == "v1" && oldAfterSwitch.EngineVersion == "v1",
		NewSessionUsedCandidate:          newOpen.EngineVersion == "v2",
		CandidateProbePassed:             candidateProbePassed,
		CandidateSessionSurvivedRollback: newAfterRollback.EngineVersion == "v2",
		PostRollbackSessionUsedInitial:   rollbackOpen.EngineVersion == "v1", CleanShutdownPassed: clean,
	}
	result.Passed = result.InitialSessionVersion == "v1" && result.RejectedSwitch.Passed && result.ValidSwitch.Passed && result.Rollback.Passed &&
		result.OldSessionSurvivedSwitch && result.NewSessionUsedCandidate && result.CandidateProbePassed && result.CandidateSessionSurvivedRollback && result.PostRollbackSessionUsedInitial && result.CleanShutdownPassed
	writeJSON(*output, result)
	fmt.Printf("YimeBroker E5-D: mode=%s passed=%t reject_ms=%.1f switch_ms=%.1f rollback_ms=%.1f\n", *mode, result.Passed,
		float64(rejected.ElapsedNS)/1e6, float64(valid.ElapsedNS)/1e6, float64(rollback.ElapsedNS)/1e6)
	if !result.Passed {
		os.Exit(1)
	}
}

type session struct {
	id       string
	sequence uint64
}

type brokerProcess struct {
	command *exec.Cmd
	input   io.WriteCloser
	output  *bufio.Reader
	waited  bool
}

func startBroker(binary, index, hash, mode, manifest, status string) (*brokerProcess, error) {
	command := exec.Command(binary, "-index", index, "-mode", mode, "-trusted-client-id", "e5d-supervisor",
		"-index-version", "v1", "-index-sha256", hash, "-index-control-manifest", manifest, "-index-control-status", status)
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
	return &brokerProcess{command: command, input: input, output: bufio.NewReader(output)}, nil
}

func (p *brokerProcess) openSession() (*session, yimebroker.Response, error) {
	response, err := p.send(yimebroker.Request{Version: 1, Sequence: 1, Operation: yimebroker.OpenSession})
	return &session{id: response.SessionID, sequence: 1}, response, err
}

func (p *brokerProcess) reset(current *session) (yimebroker.Response, error) {
	current.sequence++
	return p.send(yimebroker.Request{Version: 1, Sequence: current.sequence, SessionID: current.id, Operation: yimebroker.ResetSession})
}

func (p *brokerProcess) applyCode(current *session, code string) (yimebroker.Response, error) {
	response, err := p.reset(current)
	if err != nil {
		return response, err
	}
	for _, key := range code {
		current.sequence++
		response, err = p.send(yimebroker.Request{
			Version: 1, Sequence: current.sequence, SessionID: current.id, Operation: yimebroker.ApplyEvent,
			Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)},
		})
		if err != nil {
			return response, err
		}
	}
	return response, nil
}

func (p *brokerProcess) send(request yimebroker.Request) (yimebroker.Response, error) {
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	if _, err := p.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	type readResult struct {
		data []byte
		err  error
	}
	done := make(chan readResult, 1)
	go func() {
		line, err := p.output.ReadBytes('\n')
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

func (p *brokerProcess) closeSessions(sessions ...*session) bool {
	for _, current := range sessions {
		current.sequence++
		_, _ = p.send(yimebroker.Request{Version: 1, Sequence: current.sequence, SessionID: current.id, Operation: yimebroker.CloseSession})
	}
	_ = p.input.Close()
	err := p.command.Wait()
	p.waited = true
	return err == nil && p.command.ProcessState != nil && p.command.ProcessState.Exited()
}

func (p *brokerProcess) terminate() {
	_ = p.input.Close()
	_ = p.command.Process.Kill()
	if !p.waited {
		_ = p.command.Wait()
		p.waited = true
	}
}

func runControl(manifest, statusPath string, request yimebroker.IndexControlRequest, wantAccepted bool, wantVersion string) controlResult {
	started := time.Now()
	if err := writeManifest(manifest, request); err != nil {
		fail(err)
	}
	status, err := waitStatus(statusPath, request.RequestID, controlTimeout)
	elapsed := time.Since(started)
	passed := err == nil && status.Accepted == wantAccepted && status.Manager.ActiveVersion == wantVersion && elapsed <= maxControlLatency
	return controlResult{RequestID: request.RequestID, ElapsedNS: elapsed.Nanoseconds(), Status: status, Passed: passed}
}

func waitStatus(path, requestID string, timeout time.Duration) (yimebroker.IndexControlStatus, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil {
			var status yimebroker.IndexControlStatus
			if json.Unmarshal(data, &status) == nil && status.RequestID == requestID {
				return status, nil
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	return yimebroker.IndexControlStatus{}, fmt.Errorf("status %q timed out", requestID)
}

func writeManifest(path string, request yimebroker.IndexControlRequest) error {
	data, err := json.MarshalIndent(request, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".index-control-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err == nil {
		return nil
	}
	_ = os.Remove(path)
	return os.Rename(temporaryPath, path)
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
