package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadRecordsRejectsUnknownFieldsAndWrongTupleLength(t *testing.T) {
	dir := t.TempDir()
	unknown := filepath.Join(dir, "unknown.json")
	if err := os.WriteFile(unknown, []byte(`[{"unexpected":true}]`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRecords(unknown); err == nil || !strings.Contains(err.Error(), "unknown field") {
		t.Fatalf("unknown field was not rejected: %v", err)
	}

	wrongTuple := filepath.Join(dir, "wrong-tuple.json")
	payload := `[{"canonical_yinyuan_ids":[["N01","M01","M01"]]}]`
	if err := os.WriteFile(wrongTuple, []byte(payload), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadRecords(wrongTuple); err == nil || !strings.Contains(err.Error(), "恰有 4 项") {
		t.Fatalf("wrong tuple length was not rejected: %v", err)
	}
}

func TestValidateRecordsProtectsIsolationAndCanonicalRewrite(t *testing.T) {
	inventory := Inventory{
		Syllables: map[string]YinyuanTuple{
			"yi1": {"N23", "M01", "M01", "M01"},
			"yi2": {"N23", "M03", "M02", "M01"},
		},
		StableIDs: map[string]bool{"N23": true, "M01": true, "M02": true, "M03": true},
	}
	record := validToneSandhiRecord()
	record.AdjudicationStatus = "research_only"
	record.RuntimeEnabled = true
	record.Rewrites[0].FromID = "M02"
	issues := ValidateRecords([]Record{record}, inventory)
	if !hasIssue(issues, "isolated_record_enabled") {
		t.Fatalf("missing isolation issue: %#v", issues)
	}
	if !hasIssue(issues, "rewrite_from_mismatch") {
		t.Fatalf("missing rewrite source issue: %#v", issues)
	}
}

func TestBundledFirstBatchYinyuanExamplesRemainCanonical(t *testing.T) {
	inventory, err := LoadInventory(filepath.Join("..", "data", "yime_syllable_decomposition.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	wants := map[string]YinyuanTuple{
		"yi1": {"N23", "M01", "M01", "M01"},
		"yi2": {"N23", "M03", "M02", "M01"},
		"bu4": {"N01", "M04", "M05", "M06"},
		"bu2": {"N01", "M06", "M05", "M04"},
		"zi5": {"N13", "M20", "M20", "M20"},
		"er5": {"N12", "M23", "M23", "M23"},
	}
	for pinyin, want := range wants {
		if got := inventory.Syllables[pinyin]; got != want {
			t.Errorf("%s tuple = %#v, want %#v", pinyin, got, want)
		}
	}
}

func TestCheckedInSchemaKeepsStageZeroContract(t *testing.T) {
	path := filepath.Join("..", "..", "..", "..", "docs", "project", "connected_speech", "connected_speech_record.schema.json")
	if err := ValidateSchemaDocument(path); err != nil {
		t.Fatal(err)
	}
}

func validToneSandhiRecord() Record {
	surfaceReading := "yi2"
	surface := YinyuanSequence{{"N23", "M03", "M02", "M01"}}
	return Record{
		SchemaVersion: 1, RulesetVersion: "1.0.0", RecordID: "cs-test-yi", RecordRevision: 1,
		Text: "一", CanonicalPinyin: "yi1", Phenomenon: "tone_sandhi", Scope: "construction",
		CandidateTextPolicy: "preserve", AdjudicationStatus: "experimental", RuntimeEnabled: true,
		RuleID: "test.yi.before.qu4", SurfaceReading: &surfaceReading,
		CanonicalYinyuanIDs: YinyuanSequence{{"N23", "M01", "M01", "M01"}}, SurfaceYinyuanIDs: &surface,
		SourceObservations: []SourceObservation{{
			ObservationID: "obs-test-yi", SourcePolicy: "project_manual_v1", SourceLocator: "test:1",
			SourceSHA256: strings.Repeat("0", 64), TextRaw: "一", ReadingRaw: "yi2", TranscriptionStatus: "machine_matched",
		}},
		Rewrites: []Rewrite{
			{SyllableIndex: 0, Position: "huyin", FromID: "M01", ToID: "M03", Attributes: []string{"tone_grade"}},
			{SyllableIndex: 0, Position: "zhuyin", FromID: "M01", ToID: "M02", Attributes: []string{"tone_grade"}},
		},
	}
}

func validNoGrowthToneSandhiRecord() Record {
	surfaceReading := "bu2"
	surface := YinyuanSequence{{"N01", "M06", "M05", "M04"}}
	return Record{
		SchemaVersion: 1, RulesetVersion: "1.0.0", RecordID: "cs-test-bu", RecordRevision: 1,
		Text: "不", CanonicalPinyin: "bu4", Phenomenon: "tone_sandhi", Scope: "construction",
		CandidateTextPolicy: "preserve", AdjudicationStatus: "experimental", RuntimeEnabled: true,
		RuleID: "test.bu.before.qu4", SurfaceReading: &surfaceReading,
		CanonicalYinyuanIDs: YinyuanSequence{{"N01", "M04", "M05", "M06"}}, SurfaceYinyuanIDs: &surface,
		SourceObservations: []SourceObservation{{
			ObservationID: "obs-test-bu", SourcePolicy: "project_manual_v1", SourceLocator: "test:2",
			SourceSHA256: strings.Repeat("1", 64), TextRaw: "不", ReadingRaw: "bu2", TranscriptionStatus: "machine_matched",
		}},
		Rewrites: []Rewrite{
			{SyllableIndex: 0, Position: "huyin", FromID: "M04", ToID: "M06", Attributes: []string{"tone_grade"}},
			{SyllableIndex: 0, Position: "moyin", FromID: "M06", ToID: "M04", Attributes: []string{"tone_grade"}},
		},
	}
}

func validDecreasingProjectionRecord() Record {
	surfaceReading := "yi1"
	surface := YinyuanSequence{{"N23", "M01", "M01", "M01"}}
	return Record{
		SchemaVersion: 1, RulesetVersion: "1.0.0", RecordID: "cs-test-projection-decrease", RecordRevision: 1,
		Text: "一", CanonicalPinyin: "yi2", Phenomenon: "tone_sandhi", Scope: "construction",
		CandidateTextPolicy: "preserve", AdjudicationStatus: "experimental", RuntimeEnabled: true,
		RuleID: "test.projection.decrease", SurfaceReading: &surfaceReading,
		CanonicalYinyuanIDs: YinyuanSequence{{"N23", "M03", "M02", "M01"}}, SurfaceYinyuanIDs: &surface,
		SourceObservations: []SourceObservation{{
			ObservationID: "obs-test-projection-decrease", SourcePolicy: "project_manual_v1", SourceLocator: "test:3",
			SourceSHA256: strings.Repeat("2", 64), TextRaw: "一", ReadingRaw: "yi1", TranscriptionStatus: "machine_matched",
		}},
		Rewrites: []Rewrite{
			{SyllableIndex: 0, Position: "huyin", FromID: "M03", ToID: "M01", Attributes: []string{"tone_grade"}},
			{SyllableIndex: 0, Position: "zhuyin", FromID: "M02", ToID: "M01", Attributes: []string{"tone_grade"}},
		},
	}
}

func hasIssue(issues []Issue, code string) bool {
	for _, issue := range issues {
		if issue.Code == code {
			return true
		}
	}
	return false
}

func writeRecords(t *testing.T, path string, records []Record) {
	t.Helper()
	payload, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	payload = append(payload, '\n')
	if err := os.WriteFile(path, payload, 0o644); err != nil {
		t.Fatal(err)
	}
}
