package yimebroker

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestMultiModeDurableLearningPersistsAcrossAllModes(t *testing.T) {
	root := t.TempDir()
	fixtures := buildModeManagerFixtures(t, root)
	snapshot := filepath.Join(root, "user-model.json")
	journal := filepath.Join(root, "user-model.journal")
	const sourceID = "e6c-three-mode-user-model"

	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: sourceID, CheckpointEvery: 1000,
	})
	if err != nil {
		t.Fatal(err)
	}
	manager := openLearningModeManager(t, fixtures, store.Model())
	targets := make(map[string]string, len(fixtures))
	for _, mode := range supportedIndexModes {
		engine, err := manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		state := applyBrokerCode(t, engine, fixtures[mode].code)
		if len(state.Candidates) < 2 {
			t.Fatalf("%s learning fixture has %d candidates", mode, len(state.Candidates))
		}
		targets[mode] = state.Candidates[1].Text
		for selection := 0; selection < 2; selection++ {
			state = applyBrokerCode(t, engine, fixtures[mode].code)
			candidate := candidateByText(state.Candidates, targets[mode])
			if candidate == nil {
				t.Fatalf("%s target %q disappeared", mode, targets[mode])
			}
			selector := engine.(interface {
				SelectIdempotent(string, string) (engineapi.Result, error)
			})
			if result, selectErr := selector.SelectIdempotent(candidate.ID, "e6c-"+mode+"-selection-"+string(rune('0'+selection))); selectErr != nil || result.Commit != targets[mode] {
				t.Fatalf("%s durable selection result=%+v err=%v", mode, result, selectErr)
			}
		}
		_ = engine.(interface{ Close() error }).Close()
	}
	if got := store.Model().Generation(); got != 6 {
		t.Fatalf("shared model generation = %d, want 6", got)
	}
	if err := manager.Close(); err != nil {
		t.Fatal(err)
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}

	reopened, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: sourceID, CheckpointEvery: 1000,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	restartedManager := openLearningModeManager(t, fixtures, reopened.Model())
	defer restartedManager.Close()
	for _, mode := range supportedIndexModes {
		engine, err := restartedManager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		state := applyBrokerCode(t, engine, fixtures[mode].code)
		if len(state.Candidates) == 0 || state.Candidates[0].Text != targets[mode] || state.Candidates[0].Score.User <= 0 {
			t.Fatalf("%s recovered ranking = %+v, want learned %q first", mode, state.Candidates, targets[mode])
		}
		_ = engine.(interface{ Close() error }).Close()
	}
}

func TestModeIndexControlRejectsFailedSwitchAndRollsBackEachMode(t *testing.T) {
	root := t.TempDir()
	fixtures := buildModeManagerFixtures(t, root)
	initial := make(map[string]IndexSpec, len(fixtures))
	for mode, fixture := range fixtures {
		initial[mode] = IndexSpec{Version: "v1", Mode: mode, Path: fixture.path, ExpectedSHA256: fixture.hash}
	}
	manager, err := OpenModeIndexManager(initial, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	manifest := filepath.Join(root, "control.json")
	statusPath := filepath.Join(root, "status.json")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- WatchModeIndexControl(ctx, manifest, statusPath, manager, 10*time.Millisecond) }()
	waitModeControlStatus(t, statusPath, "startup")

	for _, mode := range supportedIndexModes {
		fixture := fixtures[mode]
		pinned, err := manager.NewEngine(mode)
		if err != nil {
			t.Fatal(err)
		}
		first := string(fixture.code[0])
		if result, applyErr := pinned.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: first}); applyErr != nil || result.State.RawInput != first {
			t.Fatalf("%s pinned composition result=%+v err=%v", mode, result, applyErr)
		}

		badID := "reject-" + mode
		writeModeControlRequest(t, manifest, IndexControlRequest{
			SchemaVersion: IndexControlSchema, RequestID: badID, Action: "swap",
			Index: &IndexSpec{Version: "bad", Mode: mode, Path: fixture.path, ExpectedSHA256: strings.Repeat("0", 64)},
		})
		bad := waitModeControlStatus(t, statusPath, badID)
		if bad.Accepted || bad.Manager.ActiveVersion != "v1" || bad.Managers[mode].ActiveVersion != "v1" {
			t.Fatalf("%s rejected switch status = %+v", mode, bad)
		}
		for _, code := range fixture.code[1:] {
			if _, applyErr := pinned.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(code)}); applyErr != nil {
				t.Fatal(applyErr)
			}
		}
		if pinned.(interface{ IndexVersion() string }).IndexVersion() != "v1" {
			t.Fatalf("%s active composition left original generation", mode)
		}

		swapID := "swap-" + mode
		writeModeControlRequest(t, manifest, IndexControlRequest{
			SchemaVersion: IndexControlSchema, RequestID: swapID, Action: "swap",
			Index: &IndexSpec{Version: "v2", Mode: mode, Path: fixture.path, ExpectedSHA256: fixture.hash},
		})
		if swapped := waitModeControlStatus(t, statusPath, swapID); !swapped.Accepted || swapped.Manager.ActiveVersion != "v2" {
			t.Fatalf("%s valid switch status = %+v", mode, swapped)
		}
		v2, err := manager.NewEngine(mode)
		if err != nil || v2.(interface{ IndexVersion() string }).IndexVersion() != "v2" {
			t.Fatalf("%s new session did not use v2: engine=%T err=%v", mode, v2, err)
		}

		rollbackID := "rollback-" + mode
		writeModeControlRequest(t, manifest, IndexControlRequest{
			SchemaVersion: IndexControlSchema, RequestID: rollbackID, Action: "rollback", Mode: mode,
		})
		if rollback := waitModeControlStatus(t, statusPath, rollbackID); !rollback.Accepted || rollback.Manager.ActiveVersion != "v1" || rollback.Manager.PreviousVersion != "v2" {
			t.Fatalf("%s rollback status = %+v", mode, rollback)
		}
		postRollback, err := manager.NewEngine(mode)
		if err != nil || postRollback.(interface{ IndexVersion() string }).IndexVersion() != "v1" || v2.(interface{ IndexVersion() string }).IndexVersion() != "v2" {
			t.Fatalf("%s rollback changed leased engines: post=%T v2=%T err=%v", mode, postRollback, v2, err)
		}
		_ = pinned.(interface{ Close() error }).Close()
		_ = v2.(interface{ Close() error }).Close()
		_ = postRollback.(interface{ Close() error }).Close()
	}
	cancel()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestResidentModeIndexManagerPreloadsAllThreeSystemIndexes(t *testing.T) {
	root := t.TempDir()
	fixtures := buildModeManagerFixtures(t, root)
	initial := make(map[string]IndexSpec, len(fixtures))
	for mode, fixture := range fixtures {
		initial[mode] = IndexSpec{Version: "v1", Mode: mode, Path: fixture.path, ExpectedSHA256: fixture.hash}
	}
	manager, err := OpenResidentModeIndexManager(initial, func(_ string, index *yimecore.FileIndex) (engineapi.Engine, error) {
		if index.StorageMode() != "resident" {
			return nil, fmt.Errorf("index storage mode = %q", index.StorageMode())
		}
		return yimecore.NewFileEngine(index, 9)
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	stats := manager.Stats()
	if len(stats) != len(supportedIndexModes) {
		t.Fatalf("manager stats = %+v", stats)
	}
	for _, mode := range supportedIndexModes {
		if stats[mode].LoadMode != "resident" || stats[mode].ActiveVersion != "v1" {
			t.Fatalf("%s resident stats = %+v", mode, stats[mode])
		}
		engine, openErr := manager.NewEngine(mode)
		if openErr != nil {
			t.Fatal(openErr)
		}
		_ = engine.(interface{ Close() error }).Close()
	}
}

type modeManagerFixture struct {
	path string
	hash string
	code string
}

func buildModeManagerFixtures(t *testing.T, root string) map[string]modeManagerFixture {
	t.Helper()
	codes := map[string]string{"full": "bjjj", "variable": "bj", "shorthand": "bk"}
	fixtures := make(map[string]modeManagerFixture, len(codes))
	for _, mode := range supportedIndexModes {
		code := codes[mode]
		source := filepath.Join(root, mode+".dict.yaml")
		contents := "# Rime dictionary\n---\nname: " + mode + "\n...\nfirst-" + mode + "\t" + code + "\t100\nlearned-" + mode + "\t" + code + "\t10\n"
		if err := os.WriteFile(source, []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(root, mode+".yidx")
		if _, err := yimecore.BuildIndexFile(mode, source, path); err != nil {
			t.Fatal(err)
		}
		hash, err := IndexFileSHA256(path)
		if err != nil {
			t.Fatal(err)
		}
		fixtures[mode] = modeManagerFixture{path: path, hash: hash, code: code}
	}
	return fixtures
}

func openLearningModeManager(t *testing.T, fixtures map[string]modeManagerFixture, model *yimecore.UserModel) *ModeIndexManager {
	t.Helper()
	initial := make(map[string]IndexSpec, len(fixtures))
	for mode, fixture := range fixtures {
		initial[mode] = IndexSpec{Version: "v1", Mode: mode, Path: fixture.path, ExpectedSHA256: fixture.hash}
	}
	manager, err := OpenModeIndexManager(initial, func(_ string, index *yimecore.FileIndex) (engineapi.Engine, error) {
		return yimecore.NewFileEngineWithUserModel(index, 9, model)
	}, nil)
	if err != nil {
		t.Fatal(err)
	}
	return manager
}

func applyBrokerCode(t *testing.T, engine engineapi.Engine, code string) engineapi.State {
	t.Helper()
	engine.Reset()
	var result engineapi.Result
	var err error
	for _, key := range code {
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result.State
}

func candidateByText(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for index := range candidates {
		if candidates[index].Text == text {
			return &candidates[index]
		}
	}
	return nil
}

func writeModeControlRequest(t *testing.T, path string, request IndexControlRequest) {
	t.Helper()
	data, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(data, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
}

func waitModeControlStatus(t *testing.T, path, requestID string) IndexControlStatus {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil {
			var status IndexControlStatus
			if json.Unmarshal(data, &status) == nil && status.RequestID == requestID {
				return status
			}
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("control status %q timed out", requestID)
	return IndexControlStatus{}
}
