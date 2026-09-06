package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

type client struct {
	file     *os.File
	scanner  *bufio.Scanner
	sequence uint64
	session  string
	deadline time.Time
}

func connectClient(pipe string, broker *processHandle) (*client, error) {
	if !strings.HasPrefix(pipe, `\\.\pipe\YimeBroker.SR4B2.`) || !broker.alive() {
		return nil, errors.New("private verified pipe required")
	}
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if !broker.alive() {
			return nil, errors.New("verified Broker exited before pipe readiness")
		}
		file, err := openOwnedPipe(pipe, broker.evidence.PID)
		if err == nil {
			if err = file.SetDeadline(time.Now().Add(10 * time.Second)); err != nil {
				file.Close()
				return nil, errors.New("private pipe does not support bounded I/O")
			}
			s := bufio.NewScanner(file)
			s.Buffer(make([]byte, 4096), yimebroker.MaxMessageBytes+1)
			return &client{file: file, scanner: s, deadline: time.Now().Add(120 * time.Second)}, nil
		}
		if errors.Is(err, errForeignPipe) {
			return nil, err
		}
		time.Sleep(50 * time.Millisecond)
	}
	return nil, errors.New("private authenticated pipe did not become ready")
}
func (c *client) close() {
	if c != nil && c.file != nil {
		_ = c.file.Close()
	}
}
func (c *client) request(request yimebroker.Request) (yimebroker.Response, error) {
	if !time.Now().Before(c.deadline) {
		return yimebroker.Response{}, errors.New("private stage request budget exceeded")
	}
	if request.Operation == yimebroker.OpenSession {
		c.sequence = 0
		c.session = ""
	}
	c.sequence++
	request.Version = yimebroker.ProtocolVersion
	request.Sequence = c.sequence
	request.SessionID = c.session
	data, err := yimebroker.EncodeRequest(request)
	if err != nil {
		return yimebroker.Response{}, errors.New("invalid synthetic request shape")
	}
	requestDeadline := time.Now().Add(10 * time.Second)
	if c.deadline.Before(requestDeadline) {
		requestDeadline = c.deadline
	}
	if err = c.file.SetDeadline(requestDeadline); err != nil {
		return yimebroker.Response{}, err
	}
	if _, err = c.file.Write(append(data, '\n')); err != nil {
		return yimebroker.Response{}, errors.New("private pipe write failed")
	}
	if !c.scanner.Scan() {
		return yimebroker.Response{}, errors.New("private pipe ended or timed out")
	}
	var response yimebroker.Response
	if err = json.Unmarshal(c.scanner.Bytes(), &response); err != nil {
		return response, errors.New("private response decode failed")
	}
	if response.Version != request.Version || response.Sequence != request.Sequence || response.Error != nil {
		return response, errors.New("private request response rejected or sequence mismatch")
	}
	if request.Operation == yimebroker.OpenSession {
		if response.SessionID == "" {
			return response, errors.New("private open returned no session")
		}
		c.session = response.SessionID
	} else if response.SessionID != c.session {
		return response, errors.New("private session response mismatch")
	}
	if request.Operation == yimebroker.CloseSession {
		c.session = ""
	}
	return response, nil
}
func (c *client) input(code string) (engineapi.State, error) {
	if _, err := c.request(yimebroker.Request{Operation: yimebroker.ResetSession}); err != nil {
		return engineapi.State{}, err
	}
	var state engineapi.State
	for _, key := range code {
		r, err := c.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}})
		if err != nil {
			return state, err
		}
		if r.Result == nil || r.Result.Commit != "" {
			return state, errors.New("unconfirmed synthetic input committed")
		}
		state = r.Result.State
	}
	return state, nil
}
func moduleSource(candidate engineapi.Candidate) bool {
	if strings.HasPrefix(candidate.SourceID, speechruntime.ModuleID+"@") {
		return true
	}
	for _, s := range candidate.Segments {
		if strings.HasPrefix(s.SourceID, speechruntime.ModuleID+"@") {
			return true
		}
	}
	return false
}
func (c *client) find(code, text string, enabled, stopAtTarget bool) (engineapi.Candidate, error) {
	state, err := c.input(code)
	if err != nil {
		return engineapi.Candidate{}, err
	}
	var target engineapi.Candidate
	count := 0
	for page := 0; page < 1000; page++ {
		if state.PageNumber != page {
			return target, errors.New("synthetic paging ordinal mismatch")
		}
		for _, candidate := range state.Candidates {
			if !enabled && moduleSource(candidate) {
				return target, errors.New("disabled static speech provenance remains")
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
				return target, errors.New("duplicate synthetic code/text candidate")
			}
			return target, nil
		}
		r, err := c.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.PageNext}})
		if err != nil {
			return target, err
		}
		if r.Result == nil || r.Result.Commit != "" {
			return target, errors.New("paging unexpectedly committed")
		}
		state = r.Result.State
	}
	return target, errors.New("synthetic paging bound exceeded")
}
func markedCanonical(numeric string, normalized map[string]string) (string, error) {
	var parts []string
	for _, syllable := range strings.Fields(numeric) {
		if normalized[syllable] == "" {
			return "", errors.New("hashed normal annotation inventory lacks canonical syllable")
		}
		parts = append(parts, normalized[syllable])
	}
	if len(parts) == 0 {
		return "", errors.New("empty canonical annotation")
	}
	return strings.Join(parts, " "), nil
}

func exerciseModes(c *client, records []connectedspeech.AdmissionRecord, normalized map[string]string, enabled, train, learned bool) error {
	for _, mode := range []string{"full", "variable", "shorthand"} {
		if _, err := c.request(yimebroker.Request{Operation: yimebroker.OpenSession, Mode: mode, CandidateLimit: 5}); err != nil {
			return err
		}
		for _, record := range records {
			standard, err := markedCanonical(record.CanonicalPinyin, normalized)
			if err != nil {
				return err
			}
			codes, ok := record.Codes[mode]
			if !ok || codes.Canonical == "" || codes.Alias == "" {
				return errors.New("reviewed sample lacks mode codes")
			}
			canonical, err := c.find(codes.Canonical, record.Text, enabled, false)
			if err != nil {
				return err
			}
			if canonical.ID == "" {
				return errors.New("normal canonical route unavailable")
			}
			alias, err := c.find(codes.Alias, record.Text, enabled, false)
			if err != nil {
				return err
			}
			if enabled && (alias.ID == "" || (!moduleSource(alias) && alias.SourceID != "user-model")) {
				return errors.New("normal admitted alias lacks provenance")
			}
			if alias.ID != "" && (enabled || alias.SourceID == "user-model") && alias.Annotations.StandardPinyin != standard {
				return errors.New("normal alias annotation lost canonical reading")
			}
		}
		record := records[0]
		code := record.Codes[mode].Alias
		if learned {
			candidate, err := c.find(code, record.Text, enabled, true)
			if err != nil {
				return err
			}
			if candidate.ID == "" || candidate.Score.User <= 0 {
				return errors.New("normal learned alias did not survive restart/toggle")
			}
		}
		if _, err := c.input(code); err != nil {
			return err
		}
		cleared, err := c.request(yimebroker.Request{Operation: yimebroker.ApplyEvent, Event: engineapi.Event{Operation: engineapi.Clear}})
		if err != nil {
			return err
		}
		if cleared.Result == nil || cleared.Result.Commit != "" || cleared.Result.State.RawInput != "" {
			return errors.New("synthetic cancellation did not clear without commit")
		}
		if train {
			for i := 0; i < 2; i++ {
				candidate, err := c.find(code, record.Text, true, true)
				if err != nil {
					return err
				}
				if candidate.ID == "" {
					return errors.New("normal training target unavailable")
				}
				selected, err := c.request(yimebroker.Request{Operation: yimebroker.Select, CandidateID: candidate.ID, MutationID: fmt.Sprintf("sr4b2-%s-%d", mode, i)})
				if err != nil {
					return err
				}
				if selected.Result == nil || selected.Result.Commit != record.Text {
					return errors.New("explicit synthetic selection committed wrong result")
				}
			}
		}
		if _, err := c.request(yimebroker.Request{Operation: yimebroker.CloseSession}); err != nil {
			return err
		}
	}
	return nil
}
