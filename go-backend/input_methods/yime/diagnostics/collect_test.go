package diagnostics

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIssueReadyReportDoesNotIncludeRawLogPayloads(t *testing.T) {
	logDir := t.TempDir()
	const canary = "sensitive-ime-payload-canary"
	if err := os.WriteFile(filepath.Join(logDir, "go_backend.log"), []byte("payload="+canary+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	opts := DefaultIssueReadyOptions()
	if opts.IncludeRawLogExcerpt {
		t.Fatal("issue-ready diagnostics must keep raw logs opt-in")
	}
	report := BuildStructuredReport(Context{LogDir: logDir}, opts)
	if strings.Contains(report, canary) {
		t.Fatalf("anonymized issue-ready report leaked raw log payload: %s", report)
	}

	opts.IncludeRawLogExcerpt = true
	report = BuildStructuredReport(Context{LogDir: logDir}, opts)
	if strings.Contains(report, canary) {
		t.Fatalf("anonymized report leaked explicitly requested raw log payload: %s", report)
	}
	if !strings.Contains(report, "Omitted because anonymization is enabled") {
		t.Fatalf("expected an explicit raw-log omission notice: %s", report)
	}
}
