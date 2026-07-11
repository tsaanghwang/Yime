package systemlexicon

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDeriveFromFullDictionaryGeneratesThreeModes(t *testing.T) {
	input := filepath.Join(t.TempDir(), "source.yaml")
	content := "# source\n---\nname: imported\nversion: \"1\"\nsort: by_weight\n...\n阿\tHsdf\t100\n吧\tqfff\t90\n阿吧\tHsdfqfff\t80\n"
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
		"yime_full.dict.yaml":      {"阿\tHsdf\t100", "阿吧\tHsdfqfff\t80"},
		"yime_variable.dict.yaml":  {"阿\tsdf\t100", "阿吧\tsdfqf\t80"},
		"yime_shorthand.dict.yaml": {"阿\tsf\t100", "阿吧\tsfqf\t80"},
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
