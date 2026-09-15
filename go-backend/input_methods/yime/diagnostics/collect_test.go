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

func TestTrialStatusReportUsesYimeCoreRuntimeContract(t *testing.T) {
	root := t.TempDir()
	ctx := Context{
		UserDir: filepath.Join(root, "state"), SharedDir: filepath.Join(root, "package", "data"),
		HelpDir: filepath.Join(root, "package", "help"), LogDir: filepath.Join(root, "state", "logs"),
		InstallRoot: filepath.Join(root, "package"), Experimental: true,
	}
	report := BuildStatusReport(ctx)
	for _, expected := range []string{"YimeCoreTrialRuntime.exe", "YimeBroker.exe", "YimeCoreToolCenter.exe", "runtime-config.json", "runtime-status.json"} {
		if !strings.Contains(report, expected) {
			t.Fatalf("Trial report lacks %q:\n%s", expected, report)
		}
	}
	for _, forbidden := range []string{"PIMELauncher", "server.exe", "rime_deployer.exe", "default.custom.yaml"} {
		if strings.Contains(report, forbidden) {
			t.Fatalf("Trial report leaked production diagnostic %q:\n%s", forbidden, report)
		}
	}
}
