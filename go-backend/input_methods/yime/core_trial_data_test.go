package yime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type lexiconCountManifest struct {
	EntryCount int    `json:"entry_count"`
	SourceFile string `json:"source_file"`
}

type runtimeProfile struct {
	DefaultSchema     string   `json:"default_schema"`
	RuntimeDictionary string   `json:"runtime_dictionary"`
	OfflineOnlyFiles  []string `json:"offline_only_files"`
}

func readLexiconCountManifest(t *testing.T, name string) lexiconCountManifest {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("data", name))
	if err != nil {
		t.Fatal(err)
	}
	var manifest lexiconCountManifest
	if err := json.Unmarshal(data, &manifest); err != nil {
		t.Fatal(err)
	}
	return manifest
}

func TestCoreTrialLexiconIsIsolatedAndSmallerThanProduction(t *testing.T) {
	production := readLexiconCountManifest(t, "yime_lexicon_manifest.json")
	trial := readLexiconCountManifest(t, "yime_core_trial_manifest.json")
	if trial.EntryCount <= 0 {
		t.Fatal("core-trial lexicon must contain entries")
	}
	if trial.SourceFile != "two_level_full.dict.yaml" {
		t.Fatalf("unexpected shipped core-trial source: %q", trial.SourceFile)
	}
	if production.EntryCount <= trial.EntryCount {
		t.Fatalf(
			"core-trial lexicon must be smaller than production: trial=%d production=%d",
			trial.EntryCount,
			production.EntryCount,
		)
	}
	if trial.EntryCount*2 >= production.EntryCount {
		t.Fatalf(
			"core-trial experiment should remain below half of production entries: trial=%d production=%d",
			trial.EntryCount,
			production.EntryCount,
		)
	}
}

func TestCoreTrialSchemaKeepsSentenceCompositionAndSeparateLearning(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("data", "yime_core_trial.schema.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	checks := []string{
		"dictionary: yime_core_trial",
		"user_dict: yime_core_trial_two_level_1124631_layout_6d00e609f689_script_v1",
		"user_dict: custom_phrase_variable",
		"enable_sentence: true",
		"sentence_over_completion: true",
	}
	for _, check := range checks {
		if !strings.Contains(content, check) {
			t.Fatalf("core-trial schema missing %q", check)
		}
	}
}

func TestRuntimeProfileMakesCompactDictionaryTheOnlyYimeRuntimeLexicon(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("data", "yime_runtime_profile.json"))
	if err != nil {
		t.Fatal(err)
	}
	var profile runtimeProfile
	if err := json.Unmarshal(data, &profile); err != nil {
		t.Fatal(err)
	}
	if profile.DefaultSchema != "yime_core_trial" {
		t.Fatalf("unexpected default schema: %q", profile.DefaultSchema)
	}
	if profile.RuntimeDictionary != "yime_core_trial.dict.yaml" {
		t.Fatalf("unexpected runtime dictionary: %q", profile.RuntimeDictionary)
	}
	requiredOffline := map[string]bool{
		"yime_full.dict.yaml":      false,
		"yime_variable.dict.yaml":  false,
		"yime_shorthand.dict.yaml": false,
	}
	for _, name := range profile.OfflineOnlyFiles {
		if _, ok := requiredOffline[name]; ok {
			requiredOffline[name] = true
		}
	}
	for name, found := range requiredOffline {
		if !found {
			t.Fatalf("legacy dictionary %s is not declared offline-only", name)
		}
	}
}

func TestBundledRimeDefaultListsCompactRuntimeFirst(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("data", "default.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	core := strings.Index(content, "- schema: yime_core_trial")
	luna := strings.Index(content, "- schema: luna_pinyin")
	if core < 0 || luna < 0 || core > luna {
		t.Fatalf("compact runtime must be the first bundled schema:\n%s", content)
	}
}
