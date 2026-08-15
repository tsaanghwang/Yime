package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestErhuaMixedRuntimeExportsOnlyExplicitReadyRecordsWithInheritedWeights(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	outputDir := filepath.Join(root, "out")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, mode := range erhuaMixedModes {
		writeTestDictionary(t, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"), []string{
			"明白儿\tabcd\t1200",
			"鸟儿\tignored\t9999",
		})
	}

	aliases := erhuaAliasBundle{
		SchemaVersion: 1,
		Counts: map[string]int{
			"records":                      3,
			"dual_route_ready":             2,
			"suffix_only_encoding_pending": 1,
		},
		Records: []erhuaAliasRecord{
			testProjectedReadyErhuaAlias("A", "明白儿"),
			testProjectedReadyErhuaAlias("B", "缺权重儿"),
			{RecordID: "C", Text: "待决儿", Status: "suffix_only_encoding_pending"},
		},
	}
	annotations := erhuaAnnotationBundle{
		SchemaVersion: 1,
		Records: []erhuaAnnotationRecord{
			testErhuaAnnotation("A", "明白儿"),
			testErhuaAnnotation("B", "缺权重儿"),
			testErhuaAnnotation("C", "待决儿"),
		},
	}
	aliasesPath := filepath.Join(root, "aliases.json")
	annotationsPath := filepath.Join(root, "annotations.json")
	projectionPath := filepath.Join(root, "projection.json")
	layoutPath := filepath.Join(root, "layout.json")
	writeTestJSON(t, aliasesPath, aliases)
	writeTestJSON(t, annotationsPath, annotations)
	writeTestErhuaProjection(t, projectionPath, layoutPath)

	manifest, err := RunErhuaMixedRuntime(ErhuaMixedRuntimeConfig{
		DataDir: dataDir, AliasesPath: aliasesPath, AnnotationsPath: annotationsPath,
		SoundProjectionPath: projectionPath, LayoutPath: layoutPath, OutputDir: outputDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if manifest.Summary.InheritedWeightRecordCount != 1 || manifest.Summary.DeferredMissingWeightCount != 1 {
		t.Fatalf("unexpected summary: %+v", manifest.Summary)
	}
	if manifest.Summary.ReverseLookupRowCount != 1 {
		t.Fatalf("reverse lookup rows=%d, want 1", manifest.Summary.ReverseLookupRowCount)
	}
	if len(manifest.Deferred) != 1 || manifest.Deferred[0] != "缺权重儿" {
		t.Fatalf("unexpected deferred records: %v", manifest.Deferred)
	}
	for _, mode := range erhuaMixedModes {
		content, readErr := os.ReadFile(filepath.Join(outputDir, "yime_erhua_mixed_"+mode+".dict.yaml"))
		if readErr != nil {
			t.Fatal(readErr)
		}
		text := string(content)
		for _, want := range []string{"明白儿\tabcde\t1200", "明白儿\tabcd\t1200"} {
			if !strings.Contains(text, want) {
				t.Fatalf("%s dictionary lacks %q", mode, want)
			}
		}
		for _, forbidden := range []string{"鸟儿", "缺权重儿", "待决儿"} {
			if strings.Contains(text, forbidden) {
				t.Fatalf("%s dictionary unexpectedly contains %s", mode, forbidden)
			}
		}
	}
	reverseSource, err := os.ReadFile(filepath.Join(outputDir, ErhuaReverseSourceFileName))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"A\t明白儿\tpsc_erhua\tming2 bai2 er5", "TEST-ERHUA-ORAL", "N01 R01 R02 R03", "R01→KEY-H→M01(b)"} {
		if !strings.Contains(string(reverseSource), want) {
			t.Fatalf("reverse source lacks %q:\n%s", want, reverseSource)
		}
	}
}

func TestErhuaMixedRuntimeRejectsUnmatchedAuthorization(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, mode := range erhuaMixedModes {
		writeTestDictionary(t, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"), []string{"明白儿\tabcd\t1200"})
	}
	aliasesPath := filepath.Join(root, "aliases.json")
	annotationsPath := filepath.Join(root, "annotations.json")
	projectionPath := filepath.Join(root, "projection.json")
	layoutPath := filepath.Join(root, "layout.json")
	writeTestJSON(t, aliasesPath, erhuaAliasBundle{
		SchemaVersion: 1,
		Counts:        map[string]int{"dual_route_ready": 1},
		Records:       []erhuaAliasRecord{testProjectedReadyErhuaAlias("A", "明白儿")},
	})
	writeTestJSON(t, annotationsPath, erhuaAnnotationBundle{
		SchemaVersion: 1,
		Records:       []erhuaAnnotationRecord{testErhuaAnnotation("OTHER", "明白儿")},
	})
	writeTestErhuaProjection(t, projectionPath, layoutPath)
	_, err := RunErhuaMixedRuntime(ErhuaMixedRuntimeConfig{
		DataDir: dataDir, AliasesPath: aliasesPath, AnnotationsPath: annotationsPath,
		SoundProjectionPath: projectionPath, LayoutPath: layoutPath, OutputDir: filepath.Join(root, "out"),
	})
	if err == nil || !strings.Contains(err.Error(), "lacks matching explicit erhua authorization") {
		t.Fatalf("expected explicit authorization failure, got %v", err)
	}
}

func TestErhuaMixedRuntimeRejectsFusedCodeLongerThanCompatibilityCode(t *testing.T) {
	record := testReadyErhuaAlias("A", "明白儿", "abc", "abcd")
	if err := validateErhuaRouteCodes(record); err == nil || !strings.Contains(err.Error(), "longer") {
		t.Fatalf("expected code-length failure, got %v", err)
	}
}

func TestErhuaSoundProjectionRejectsOneSoundPerKeyDisguise(t *testing.T) {
	_, err := indexErhuaSoundProjection(erhuaSoundProjectionBundle{
		SchemaVersion: 1,
		KeyClasses: []erhuaSoundKeyClass{
			{KeyClassID: "KEY-H", ToneGrade: "high", CarrierYinyuanID: "M01"},
		},
		SoundUnits: []erhuaSoundUnit{
			{SoundUnitID: "R01", QualityFamily: "pilot", ToneGrade: "high", RepresentativeIPA: "a", KeyClassID: "KEY-H", AdmissionStatus: "runtime_pilot"},
		},
		SurfaceClasses: []erhuaSurfaceProjection{
			{SurfaceClass: "TEST", RuntimeStatus: "pilot", RhoticFinalPositions: []int{1}, SoundFamily: "pilot"},
		},
	}, erhuaYinyuanLayout{FormatVersion: 1, YinyuanIDToKey: map[string]string{"M01": "a"}})
	if err == nil || !strings.Contains(err.Error(), "does not demonstrate many-to-one") {
		t.Fatalf("expected many-to-one projection failure, got %v", err)
	}
}

func TestErhuaMixedRuntimeRejectsHandWrittenLayoutCodeMismatch(t *testing.T) {
	root := t.TempDir()
	projectionPath := filepath.Join(root, "projection.json")
	layoutPath := filepath.Join(root, "layout.json")
	writeTestErhuaProjection(t, projectionPath, layoutPath)
	projection, err := loadErhuaSoundProjection(projectionPath)
	if err != nil {
		t.Fatal(err)
	}
	layout, err := loadErhuaYinyuanLayout(layoutPath)
	if err != nil {
		t.Fatal(err)
	}
	index, err := indexErhuaSoundProjection(projection, layout)
	if err != nil {
		t.Fatal(err)
	}
	record := testProjectedReadyErhuaAlias("A", "明白儿")
	route := record.Routes["fused_erhua"]
	code := route.Codes["full"]
	code.LayoutKeyCode = "abce"
	route.Codes["full"] = code
	record.Routes["fused_erhua"] = route
	if err := index.validateRouteLayout(record); err == nil || !strings.Contains(err.Error(), "does not match ID projection") {
		t.Fatalf("expected layout projection mismatch, got %v", err)
	}
}

func testReadyErhuaAlias(id, text, suffixCode, fusedCode string) erhuaAliasRecord {
	makeCodes := func(value string) map[string]erhuaModeCode {
		result := map[string]erhuaModeCode{}
		for _, mode := range erhuaMixedModes {
			ids := make([]string, len([]rune(value)))
			for index := range ids {
				ids[index] = "M01"
			}
			result[mode] = erhuaModeCode{LayoutKeyCode: value, YinyuanIDs: ids, Length: len(ids)}
		}
		return result
	}
	return erhuaAliasRecord{
		RecordID: id,
		Text:     text,
		Status:   "dual_route_ready",
		Routes: map[string]erhuaRoute{
			"suffix_compatibility": {Status: "available", NumericPinyin: "ming2 bai2 er5", Codes: makeCodes(suffixCode)},
			"fused_erhua":          {Status: "available", AttachedSyllableSource: "bai2", Codes: makeCodes(fusedCode)},
		},
	}
}

func testProjectedReadyErhuaAlias(id, text string) erhuaAliasRecord {
	makeCode := func(value string, ids []string) map[string]erhuaModeCode {
		result := map[string]erhuaModeCode{}
		for _, mode := range erhuaMixedModes {
			result[mode] = erhuaModeCode{LayoutKeyCode: value, YinyuanIDs: append([]string(nil), ids...), Length: len(ids)}
		}
		return result
	}
	return erhuaAliasRecord{
		RecordID: id,
		Text:     text,
		Status:   "dual_route_ready",
		Routes: map[string]erhuaRoute{
			"suffix_compatibility": {
				Status:        "available",
				NumericPinyin: "ming2 bai2 er5",
				Codes:         makeCode("abcde", []string{"N01", "M01", "M02", "M03", "M04"}),
			},
			"fused_erhua": {
				Status:                     "available",
				SurfaceClass:               "TEST-ERHUA-ORAL",
				AttachedSyllableSource:     "bai2",
				AttachedSyllableYinyuanIDs: []string{"N01", "M01", "M02", "M03"},
				Codes:                      makeCode("abcd", []string{"N01", "M01", "M02", "M03"}),
			},
		},
	}
}

func testErhuaAnnotation(id, text string) erhuaAnnotationRecord {
	return erhuaAnnotationRecord{
		RecordID:            id,
		RecordType:          "explicit_word_final_erhua",
		Text:                text,
		ProductiveInference: "forbidden",
		Authorization:       erhuaAnnotationAuthorization{SourceKind: "psc_erhua"},
	}
}

func writeTestDictionary(t *testing.T, path string, rows []string) {
	t.Helper()
	content := "# Rime dictionary\n---\nname: test\nversion: \"1\"\nsort: by_weight\n...\n" + strings.Join(rows, "\n") + "\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeTestJSON(t *testing.T, path string, payload any) {
	t.Helper()
	content, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, content, 0o644); err != nil {
		t.Fatal(err)
	}
}

func writeTestErhuaProjection(t *testing.T, projectionPath, layoutPath string) {
	t.Helper()
	writeTestJSON(t, layoutPath, erhuaYinyuanLayout{
		FormatVersion: 1,
		YinyuanIDToKey: map[string]string{
			"N01": "a", "M01": "b", "M02": "c", "M03": "d", "M04": "e",
		},
	})
	writeTestJSON(t, projectionPath, erhuaSoundProjectionBundle{
		SchemaVersion: 1,
		KeyClasses: []erhuaSoundKeyClass{
			{KeyClassID: "KEY-H", ToneGrade: "high", CarrierYinyuanID: "M01"},
			{KeyClassID: "KEY-M", ToneGrade: "mid", CarrierYinyuanID: "M02"},
			{KeyClassID: "KEY-L", ToneGrade: "low", CarrierYinyuanID: "M03"},
		},
		SoundUnits: []erhuaSoundUnit{
			{SoundUnitID: "R01", QualityFamily: "pilot", ToneGrade: "high", RepresentativeIPA: "a", KeyClassID: "KEY-H", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R02", QualityFamily: "pilot", ToneGrade: "mid", RepresentativeIPA: "b", KeyClassID: "KEY-M", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R03", QualityFamily: "pilot", ToneGrade: "low", RepresentativeIPA: "c", KeyClassID: "KEY-L", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R04", QualityFamily: "research", ToneGrade: "high", RepresentativeIPA: "d", KeyClassID: "KEY-H", AdmissionStatus: "research_only"},
			{SoundUnitID: "R05", QualityFamily: "research", ToneGrade: "mid", RepresentativeIPA: "e", KeyClassID: "KEY-M", AdmissionStatus: "research_only"},
			{SoundUnitID: "R06", QualityFamily: "research", ToneGrade: "low", RepresentativeIPA: "f", KeyClassID: "KEY-L", AdmissionStatus: "research_only"},
		},
		SurfaceClasses: []erhuaSurfaceProjection{
			{SurfaceClass: "TEST-ERHUA-ORAL", RuntimeStatus: "pilot", RhoticFinalPositions: []int{1, 2, 3}, RetainedPositionYinyuanIDs: map[string][]string{}, SoundFamily: "pilot"},
		},
	})
}
