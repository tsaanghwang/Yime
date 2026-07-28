package yime

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const curatedCoreEntryCount = 1124631

type coreRuntimeManifest struct {
	EntryCount   int               `json:"entry_count"`
	SourceFile   string            `json:"source_file"`
	SourceSHA256 string            `json:"source_sha256"`
	OutputSHA256 map[string]string `json:"output_sha256"`
}

type coreSourceManifest struct {
	SourceDictionarySHA256 string `json:"source_dictionary_sha256"`
	EntryCount             int    `json:"entry_count"`
	DistinctTexts          int    `json:"distinct_texts"`
	RankingEvidence        struct {
		PolicyID                       string `json:"policy_id"`
		DirectBCC                      int    `json:"direct_bcc"`
		ProvisionalRimeLMDG            int    `json:"provisional_rime_lmdg"`
		ProvisionalStructuralFloor     int    `json:"provisional_structural_floor"`
		MissingSelectedSourceTexts     int    `json:"missing_selected_source_texts"`
		RawBCCAndLMDGValuesAdded       bool   `json:"raw_bcc_and_lmdg_values_added"`
		SourcePrioritySeparationPassed bool   `json:"source_priority_separation_passed"`
	} `json:"ranking_evidence"`
}

type coreRuntimeProfile struct {
	DefaultSchema       string   `json:"default_schema"`
	RuntimeSchemas      []string `json:"runtime_schemas"`
	RuntimeDictionaries []string `json:"runtime_dictionaries"`
	CandidateLayers     []string `json:"candidate_layers"`
	EntryCountPerMode   int      `json:"entry_count_per_mode"`
}

func readJSONFile(t *testing.T, name string, target any) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("data", name))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, target); err != nil {
		t.Fatal(err)
	}
}

func fileSHA256(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func TestCuratedCoreEvidenceAndThreeModeDerivationAreLocked(t *testing.T) {
	var generated coreRuntimeManifest
	readJSONFile(t, "yime_lexicon_manifest.json", &generated)
	var source coreSourceManifest
	readJSONFile(t, "yime_core_source_manifest.json", &source)

	if generated.EntryCount != curatedCoreEntryCount ||
		source.EntryCount != curatedCoreEntryCount {
		t.Fatalf("unexpected core entry count: generated=%d source=%d",
			generated.EntryCount, source.EntryCount)
	}
	if generated.SourceFile != "two_level_full.dict.yaml" {
		t.Fatalf("unexpected curated core source: %q", generated.SourceFile)
	}
	if generated.SourceSHA256 != source.SourceDictionarySHA256 {
		t.Fatal("generated dictionaries and ranking evidence use different sources")
	}
	if source.DistinctTexts != 1116892 ||
		source.RankingEvidence.PolicyID !=
			"bcc-primary-lmdg-fallback-structural-floor-v1" ||
		source.RankingEvidence.MissingSelectedSourceTexts != 0 ||
		source.RankingEvidence.RawBCCAndLMDGValuesAdded ||
		!source.RankingEvidence.SourcePrioritySeparationPassed {
		t.Fatalf("invalid ranking evidence: %#v", source)
	}
	if source.RankingEvidence.DirectBCC+
		source.RankingEvidence.ProvisionalRimeLMDG+
		source.RankingEvidence.ProvisionalStructuralFloor !=
		source.DistinctTexts {
		t.Fatal("ranking evidence does not classify every core text")
	}

	for _, name := range []string{
		"yime_full.dict.yaml",
		"yime_variable.dict.yaml",
		"yime_shorthand.dict.yaml",
	} {
		want := generated.OutputSHA256[name]
		if want == "" {
			t.Fatalf("manifest has no hash for %s", name)
		}
		if got := fileSHA256(t, filepath.Join("data", name)); got != want {
			t.Fatalf("%s hash mismatch: got=%s want=%s", name, got, want)
		}
	}
}

func TestAllCoreModesConnectLearningCustomPhrasesAndSentenceComposition(
	t *testing.T,
) {
	for _, mode := range []string{"variable", "full", "shorthand"} {
		data, err := os.ReadFile(
			filepath.Join("data", "yime_"+mode+".schema.yaml"),
		)
		if err != nil {
			t.Fatal(err)
		}
		content := string(data)
		checks := []string{
			"dictionary: yime_" + mode,
			"user_dict: yime_" + mode + "_core_1124631_",
			"user_dict: custom_phrase_" + mode,
			"enable_user_dict: true",
			"enable_sentence: true",
			"sentence_over_completion: true",
		}
		for _, check := range checks {
			if !strings.Contains(content, check) {
				t.Fatalf("%s schema missing %q", mode, check)
			}
		}
	}
}

func TestRuntimeProfileContainsOnlyCoreBackedThreeModeChain(t *testing.T) {
	var profile coreRuntimeProfile
	readJSONFile(t, "yime_runtime_profile.json", &profile)
	if profile.DefaultSchema != "yime_variable" ||
		profile.EntryCountPerMode != curatedCoreEntryCount {
		t.Fatalf("unexpected runtime profile: %#v", profile)
	}
	for _, required := range []string{
		"yime_variable", "yime_full", "yime_shorthand",
	} {
		if !containsString(profile.RuntimeSchemas, required) {
			t.Fatalf("runtime profile lacks schema %s", required)
		}
		if !containsString(
			profile.RuntimeDictionaries,
			required+".dict.yaml",
		) {
			t.Fatalf("runtime profile lacks dictionary %s", required)
		}
	}
	for _, layer := range []string{
		"curated_system_core",
		"rime_user_learning",
		"user_custom_phrases",
		"user_blocklist_filter",
	} {
		if !containsString(profile.CandidateLayers, layer) {
			t.Fatalf("runtime profile lacks candidate layer %s", layer)
		}
	}
	for _, retired := range []string{
		"yime_core_trial.dict.yaml",
		"yime_core_trial.schema.yaml",
		"yime_core_trial_manifest.json",
	} {
		if _, err := os.Stat(filepath.Join("data", retired)); !os.IsNotExist(err) {
			t.Fatalf("retired runtime artifact still exists: %s", retired)
		}
	}
}

func TestBundledRimeDefaultListsAllThreeCoreModes(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("data", "default.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	variable := strings.Index(content, "- schema: yime_variable")
	full := strings.Index(content, "- schema: yime_full")
	shorthand := strings.Index(content, "- schema: yime_shorthand")
	luna := strings.Index(content, "- schema: luna_pinyin")
	if variable < 0 || full < variable || shorthand < full || luna < shorthand {
		t.Fatalf("three core modes must lead the bundled schema list:\n%s", content)
	}
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
