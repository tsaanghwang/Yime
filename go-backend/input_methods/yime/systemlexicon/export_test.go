package systemlexicon

import (
	"strings"
	"testing"
)

func TestBuildReportPointsToRepositoryOfflineLexiconWorkflow(t *testing.T) {
	summary := Summary{
		TotalEntries: 2,
		FindingCount: 1,
		ByRule:       map[RuleID]int{RuleSuffixParticle: 1},
		DictPath:     "runtime-dictionary.yaml",
		Mode:         "full",
	}
	findings := []Finding{{Rule: RuleSuffixParticle, Text: "走了吗", Code: "abc", Weight: 10}}

	report := BuildReport(summary, findings)
	joinedNotes := strings.Join(report.Notes, "\n")
	if strings.Contains(joinedNotes, "Yime-python-prototype") {
		t.Fatalf("report notes still reference the retired repository: %q", joinedNotes)
	}
	if !strings.Contains(joinedNotes, "tools/lexicon") || !strings.Contains(joinedNotes, "正式离线词库流程") {
		t.Fatalf("report notes do not point to the repository offline lexicon workflow: %q", joinedNotes)
	}

	if report.Summary.TotalEntries != summary.TotalEntries ||
		report.Summary.FindingCount != summary.FindingCount ||
		report.Summary.ByRule[RuleSuffixParticle] != summary.ByRule[RuleSuffixParticle] ||
		report.Summary.DictPath != summary.DictPath ||
		report.Summary.Mode != summary.Mode {
		t.Fatalf("report summary changed: got %#v, want %#v", report.Summary, summary)
	}
	if len(report.Findings) != 1 || report.Findings[0] != findings[0] {
		t.Fatalf("report findings changed: got %#v, want %#v", report.Findings, findings)
	}
	findings[0].Text = "changed after export"
	if report.Findings[0].Text != "走了吗" {
		t.Fatalf("report findings no longer isolate export data from runtime input: %#v", report.Findings)
	}
}
