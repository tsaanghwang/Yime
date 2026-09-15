package yimebroker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// This is a transport-neutral composition contract, not a pronunciation-rule,
// installed Broker, named-pipe, or native-host acceptance. Every dictionary and
// durable record is synthetic and created beneath t.TempDir. Real reviewed
// module inventories and their three-mode derivation require a separate gate.
func TestConnectedSpeechReconnectBrokerBundleDurableLifecycle(t *testing.T) {
	for _, fixture := range []struct{ mode, canonical, alias string }{
		{"full", "abcd", "xycd"},
		{"variable", "abd", "xyd"},
		{"shorthand", "ab", "xy"},
	} {
		t.Run(fixture.mode, func(t *testing.T) {
			root := t.TempDir()
			const target = "审"
			const moduleID = "reviewed-connected-speech-fixture"
			const modelID = "connected-speech-reconnect-synthetic-v1"
			var coreBody strings.Builder
			fmt.Fprintf(&coreBody, "%s\t%s\t1000\n", target, fixture.canonical)
			for i := 0; i < 6; i++ {
				fmt.Fprintf(&coreBody, "%c\t%s\t%d\n", rune('甲'+i), fixture.alias, 100-i)
			}
			core := reconnectFixtureIndex(t, root, fixture.mode, "core", coreBody.String())
			// The duplicate canonical entry protects code/text deduplication;
			// neither this synthetic entry nor its codes authorize a real rule.
			overlay := reconnectFixtureIndex(t, root, fixture.mode, "reviewed-overlay",
				fmt.Sprintf("%s\t%s\t1\n%s\t%s\t1\n", target, fixture.alias, target, fixture.canonical))
			enabled, err := yimecore.NewBundleIndex(core, []yimecore.BundleModule{{ID: moduleID, Index: overlay}})
			if err != nil {
				t.Fatal(err)
			}
			disabled, err := yimecore.NewBundleIndex(core, nil)
			if err != nil {
				t.Fatal(err)
			}
			if enabled.SourceID() == disabled.SourceID() {
				t.Fatal("bundle identity did not bind the enabled module set")
			}
			config := DurableUserModelConfig{
				SnapshotPath: filepath.Join(root, "model.json"), JournalPath: filepath.Join(root, "model.journal"),
				SourceID: modelID, CheckpointEvery: 1000,
			}
			store, err := OpenDurableUserModel(config)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = store.Close() })
			session := newReconnectSession(t, fixture.mode, enabled, store.Model())
			canonical := session.input(fixture.canonical)
			if matches := reconnectMatches(session.pages(canonical), target); len(matches) != 1 ||
				!strings.HasPrefix(matches[0].SourceID, "core@") {
				t.Fatal("canonical route was not retained exactly once with core provenance")
			}
			first := session.input(fixture.alias)
			if first.PageNumber != 0 || len(first.Candidates) != 5 || !first.HasNext ||
				len(reconnectMatches(first.Candidates, target)) != 0 {
				t.Fatal("low-weight alias changed the initial first page")
			}
			later := session.event(engineapi.Event{Operation: engineapi.PageNext}).State
			matches := reconnectMatches(later.Candidates, target)
			if later.PageNumber != 1 || len(matches) != 1 || matches[0].Weight != 1 ||
				!strings.HasPrefix(matches[0].SourceID, moduleID+"@") {
				t.Fatal("low-weight reviewed alias is not reachable on the later page with module provenance")
			}
			cancelled := session.event(engineapi.Event{Operation: engineapi.Clear})
			if cancelled.Commit != "" || cancelled.State.RawInput != "" ||
				len(cancelled.State.Candidates) != 0 || store.Model().Generation() != 0 {
				t.Fatal("cancelling unconfirmed alias input committed or learned")
			}
			for selection := 0; selection < 2; selection++ {
				state := session.input(fixture.alias)
				candidate := session.find(state, target)
				selected := session.request(Request{Operation: Select, CandidateID: candidate.ID,
					MutationID: fmt.Sprintf("reconnect-%s-selection-%d", fixture.mode, selection)})
				if selected.Result == nil || selected.Result.Commit != target ||
					store.Model().Generation() != uint64(selection+1) {
					t.Fatal("explicit alias selection did not create exactly one durable mutation")
				}
			}
			learned := store.Model().LearnedRecords()
			if !hasLearnedRecord(learned, fixture.alias, target) || hasLearnedRecord(learned, fixture.canonical, target) {
				t.Fatal("alias selection was not learned on its own input path")
			}
			session.close()
			if err := store.Close(); err != nil {
				t.Fatal(err)
			}

			reopened, err := OpenDurableUserModel(config)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = reopened.Close() })
			assertModel := func() {
				t.Helper()
				if reopened.Model().SourceID() != modelID || reopened.Model().Generation() != 2 ||
					!reflect.DeepEqual(reopened.Model().LearnedRecords(), learned) {
					t.Fatal("clean reopen or module selection changed the durable model")
				}
			}
			assertModel()
			restarted := newReconnectSession(t, fixture.mode, enabled, reopened.Model())
			state := restarted.input(fixture.alias)
			if len(state.Candidates) == 0 || state.Candidates[0].Text != target || state.Candidates[0].Score.User <= 0 {
				t.Fatal("clean reopen did not retain learned alias ranking")
			}
			restarted.close()

			without := newReconnectSession(t, fixture.mode, disabled, reopened.Model())
			for _, code := range []string{fixture.canonical, fixture.alias} {
				candidates := without.pages(without.input(code))
				for _, candidate := range candidates {
					if strings.HasPrefix(candidate.SourceID, moduleID+"@") {
						t.Fatal("disabled module still contributed candidate provenance")
					}
					for _, segment := range candidate.Segments {
						if strings.HasPrefix(segment.SourceID, moduleID+"@") {
							t.Fatal("disabled module still contributed segment provenance")
						}
					}
				}
				if code == fixture.canonical && len(reconnectMatches(candidates, target)) != 1 {
					t.Fatal("module disable removed or duplicated the canonical route")
				}
				// An independently learned code/text can remain reachable as
				// user-model. Removing a static module must not erase learning.
			}
			without.close()
			assertModel()

			reenabled, err := yimecore.NewBundleIndex(core, []yimecore.BundleModule{{ID: moduleID, Index: overlay}})
			if err != nil || reenabled.SourceID() != enabled.SourceID() {
				t.Fatal("reenabling the same immutable module did not restore its bundle identity")
			}
			reconnected := newReconnectSession(t, fixture.mode, reenabled, reopened.Model())
			state = reconnected.input(fixture.alias)
			if len(state.Candidates) == 0 || state.Candidates[0].Text != target || state.Candidates[0].Score.User <= 0 {
				t.Fatal("reenabling the module lost its existing learned ranking")
			}
			// Learning may recall the candidate before the page-sized static
			// fetch reaches its weight-1 row. Both real contributing sources
			// are valid; static module reachability was checked before learning.
			if matches := reconnectMatches(reconnected.pages(state), target); len(matches) != 1 ||
				(matches[0].SourceID != "user-model" && !strings.HasPrefix(matches[0].SourceID, moduleID+"@")) {
				sources := make([]string, len(matches))
				for i, candidate := range matches {
					sources[i] = candidate.SourceID
				}
				t.Fatalf("reenabling duplicated the learned/static candidate or lost module provenance: match_count=%d sources=%v", len(matches), sources)
			}
			reconnected.close()
			assertModel()
		})
	}
}

func TestReconnectLifecycleWaitsForDurableSelection(t *testing.T) {
	root := t.TempDir()
	const code, target = "abcd", "审"
	index := reconnectFixtureIndex(t, root, "full", "slow-durable-core", target+"\t"+code+"\t1\n")
	bundle, err := yimecore.NewBundleIndex(index, nil)
	if err != nil {
		t.Fatal(err)
	}
	config := DurableUserModelConfig{
		SnapshotPath: filepath.Join(root, "model.json"), JournalPath: filepath.Join(root, "model.journal"),
		SourceID: "reconnect-slow-durable-synthetic-v1", CheckpointEvery: 1000,
	}
	store, err := OpenDurableUserModel(config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	// Force persistence beyond the interactive 50ms budget without replacing
	// the real journal writer, Sync, or post-apply commit hook. This is a
	// lifecycle correctness fixture, not a latency acceptance test.
	const persistDelay = 150 * time.Millisecond
	store.Model().SetMutationHooks(func(mutation yimecore.UserMutation) error {
		time.Sleep(persistDelay)
		return store.persist(mutation)
	}, store.commit)
	session := newReconnectSession(t, "full", bundle, store.Model())
	candidate := session.find(session.input(code), target)
	started := time.Now()
	selected := session.request(Request{Operation: Select, CandidateID: candidate.ID, MutationID: "slow-durable-selection"})
	if time.Since(started) < persistDelay {
		t.Fatal("selection acknowledged before the delayed durable writer completed")
	}
	if selected.Result == nil || selected.Result.Commit != target || store.Model().Generation() != 1 ||
		store.Stats().JournalGeneration != 1 {
		t.Fatal("delayed selection did not commit exactly one journaled mutation")
	}
	learned := store.Model().LearnedRecords()
	if !hasLearnedRecord(learned, code, target) {
		t.Fatal("delayed selection was not learned")
	}
	session.close()
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenDurableUserModel(config)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = reopened.Close() })
	if reopened.Model().Generation() != 1 || !reflect.DeepEqual(reopened.Model().LearnedRecords(), learned) {
		t.Fatal("delayed durable selection changed after clean reopen")
	}
}

func reconnectFixtureIndex(t *testing.T, root, mode, name, body string) *yimecore.FileIndex {
	t.Helper()
	source := filepath.Join(root, name+".dict.yaml")
	if err := os.WriteFile(source, []byte("---\nname: "+name+"\n...\n"+body), 0o600); err != nil {
		t.Fatal(err)
	}
	indexPath := filepath.Join(root, name+".yidx")
	if _, err := yimecore.BuildIndexFile(mode, source, indexPath); err != nil {
		t.Fatal(err)
	}
	index, err := yimecore.OpenFileIndex(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })
	return index
}

type reconnectSession struct {
	t          *testing.T
	dispatcher *Dispatcher
	client     TrustedClient
	id         string
	sequence   uint64
}

func newReconnectSession(t *testing.T, mode string, bundle *yimecore.BundleIndex, model *yimecore.UserModel) *reconnectSession {
	t.Helper()
	// These semantic lifecycle checks include real journal Sync and race
	// instrumentation on shared CI runners. Keep a bounded fixture budget,
	// separate from the production 50ms interactive deadline; dedicated
	// dispatcher timeout/eviction tests retain their short explicit deadlines.
	const operationBudget = 5 * time.Second
	dispatcher, err := NewModeDispatcher(mode, func(requestedMode string) (engineapi.Engine, error) {
		if requestedMode != mode {
			return nil, fmt.Errorf("unexpected fixture mode %q", requestedMode)
		}
		return yimecore.NewBundleEngineWithUserModel(bundle, 9, model)
	}, Config{OperationTimeout: operationBudget})
	if err != nil {
		t.Fatal(err)
	}
	session := &reconnectSession{t: t, dispatcher: dispatcher, client: TrustedClient{ID: "reconnect-synthetic-client"}}
	// HandleJSON must retain strict decoding, rather than accepting a typed
	// request that bypasses the wire's unknown-field boundary.
	rejected := session.decode(dispatcher.HandleJSON(context.Background(), session.client,
		[]byte(`{"version":1,"sequence":1,"operation":"open","unreviewed_module":"forged"}`)))
	if rejected.Error == nil || rejected.Error.Code != CodeInvalidRequest || dispatcher.ActiveSessions() != 0 {
		t.Fatal("strict protocol accepted an undeclared module field")
	}
	opened := session.request(Request{Operation: OpenSession, Mode: mode, CandidateLimit: 5})
	if opened.SessionID == "" {
		t.Fatal("synthetic session has no identity")
	}
	session.id = opened.SessionID
	t.Cleanup(func() { dispatcher.CloseSession(session.client, session.id) })
	return session
}

func (s *reconnectSession) decode(data []byte) Response {
	s.t.Helper()
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var response Response
	if err := decoder.Decode(&response); err != nil {
		s.t.Fatal(err)
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		s.t.Fatal("response contained trailing JSON data")
	}
	return response
}

func (s *reconnectSession) request(request Request) Response {
	s.t.Helper()
	s.sequence++
	request.Version, request.Sequence, request.SessionID = ProtocolVersion, s.sequence, s.id
	data, err := EncodeRequest(request)
	if err != nil {
		s.t.Fatal(err)
	}
	response := s.decode(s.dispatcher.HandleJSON(context.Background(), s.client, data))
	if response.Error != nil || response.Version != ProtocolVersion || response.Sequence != s.sequence {
		s.t.Fatalf("synthetic protocol operation %s failed: %+v", request.Operation, response.Error)
	}
	return response
}

func (s *reconnectSession) event(event engineapi.Event) engineapi.Result {
	s.t.Helper()
	response := s.request(Request{Operation: ApplyEvent, Event: event})
	if response.Result == nil {
		s.t.Fatal("synthetic apply response has no result")
	}
	return *response.Result
}

func (s *reconnectSession) input(code string) engineapi.State {
	s.t.Helper()
	s.request(Request{Operation: ResetSession})
	var result engineapi.Result
	for _, key := range code {
		result = s.event(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if result.Commit != "" {
			s.t.Fatal("unconfirmed synthetic input unexpectedly committed")
		}
	}
	return result.State
}

func (s *reconnectSession) pages(state engineapi.State) []engineapi.Candidate {
	s.t.Helper()
	var candidates []engineapi.Candidate
	for page := 0; page < 10; page++ {
		candidates = append(candidates, state.Candidates...)
		if !state.HasNext {
			return candidates
		}
		state = s.event(engineapi.Event{Operation: engineapi.PageNext}).State
	}
	s.t.Fatal("synthetic paging did not terminate")
	return nil
}

func (s *reconnectSession) find(state engineapi.State, text string) engineapi.Candidate {
	s.t.Helper()
	for page := 0; page < 10; page++ {
		if matches := reconnectMatches(state.Candidates, text); len(matches) == 1 {
			return matches[0]
		}
		if !state.HasNext {
			break
		}
		state = s.event(engineapi.Event{Operation: engineapi.PageNext}).State
	}
	s.t.Fatal("synthetic target is not reachable")
	return engineapi.Candidate{}
}

func (s *reconnectSession) close() {
	s.t.Helper()
	s.request(Request{Operation: CloseSession})
	if s.dispatcher.ActiveSessions() != 0 {
		s.t.Fatal("synthetic session was not released")
	}
}

func reconnectMatches(candidates []engineapi.Candidate, text string) []engineapi.Candidate {
	var matches []engineapi.Candidate
	for _, candidate := range candidates {
		if candidate.Text == text {
			matches = append(matches, candidate)
		}
	}
	return matches
}
