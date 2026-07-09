package userblocklist

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadWriteAndFilterBlocklist(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, SourceFileName)

	if err := WritePhrases(path, []string{"走了吗", "测试词"}); err != nil {
		t.Fatal(err)
	}
	entries, err := LoadEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %#v", entries)
	}

	set, err := LoadSet(path)
	if err != nil {
		t.Fatal(err)
	}
	if !IsBlocked(set, "走了吗") || IsBlocked(set, "中国") {
		t.Fatalf("unexpected block set %#v", set)
	}

	filtered := FilterEntries(entries, "测试")
	if len(filtered) != 1 || filtered[0].Phrase != "测试词" {
		t.Fatalf("unexpected filtered %#v", filtered)
	}
}

func TestUpsertAndRemovePhrases(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, SourceFileName)
	if err := EnsureSourceFile(path); err != nil {
		t.Fatal(err)
	}
	if _, err := UpsertPhrase(path, "屏蔽词"); err != nil {
		t.Fatal(err)
	}
	updated, err := UpsertPhrase(path, "屏蔽词")
	if err != nil || !updated {
		t.Fatalf("expected duplicate upsert, got updated=%v err=%v", updated, err)
	}
	if err := RemovePhrases(path, []string{"屏蔽词"}); err != nil {
		t.Fatal(err)
	}
	entries, err := LoadEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Fatalf("expected empty list, got %#v", entries)
	}
}

func TestImportPhrasesSkipsInvalidAndDuplicates(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, SourceFileName)
	if err := WritePhrases(path, []string{"已有词"}); err != nil {
		t.Fatal(err)
	}
	added, skipped, err := ImportPhrases(path, []string{"新词", "已有词", " ", "另一词"})
	if err != nil {
		t.Fatal(err)
	}
	if added != 2 || skipped != 2 {
		t.Fatalf("expected added=2 skipped=2, got added=%d skipped=%d", added, skipped)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "新词") || !strings.Contains(string(data), "另一词") {
		t.Fatalf("unexpected file content %q", string(data))
	}
}
