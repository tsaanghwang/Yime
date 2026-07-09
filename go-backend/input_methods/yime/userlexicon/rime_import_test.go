package userlexicon

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
)

func TestHydrateSourceIfEmptyImportsFromRimeLexicon(t *testing.T) {
	userDir := t.TempDir()
	codeMap := map[string]reverselookup.CodeRecord{
		"zhong1": {Variable: "a", Full: "aa", Shorthand: "a"},
		"guo2":   {Variable: "b", Full: "bb", Shorthand: "b"},
	}
	rimePath := RimeLexiconPath(userDir, "variable")
	if err := os.WriteFile(rimePath, []byte("中国\tab\t1000000\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	hydrated, err := HydrateSourceIfEmpty(userDir, reverselookup.ModeVariable, codeMap)
	if err != nil {
		t.Fatal(err)
	}
	if !hydrated {
		t.Fatal("expected hydration from Rime lexicon")
	}
	entries, err := LoadSourceEntries(filepath.Join(userDir, SourceFileName))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Phrase != "中国" || entries[0].Pinyin != "zhong1 guo2" {
		t.Fatalf("unexpected hydrated entries: %#v", entries)
	}
}
