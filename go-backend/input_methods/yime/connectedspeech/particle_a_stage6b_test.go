package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParticleAStage6BProjectionIsCompleteReadOnlyAndOffline(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	config := DefaultParticleAStage6BConfig(repoRoot)
	before := map[string][]byte{}
	for _, path := range []string{config.ScopePath, config.ProjectionPath, filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"), filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"), filepath.Join(config.DataDir, "yime_yinyuan_layout.json"), filepath.Join(config.DataDir, "yime_full.dict.yaml"), filepath.Join(config.DataDir, "yime_variable.dict.yaml"), filepath.Join(config.DataDir, "yime_shorthand.dict.yaml")} {
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		before[path] = payload
	}
	config.OutputDir = filepath.Join(t.TempDir(), ".tmp", "particle-a-stage6b-projection")
	config.AllowedOutputRoot = filepath.Dir(config.OutputDir)
	result, err := RunParticleAStage6BProjection(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ExplicitParticleACount != result.Summary.ProjectableCandidateCount || result.Summary.UnresolvedCount != 0 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.ThreeModeProjectionRows != result.Summary.ProjectableCandidateCount*3 || len(result.Summary.ClassCounts) != 6 || result.Summary.BlockedLongerCount != 0 {
		t.Fatalf("incomplete projection: %#v", result.Summary)
	}
	for path, want := range before {
		got, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("projection modified input %s", path)
		}
	}
	wantReports := []string{"REPORT.md", "candidate_inventory.tsv", "class_summary.tsv", "input_hashes_after.json", "input_hashes_before.json", "manifest.json", "summary.json", "three_mode_projection.tsv", "unresolved.tsv"}
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
	classSummary, err := os.ReadFile(filepath.Join(config.OutputDir, "class_summary.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(classSummary)
	for _, want := range []string{"PA-NG\tnga5\treplace_a5_shouyin\tN26\t'", "PA-APICAL-FRONT\tza5\treplace_a5_shouyin\tN27\t`", "\tresearch_only\tfalse\t"} {
		if !strings.Contains(text, want) {
			t.Fatalf("class summary missing %q", want)
		}
	}
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".dict.yaml") || strings.HasSuffix(entry.Name(), ".schema.yaml") {
			t.Fatalf("offline stage emitted runtime file %s", entry.Name())
		}
	}
}

func TestParticleAStage6BTargetTuplesOnlyReplaceA5Shouyin(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	config := DefaultParticleAStage6BConfig(repoRoot)
	inventory, err := LoadInventory(filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	policy, err := loadParticleAStage6BPolicy(config.ProjectionPath)
	if err != nil {
		t.Fatal(err)
	}
	byClass := map[string]YinyuanTuple{}
	for _, class := range policy {
		tuple, err := particleAStage6BTargetTuple(class, inventory)
		if err != nil {
			t.Fatal(err)
		}
		byClass[class.ClassID] = tuple
	}
	base := inventory.Syllables["a5"]
	for classID, onset := range map[string]string{"PA-U": "N24", "PA-N": "N08", "PA-NG": "N26", "PA-APICAL-FRONT": "N27", "PA-RETROFLEX": "N19", "PA-VOWEL-IY": "N23"} {
		got := byClass[classID]
		if got[0] != onset || got[1] != base[1] || got[2] != base[2] || got[3] != base[3] {
			t.Fatalf("%s tuple=%v", classID, got)
		}
	}
}

func TestParticleAStage6BRejectsRuntimeEligiblePolicy(t *testing.T) {
	policy := []particleAProjectionClass{{ClassID: "PA-U", SurfacePinyin: "wa5", TupleStrategy: "replace_a5_shouyin", TargetShouyinID: "N24", SourceScope: "x", AdjudicationStatus: "research_only", RuntimeEligible: true, Note: "x"}}
	if err := validateParticleAStage6BPolicy(policy); err == nil {
		t.Fatal("expected runtime policy rejection")
	}
}
