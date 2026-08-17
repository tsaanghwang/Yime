package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

func TestRunAuditDerivesThreeModesReportsCollisionsAndIsDeterministic(t *testing.T) {
	fixture := newAuditFixture(t, []Record{validNoGrowthToneSandhiRecord()})
	fixture.config.Switches = Switches{Enabled: true, ToneSandhi: true}

	first, err := RunAudit(fixture.config)
	if err != nil {
		t.Fatal(err)
	}
	if !first.Summary.Passed || !first.Summary.BaselineHashesMatch {
		t.Fatalf("summary = %#v", first.Summary)
	}
	if first.Summary.TrialRecordCount != 1 || first.Summary.TrialAliasCount != 1 {
		t.Fatalf("trial counts = %#v", first.Summary)
	}
	if first.Summary.CollisionCount != 3 || first.Summary.PotentialRankingCount != 3 || first.Summary.ActualRankingChanges != 0 {
		t.Fatalf("collision/ranking summary = %#v", first.Summary)
	}
	coverage := readTSVLines(t, filepath.Join(fixture.config.OutputDir, "three_mode_coverage.tsv"))
	if len(coverage) != 4 {
		t.Fatalf("coverage rows = %d, want header + 3 modes", len(coverage))
	}
	firstOutput := snapshotReports(t, fixture.config.OutputDir)

	second, err := RunAudit(fixture.config)
	if err != nil {
		t.Fatal(err)
	}
	if !second.Summary.Passed {
		t.Fatalf("second summary = %#v", second.Summary)
	}
	secondOutput := snapshotReports(t, fixture.config.OutputDir)
	if len(firstOutput) != len(secondOutput) {
		t.Fatalf("report file counts differ: %d vs %d", len(firstOutput), len(secondOutput))
	}
	for name, firstBytes := range firstOutput {
		if secondBytes := secondOutput[name]; string(secondBytes) != string(firstBytes) {
			t.Errorf("report %s is not byte deterministic", name)
		}
	}
}

func TestRunAuditDefaultsToNoTrialAliases(t *testing.T) {
	fixture := newAuditFixture(t, []Record{validNoGrowthToneSandhiRecord()})
	result, err := RunAudit(fixture.config)
	if err != nil {
		t.Fatal(err)
	}
	if result.Summary.TrialRecordCount != 0 || result.Summary.TrialAliasCount != 0 {
		t.Fatalf("disabled modules produced trial output: %#v", result.Summary)
	}
	if !result.Summary.Passed {
		t.Fatalf("disabled baseline should pass: %#v", result.Summary)
	}
}

func TestRunAuditNeverEmitsIsolatedRecords(t *testing.T) {
	record := validNoGrowthToneSandhiRecord()
	record.AdjudicationStatus = "research_only"
	record.RuntimeEnabled = false
	fixture := newAuditFixture(t, []Record{record})
	fixture.config.Switches = Switches{Enabled: true, ToneSandhi: true}
	result, err := RunAudit(fixture.config)
	if err != nil {
		t.Fatal(err)
	}
	if result.Summary.TrialRecordCount != 0 || result.Summary.IsolatedRecordCount != 1 {
		t.Fatalf("isolated record escaped or was not counted: %#v", result.Summary)
	}
	rejected := strings.Join(readTSVLines(t, filepath.Join(fixture.config.OutputDir, "rejected_records.tsv")), "\n")
	if !strings.Contains(rejected, "isolated_status") {
		t.Fatalf("isolated reason missing:\n%s", rejected)
	}
}

func TestRunAuditRejectsOutputOutsideTemporaryBoundaryBeforeDeletion(t *testing.T) {
	fixture := newAuditFixture(t, []Record{validNoGrowthToneSandhiRecord()})
	outside := filepath.Join(fixture.root, "outside")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	sentinel := filepath.Join(outside, "keep.txt")
	writeText(t, sentinel, "keep")
	fixture.config.OutputDir = outside
	if _, err := RunAudit(fixture.config); err == nil || !strings.Contains(err.Error(), "允许的临时根目录") {
		t.Fatalf("outside output was not rejected: %v", err)
	}
	if _, err := os.Stat(sentinel); err != nil {
		t.Fatalf("boundary rejection modified outside directory: %v", err)
	}
}

func TestRunAuditAllowsVariableAndShorthandLengthChangesInBothDirections(t *testing.T) {
	for _, test := range []struct {
		name     string
		record   Record
		relation string
	}{
		{name: "increase", record: validToneSandhiRecord(), relation: "increased"},
		{name: "decrease", record: validDecreasingProjectionRecord(), relation: "decreased"},
	} {
		t.Run(test.name, func(t *testing.T) {
			fixture := newAuditFixture(t, []Record{test.record})
			fixture.config.Switches = Switches{Enabled: true, ToneSandhi: true}
			result, err := RunAudit(fixture.config)
			if err != nil {
				t.Fatal(err)
			}
			if !result.Summary.Gates["mode_length_projection_valid"] {
				t.Fatalf("valid mode projection was rejected: %#v", result.Summary)
			}
			lengthReport := strings.Join(readTSVLines(t, filepath.Join(fixture.config.OutputDir, "code_length.tsv")), "\n")
			if !strings.Contains(lengthReport, "variable") || !strings.Contains(lengthReport, test.relation) {
				t.Fatalf("length relation was not reported:\n%s", lengthReport)
			}
		})
	}
}

func TestProjectedLengthBoundsApplyToEverySyllable(t *testing.T) {
	if !projectedSyllableLengthsValid("ab cde fghi", 3) {
		t.Fatal("per-syllable lengths 2,3,4 should be valid")
	}
	for _, spelling := range []string{
		"a bcde",   // 第一音节只有首音，没有保留干音位置。
		"abcde bc", // 第一音节超过四码。
		"ab",       // 音节组数不足。
	} {
		if projectedSyllableLengthsValid(spelling, 2) {
			t.Errorf("invalid per-syllable projection accepted: %q", spelling)
		}
	}
	if !fixedSyllableLengthsValid("abcd efgh", 2) || fixedSyllableLengthsValid("abc defg", 2) {
		t.Fatal("fixed mode must retain exactly four codes for every syllable")
	}
}

type auditFixture struct {
	root   string
	config Config
}

func newAuditFixture(t *testing.T, records []Record) auditFixture {
	t.Helper()
	root := t.TempDir()
	dataDir := filepath.Join(root, "go-backend", "input_methods", "yime", "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	profile := testProfile(t)
	layoutBytes, err := json.MarshalIndent(profile, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	writeText(t, filepath.Join(dataDir, "yime_yinyuan_layout.json"), string(layoutBytes)+"\n")
	decomposition := "pinyin_tone\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\n" +
		"yi1\tN23\tM01\tM01\tM01\n" +
		"yi2\tN23\tM03\tM02\tM01\n" +
		"bu4\tN01\tM04\tM05\tM06\n" +
		"bu2\tN01\tM06\tM05\tM04\n"
	writeText(t, filepath.Join(dataDir, "yime_syllable_decomposition.tsv"), decomposition)
	writeText(t, filepath.Join(dataDir, "yime_pinyin_codes.tsv"), "pinyin_tone\tfull\nyi1\ttest\n")

	canonical, err := projectSequence(records[0].CanonicalYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	trial, err := projectSequence(*records[0].SurfaceYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []struct{ name, canonical, trial string }{
		{"full", canonical.FullSpelling, trial.FullSpelling},
		{"variable", canonical.VariableSpelling, trial.VariableSpelling},
		{"shorthand", canonical.ShorthandSpelling, trial.ShorthandSpelling},
	} {
		dictionary := "# test dictionary\n---\nname: test\n...\n" +
			"一\t" + mode.canonical + "\t200\n" +
			"乙\t" + mode.trial + "\t100\n"
		writeText(t, filepath.Join(dataDir, "yime_"+mode.name+".dict.yaml"), dictionary)
		writeText(t, filepath.Join(dataDir, "yime_"+mode.name+".schema.yaml"), "schema:\n  schema_id: test\n")
	}
	writeText(t, filepath.Join(dataDir, "yime_lexicon_manifest.json"), "{}\n")
	writeText(t, filepath.Join(dataDir, "yime_runtime_profile.json"), "{}\n")

	recordsPath := filepath.Join(root, "records.json")
	writeRecords(t, recordsPath, records)
	schemaPath := filepath.Join(root, "schema.json")
	writeText(t, schemaPath, `{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.invalid/connected-speech-record-v1.json",
  "type": "object",
  "required": ["schema_version", "ruleset_version", "record_id", "text", "canonical_pinyin", "adjudication_status", "runtime_enabled", "source_observations", "canonical_yinyuan_ids"],
  "properties": {
    "schema_version": {}, "ruleset_version": {}, "record_id": {}, "text": {}, "canonical_pinyin": {},
    "adjudication_status": {}, "runtime_enabled": {}, "source_observations": {}, "canonical_yinyuan_ids": {}
  },
  "$defs": {"syllableSequence": {}}
}
`)
	config := Config{
		RepoRoot: root, RecordsPath: recordsPath, SchemaPath: schemaPath, DataDir: dataDir,
		DecompositionPath: filepath.Join(dataDir, "yime_syllable_decomposition.tsv"),
		LayoutPath:        filepath.Join(dataDir, "yime_yinyuan_layout.json"),
		OutputDir:         filepath.Join(root, ".tmp", "connected-speech-audit"),
		AllowedOutputRoot: filepath.Join(root, ".tmp"),
	}
	return auditFixture{root: root, config: config}
}

func testProfile(t *testing.T) layoutdesigner.Profile {
	t.Helper()
	ids := layoutdesigner.ExpectedIDs()
	keys := []rune(codemode.LayoutAlphabet)
	if len(keys) < len(ids) {
		t.Fatalf("layout alphabet has %d keys for %d IDs", len(keys), len(ids))
	}
	projection := make(map[string]string, len(ids))
	for index, id := range ids {
		projection[id] = string(keys[index])
	}
	projection["N26"] = projection["N12"]
	projection["N27"] = projection["N25"]
	profile := layoutdesigner.Profile{FormatVersion: layoutdesigner.ProfileFormatVersion, Name: "test", Projection: projection}
	if err := profile.Validate(); err != nil {
		t.Fatal(err)
	}
	return profile
}

func snapshotReports(t *testing.T, dir string) map[string][]byte {
	t.Helper()
	names := append([]string{"manifest.json"}, deterministicReportFiles...)
	sort.Strings(names)
	result := make(map[string][]byte, len(names))
	for _, name := range names {
		payload, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		result[name] = payload
	}
	return result
}

func readTSVLines(t *testing.T, path string) []string {
	t.Helper()
	payload, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimSpace(string(payload)), "\n")
}

func writeText(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
