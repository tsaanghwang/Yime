package yimebroker

import (
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestIndexManagerKeepsExistingSessionAndRollsBackTransactionally(t *testing.T) {
	indexPath, hash := buildManagerFixture(t)
	validator := func(engine engineapi.Engine) error {
		_, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "a"})
		return err
	}
	manager, err := OpenIndexManager(IndexSpec{Version: "v1", Mode: "full", Path: indexPath, ExpectedSHA256: hash}, nil, validator)
	if err != nil {
		t.Fatal(err)
	}
	oldEngine, err := manager.NewEngine()
	if err != nil {
		t.Fatal(err)
	}
	if version := oldEngine.(interface{ IndexVersion() string }).IndexVersion(); version != "v1" {
		t.Fatalf("old version = %q", version)
	}
	if err := manager.Swap(IndexSpec{Version: "v2", Mode: "full", Path: indexPath, ExpectedSHA256: hash}); err != nil {
		t.Fatal(err)
	}
	newEngine, err := manager.NewEngine()
	if err != nil {
		t.Fatal(err)
	}
	if version := newEngine.(interface{ IndexVersion() string }).IndexVersion(); version != "v2" {
		t.Fatalf("new version = %q", version)
	}
	if _, err := oldEngine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "a"}); err != nil {
		t.Fatal(err)
	}
	if result, err := oldEngine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "1"}); err != nil || result.State.RawInput != "a1" {
		t.Fatalf("old session after switch result=%+v err=%v", result, err)
	}
	if err := manager.Swap(IndexSpec{Version: "bad", Mode: "full", Path: indexPath, ExpectedSHA256: strings.Repeat("0", 64)}); err == nil {
		t.Fatal("invalid hash switch unexpectedly succeeded")
	}
	if stats := manager.Stats(); stats.ActiveVersion != "v2" || stats.Rejected != 1 {
		t.Fatalf("rejected switch changed active state: %+v", stats)
	}
	if err := manager.Rollback(); err != nil {
		t.Fatal(err)
	}
	if stats := manager.Stats(); stats.ActiveVersion != "v1" || stats.PreviousVersion != "v2" || stats.Rollbacks != 1 || stats.ActiveSessions != 2 {
		t.Fatalf("rollback stats = %+v", stats)
	}
	_ = oldEngine.(interface{ Close() error }).Close()
	_ = newEngine.(interface{ Close() error }).Close()
	if stats := manager.Stats(); stats.ActiveSessions != 0 {
		t.Fatalf("session references leaked: %+v", stats)
	}
	if err := manager.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestResidentIndexManagerKeepsFullLoadPolicyAcrossSwapAndRollback(t *testing.T) {
	indexPath, hash := buildManagerFixture(t)
	observedModes := make([]string, 0, 3)
	builder := func(index *yimecore.FileIndex) (engineapi.Engine, error) {
		observedModes = append(observedModes, index.StorageMode())
		return yimecore.NewFileEngine(index, 9)
	}
	manager, err := OpenResidentIndexManager(
		IndexSpec{Version: "v1", Mode: "full", Path: indexPath, ExpectedSHA256: hash}, builder, nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	v1, err := manager.NewEngine()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.Swap(IndexSpec{Version: "v2", Mode: "full", Path: indexPath, ExpectedSHA256: hash}); err != nil {
		t.Fatal(err)
	}
	v2, err := manager.NewEngine()
	if err != nil {
		t.Fatal(err)
	}
	if err := manager.Rollback(); err != nil {
		t.Fatal(err)
	}
	post, err := manager.NewEngine()
	if err != nil {
		t.Fatal(err)
	}
	if len(observedModes) != 3 {
		t.Fatalf("builder calls = %d, want 3", len(observedModes))
	}
	for index, mode := range observedModes {
		if mode != "resident" {
			t.Fatalf("builder call %d storage mode = %q", index, mode)
		}
	}
	if stats := manager.Stats(); stats.LoadMode != "resident" || stats.ActiveVersion != "v1" || stats.PreviousVersion != "v2" {
		t.Fatalf("resident rollback stats = %+v", stats)
	}
	_ = v1.(interface{ Close() error }).Close()
	_ = v2.(interface{ Close() error }).Close()
	_ = post.(interface{ Close() error }).Close()
}

func TestDispatcherReleasesManagedIndexSessionOnCloseAndLateTimeout(t *testing.T) {
	indexPath, hash := buildManagerFixture(t)
	manager, err := OpenIndexManager(IndexSpec{Version: "v1", Mode: "full", Path: indexPath, ExpectedSHA256: hash}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	dispatcher, err := NewDispatcher(manager.NewEngine, Config{OperationTimeout: 5 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	client := TrustedClient{ID: "managed"}
	limited := dispatch(t, dispatcher, client, Request{
		Version: 1, Sequence: 1, Operation: OpenSession, CandidateLimit: 5,
	})
	if limited.Error != nil {
		t.Fatalf("managed session rejected candidate limit: %+v", limited)
	}
	closedLimited := dispatch(t, dispatcher, client, Request{
		Version: 1, Sequence: 2, SessionID: limited.SessionID, Operation: CloseSession,
	})
	if closedLimited.Error != nil || manager.Stats().ActiveSessions != 0 {
		t.Fatalf("limited managed session leaked: %+v stats=%+v", closedLimited, manager.Stats())
	}
	sessionID := openSession(t, dispatcher, client)
	response := dispatch(t, dispatcher, client, Request{Version: 1, Sequence: 2, SessionID: sessionID, Operation: CloseSession})
	if response.Error != nil || manager.Stats().ActiveSessions != 0 {
		t.Fatalf("closed managed session = %+v stats=%+v", response, manager.Stats())
	}

	blockingManager := &blockingManagedFactory{release: make(chan struct{})}
	timeoutDispatcher, err := NewDispatcher(blockingManager.newEngine, Config{OperationTimeout: 5 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	timeoutSession := openSession(t, timeoutDispatcher, TrustedClient{ID: "timeout"})
	timedOut := dispatch(t, timeoutDispatcher, TrustedClient{ID: "timeout"}, Request{Version: 1, Sequence: 2, SessionID: timeoutSession, Operation: ResetSession})
	if timedOut.Error == nil || timedOut.Error.Code != CodeTimeout {
		t.Fatalf("timeout response = %+v", timedOut)
	}
	close(blockingManager.release)
	deadline := time.Now().Add(time.Second)
	for blockingManager.closed.Load() == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if blockingManager.closed.Load() != 1 {
		t.Fatal("late timed-out engine was not closed")
	}
	_ = manager.Close()
}

type blockingManagedFactory struct {
	release chan struct{}
	closed  atomic.Int32
}

func (f *blockingManagedFactory) newEngine() (engineapi.Engine, error) {
	return &blockingManagedEngine{factory: f}, nil
}

type blockingManagedEngine struct{ factory *blockingManagedFactory }

func (e *blockingManagedEngine) Apply(engineapi.Event) (engineapi.Result, error) {
	return e.Reset(), nil
}
func (e *blockingManagedEngine) Select(string) (engineapi.Result, error) { return e.Reset(), nil }
func (e *blockingManagedEngine) Reset() engineapi.Result {
	<-e.factory.release
	return engineapi.Result{}
}
func (e *blockingManagedEngine) Close() error {
	e.factory.closed.Add(1)
	return nil
}

func buildManagerFixture(t *testing.T) (string, string) {
	t.Helper()
	directory := t.TempDir()
	source := filepath.Join(directory, "fixture.dict.yaml")
	content := "# Rime dictionary\n---\nname: fixture\n...\n一\ta1\t100\n二\ta2\t90\n"
	if err := os.WriteFile(source, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	indexPath := filepath.Join(directory, "fixture.yidx")
	if _, err := yimecore.BuildIndexFile("full", source, indexPath); err != nil {
		t.Fatal(err)
	}
	hash, err := hashIndexFile(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	return indexPath, hash
}
