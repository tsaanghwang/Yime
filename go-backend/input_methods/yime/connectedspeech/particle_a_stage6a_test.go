package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParticleAStage6AAuditIsCompleteAndReadOnly(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	config := DefaultParticleAStage6AConfig(repoRoot)
	before := map[string][]byte{}
	for _, path := range []string{config.ScopePath, config.PositionPolicyPath, filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"), filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"), filepath.Join(config.DataDir, "yime_full.dict.yaml")} {
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		before[path] = payload
	}
	config.OutputDir = filepath.Join(t.TempDir(), ".tmp", "particle-a-stage6a-audit")
	config.AllowedOutputRoot = filepath.Dir(config.OutputDir)
	result, err := RunParticleAStage6AAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ClassifiedCount == 0 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if len(result.Summary.ClassCounts) != 6 || result.Summary.UnresolvedCount != 0 {
		t.Fatalf("incomplete classification: %#v", result.Summary)
	}
	if result.Summary.ParticleAOccurrenceCount != 6754 || result.Summary.EligibleWithHostCount != 6728 || result.Summary.InitialNoHostCount != 20 || result.Summary.MedialWithHostCount != 71 || result.Summary.FinalWithHostCount != 6657 || result.Summary.NonA5WithHostCount != 6 {
		t.Fatalf("position policy inventory changed: %#v", result.Summary)
	}
	for path, want := range before {
		got, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("audit modified input %s", path)
		}
	}
	wantReports := []string{"REPORT.md", "candidate_inventory.tsv", "class_summary.tsv", "input_hashes_after.json", "input_hashes_before.json", "manifest.json", "position_inventory.tsv", "summary.json", "unresolved.tsv"}
	entries, err := os.ReadDir(config.OutputDir)
	if err != nil {
		t.Fatal(err)
	}
	gotReports := []string{}
	for _, entry := range entries {
		if !entry.IsDir() {
			gotReports = append(gotReports, entry.Name())
		}
	}
	if !reflect.DeepEqual(gotReports, wantReports) {
		t.Fatalf("reports=%v, want %v", gotReports, wantReports)
	}
	payload, err := os.ReadFile(filepath.Join(config.OutputDir, "candidate_inventory.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(payload)
	if !strings.Contains(text, "\tpreserve\tresearch_only\tfalse\t") {
		t.Fatalf("candidate policy missing:\n%s", text[:min(len(text), 1000)])
	}
}

func TestParticleAPositionPolicyKeepsInitialAAndClassifiesMedialA5(t *testing.T) {
	rows := [][]string{
		{"text", "full_code", "weight", "syllable_index", "position_class", "canonical_a_code", "reading_status", "treatment", "candidate_policy", "runtime_enabled", "note"},
		{"啊哈", "'fff hfff", "1", "0", "INITIAL_NO_HOST", "'fff", "non_a5", "keep_canonical_no_assimilation", "canonical_only", "false", "x"},
		{"等啊等", "]ww/ 'ddd ]ww/", "1", "1", "MEDIAL_WITH_HOST", "'ddd", "a5", "classify_by_previous_final", "parallel_alias_keep_canonical", "false", "x"},
	}
	if !particleAPositionTreatment(rows, "INITIAL_NO_HOST", "keep_canonical_no_assimilation") || !particleAPositionA5Treatment(rows) || !particleAPositionDualTrack(rows) {
		t.Fatal("词首啊与句中啊的位置政策没有分离")
	}
}

func TestParticleAFinalClassification(t *testing.T) {
	cases := map[string]string{
		"hao3/ao3": "PA-U", "liu2/iou2": "PA-U", "tian1/ian1": "PA-N", "xing2/ing2": "PA-NG",
		"si4/_i4": "PA-APICAL-FRONT", "shi4/_i4": "PA-RETROFLEX", "er2/er2": "PA-RETROFLEX", "mei3/ei3": "PA-VOWEL-IY",
	}
	for input, want := range cases {
		parts := strings.Split(input, "/")
		if got := particleAFinalClass(parts[0], parts[1]); got != want {
			t.Errorf("%s=%s, want %s", input, got, want)
		}
	}
}

func TestParticleAStage6ARejectsRuntimeEligibleScope(t *testing.T) {
	scope := []particleAScopeClass{{ClassID: "PA-U", Priority: 10, SurfaceReading: "wa", AdjudicationStatus: "research_only", RuntimeEligible: true, Note: "x"}}
	if err := validateParticleAScope(scope); err == nil {
		t.Fatal("expected runtime-eligible scope to be rejected")
	}
}
