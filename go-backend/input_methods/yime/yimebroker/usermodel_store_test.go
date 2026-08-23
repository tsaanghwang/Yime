package yimebroker

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestDurableUserModelRecoversJournalAndTruncatesTornTail(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "系统", Code: "a1", Weight: 1000},
		{Text: "学习", Code: "a1", Weight: 900},
	})
	if err != nil {
		t.Fatal(err)
	}
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "durable-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := yimecore.NewEngineWithUserModel(index, 9, store.Model())
	if err != nil {
		t.Fatal(err)
	}
	state := applyTestCode(t, engine, "a1")
	var target string
	for _, candidate := range state.Candidates {
		if candidate.Text == "学习" {
			target = candidate.ID
		}
	}
	if _, err := engine.Select(target); err != nil {
		t.Fatal(err)
	}
	if store.Stats().JournalGeneration != 1 {
		t.Fatalf("journal stats = %+v", store.Stats())
	}
	if err := store.abortForTest(); err != nil {
		t.Fatal(err)
	}
	if err := appendFile(journal, []byte(`{"schema_version":"partial`)); err != nil {
		t.Fatal(err)
	}

	recovered, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "durable-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	stats := recovered.Stats()
	if stats.RecoveredMutations != 1 || stats.TruncatedTailBytes == 0 || recovered.Model().Generation() != 1 {
		t.Fatalf("recovery stats = %+v generation=%d", stats, recovered.Model().Generation())
	}
	recoveredEngine, err := yimecore.NewEngineWithUserModel(index, 9, recovered.Model())
	if err != nil {
		t.Fatal(err)
	}
	if first := applyTestCode(t, recoveredEngine, "a1").Candidates[0].Text; first != "学习" {
		t.Fatalf("recovered ranking = %q", first)
	}
	if err := recovered.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestDurableUserModelRejectsCompleteJournalCorruption(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "corrupt-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	store.Model().SetMutationWriter(nil)
	store.Model().SetMutationWriter(store.persist)
	mutation := yimecore.UserMutation{Generation: 1, Kind: yimecore.UserMutationSelect, Code: "a1", Text: "候选"}
	if err := store.persist(mutation); err != nil {
		t.Fatal(err)
	}
	if err := store.abortForTest(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(journal)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)/2] ^= 1
	if err := os.WriteFile(journal, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenDurableUserModel(DurableUserModelConfig{SnapshotPath: snapshot, JournalPath: journal, SourceID: "corrupt-test"}); !errors.Is(err, ErrCorruptUserJournal) {
		t.Fatalf("corrupt journal error = %v", err)
	}
}

func applyTestCode(t *testing.T, engine engineapi.Engine, code string) engineapi.State {
	t.Helper()
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result.State
}

func appendFile(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	return file.Sync()
}
