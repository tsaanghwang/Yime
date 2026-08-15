package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
)

func TestNeutralChainAuditReportCompletenessAndReadOnlyInputs(t *testing.T) {
	repoRoot := t.TempDir()
	dataDir := filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"yime_pinyin_codes.tsv": "pinyin_tone\tfull\na1\t'fff\nzi5\t6KKK\n",
		"yime_syllable_decomposition.tsv": "pinyin_tone\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\tlayout_code\n" +
			"a1\tN12\tM10\tM10\tM10\t'fff\n" +
			"zi5\tN13\tM20\tM20\tM20\t6KKK\n",
		"pinyin_normalized.json":         "{\"a1\":\"ā\",\"zi5\":\"zi\"}\n",
		"yime_pinyin_reverse_source.tsv": "text\tsource_full_code\tnumeric_pinyin\tmarked_pinyin\n",
		"yime_full.dict.yaml":            "---\nname: yime_full\n...\n子\t6KKK\t100\n",
		"yime_variable.dict.yaml":        "---\nname: yime_variable\n...\n子\t6K\t100\n",
		"yime_shorthand.dict.yaml":       "---\nname: yime_shorthand\n...\n子\t6K\t100\n",
	}
	before := map[string][]byte{}
	for name, content := range files {
		path := filepath.Join(dataDir, name)
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
		before[name] = []byte(content)
	}

	config := DefaultNeutralChainAuditConfig(repoRoot)
	result, err := RunNeutralChainAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.NeutralSyllableCount != 1 || result.Summary.NeutralLexiconEntryCount != 1 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.ReverseLookupCheckCount != 3 || result.Summary.UserLexiconCheckCount != 3 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("incomplete chain coverage: %#v", result.Summary)
	}

	wantReports := append([]string(nil), neutralChainReportFiles...)
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

	var summary NeutralChainAuditSummary
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

func TestNeutralChainAuditRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	repoRoot := t.TempDir()
	config := DefaultNeutralChainAuditConfig(repoRoot)
	config.OutputDir = filepath.Join(repoRoot, "reports", "neutral-tone-chain-audit")
	if _, err := RunNeutralChainAudit(config); err == nil {
		t.Fatal("expected output outside .tmp to be rejected")
	}
}
