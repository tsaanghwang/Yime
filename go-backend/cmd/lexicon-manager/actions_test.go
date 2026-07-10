//go:build windows

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
)

func TestRebuildAllLexiconsWritesAllModes(t *testing.T) {
	userDir := t.TempDir()
	sourcePath := filepath.Join(userDir, "yime_user_phrases.txt")
	if err := os.WriteFile(sourcePath, []byte("中国\tzhong1 guo2\t1000000\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	state := &appState{
		userDir:         userDir,
		sourcePath:      sourcePath,
		rimeLexiconPath: filepath.Join(userDir, "custom_phrase_variable.txt"),
		codeMap: map[string]reverselookup.CodeRecord{
			"zhong1": {Variable: "zv", Full: "zf", Shorthand: "zs"},
			"guo2":   {Variable: "gv", Full: "gf", Shorthand: "gs"},
		},
	}

	if err := state.rebuildAllLexicons(); err != nil {
		t.Fatalf("rebuildAllLexicons failed: %v", err)
	}

	seen := map[string]string{}
	for _, mode := range []string{"variable", "full", "shorthand"} {
		path := filepath.Join(userDir, "custom_phrase_"+mode+".txt")
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s failed: %v", path, err)
		}
		content := string(data)
		if !strings.Contains(content, "中国") {
			t.Fatalf("%s missing phrase: %q", path, content)
		}
		seen[mode] = content
	}

	if seen["variable"] == seen["full"] || seen["variable"] == seen["shorthand"] || seen["full"] == seen["shorthand"] {
		t.Fatalf("expected different generated codes per mode, got %#v", seen)
	}
}

func TestRebuildAndDeployAllLexiconsInvokesRimeBuild(t *testing.T) {
	userDir := t.TempDir()
	sharedDir := t.TempDir()
	sourcePath := filepath.Join(userDir, "yime_user_phrases.txt")
	if err := os.WriteFile(sourcePath, []byte("中国\tzhong1 guo2\t1000000\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	state := &appState{
		userDir:         userDir,
		sharedDir:       sharedDir,
		sourcePath:      sourcePath,
		rimeLexiconPath: filepath.Join(userDir, "custom_phrase_variable.txt"),
		codeMap: map[string]reverselookup.CodeRecord{
			"zhong1": {Variable: "zv", Full: "zf", Shorthand: "zs"},
			"guo2":   {Variable: "gv", Full: "gf", Shorthand: "gs"},
		},
	}

	called := 0
	oldInvoke := invokeRimeBuild
	invokeRimeBuild = func(gotUserDir, gotSharedDir string) error {
		called++
		if gotUserDir != userDir || gotSharedDir != sharedDir {
			t.Fatalf("unexpected build args userDir=%q sharedDir=%q", gotUserDir, gotSharedDir)
		}
		return nil
	}
	defer func() { invokeRimeBuild = oldInvoke }()

	if err := state.rebuildAndDeployAllLexicons(); err != nil {
		t.Fatalf("rebuildAndDeployAllLexicons failed: %v", err)
	}
	if called != 1 {
		t.Fatalf("expected invokeRimeBuild to be called once, got %d", called)
	}
}

func TestIsSystemLexiconPhrase(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	dictPath := filepath.Join(sharedDir, "yime_variable.dict.yaml")
	content := "name: test\n...\n中国\tzhongguo\t100\n自定义\tzidingyi\t50\n"
	if err := os.WriteFile(dictPath, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	state := &appState{
		sharedDir: sharedDir,
		userDir:   userDir,
		mode:      reverselookup.ModeVariable,
	}

	ok, err := state.isSystemLexiconPhrase("中国")
	if err != nil {
		t.Fatalf("isSystemLexiconPhrase returned error: %v", err)
	}
	if !ok {
		t.Fatal("expected phrase to exist in system lexicon")
	}

	ok, err = state.isSystemLexiconPhrase("不存在")
	if err != nil {
		t.Fatalf("isSystemLexiconPhrase returned error: %v", err)
	}
	if ok {
		t.Fatal("expected phrase to be absent from system lexicon")
	}
}
