package systemlexicon

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeriveFromFullDictionaryGeneratesThreeModes(t *testing.T) {
	// The fixture is generated independently by the canonical Python semantic
	// pipeline, so this tests current projection without deriving expectations
	// through the same Go implementation under test.
	data, err := os.ReadFile("../codemode/testdata/canonical_syllables.json")
	if err != nil {
		t.Fatal(err)
	}
	type syllable struct{ Pinyin, Full, Variable, Shorthand string }
	var fixture struct {
		Syllables []syllable `json:"syllables"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	byPinyin := map[string]syllable{}
	for _, row := range fixture.Syllables {
		byPinyin[row.Pinyin] = row
	}
	a, ba := byPinyin["a2"], byPinyin["ba1"]
	if len(a.Full) != 4 || len(ba.Full) != 4 || a.Variable == "" || a.Shorthand == "" || ba.Variable == "" || ba.Shorthand == "" {
		t.Fatal("canonical syllable fixture is missing a2/ba1")
	}
	input := filepath.Join(t.TempDir(), "source.yaml")
	content := fmt.Sprintf("# source\n---\nname: imported\nversion: \"1\"\nsort: by_weight\n...\n阿\t%s\t100\n吧\t%s\t90\n阿吧\t%s%s\t80\n", a.Full, ba.Full, a.Full, ba.Full)
	if err := os.WriteFile(input, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "out")
	manifest, err := DeriveFromFullDictionary(input, out)
	if err != nil {
		t.Fatal(err)
	}
	if manifest.EntryCount != 3 || manifest.SourceSHA256 == "" {
		t.Fatalf("unexpected manifest: %#v", manifest)
	}
	checks := map[string][]string{
		"yime_full.dict.yaml":      {"阿\t" + a.Full + "\t100", "阿吧\t" + a.Full + " " + ba.Full + "\t80"},
		"yime_variable.dict.yaml":  {"阿\t" + a.Variable + "\t100", "阿吧\t" + a.Variable + " " + ba.Variable + "\t80"},
		"yime_shorthand.dict.yaml": {"阿\t" + a.Shorthand + "\t100", "阿吧\t" + a.Shorthand + " " + ba.Shorthand + "\t80"},
	}
	for name, fragments := range checks {
		data, err := os.ReadFile(filepath.Join(out, name))
		if err != nil {
			t.Fatal(err)
		}
		for _, fragment := range fragments {
			if !strings.Contains(string(data), fragment) {
				t.Fatalf("%s missing %q", name, fragment)
			}
		}
	}
	if _, err := os.Stat(filepath.Join(out, ManifestFileName)); err != nil {
		t.Fatalf("manifest missing: %v", err)
	}
	secondOut := filepath.Join(t.TempDir(), "second")
	if _, err := DeriveFromFullDictionary(filepath.Join(out, "yime_full.dict.yaml"), secondOut); err != nil {
		t.Fatal(err)
	}
	for name := range checks {
		first, _ := os.ReadFile(filepath.Join(out, name))
		second, _ := os.ReadFile(filepath.Join(secondOut, name))
		if string(first) != string(second) {
			t.Fatalf("%s is not deterministic when generated full data is reused", name)
		}
	}
}

func TestDeriveFromFullDictionaryDoesNotReplaceOutputsOnInvalidCode(t *testing.T) {
	out := t.TempDir()
	target := filepath.Join(out, "yime_full.dict.yaml")
	if err := os.WriteFile(target, []byte("previous"), 0o644); err != nil {
		t.Fatal(err)
	}
	input := filepath.Join(t.TempDir(), "bad.yaml")
	if err := os.WriteFile(input, []byte("---\n...\n坏\tabc\t1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := DeriveFromFullDictionary(input, out); err == nil {
		t.Fatal("expected invalid code to fail")
	}
	data, err := os.ReadFile(target)
	if err != nil || string(data) != "previous" {
		t.Fatalf("existing output changed: %q, %v", data, err)
	}
}
