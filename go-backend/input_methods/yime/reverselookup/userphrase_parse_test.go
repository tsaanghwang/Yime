package reverselookup

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseUserPhraseFieldsAcceptsYimeCodeColumn(t *testing.T) {
	codeMap := map[string]CodeRecord{
		"zhong1": {Variable: "a", Full: "aa", Shorthand: "a"},
		"guo2":   {Variable: "b", Full: "bb", Shorthand: "b"},
	}
	phrase, pinyin, ok := ParseUserPhraseFields([]string{"中国", "ab"}, codeMap, ModeVariable)
	if !ok || phrase != "中国" || pinyin != "zhong1 guo2" {
		t.Fatalf("expected code column to decode, got ok=%v phrase=%q pinyin=%q", ok, phrase, pinyin)
	}
}

func TestResolveDictPathPrefersSharedDir(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	dict := []byte("name: test\n...\n巴\tsdf\n")
	sharedPath := filepath.Join(sharedDir, "yime_variable.dict.yaml")
	if err := os.WriteFile(sharedPath, dict, 0o644); err != nil {
		t.Fatal(err)
	}
	got := resolveDictPath(sharedDir, userDir, "yime_variable")
	if got != sharedPath {
		t.Fatalf("expected shared dict path %q, got %q", sharedPath, got)
	}
}
