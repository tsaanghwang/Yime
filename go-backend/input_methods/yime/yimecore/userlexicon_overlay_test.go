package yimecore

import (
	"os"
	"path/filepath"
	"testing"
)

func TestTrialUserLexiconIsLoadedByNewSessions(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "system.dict.yaml")
	if err := os.WriteFile(dictionary, []byte("---\nname: test\n...\n"+
		"系统词一\tab\t10\n系统词二\tab\t9\n系统词三\tab\t8\n"+
		"系统词四\tab\t7\n系统词五\tab\t6\n系统词六\tab\t5\n"+
		"系统词七\tab\t4\n系统词八\tab\t3\n系统词九\tab\t2\n系统词十\tab\t1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	indexPath := filepath.Join(root, "variable.yidx")
	if _, err := BuildIndexFile("variable", dictionary, indexPath); err != nil {
		t.Fatal(err)
	}
	index, err := OpenFileIndex(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	defer index.Close()

	lexiconPath := filepath.Join(root, "custom_phrase_variable.txt")
	if err := os.WriteFile(lexiconPath, []byte("# trial user lexicon\n用户词\tab\t9999\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	engine, err := NewFileEngineWithUserLexicon(index, 9, lexiconPath, nil)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	if len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "用户词" {
		t.Fatalf("trial user lexicon did not lead the new session: %+v", result.State.Candidates)
	}

	if err := os.WriteFile(lexiconPath, []byte("# cleared\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	newEngine, err := NewFileEngineWithUserLexicon(index, 9, lexiconPath, nil)
	if err != nil {
		t.Fatal(err)
	}
	newResult := applyCode(t, newEngine, "ab")
	if len(newResult.State.Candidates) == 0 || newResult.State.Candidates[0].Text != "系统词一" {
		t.Fatalf("new session did not adopt cleared user lexicon: %+v", newResult.State.Candidates)
	}
}
