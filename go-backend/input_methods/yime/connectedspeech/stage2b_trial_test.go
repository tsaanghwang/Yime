package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestStage2BTrialWritesOnlyTemporaryThreeModeLexicons(t *testing.T) {
	records := []Record{validToneSandhiRecord(), validNoGrowthToneSandhiRecord()}
	fixture := newAuditFixture(t, records)
	config := Stage2BTrialConfig{
		RepoRoot: fixture.root, DataDir: fixture.config.DataDir, RecordsPath: fixture.config.RecordsPath,
		SchemaPath:        fixture.config.SchemaPath,
		OutputDir:         filepath.Join(fixture.root, ".tmp", "connected-speech-stage2b-rime"),
		AllowedOutputRoot: filepath.Join(fixture.root, ".tmp"),
	}
	profile := testProfile(t)
	firstCanonical, err := projectSequence(records[0].CanonicalYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	secondCanonical, err := projectSequence(records[1].CanonicalYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	firstSurface, err := projectSequence(*records[0].SurfaceYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	secondSurface, err := projectSequence(*records[1].SurfaceYinyuanIDs, profile)
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range stage2BTrialModes {
		content := "---\nname: yime_" + mode.Mode + "\n...\n" +
			"一\t" + recordCode(firstCanonical, mode.Mode) + "\t2024\n" +
			"不\t" + recordCode(secondCanonical, mode.Mode) + "\t9342\n"
		writeText(t, filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml"), content)
	}
	before := map[string][]byte{}
	for _, name := range stage2BTrialBaselineFiles {
		payload, err := os.ReadFile(filepath.Join(config.DataDir, name))
		if err != nil {
			t.Fatal(err)
		}
		before[name] = payload
	}

	result, err := RunStage2BRimeTrial(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.TrialAliasCount != 2 || result.Summary.ThreeModeEntryCount != 6 {
		t.Fatalf("unexpected Stage 2B summary: %#v", result.Summary)
	}
	if result.Summary.StaticDictionaryAliases != 2 || result.Summary.DynamicCandidateAliases != 0 {
		t.Fatalf("unexpected Stage 2B weight classification: %#v", result.Summary)
	}
	if result.Summary.RuntimeAliasesGenerated != 0 || result.Summary.GrowingProjectionCount == 0 {
		t.Fatalf("Stage 2B did not preserve the offline/growing-projection contract: %#v", result.Summary)
	}
	for _, mode := range stage2BTrialModes {
		dictionary, err := os.ReadFile(filepath.Join(config.OutputDir, mode.Dictionary))
		if err != nil {
			t.Fatal(err)
		}
		text := string(dictionary)
		if strings.Contains(text, "import_tables:") || !strings.Contains(text, "一\t") || !strings.Contains(text, "不\t") {
			t.Fatalf("incomplete %s trial dictionary:\n%s", mode.Mode, text)
		}
		if !strings.Contains(text, "一\t"+recordCode(firstCanonical, mode.Mode)+"\t2024") ||
			!strings.Contains(text, "不\t"+recordCode(secondCanonical, mode.Mode)+"\t9342") {
			t.Fatalf("%s trial dictionary did not inherit canonical weights:\n%s", mode.Mode, text)
		}
		if !strings.Contains(text, "一\t"+recordCode(firstSurface, mode.Mode)+"\t2024") ||
			!strings.Contains(text, "不\t"+recordCode(secondSurface, mode.Mode)+"\t9342") {
			t.Fatalf("%s trial aliases did not inherit canonical weights:\n%s", mode.Mode, text)
		}
		baseline, err := os.ReadFile(filepath.Join(config.OutputDir, mode.BaselineDictionary))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Count(string(baseline), "一\t") != 1 || strings.Count(string(baseline), "不\t") != 1 {
			t.Fatalf("%s baseline dictionary must contain only canonical fixtures:\n%s", mode.Mode, baseline)
		}
		patch, err := os.ReadFile(filepath.Join(config.OutputDir, mode.Patch))
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(patch), "translator/dictionary: yime_connected_speech_stage2b_"+mode.Mode) {
			t.Fatalf("wrong %s schema patch: %s", mode.Mode, patch)
		}
		if !strings.Contains(string(patch), "translator/enable_sentence: false") {
			t.Fatalf("%s trial patch did not isolate direct dictionary aliases: %s", mode.Mode, patch)
		}
	}
	entries, err := os.ReadFile(filepath.Join(config.OutputDir, "stage2b_entries.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	entryText := string(entries)
	if !strings.Contains(entryText, "inherited_weight") || strings.Count(entryText, "\t2024\t") != 3 || strings.Count(entryText, "\t9342\t") != 3 {
		t.Fatalf("Stage 2B entry report did not preserve three-mode inherited weights:\n%s", entryText)
	}
	for name, want := range before {
		got, err := os.ReadFile(filepath.Join(config.DataDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("Stage 2B trial modified canonical input %s", name)
		}
	}
}

func TestStage2BTrialRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultStage2BTrialConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "connected-speech-stage2b-rime")
	if _, err := RunStage2BRimeTrial(config); err == nil {
		t.Fatal("expected Stage 2B output outside .tmp to be rejected")
	}
}

func TestStage2BTrialRoutesAliasWithoutStaticWeightToDynamicPolicy(t *testing.T) {
	records := []Record{validToneSandhiRecord(), validNoGrowthToneSandhiRecord()}
	fixture := newAuditFixture(t, records)
	config := Stage2BTrialConfig{
		RepoRoot: fixture.root, DataDir: fixture.config.DataDir, RecordsPath: fixture.config.RecordsPath,
		SchemaPath:        fixture.config.SchemaPath,
		OutputDir:         filepath.Join(fixture.root, ".tmp", "connected-speech-stage2b-rime"),
		AllowedOutputRoot: filepath.Join(fixture.root, ".tmp"),
	}
	result, err := RunStage2BRimeTrial(config)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Summary.Passed || result.Summary.StaticDictionaryAliases != 1 || result.Summary.DynamicCandidateAliases != 1 {
		t.Fatalf("missing static weight was not routed to the dynamic policy: %#v", result.Summary)
	}
	entries, err := os.ReadFile(filepath.Join(config.OutputDir, "stage2b_entries.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(string(entries), stage2BDynamicWeight) != 3 {
		t.Fatalf("dynamic weight policy was not reported for all three modes:\n%s", entries)
	}
	for _, mode := range stage2BTrialModes {
		dictionary, err := os.ReadFile(filepath.Join(config.OutputDir, mode.Dictionary))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(dictionary), records[1].Text+"\t") {
			t.Fatalf("dynamic candidate was incorrectly materialized with a fabricated static weight in %s:\n%s", mode.Mode, dictionary)
		}
	}
}

func TestStage2BTrialRejectsInconsistentCanonicalWeightsAcrossModes(t *testing.T) {
	records := []Record{validToneSandhiRecord(), validNoGrowthToneSandhiRecord()}
	fixture := newAuditFixture(t, records)
	config := Stage2BTrialConfig{
		RepoRoot: fixture.root, DataDir: fixture.config.DataDir, RecordsPath: fixture.config.RecordsPath,
		SchemaPath:        fixture.config.SchemaPath,
		OutputDir:         filepath.Join(fixture.root, ".tmp", "connected-speech-stage2b-rime"),
		AllowedOutputRoot: filepath.Join(fixture.root, ".tmp"),
	}
	profile := testProfile(t)
	for _, mode := range stage2BTrialModes {
		weight := "200"
		if mode.Mode == "shorthand" {
			weight = "201"
		}
		for _, record := range records {
			canonical, err := projectSequence(record.CanonicalYinyuanIDs, profile)
			if err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml")
			file, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := file.WriteString(record.Text + "\t" + recordCode(canonical, mode.Mode) + "\t" + weight + "\n"); err != nil {
				file.Close()
				t.Fatal(err)
			}
			if err := file.Close(); err != nil {
				t.Fatal(err)
			}
		}
	}
	if _, err := RunStage2BRimeTrial(config); err == nil || !strings.Contains(err.Error(), "inconsistent canonical weights across modes") {
		t.Fatalf("inconsistent canonical weights were not rejected: %v", err)
	}
}
