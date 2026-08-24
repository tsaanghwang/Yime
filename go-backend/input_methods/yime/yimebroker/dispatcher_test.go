package yimebroker

import (
	"context"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestStrictProtocolRejectsIdentityUnknownFieldsAndOversize(t *testing.T) {
	for _, data := range [][]byte{
		[]byte(`{"version":1,"sequence":1,"operation":"open","client_id":"forged"}`),
		[]byte(`{"version":1,"sequence":1,"operation":"open"} {}`),
		append([]byte(`{"version":1,"sequence":1,"operation":"open","padding":"`), append([]byte(strings.Repeat("x", MaxMessageBytes)), []byte(`"}`)...)...),
	} {
		if _, err := DecodeRequest(data); err == nil {
			t.Fatalf("DecodeRequest(%d bytes) unexpectedly succeeded", len(data))
		}
	}
}

func TestProtocolRestrictsAndEchoesMutationID(t *testing.T) {
	invalid := []Request{
		{Version: 1, Sequence: 1, Operation: OpenSession, MutationID: "request-0001"},
		{Version: 1, Sequence: 2, SessionID: "s", Operation: ResetSession, MutationID: "request-0001"},
		{Version: 1, Sequence: 2, SessionID: "s", Operation: Select, CandidateID: "c", MutationID: "short"},
	}
	for _, request := range invalid {
		if _, err := EncodeRequest(request); err == nil {
			t.Fatalf("invalid mutation request encoded: %+v", request)
		}
	}
	dispatcher := newMemoryDispatcher(t, Config{})
	client := TrustedClient{ID: "idempotent-client"}
	sessionID := openSession(t, dispatcher, client)
	state := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 2, SessionID: sessionID, Operation: ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "1"}})
	const mutationID = "request-0001"
	selected := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 3, SessionID: sessionID, Operation: Select,
		CandidateID: state.Result.State.Candidates[0].ID, MutationID: mutationID})
	if selected.Error != nil || selected.MutationID != mutationID {
		t.Fatalf("idempotent response = %+v", selected)
	}
}

func TestLegacySurfaceMutationIDsAreScopedPerSession(t *testing.T) {
	const legacy = "e6b2a-surface-1234-1"
	first := durableMutationID("s-0000000000000001", legacy)
	second := durableMutationID("s-0000000000000002", legacy)
	if first == second || first != "s-0000000000000001:"+legacy || second != "s-0000000000000002:"+legacy {
		t.Fatalf("legacy mutation IDs were not isolated: first=%q second=%q", first, second)
	}
	const current = "e6c-12345678-1234-1234-1234-123456789abc-1"
	if got := durableMutationID("s-0000000000000001", current); got != current {
		t.Fatalf("current globally stable mutation ID changed: %q", got)
	}
}

func TestLegacySurfaceSelectionsLearnAcrossIndependentSessions(t *testing.T) {
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "甲", Code: "1", Weight: 10},
		{Text: "乙", Code: "1", Weight: 9},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := yimecore.NewUserModel("legacy-surface-regression")
	if err != nil {
		t.Fatal(err)
	}
	dispatcher, err := NewDispatcher(func() (engineapi.Engine, error) {
		return yimecore.NewEngineWithUserModel(index, 9, model)
	}, Config{})
	if err != nil {
		t.Fatal(err)
	}
	client := TrustedClient{ID: "legacy-installed-text-service"}
	const mutationID = "e6b2a-surface-4321-1"
	for sessionIndex, candidateIndex := range []int{0, 1} {
		sessionID := openSession(t, dispatcher, client)
		state := dispatch(t, dispatcher, client, Request{
			Version: 1, Sequence: 2, SessionID: sessionID, Operation: ApplyEvent,
			Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "1"},
		})
		selected := dispatch(t, dispatcher, client, Request{
			Version: 1, Sequence: 3, SessionID: sessionID, Operation: Select,
			CandidateID: state.Result.State.Candidates[candidateIndex].ID, MutationID: mutationID,
		})
		if selected.Error != nil || selected.MutationID != mutationID {
			t.Fatalf("session %d legacy selection failed: %+v", sessionIndex, selected)
		}
	}
	if got := model.Generation(); got != 2 {
		t.Fatalf("legacy independent-session selections produced generation %d, want 2", got)
	}
}

func TestDispatcherKeepsSentenceCommitAvailableWhileFirstWordChoicesAreVisible(t *testing.T) {
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	dispatcher, err := NewDispatcher(func() (engineapi.Engine, error) {
		return yimecore.NewEngine(index, 9)
	}, Config{})
	if err != nil {
		t.Fatal(err)
	}
	client := TrustedClient{ID: "dynamic-sentence-ui"}
	sessionID := openSession(t, dispatcher, client)
	sequence := uint64(1)
	var sentence engineapi.Candidate
	for _, code := range "abcd" {
		sequence++
		response := dispatch(t, dispatcher, client, Request{
			Version: 1, Sequence: sequence, SessionID: sessionID, Operation: ApplyEvent,
			Event: engineapi.Event{Operation: engineapi.AppendCode, Code: string(code)},
		})
		if response.Result == nil {
			t.Fatalf("sentence input failed: %+v", response)
		}
		for _, candidate := range response.Result.State.Candidates {
			if candidate.Text == "甲丙" {
				sentence = candidate
			}
		}
	}
	if len(sentence.Segments) != 2 {
		t.Fatalf("generated sentence missing: %+v", sentence)
	}
	sequence++
	focused := dispatch(t, dispatcher, client, Request{
		Version: 1, Sequence: sequence, SessionID: sessionID, Operation: ApplyEvent,
		Event: engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
			SegmentStart: sentence.Segments[0].Start, SegmentEnd: sentence.Segments[0].End},
	})
	if focused.Result == nil || len(focused.Result.State.Candidates) != 2 ||
		focused.Result.State.Candidates[0].Text != "甲" || focused.Result.State.Candidates[1].Text != "乙" {
		t.Fatalf("first-word candidate sequence mismatch: %+v", focused)
	}
	sequence++
	committed := dispatch(t, dispatcher, client, Request{
		Version: 1, Sequence: sequence, SessionID: sessionID, Operation: Select,
		CandidateID: sentence.ID, MutationID: "dynamic-sentence-row-0001",
	})
	if committed.Result == nil || committed.Result.Commit != "甲丙" ||
		committed.Result.State.RawInput != "" {
		t.Fatalf("sentence row commit failed while first-word choices were visible: %+v", committed)
	}
}

func TestDispatcherKeepsSessionsIsolatedAndRejectsReplay(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	a := TrustedClient{ID: "client-a"}
	b := TrustedClient{ID: "client-b"}
	aSession := openSession(t, dispatcher, a)
	bSession := openSession(t, dispatcher, b)

	aResult := dispatch(t, dispatcher, a, Request{Version: 1, Sequence: 2, SessionID: aSession, Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "1"}})
	if aResult.Result == nil || aResult.Result.State.RawInput != "1" {
		t.Fatalf("client A state = %+v", aResult)
	}
	bResult := dispatch(t, dispatcher, b, Request{Version: 1, Sequence: 2, SessionID: bSession, Operation: ResetSession})
	if bResult.Result == nil || bResult.Result.State.RawInput != "" {
		t.Fatalf("client B state = %+v", bResult)
	}
	forged := dispatch(t, dispatcher, b, Request{Version: 1, Sequence: 3, SessionID: aSession, Operation: ResetSession})
	if forged.Error == nil || forged.Error.Code != CodeSessionNotFound {
		t.Fatalf("cross-client request = %+v", forged)
	}
	replay := dispatch(t, dispatcher, a, Request{Version: 1, Sequence: 2, SessionID: aSession, Operation: ResetSession})
	if replay.Error == nil || replay.Error.Code != CodeSequence {
		t.Fatalf("replay = %+v", replay)
	}
}

func TestDispatcherEnforcesTotalAndPerClientQuotas(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{MaxSessions: 2, MaxSessionsPerClient: 1, OperationTimeout: time.Second})
	openSession(t, dispatcher, TrustedClient{ID: "a"})
	secondA := dispatch(t, dispatcher, TrustedClient{ID: "a"}, Request{Version: 1, Sequence: 1, Operation: OpenSession})
	if secondA.Error == nil || secondA.Error.Code != CodeSessionLimit {
		t.Fatalf("per-client quota = %+v", secondA)
	}
	openSession(t, dispatcher, TrustedClient{ID: "b"})
	third := dispatch(t, dispatcher, TrustedClient{ID: "c"}, Request{Version: 1, Sequence: 1, Operation: OpenSession})
	if third.Error == nil || third.Error.Code != CodeSessionLimit {
		t.Fatalf("total quota = %+v", third)
	}
}

func TestDispatcherEvictsTimedOutAndPanickingSessions(t *testing.T) {
	for _, test := range []struct {
		name string
		mode string
		want ErrorCode
	}{
		{name: "timeout", mode: "block", want: CodeTimeout},
		{name: "panic", mode: "panic", want: CodeEnginePanic},
	} {
		t.Run(test.name, func(t *testing.T) {
			engine := &faultEngine{mode: test.mode, release: make(chan struct{})}
			dispatcher, err := NewDispatcher(func() (engineapi.Engine, error) { return engine, nil }, Config{OperationTimeout: 5 * time.Millisecond})
			if err != nil {
				t.Fatal(err)
			}
			client := TrustedClient{ID: "fault-client"}
			sessionID := openSession(t, dispatcher, client)
			response := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 2, SessionID: sessionID, Operation: ResetSession})
			if response.Error == nil || response.Error.Code != test.want {
				t.Fatalf("fault response = %+v", response)
			}
			if dispatcher.ActiveSessions() != 0 {
				t.Fatalf("faulted session was retained")
			}
			after := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 3, SessionID: sessionID, Operation: ResetSession})
			if after.Error == nil || after.Error.Code != CodeSessionNotFound {
				t.Fatalf("evicted request = %+v", after)
			}
			close(engine.release)
		})
	}
}

func TestConcurrentSessionsRemainIndependent(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{MaxSessions: 16, MaxSessionsPerClient: 1, OperationTimeout: time.Second})
	var wait sync.WaitGroup
	for i := 0; i < 12; i++ {
		wait.Add(1)
		go func(i int) {
			defer wait.Done()
			client := TrustedClient{ID: string(rune('a' + i))}
			sessionID := openSession(t, dispatcher, client)
			response := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 2, SessionID: sessionID, Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "7"}})
			if response.Error != nil || response.Result.State.RawInput != "7" {
				t.Errorf("client %d response = %+v", i, response)
			}
		}(i)
	}
	wait.Wait()
}

func TestModeDispatcherDefaultsToVariableAndKeepsOpenedSessionsStable(t *testing.T) {
	indices := map[string]*yimecore.Index{}
	codes := map[string]string{"full": "af", "variable": "av", "shorthand": "as"}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		index, err := yimecore.NewIndex([]yimecore.Entry{{Text: mode, Code: codes[mode], Weight: 10}})
		if err != nil {
			t.Fatal(err)
		}
		indices[mode] = index
	}
	dispatcher, err := NewModeDispatcher("variable", func(mode string) (engineapi.Engine, error) {
		return yimecore.NewEngine(indices[mode], 9)
	}, Config{})
	if err != nil {
		t.Fatal(err)
	}
	client := TrustedClient{ID: "mode-client"}
	opened := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 1, Operation: OpenSession})
	variable := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 2, SessionID: opened.SessionID,
		Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "a"}})
	if variable.Result.State.RawInput != "a" {
		t.Fatalf("default mode partial composition = %+v", variable)
	}

	fullClient := TrustedClient{ID: "full-mode-client"}
	fullOpened := dispatch(t, dispatcher, fullClient, Request{Version: 1, Sequence: 1, Operation: OpenSession, Mode: "full"})
	full := dispatch(t, dispatcher, fullClient, Request{Version: 1, Sequence: 2, SessionID: fullOpened.SessionID,
		Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "af"}})
	if got := full.Result.State.Candidates[0].Text; got != "full" {
		t.Fatalf("explicit mode candidate = %q", got)
	}
	continued := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 3, SessionID: opened.SessionID,
		Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "v"}})
	if continued.Error != nil || continued.Result.State.RawInput != "av" || continued.Result.State.Candidates[0].Text != "variable" {
		t.Fatalf("toolbar-style mode change moved active composition: %+v", continued)
	}
	shorthandClient := TrustedClient{ID: "shorthand-mode-client"}
	shorthandOpened := dispatch(t, dispatcher, shorthandClient, Request{Version: 1, Sequence: 1, Operation: OpenSession, Mode: "shorthand"})
	shorthand := dispatch(t, dispatcher, shorthandClient, Request{Version: 1, Sequence: 2, SessionID: shorthandOpened.SessionID,
		Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "as"}})
	if shorthand.Error != nil || shorthand.Result.State.Candidates[0].Text != "shorthand" {
		t.Fatalf("new idle session did not adopt requested toolbar mode: %+v", shorthand)
	}
}

func newMemoryDispatcher(t *testing.T, config Config) *Dispatcher {
	t.Helper()
	index, err := yimecore.NewIndex([]yimecore.Entry{{Text: "一", Code: "1", Weight: 10}, {Text: "七", Code: "7", Weight: 9}})
	if err != nil {
		t.Fatal(err)
	}
	dispatcher, err := NewDispatcher(func() (engineapi.Engine, error) { return yimecore.NewEngine(index, 9) }, config)
	if err != nil {
		t.Fatal(err)
	}
	return dispatcher
}

func openSession(t *testing.T, dispatcher *Dispatcher, client TrustedClient) string {
	t.Helper()
	response := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 1, Operation: OpenSession})
	if response.Error != nil || response.SessionID == "" {
		t.Fatalf("open session = %+v", response)
	}
	return response.SessionID
}

func dispatch(t *testing.T, dispatcher *Dispatcher, client TrustedClient, request Request) Response {
	t.Helper()
	data, err := EncodeRequest(request)
	if err != nil {
		t.Fatal(err)
	}
	encoded := dispatcher.HandleJSON(context.Background(), client, data)
	var response Response
	if err := json.Unmarshal(encoded, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

type faultEngine struct {
	mode    string
	release chan struct{}
}

func (e *faultEngine) Apply(engineapi.Event) (engineapi.Result, error) { return e.Reset(), nil }
func (e *faultEngine) Select(string) (engineapi.Result, error)         { return e.Reset(), nil }
func (e *faultEngine) Reset() engineapi.Result {
	switch e.mode {
	case "block":
		<-e.release
	case "panic":
		panic("forced test panic")
	}
	return engineapi.Result{}
}
