package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestGenerationCloneReplaysJournalWithoutChangingFixture(t *testing.T) {
	state := t.TempDir()
	model := filepath.Join(state, "user-model", "installed-v1")
	snapshot := filepath.Join(model, "user-model.json")
	store, err := yimebroker.OpenDurableUserModel(yimebroker.DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: filepath.Join(model, "user-model.journal"), SourceID: normalNamespace,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	index, err := yimecore.NewIndex([]yimecore.Entry{{Text: "测试", Code: "ab", Weight: 1}})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := yimecore.NewEngineWithUserModel(index, 9, store.Model())
	if err != nil {
		t.Fatal(err)
	}
	var result engineapi.Result
	for _, key := range "ab" {
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	if _, err := engine.Select(result.State.Candidates[0].ID); err != nil {
		t.Fatal(err)
	}
	// No checkpoint: the fixture result must come from journal replay.
	if _, err := os.Stat(snapshot); !os.IsNotExist(err) {
		t.Fatalf("unexpected checkpoint: %v", err)
	}
	before, err := stateHashes(model)
	if err != nil {
		t.Fatal(err)
	}
	got, err := generationClone(state, t.TempDir())
	if err != nil || got != 1 {
		t.Fatalf("generation=%d error=%v", got, err)
	}
	after, err := stateHashes(model)
	if err != nil || !sameRecords(before, after) {
		t.Fatalf("original model changed: %v", err)
	}
}
