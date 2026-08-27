package learningmanager

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestStoppedLearningRoundTripAndClear(t *testing.T) {
	stateRoot := t.TempDir()
	const version = "layout-test"
	paths, err := ModelPaths(stateRoot, version)
	if err != nil {
		t.Fatal(err)
	}
	sourceID, _ := ModelSourceID(version)
	model, err := yimecore.OpenUserModel(paths.Snapshot, sourceID)
	if err != nil {
		t.Fatal(err)
	}
	if err := model.ApplyRecoveredMutation(yimecore.UserMutation{Generation: 1, Kind: yimecore.UserMutationSelect, Code: "abcd", Text: "新词"}); err != nil {
		t.Fatal(err)
	}
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths.Journal, []byte("superseded"), 0o600); err != nil {
		t.Fatal(err)
	}
	backup := filepath.Join(t.TempDir(), "backup.json")
	if err := ExportStopped(stateRoot, version, backup); err != nil {
		t.Fatal(err)
	}
	if err := ClearStopped(stateRoot, version); err != nil {
		t.Fatal(err)
	}
	if records, err := RecordsStopped(stateRoot, version); err != nil || len(records) != 0 {
		t.Fatalf("cleared records=%#v err=%v", records, err)
	}
	if _, err := os.Stat(paths.Journal); !os.IsNotExist(err) {
		t.Fatalf("journal survived clear: %v", err)
	}
	if err := ImportStopped(stateRoot, version, backup); err != nil {
		t.Fatal(err)
	}
	if records, err := RecordsStopped(stateRoot, version); err != nil || len(records) != 1 || records[0].Text != "新词" {
		t.Fatalf("imported records=%#v err=%v", records, err)
	}
}

func TestScanStoppedReportsOnlyFrequentNonSystemEntries(t *testing.T) {
	stateRoot := t.TempDir()
	const version = "installed-v1"
	paths, _ := ModelPaths(stateRoot, version)
	sourceID, _ := ModelSourceID(version)
	model, err := yimecore.OpenUserModel(paths.Snapshot, sourceID)
	if err != nil {
		t.Fatal(err)
	}
	mutations := []yimecore.UserMutation{
		{Generation: 1, Kind: yimecore.UserMutationSelect, Code: "aa", Text: "系统词"},
		{Generation: 2, Kind: yimecore.UserMutationSelect, Code: "bb", Text: "新词"},
		{Generation: 3, Kind: yimecore.UserMutationSelect, Code: "bb", Text: "新词"},
	}
	for _, mutation := range mutations {
		if err := model.ApplyRecoveredMutation(mutation); err != nil {
			t.Fatal(err)
		}
	}
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "system.dict.yaml")
	indexPath := filepath.Join(t.TempDir(), "variable.yidx")
	if err := os.WriteFile(source, []byte("---\nname: system\nversion: \"1\"\n...\n系统词\taa\t10\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", source, indexPath); err != nil {
		t.Fatal(err)
	}
	result, err := ScanStopped(stateRoot, version, indexPath, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(result) != 1 || result[0] != (Promotion{Code: "bb", Text: "新词", Selections: 2}) {
		t.Fatalf("promotions=%#v", result)
	}
}
