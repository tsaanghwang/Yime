package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func TestYiBuChainAuditCompletenessAndReadOnlyInputs(t *testing.T) {
	repoRoot := t.TempDir()
	dataDir := filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data")
	casesDir := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(casesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	codes := "pinyin_tone\tfull\n" +
		"yi1\tyjjj\n" +
		"yi4\tyjkl\n" +
		"ben3\tbxxz\n" +
		"di4\t]jkl\n"
	if err := os.WriteFile(filepath.Join(dataDir, "yime_pinyin_codes.tsv"), []byte(codes), 0o644); err != nil {
		t.Fatal(err)
	}
	runtime, err := codemode.BuildRecord("yjjj bxxz")
	if err != nil {
		t.Fatal(err)
	}
	ordinal, err := codemode.BuildRecord("]jkl yjjj")
	if err != nil {
		t.Fatal(err)
	}
	modeCodes := map[string][]string{
		"full":      {runtime.FullSpelling, ordinal.FullSpelling},
		"variable":  {runtime.VariableSpelling, ordinal.VariableSpelling},
		"shorthand": {runtime.ShorthandSpelling, ordinal.ShorthandSpelling},
	}
	texts := []string{"一本", "第一"}
	before := map[string][]byte{"yime_pinyin_codes.tsv": []byte(codes)}
	for mode, entries := range modeCodes {
		content := "---\nname: yime_" + mode + "\n...\n"
		for index, code := range entries {
			content += texts[index] + "\t" + code + "\t100\n"
		}
		name := "yime_" + mode + ".dict.yaml"
		if err := os.WriteFile(filepath.Join(dataDir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		before[name] = []byte(content)
	}
	cases := strings.Join([]string{
		"case_id\ttext\tclassification\truntime_pinyin\ttrial_pinyin\ttrial_runtime_expected\tdecision\treason",
		"CS-1\t一本\tmissing_alias\tyi1 ben3\tyi4 ben3\tfalse\toffline_trial\tfixture",
		"CS-2\t第一\texcluded\tdi4 yi1\t\tfalse\texcluded\tfixture",
	}, "\n") + "\n"
	if err := os.WriteFile(filepath.Join(casesDir, "stage2_yi_bu_cases.tsv"), []byte(cases), 0o644); err != nil {
		t.Fatal(err)
	}

	config := DefaultYiBuChainAuditConfig(repoRoot)
	result, err := RunYiBuChainAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.CaseCount != 2 || result.Summary.ThreeModeCheckCount != 6 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.MissingAliasCount != 1 || result.Summary.ExcludedCount != 1 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unexpected classification coverage: %#v", result.Summary)
	}

	wantReports := append([]string(nil), yiBuChainReportFiles...)
	wantReports = append(wantReports, "manifest.json")
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

	var summary YiBuChainAuditSummary
	data, err := os.ReadFile(filepath.Join(config.OutputDir, "summary.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &summary); err != nil {
		t.Fatal(err)
	}
	for gate, passed := range summary.Gates {
		if !passed {
			t.Fatalf("gate %s did not pass", gate)
		}
	}
	for name, want := range before {
		got, err := os.ReadFile(filepath.Join(dataDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("audit modified canonical input %s", name)
		}
	}
}

func TestYiBuChainAuditRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	repoRoot := t.TempDir()
	config := DefaultYiBuChainAuditConfig(repoRoot)
	config.OutputDir = filepath.Join(repoRoot, "reports", "connected-speech-stage2-yi-bu-audit")
	if _, err := RunYiBuChainAudit(config); err == nil {
		t.Fatal("expected output outside .tmp to be rejected")
	}
}
