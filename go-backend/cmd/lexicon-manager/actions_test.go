//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/runtimechange"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
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
	oldNotify := notifyRuntimeChange
	invokeRimeBuild = func(gotUserDir, gotSharedDir string) error {
		called++
		if gotUserDir != userDir || gotSharedDir != sharedDir {
			t.Fatalf("unexpected build args userDir=%q sharedDir=%q", gotUserDir, gotSharedDir)
		}
		return nil
	}
	notified := 0
	notifyRuntimeChange = func(gotUserDir, scope string, requiresRedeploy bool) (runtimechange.Event, error) {
		notified++
		if gotUserDir != userDir || scope != runtimechange.ScopeLexicon || !requiresRedeploy {
			t.Fatalf("unexpected notification userDir=%q scope=%q redeploy=%t", gotUserDir, scope, requiresRedeploy)
		}
		return runtimechange.Event{}, nil
	}
	defer func() {
		invokeRimeBuild = oldInvoke
		notifyRuntimeChange = oldNotify
	}()

	if err := state.rebuildAndDeployAllLexicons(); err != nil {
		t.Fatalf("rebuildAndDeployAllLexicons failed: %v", err)
	}
	if called != 1 {
		t.Fatalf("expected invokeRimeBuild to be called once, got %d", called)
	}
	if notified != 1 {
		t.Fatalf("expected one runtime notification, got %d", notified)
	}
}

func TestRebuildAndDeployDoesNotNotifyAfterBuildFailure(t *testing.T) {
	state := &appState{userDir: t.TempDir(), sharedDir: t.TempDir(), sourcePath: filepath.Join(t.TempDir(), "missing.txt")}
	oldNotify := notifyRuntimeChange
	notifyRuntimeChange = func(string, string, bool) (runtimechange.Event, error) {
		t.Fatal("runtime notification must not run after rebuild failure")
		return runtimechange.Event{}, nil
	}
	defer func() { notifyRuntimeChange = oldNotify }()
	if err := state.rebuildAndDeployAllLexicons(); err == nil {
		t.Fatal("expected rebuild failure")
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

func TestValidateEntryForAddRejectsSystemPhraseBeforePinyinValidation(t *testing.T) {
	sharedDir := t.TempDir()
	if err := os.WriteFile(
		filepath.Join(sharedDir, "yime_variable.dict.yaml"),
		[]byte("name: test\n...\n中国\tzhongguo\t100\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}

	state := &appState{
		sharedDir: sharedDir,
		userDir:   t.TempDir(),
		mode:      reverselookup.ModeVariable,
	}
	err := state.validateEntryForAdd(userlexicon.Entry{
		Phrase: "中国",
		Pinyin: "not-valid-pinyin",
		Weight: "100",
	})
	if !errors.Is(err, errPhraseInSystemLexicon) {
		t.Fatalf("expected system lexicon duplicate error, got %v", err)
	}
}

func TestBuildImportTemplateCopiesHeaderAndFirstThreeEntries(t *testing.T) {
	sourcePath := filepath.Join(t.TempDir(), userlexicon.SourceFileName)
	source := strings.Join([]string{
		"# header one",
		"# header two",
		"one\tone1\t100",
		"two\ttwo1\t200",
		"three\tthree1\t300",
		"four\tfour1\t400",
	}, "\n") + "\n"
	if err := os.WriteFile(sourcePath, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := buildImportTemplateContent(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	content := string(got)
	for _, expected := range []string{"# header one", "# header two", "one\tone1\t100", "two\ttwo1\t200", "three\tthree1\t300"} {
		if !strings.Contains(content, expected) {
			t.Fatalf("template missing %q: %q", expected, content)
		}
	}
	if strings.Contains(content, "four\tfour1\t400") {
		t.Fatalf("template must not copy the fourth entry: %q", content)
	}
}

func TestImportFileMatchesTemplateIgnoresLineEndingChanges(t *testing.T) {
	path := filepath.Join(t.TempDir(), userlexicon.SourceFileName)
	if err := os.WriteFile(path, []byte("# header\r\none\tone1\t100\r\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !importFileMatchesTemplate(path, []byte("# header\none\tone1\t100\n")) {
		t.Fatal("equivalent template content should be recognized")
	}
	if err := os.WriteFile(path, []byte("# header\r\none\tone1\t100\r\nnew\tnew1\t100\r\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if importFileMatchesTemplate(path, []byte("# header\none\tone1\t100\n")) {
		t.Fatal("a template with appended entries must be importable")
	}
}
