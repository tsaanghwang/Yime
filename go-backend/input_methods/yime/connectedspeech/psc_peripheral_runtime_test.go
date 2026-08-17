package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func TestPSCPeripheralRuntimeFiltersSourcesAndPreservesCore(t *testing.T) {
	t.Parallel()
	temp := t.TempDir()
	catalogPath := filepath.Join(temp, "psc_candidate_readings.json")
	outputDir := filepath.Join(temp, "output")
	sourcePath := filepath.Join(temp, "psc_pronunciation_peripheral_source.json")
	if err := os.MkdirAll(outputDir, 0o755); err != nil {
		t.Fatal(err)
	}
	codesPath := filepath.Join("..", "data", "yime_pinyin_codes.tsv")
	codes, err := loadPSCFullCodes(codesPath)
	if err != nil {
		t.Fatal(err)
	}
	duplicateFull := codes["hua1"] + codes["er5"]
	duplicateRecord, err := codemode.BuildRecord(duplicateFull)
	if err != nil {
		t.Fatal(err)
	}
	coreByMode := map[string]string{
		"full":      duplicateRecord.FullSpelling,
		"variable":  duplicateRecord.VariableSpelling,
		"shorthand": duplicateRecord.ShorthandSpelling,
	}
	coreHashes := map[string]string{}
	for _, mode := range pscPeripheralModes {
		path := filepath.Join(outputDir, "yime_"+mode+".dict.yaml")
		body := "---\nname: yime_" + mode + "\n...\n花儿\t" + coreByMode[mode] + "\t999\n"
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		coreHashes[mode], err = fileSHA256(path)
		if err != nil {
			t.Fatal(err)
		}
	}
	catalog := pscCandidateCatalog{
		SchemaVersion: "yime-reviewed-psc-candidate-readings-v1",
		Records: []pscCandidateCoverageRecord{
			pscTestRecord("花儿", "hua1 er5", "psc_erhua", true),
			pscTestRecord("阿们", "a1 men5", "psc_neutral_tone", true),
			pscTestRecord("测试", "ce4 shi4", "psc_main", true),
			pscTestRecord("蒜瓣", "suan4 ban4", "psc_erhua", true),
			pscTestRecord("未审", "wei4 shen3", "psc_neutral_tone", false),
		},
	}
	data, err := json.Marshal(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(catalogPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	manifest, err := RunPSCPeripheralRuntime(PSCPeripheralRuntimeConfig{
		CatalogPath: catalogPath,
		CodesPath:   codesPath,
		DataDir:     outputDir,
		SourcePath:  sourcePath,
		OutputDir:   outputDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !manifest.Summary.Passed || manifest.Summary.SourceRecordCount != 2 ||
		manifest.Summary.EncodedRecordCount != 1 || manifest.Summary.AlreadyInCoreRecordCount != 1 ||
		manifest.Summary.NeutralToneRecordCount != 1 || manifest.Summary.ErhuaRecordCount != 1 {
		t.Fatalf("unexpected summary: %#v", manifest.Summary)
	}
	for _, mode := range pscPeripheralModes {
		corePath := filepath.Join(outputDir, "yime_"+mode+".dict.yaml")
		gotHash, hashErr := fileSHA256(corePath)
		if hashErr != nil {
			t.Fatal(hashErr)
		}
		if gotHash != coreHashes[mode] {
			t.Fatalf("%s core dictionary changed", mode)
		}
		output, readErr := os.ReadFile(filepath.Join(outputDir, "yime_psc_peripheral_"+mode+".dict.yaml"))
		if readErr != nil {
			t.Fatal(readErr)
		}
		text := string(output)
		if !strings.Contains(text, "阿们\t") || !strings.Contains(text, "\t1\n") {
			t.Fatalf("%s peripheral dictionary lacks fixed-low-frequency entry:\n%s", mode, text)
		}
		for _, line := range strings.Split(text, "\n") {
			if strings.HasPrefix(line, "阿们\t") {
				fields := strings.Split(line, "\t")
				if len(fields) != 3 || strings.Contains(fields[1], " ") {
					t.Fatalf("%s table dictionary code must be continuous: %q", mode, line)
				}
			}
		}
		for _, excluded := range []string{"花儿\t", "测试\t", "蒜瓣\t", "未审\t"} {
			if strings.Contains(text, excluded) {
				t.Fatalf("%s peripheral dictionary unexpectedly contains %q", mode, excluded)
			}
		}
	}
	var snapshot PSCPeripheralSource
	snapshotData, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(snapshotData, &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Records) != 2 || snapshot.Counts["records"] != 2 {
		t.Fatalf("unexpected source snapshot: %#v", snapshot.Counts)
	}
}

func pscTestRecord(text, numeric, sourceKind string, reviewed bool) pscCandidateCoverageRecord {
	state := "pending"
	if reviewed {
		state = "confirmed"
	}
	return pscCandidateCoverageRecord{
		Text:           text,
		NumericPinyin:  numeric,
		Source:         "psc_candidate_coverage",
		SourceCategory: pscPeripheralSourceCategory,
		CandidateLayer: pscPeripheralCandidateLayer,
		SourcePrimary:  false,
		Evidence: []pscCandidateEvidence{{
			SourceKind:   sourceKind,
			SourceKey:    sourceKind + ":1",
			ReviewState:  state,
			SourceText:   text,
			ExpandedText: text,
		}},
	}
}
