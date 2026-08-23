package userlexicon

import (
	"os"
	"path/filepath"
	"testing"
)

func TestMergeSourceEntriesAppliesBatchWithLastWriteWins(t *testing.T) {
	current := []Entry{
		{Phrase: "甲", Pinyin: "jia3", Weight: "1"},
		{Phrase: "乙", Pinyin: "yi3", Weight: "2"},
	}
	imported := []Entry{
		{Phrase: "乙", Pinyin: "yi4", Weight: "3"},
		{Phrase: "丙", Pinyin: "bing3", Weight: "4"},
		{Phrase: "乙", Pinyin: "yi3", Weight: "5"},
	}

	got := MergeSourceEntries(current, imported)
	if len(got) != 3 {
		t.Fatalf("expected three merged rows, got %#v", got)
	}
	if got[0].Phrase != "甲" || got[1].Phrase != "乙" || got[1].Weight != "5" || got[2].Phrase != "丙" {
		t.Fatalf("unexpected merge result: %#v", got)
	}
}

func TestValidateImportFileRejectsOversizedInputBeforeParsing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "large.tsv")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(MaxImportFileSize + 1); err != nil {
		file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	if err := ValidateImportFile(path); err == nil {
		t.Fatal("expected oversized import to be rejected")
	}
}

func TestWriteSourceEntriesReplacesWholeBatch(t *testing.T) {
	path := filepath.Join(t.TempDir(), SourceFileName)
	want := []Entry{{Phrase: "测试", Pinyin: "ce4 shi4", Weight: "9"}}
	if err := WriteSourceEntries(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := LoadSourceEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Phrase != want[0].Phrase || got[0].Weight != want[0].Weight {
		t.Fatalf("unexpected persisted rows: %#v", got)
	}
}
