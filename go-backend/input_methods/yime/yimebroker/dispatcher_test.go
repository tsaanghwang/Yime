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
	for _, mode := range []string{"full", "variable", "shorthand"} {
		index, err := yimecore.NewIndex([]yimecore.Entry{{Text: mode, Code: "a", Weight: 10}})
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
	if got := variable.Result.State.Candidates[0].Text; got != "variable" {
		t.Fatalf("default mode candidate = %q", got)
	}

	fullClient := TrustedClient{ID: "full-mode-client"}
	fullOpened := dispatch(t, dispatcher, fullClient, Request{Version: 1, Sequence: 1, Operation: OpenSession, Mode: "full"})
	full := dispatch(t, dispatcher, fullClient, Request{Version: 1, Sequence: 2, SessionID: fullOpened.SessionID,
		Operation: ApplyEvent, Event: engineapi.Event{Operation: engineapi.AppendCode, Code: "a"}})
	if got := full.Result.State.Candidates[0].Text; got != "full" {
		t.Fatalf("explicit mode candidate = %q", got)
	}
	if got := variable.Result.State.Candidates[0].Text; got != "variable" {
		t.Fatalf("opening another mode mutated existing session: %q", got)
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
