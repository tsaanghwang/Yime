package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestParticleAStage6CReviewGateIsCompleteReadOnlyAndOffline(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	config := DefaultParticleAStage6CConfig(repoRoot)
	before := map[string][]byte{}
	for _, path := range []string{config.ReviewPath, config.SourcesPath, config.DecisionsPath} {
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		before[path] = payload
	}
	temporaryRoot := t.TempDir()
	config.Stage6BOutputDir = filepath.Join(temporaryRoot, "particle-a-stage6b-projection")
	config.OutputDir = filepath.Join(temporaryRoot, "particle-a-stage6c-review")
	config.AllowedOutputRoot = temporaryRoot
	result, err := RunParticleAStage6CReview(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ReviewCount != 30 || result.Summary.MatchedCount != 30 || result.Summary.PendingCount != 30 || result.Summary.DecisionCount != 0 || result.Summary.UnresolvedCount != 0 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.SemanticOnlyCount != 5 || result.Summary.KeyChangingCount != 25 || result.Summary.ThreeModeProjectionRows != 90 {
		t.Fatalf("review distribution changed: %#v", result.Summary)
	}
	for path, want := range before {
		got, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("review modified %s", path)
		}
	}
	wantReports := []string{"REPORT.md", "input_hashes_after.json", "input_hashes_before.json", "manifest.json", "review_projection.tsv", "summary.json", "unresolved.tsv"}
	entries, err := os.ReadDir(config.OutputDir)
	if err != nil {
		t.Fatal(err)
	}
	gotReports := []string{}
	for _, entry := range entries {
		if !entry.IsDir() {
			gotReports = append(gotReports, entry.Name())
			if strings.HasSuffix(entry.Name(), ".dict.yaml") || strings.HasSuffix(entry.Name(), ".schema.yaml") {
				t.Fatalf("review emitted runtime file %s", entry.Name())
			}
		}
	}
	if !reflect.DeepEqual(gotReports, wantReports) {
		t.Fatalf("reports=%v, want %v", gotReports, wantReports)
	}
}

func TestParticleAStage6CModeGateSeparatesSharedKeyFromChangedKey(t *testing.T) {
	row := func(canonical, surface string) []string {
		return []string{"PA-6B-X", "测试啊", "PA-NG", "full", canonical, surface, "8", "8", "0", "true", "true", "1", "1", "0", "0", "", "research_only_not_generated"}
	}
	sharedReview := particleAStage6CReview{Text: "测试啊", ClassID: "PA-NG", EvidenceClass: "semantic_only_shared_key"}
	if err := validateParticleAStage6CModeRows([][]string{row("a b", "a b"), func() []string { x := row("a b", "a b"); x[3] = "variable"; return x }(), func() []string { x := row("a b", "a b"); x[3] = "shorthand"; return x }()}, sharedReview); err != nil {
		t.Fatal(err)
	}
	changedReview := sharedReview
	changedReview.EvidenceClass = "input_alias_key_change"
	if err := validateParticleAStage6CModeRows([][]string{row("a b", "a b"), func() []string { x := row("a b", "a b"); x[3] = "variable"; return x }(), func() []string { x := row("a b", "a b"); x[3] = "shorthand"; return x }()}, changedReview); err == nil {
		t.Fatal("expected unchanged physical code to be rejected for key-changing review")
	}
}

func TestParticleAStage6CApprovedDecisionMustKeepCanonicalPath(t *testing.T) {
	sources := map[string]particleAStage6CSource{"S": {ID: "S"}}
	decision := particleAStage6CDecision{ReviewID: "R", Decision: "approved", Applicability: "通常语境", CandidatePolicy: "replace_canonical", Reviewer: "owner", ReviewedAt: "2026-08-17", Note: "x", SourceIDs: []string{"S"}}
	if err := validateParticleAStage6CDecision(decision, sources); err == nil {
		t.Fatal("expected canonical replacement to be rejected")
	}
}

func TestParticleAStage6CRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultParticleAStage6CConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "particle-a-stage6c-review")
	config.AllowedOutputRoot = filepath.Join(root, ".tmp")
	if err := validateParticleAStage6CConfig(&config); err == nil {
		t.Fatal("expected output boundary rejection")
	}
}
