package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type brokerChild struct {
	cmd           *exec.Cmd
	input         io.WriteCloser
	output        *bufio.Scanner
	cancel        context.CancelFunc
	context       context.Context
	endContextErr error
	sequence      uint64
	session       string
	closed        bool
}

func startChild(root, broker, manifest string) (*brokerChild, error) {
	return startChildWithLaunch(root, broker, manifest, childLaunch{})
}

type childLaunch struct {
	directory   string
	environment []string
}

func startChildWithLaunch(root, broker, manifest string, launch childLaunch) (*brokerChild, error) {
	hash, err := speechruntime.HashFile(filepath.Join(root, manifest))
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	cmd := exec.CommandContext(ctx, broker, "-speech-experiment-root", root, "-speech-experiment-manifest", manifest, "-speech-experiment-sha256", hash, "-trusted-client-id", "speech-isolated-fixture")
	cmd.Dir = launch.directory
	cmd.Env = launch.environment
	hideChild(cmd)
	cmd.Stderr = io.Discard
	in, err := cmd.StdinPipe()
	if err != nil {
		cancel()
		return nil, err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		in.Close()
		cancel()
		return nil, err
	}
	if err = cmd.Start(); err != nil {
		in.Close()
		out.Close()
		cancel()
		return nil, err
	}
	scanner := bufio.NewScanner(out)
	scanner.Buffer(make([]byte, 4096), yimebroker.MaxMessageBytes+1)
	return &brokerChild{cmd: cmd, input: in, output: scanner, cancel: cancel, context: ctx}, nil
}

func (b *brokerChild) finish() error {
	if b.closed {
		return nil
	}
	b.closed = true
	err := b.input.Close()
	waitErr := b.cmd.Wait()
	b.endContextErr = b.context.Err()
	b.cancel()
	return errors.Join(err, waitErr)
}

func confirmedAdmissionRejection(exitCode int, contextErr, processErr error) bool {
	// Exit 42 is reserved by the new Broker for pre-state admission failure.
	// A crash, generic failure or timeout must never count as correct rejection.
	return exitCode == 42 && contextErr == nil && processErr != nil
}

func (b *brokerChild) abort() {
	if !b.closed {
		b.closed = true
		b.input.Close()
		b.cancel()
		_ = b.cmd.Wait()
	}
}

func (b *brokerChild) request(request yimebroker.Request) (yimebroker.Response, error) {
	if request.Operation == yimebroker.OpenSession {
		// Sequence numbers belong to a session, not the transport connection.
		b.sequence = 0
	}
	b.sequence++
	request.Version = yimebroker.ProtocolVersion
	request.Sequence = b.sequence
	request.SessionID = b.session
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, err
	}
	if _, err = b.input.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, err
	}
	if !b.output.Scan() {
		return yimebroker.Response{}, errors.New("isolated Broker ended before response")
	}
	var response yimebroker.Response
	if err = json.Unmarshal(b.output.Bytes(), &response); err != nil {
		return response, errors.New("invalid isolated Broker response")
	}
	if response.Error != nil {
		return response, fmt.Errorf("isolated Broker request failed: operation=%s event=%d sequence=%d code=%s", request.Operation, request.Event.Operation, request.Sequence, response.Error.Code)
	}
	if response.Version != request.Version || response.Sequence != request.Sequence {
		return response, errors.New("isolated Broker response version or sequence mismatch")
	}
	return response, nil
}

func (b *brokerChild) inputCode(code string) (engineapi.State, error) {
	if _, err := b.request(yimebroker.Request{Operation: yimebroker.ResetSession}); err != nil {
		return engineapi.State{}, err
	}
	var state engineapi.State
	for _, key := range code {
		r, err := b.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}})
		if err != nil {
			return state, err
		}
		if r.Result == nil || r.Result.Commit != "" {
			return state, errors.New("unconfirmed input unexpectedly committed")
		}
		state = r.Result.State
	}
	return state, nil
}

func moduleSource(candidate engineapi.Candidate) bool {
	if strings.HasPrefix(candidate.SourceID, speechruntime.ModuleID+"@") {
		return true
	}
	for _, segment := range candidate.Segments {
		if strings.HasPrefix(segment.SourceID, speechruntime.ModuleID+"@") {
			return true
		}
	}
	return false
}

func (b *brokerChild) find(code, text string, enabled, stopAtTarget bool) (engineapi.Candidate, error) {
	state, err := b.inputCode(code)
	if err != nil {
		return engineapi.Candidate{}, err
	}
	var target engineapi.Candidate
	count := 0
	for page := 0; page < 1000; page++ {
		if state.PageNumber != page {
			return target, errors.New("candidate page number mismatch")
		}
		for _, candidate := range state.Candidates {
			if !enabled && moduleSource(candidate) {
				return target, errors.New("disabled module still contributes provenance")
			}
			if candidate.Text == text && candidate.Code == code {
				target = candidate
				count++
				if stopAtTarget {
					return target, nil
				}
			}
		}
		if !state.HasNext {
			if count > 1 {
				return target, errors.New("duplicate code and text candidate")
			}
			return target, nil
		}
		r, err := b.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.PageNext}})
		if err != nil {
			return target, err
		}
		if r.Result == nil || r.Result.Commit != "" {
			return target, errors.New("paging committed unexpectedly")
		}
		state = r.Result.State
	}
	return target, errors.New("paging exceeded isolated bound")
}

func ownModelGeneration(root string) (uint64, error) {
	// Read the already checkpointed synthetic snapshot only. In particular do
	// not recover or checkpoint its journal between two actual Broker starts.
	path, err := speechruntime.Child(root, "state/model.json")
	if err != nil {
		return 0, err
	}
	before, err := speechruntime.HashFile(path)
	if err != nil {
		return 0, err
	}
	model, err := yimecore.OpenUserModel(path, speechruntime.ModelNamespace)
	if err != nil {
		return 0, err
	}
	after, err := speechruntime.HashFile(path)
	if err != nil || after != before {
		return 0, errors.New("private snapshot changed during read-only count")
	}
	return model.Generation(), nil
}

func exercise(root, broker, expected string) (resultErr error) {
	return exerciseWithLaunch(root, broker, expected, childLaunch{})
}

func exerciseWithLaunch(root, broker, expected string, launch childLaunch) (resultErr error) {
	if err := speechruntime.IsTrialRoot(root); err != nil {
		return err
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return err
	}
	absBroker, err := filepath.Abs(broker)
	if err != nil {
		return err
	}
	if absBroker != filepath.Join(absRoot, "bin", "YimeBroker-speech.exe") {
		return errors.New("only the owned new Broker below trial/bin may execute")
	}
	if err := speechruntime.PlainPath(absBroker); err != nil {
		return err
	}
	hash, err := speechruntime.HashFile(absBroker)
	if err != nil || hash != expected || len(expected) != 64 {
		return errors.New("new Broker hash mismatch")
	}
	if _, err := os.Stat(filepath.Join(root, "state")); !os.IsNotExist(err) {
		return errors.New("exercise must start without any learning state")
	}
	var records connectedspeech.AdmissionResult
	if err := readJSON(filepath.Join(root, "admitted-records.json"), &records); err != nil {
		return err
	}
	if len(records.Records) != 24 {
		return errors.New("expected 24 admitted records")
	}
	var stages []map[string]any
	defer func() {
		report := map[string]any{"schema_version": "yimecore-speech-process-acceptance-v1", "passed": resultErr == nil, "broker_sha256": expected, "stages": stages, "transport": "owned anonymous stdio pipes to newly built YimeBroker", "rime_executed": false, "installed_broker_connected": false, "user_data_read": false, "windows_reboot_tested": false, "registered_or_live_host_tested": false}
		if resultErr != nil {
			report["failure"] = resultErr.Error()
		}
		resultErr = errors.Join(resultErr, writeNew(filepath.Join(root, "process-outcome.json"), report))
	}()
	for _, stage := range []struct {
		name                    string
		enabled, train, learned bool
		want                    uint64
	}{{"disabled-before", false, false, false, 0}, {"enabled-train", true, true, false, 6}, {"enabled-restart", true, false, true, 6}, {"disabled-after", false, false, true, 6}, {"reenabled", true, false, true, 6}} {
		manifest := "bundle-off.json"
		if stage.enabled {
			manifest = "bundle-on.json"
		}
		child, err := startChildWithLaunch(root, absBroker, manifest, launch)
		if err != nil {
			return err
		}
		stageErr := func() error {
			defer child.abort()
			for _, mode := range []string{"full", "variable", "shorthand"} {
				opened, err := child.request(yimebroker.Request{Operation: yimebroker.OpenSession, Mode: mode, CandidateLimit: 5})
				if err != nil {
					return err
				}
				child.session = opened.SessionID
				for _, record := range records.Records {
					canonical, err := child.find(record.Codes[mode].Canonical, record.Text, stage.enabled, false)
					if err != nil {
						return err
					}
					if canonical.ID == "" {
						return errors.New("canonical route not reachable")
					}
					alias, err := child.find(record.Codes[mode].Alias, record.Text, stage.enabled, false)
					if err != nil {
						return err
					}
					if stage.enabled && (alias.ID == "" || (!moduleSource(alias) && alias.SourceID != "user-model")) {
						return errors.New("admitted alias not reachable with expected provenance")
					}
				}
				record := records.Records[0]
				if stage.learned {
					candidate, err := child.find(record.Codes[mode].Alias, record.Text, stage.enabled, true)
					if err != nil {
						return err
					}
					if candidate.ID == "" || candidate.Score.User <= 0 {
						return errors.New("learned alias did not survive process reopen or module toggle")
					}
				}
				if _, err := child.inputCode(record.Codes[mode].Alias); err != nil {
					return err
				}
				cancelled, err := child.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.Clear}})
				if err != nil {
					return err
				}
				if cancelled.Result == nil || cancelled.Result.Commit != "" || cancelled.Result.State.RawInput != "" {
					return errors.New("cancel did not clear without commit")
				}
				if stage.train {
					for i := 0; i < 2; i++ {
						candidate, err := child.find(record.Codes[mode].Alias, record.Text, true, true)
						if err != nil {
							return err
						}
						if candidate.ID == "" {
							return errors.New("training target missing")
						}
						selected, err := child.request(yimebroker.Request{Operation: yimebroker.Select, CandidateID: candidate.ID, MutationID: fmt.Sprintf("isolated-%s-%d", mode, i)})
						if err != nil {
							return err
						}
						if selected.Result == nil || selected.Result.Commit != record.Text {
							return errors.New("explicit selection did not commit intended approved fixture")
						}
					}
				}
				if _, err := child.request(yimebroker.Request{Operation: yimebroker.CloseSession}); err != nil {
					return err
				}
				child.session = ""
			}
			return child.finish()
		}()
		if stageErr != nil {
			return fmt.Errorf("%s: %w", stage.name, stageErr)
		}
		generation, err := ownModelGeneration(root)
		if err != nil {
			return err
		}
		if generation != stage.want {
			return errors.New("unexpected private durable mutation count")
		}
		stages = append(stages, map[string]any{"name": stage.name, "pid": child.cmd.Process.Pid, "enabled": stage.enabled, "modes_passed": 3, "canonical_checks": 72, "alias_or_disabled_source_checks": 72, "learning_generation": generation, "exit_code": 0, "passed": true})
	}
	// An invalid next generation is rejected before touching the private model.
	beforeSnapshot, _ := speechruntime.HashFile(filepath.Join(root, "state", "model.json"))
	beforeJournal, _ := speechruntime.HashFile(filepath.Join(root, "state", "model.journal"))
	var broken speechruntime.Manifest
	if err := readJSON(filepath.Join(root, "bundle-on.json"), &broken); err != nil {
		return err
	}
	item := broken.Generation.Modes["full"]
	item.Core.ExpectedSHA256 = strings.Repeat("0", 64)
	broken.Generation.Modes["full"] = item
	if err := writeNew(filepath.Join(root, "bundle-rejected.json"), broken); err != nil {
		return err
	}
	child, err := startChildWithLaunch(root, absBroker, "bundle-rejected.json", launch)
	if err != nil {
		return err
	}
	err = child.finish()
	if !confirmedAdmissionRejection(child.cmd.ProcessState.ExitCode(), child.endContextErr, err) {
		return errors.New("mismatched admission generation did not produce a confirmed pre-state rejection")
	}
	afterSnapshot, _ := speechruntime.HashFile(filepath.Join(root, "state", "model.json"))
	afterJournal, _ := speechruntime.HashFile(filepath.Join(root, "state", "model.journal"))
	if beforeSnapshot == "" || beforeJournal == "" || beforeSnapshot != afterSnapshot || beforeJournal != afterJournal {
		return errors.New("rejected generation changed private durable state")
	}
	stages = append(stages, map[string]any{"name": "invalid-generation-rejected", "pid": child.cmd.Process.Pid, "state_unchanged": true, "exit_code": child.cmd.ProcessState.ExitCode(), "passed": true})
	// Reopen the original valid generation, rather than infer recovery merely
	// from unchanged bytes or the failed child's exit.
	recovered, err := startChildWithLaunch(root, absBroker, "bundle-on.json", launch)
	if err != nil {
		return err
	}
	defer recovered.abort()
	for _, mode := range []string{"full", "variable", "shorthand"} {
		opened, err := recovered.request(yimebroker.Request{Operation: yimebroker.OpenSession, Mode: mode, CandidateLimit: 5})
		if err != nil {
			return err
		}
		recovered.session = opened.SessionID
		record := records.Records[0]
		canonical, err := recovered.find(record.Codes[mode].Canonical, record.Text, true, false)
		if err != nil || canonical.ID == "" {
			return errors.New("canonical route did not recover after rejection")
		}
		learned, err := recovered.find(record.Codes[mode].Alias, record.Text, true, true)
		if err != nil || learned.ID == "" || learned.Score.User <= 0 {
			return errors.New("learned alias did not recover after rejection")
		}
		if _, err := recovered.request(yimebroker.Request{Operation: yimebroker.CloseSession}); err != nil {
			return err
		}
		recovered.session = ""
	}
	if err := recovered.finish(); err != nil {
		return err
	}
	generation, err := ownModelGeneration(root)
	if err != nil || generation != 6 {
		return errors.New("recovery changed private mutation count")
	}
	stages = append(stages, map[string]any{"name": "valid-generation-recovery", "pid": recovered.cmd.Process.Pid, "modes_passed": 3, "canonical_checks": 3, "learned_alias_checks": 3, "learning_generation": generation, "exit_code": 0, "passed": true})
	return nil
}
