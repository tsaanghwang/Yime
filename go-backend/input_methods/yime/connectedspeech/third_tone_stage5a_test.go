package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func TestThirdToneStage5AAuditIsCompleteAndReadOnly(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "go-backend", "input_methods", "yime", "data")
	docsDir := filepath.Join(root, "docs", "project", "connected_speech")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dataDir, "trainer"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(docsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"yime_pinyin_codes.tsv", "yime_syllable_decomposition.tsv", "yime_yinyuan_layout.json"} {
		copyFileForThirdToneTest(t, filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", name), filepath.Join(dataDir, name))
	}
	copyFileForThirdToneTest(t, filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "trainer", "yinyuan_catalog.json"), filepath.Join(dataDir, "trainer", "yinyuan_catalog.json"))
	copyFileForThirdToneTest(t, filepath.Join(repoRoot, "docs", "project", "connected_speech", "third_tone_sandhi_scope.tsv"), filepath.Join(docsDir, "third_tone_sandhi_scope.tsv"))

	fullCodes := loadThirdToneTestCodes(t, filepath.Join(dataDir, "yime_pinyin_codes.tsv"), []string{"ni3", "hao3", "wo3", "hen3", "ni2"})
	canonical, err := codemode.BuildRecord(fullCodes["ni3"] + fullCodes["hao3"])
	if err != nil {
		t.Fatal(err)
	}
	longer, err := codemode.BuildRecord(fullCodes["wo3"] + fullCodes["hen3"] + fullCodes["hao3"])
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join(dataDir, "yime_"+mode+".dict.yaml")
		code := thirdToneModeCode(canonical, mode)
		longerCode := thirdToneModeCode(longer, mode)
		writeText(t, path, "---\nname: yime_"+mode+"\n...\n你好\t"+code+"\t900\n我很好\t"+longerCode+"\t800\n")
	}
	config := DefaultThirdToneStage5AConfig(root)
	before := map[string][]byte{}
	for _, path := range []string{config.ScopePath, filepath.Join(dataDir, "yime_full.dict.yaml"), filepath.Join(dataDir, "yime_variable.dict.yaml"), filepath.Join(dataDir, "yime_shorthand.dict.yaml")} {
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		before[path] = payload
	}
	result, err := RunThirdToneStage5AAudit(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.ProjectableCandidateCount != 1 || result.Summary.ThreeModeProjectionRowCount != 3 {
		t.Fatalf("unexpected summary: %#v", result.Summary)
	}
	if result.Summary.BlockedLongerCandidateCount != 1 || result.Summary.LongerEntryWithPairCount != 1 || result.Summary.ThreePlusChainCount != 1 || result.Summary.RuntimeAliasesGenerated != 0 {
		t.Fatalf("unsafe longer-sequence classification: %#v", result.Summary)
	}
	projection, err := os.ReadFile(filepath.Join(config.OutputDir, "three_mode_projection.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(string(projection), "T3-5A-00001") != 3 || !strings.Contains(string(projection), "blocked_surface_longer") {
		t.Fatalf("incomplete projection report:\n%s", projection)
	}
	wantReports := []string{
		"REPORT.md", "candidate_inventory.tsv", "deferred_longer_sequences.tsv", "input_hashes_after.json",
		"input_hashes_before.json", "manifest.json", "summary.json", "three_mode_projection.tsv", "unresolved.tsv",
	}
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
	if !reflect.DeepEqual(gotReports, wantReports) {
		t.Fatalf("reports=%v, want %v", gotReports, wantReports)
	}
	if len(result.Manifest.InputSHA256) == 0 || len(result.Manifest.OutputSHA256) != len(wantReports)-1 {
		t.Fatalf("incomplete manifest: %#v", result.Manifest)
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
}

func TestThirdToneStage5ARejectsRuntimeEligibleScope(t *testing.T) {
	scope := []thirdToneScopeClass{
		{ClassID: "T3-DISYLLABLE-LEXICON", AdjudicationStatus: "research_only", RuntimeEligible: true, BoundaryEvidence: "x", Note: "x"},
		{ClassID: "T3-PAIR-IN-LONGER", AdjudicationStatus: "deferred", BoundaryEvidence: "x", Note: "x"},
		{ClassID: "T3-CHAIN-THREE-PLUS", AdjudicationStatus: "deferred", BoundaryEvidence: "x", Note: "x"},
	}
	if err := validateThirdToneScope(scope); err == nil {
		t.Fatal("expected runtime-eligible stage 5A scope to be rejected")
	}
}

func TestThirdToneStage5ARejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultThirdToneStage5AConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "third-tone-stage5a-audit")
	if _, err := RunThirdToneStage5AAudit(config); err == nil {
		t.Fatal("expected output outside .tmp to be rejected")
	}
}

func copyFileForThirdToneTest(t *testing.T, source, target string) {
	t.Helper()
	payload, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, payload, 0o644); err != nil {
		t.Fatal(err)
	}
}

func loadThirdToneTestCodes(t *testing.T, path string, wanted []string) map[string]string {
	t.Helper()
	codes, err := loadCanonicalCodeRows(path)
	if err != nil {
		t.Fatal(err)
	}
	result := map[string]string{}
	for _, pinyin := range wanted {
		if codes[pinyin] == "" {
			t.Fatalf("missing fixture pinyin %s", pinyin)
		}
		result[pinyin] = codes[pinyin]
	}
	return result
}
