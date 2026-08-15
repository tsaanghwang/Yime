package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
)

func TestCheckedInContextualToneModelIsValid(t *testing.T) {
	model, conflicts := loadCheckedInContextualToneModel(t)
	if issues := ValidateContextualToneModel(model, conflicts); len(issues) != 0 {
		t.Fatalf("checked-in model issues: %#v", issues)
	}
	if model.RuntimeEnabled || model.MaximumGlobalPasses != 1 {
		t.Fatalf("unsafe checked-in model boundary: %#v", model)
	}
}

func TestContextualToneModelAuditReportCompletenessAndReadOnlyInputs(t *testing.T) {
	modelPath, conflictsPath := checkedInContextualTonePaths(t)
	repoRoot := t.TempDir()
	docsDir := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	if err := os.MkdirAll(docsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	inputs := map[string]string{
		"contextual_tone_rule_model.json":    modelPath,
		"contextual_tone_rule_conflicts.tsv": conflictsPath,
	}
	before := map[string][]byte{}
	for name, source := range inputs {
		data, err := os.ReadFile(source)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(docsDir, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
		before[name] = append([]byte(nil), data...)
	}

	config := DefaultContextualToneModelAuditConfig(repoRoot)
	result, err := RunContextualToneModelAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.RuntimeAliasesGenerated != 0 || !result.Summary.InputHashesMatch {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.RuleCount != 19 || result.Summary.ConflictCount != 14 || result.Summary.DeferredRuleCount < 8 {
		t.Fatalf("incomplete model coverage: %#v", result.Summary)
	}

	wantReports := append([]string(nil), contextualToneReportFiles...)
	sort.Strings(wantReports)
	entries, err := os.ReadDir(config.OutputDir)
	if err != nil {
		t.Fatal(err)
	}
	gotReports := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			gotReports = append(gotReports, entry.Name())
		}
	}
	sort.Strings(gotReports)
	if !reflect.DeepEqual(gotReports, wantReports) {
		t.Fatalf("reports=%v, want %v", gotReports, wantReports)
	}

	var diskSummary ContextualToneModelAuditSummary
	data, err := os.ReadFile(filepath.Join(config.OutputDir, "summary.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &diskSummary); err != nil {
		t.Fatal(err)
	}
	for gate, passed := range diskSummary.Gates {
		if !passed {
			t.Fatalf("gate %s did not pass", gate)
		}
	}
	for name, want := range before {
		got, err := os.ReadFile(filepath.Join(docsDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("audit modified input %s", name)
		}
	}
}

func TestContextualToneModelRejectsDependencyCycle(t *testing.T) {
	model, conflicts := loadCheckedInContextualToneModel(t)
	model.Dependencies = append(model.Dependencies, ContextualToneDependency{
		FromRule: "three_mode_projection_v1", ToRule: "prosodic_domain_partition_v1", Relation: "precedes", Condition: "test cycle",
	})
	issues := ValidateContextualToneModel(model, conflicts)
	if !hasContextualToneIssue(issues, "cycle") {
		t.Fatalf("expected cycle issue, got %#v", issues)
	}
}

func TestContextualToneModelRejectsRecursiveRule(t *testing.T) {
	model, conflicts := loadCheckedInContextualToneModel(t)
	model.Rules[0].Recursive = true
	model.Rules[0].MaximumApplicationsPerSyllable = 2
	issues := ValidateContextualToneModel(model, conflicts)
	if !hasContextualToneIssue(issues, "recursive_risk") {
		t.Fatalf("expected recursive risk, got %#v", issues)
	}
}

func TestContextualToneModelRejectsUnknownConflictRule(t *testing.T) {
	model, conflicts := loadCheckedInContextualToneModel(t)
	conflicts[0].RightRule = "missing_rule"
	issues := ValidateContextualToneModel(model, conflicts)
	if !hasContextualToneIssue(issues, "unknown") {
		t.Fatalf("expected unknown rule issue, got %#v", issues)
	}
}

func TestContextualToneModelAuditRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	repoRoot := t.TempDir()
	config := DefaultContextualToneModelAuditConfig(repoRoot)
	config.OutputDir = filepath.Join(repoRoot, "reports", "contextual-tone-model-audit")
	if _, err := RunContextualToneModelAudit(config); err == nil {
		t.Fatal("expected output outside .tmp to be rejected")
	}
}

func loadCheckedInContextualToneModel(t *testing.T) (ContextualToneModel, []ContextualToneConflict) {
	t.Helper()
	modelPath, conflictsPath := checkedInContextualTonePaths(t)
	model, err := LoadContextualToneModel(modelPath)
	if err != nil {
		t.Fatal(err)
	}
	conflicts, err := LoadContextualToneConflicts(conflictsPath)
	if err != nil {
		t.Fatal(err)
	}
	return model, conflicts
}

func checkedInContextualTonePaths(t *testing.T) (string, string) {
	t.Helper()
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	base := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	return filepath.Join(base, "contextual_tone_rule_model.json"), filepath.Join(base, "contextual_tone_rule_conflicts.tsv")
}

func hasContextualToneIssue(issues []ContextualToneModelIssue, code string) bool {
	for _, issue := range issues {
		if issue.Code == code {
			return true
		}
	}
	return false
}
