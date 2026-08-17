package connectedspeech

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestErhuaMixedRuntimeInheritsCoreAndPSCPeripheralWeights(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	outputDir := filepath.Join(root, "out")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dataDir, "yime_pinyin_codes.tsv"), []byte("pinyin_tone\tcode\nming2\tabcd\nbai2\tabcd\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, mode := range erhuaMixedModes {
		writeTestDictionary(t, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"), []string{
			"明白儿\tabcd\t1200",
			"鸟儿\tignored\t9999",
		})
		pscSuffixCode := map[string]string{
			"full": "abcdabcd'III", "variable": "abcdabcd'I", "shorthand": "abdabd'I",
		}[mode]
		writeTestDictionary(t, filepath.Join(dataDir, "yime_psc_peripheral_"+mode+".dict.yaml"), []string{
			"缺权重儿\t" + pscSuffixCode + "\t1",
		})
	}

	aliases := erhuaAliasBundle{
		SchemaVersion: 2,
		Counts: map[string]int{
			"records":                      3,
			"feature_projection_ready":     2,
			"suffix_only_encoding_pending": 1,
		},
		Records: []erhuaAliasRecord{
			testProjectedReadyErhuaAlias("A", "明白儿"),
			testProjectedReadyErhuaAlias("B", "缺权重儿"),
			{RecordID: "C", Text: "待决儿", Status: "suffix_only_encoding_pending"},
		},
	}
	annotations := erhuaAnnotationBundle{
		SchemaVersion: 2,
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
	if manifest.Summary.InheritedWeightRecordCount != 2 || manifest.Summary.CoreWeightRecordCount != 1 ||
		manifest.Summary.PSCPeripheralWeightCount != 1 || manifest.Summary.DeferredMissingWeightCount != 0 {
		t.Fatalf("unexpected summary: %+v", manifest.Summary)
	}
	if manifest.Summary.FixedRuntimeWeight != 1 || manifest.Summary.RoutesPerMode != 3 || manifest.Summary.ReverseLookupRowCount != 2 {
		t.Fatalf("routes/reverse summary=%+v", manifest.Summary)
	}
	if len(manifest.Deferred) != 0 {
		t.Fatalf("unexpected deferred records: %v", manifest.Deferred)
	}
	for _, mode := range erhuaMixedModes {
		content, readErr := os.ReadFile(filepath.Join(outputDir, "yime_erhua_mixed_"+mode+".dict.yaml"))
		if readErr != nil {
			t.Fatal(readErr)
		}
		text := string(content)
		wantByMode := map[string][]string{
			"full":      {"明白儿\tabcdabcd'III\t1", "明白儿\tabcdabcd\t1"},
			"variable":  {"明白儿\tabcdabcd'I\t1", "明白儿\tabcdabcd\t1"},
			"shorthand": {"明白儿\tabdabd'I\t1", "明白儿\tabdabd\t1"},
		}
		for _, want := range wantByMode[mode] {
			if !strings.Contains(text, want) {
				t.Fatalf("%s dictionary lacks %q", mode, want)
			}
		}
		if !strings.Contains(text, "缺权重儿\t"+map[string]string{"full": "abcdabcd", "variable": "abcdabcd", "shorthand": "abdabd"}[mode]+"\t1") {
			t.Fatalf("%s dictionary lacks low-frequency fused route", mode)
		}
		if strings.Contains(text, "缺权重儿\t"+map[string]string{"full": "abcdabcd'III", "variable": "abcdabcd'I", "shorthand": "abdabd'I"}[mode]+"\t1") {
			t.Fatalf("%s dictionary duplicates the PSC suffix-compatible route", mode)
		}
		for _, forbidden := range []string{"鸟儿", "待决儿"} {
			if strings.Contains(text, forbidden) {
				t.Fatalf("%s dictionary unexpectedly contains %s", mode, forbidden)
			}
		}
	}
	reverseSource, err := os.ReadFile(filepath.Join(outputDir, ErhuaReverseSourceFileName))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"A\t明白儿\tpsc_erhua\tming2 bai2 er5", "TEST-FEATURE-RULE", "N01 R01 R02 R03", "M01+rhotic=true+nasalized=false→R01→KEY-H(b)"} {
		if !strings.Contains(string(reverseSource), want) {
			t.Fatalf("reverse source lacks %q:\n%s", want, reverseSource)
		}
	}
	if !strings.Contains(string(reverseSource), "B\t缺权重儿\tpsc_erhua\tming2 bai2 er5") {
		t.Fatalf("reverse source lacks PSC-weighted fused explanation:\n%s", reverseSource)
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
		SchemaVersion: 2,
		Counts:        map[string]int{"feature_projection_ready": 1},
		Records:       []erhuaAliasRecord{testProjectedReadyErhuaAlias("A", "明白儿")},
	})
	writeTestJSON(t, annotationsPath, erhuaAnnotationBundle{
		SchemaVersion: 2,
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

func TestErhuaSoundProjectionAcceptsCarrierSharedWithOneDerivedSound(t *testing.T) {
	_, err := indexErhuaSoundProjection(erhuaSoundProjectionBundle{
		SchemaVersion: 2,
		KeyClasses: []erhuaSoundKeyClass{
			{KeyClassID: "KEY-H", ToneGrade: "high", CarrierYinyuanID: "M01"},
			{KeyClassID: "KEY-M", ToneGrade: "mid", CarrierYinyuanID: "M02"},
			{KeyClassID: "KEY-L", ToneGrade: "low", CarrierYinyuanID: "M03"},
		},
		SoundUnits: []erhuaSoundUnit{
			{SoundUnitID: "R01", BaseYinyuanID: "M01", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "high", RepresentativeIPA: "a", KeyClassID: "KEY-H", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R02", BaseYinyuanID: "M02", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "mid", RepresentativeIPA: "b", KeyClassID: "KEY-M", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R03", BaseYinyuanID: "M03", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "low", RepresentativeIPA: "c", KeyClassID: "KEY-L", AdmissionStatus: "runtime_pilot"},
		},
	}, erhuaYinyuanLayout{FormatVersion: 1, YinyuanIDToKey: map[string]string{"M01": "a", "M02": "b", "M03": "c"}})
	if err != nil {
		t.Fatalf("carrier plus one derived sound is already a shared physical-key projection: %v", err)
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
	record, promoted, err := projectErhuaYinyuanFeatures(record, index)
	if err != nil || !promoted {
		t.Fatalf("feature projection failed: promoted=%t err=%v", promoted, err)
	}
	route := record.Routes["fused_erhua"]
	code := route.Codes["full"]
	code.LayoutKeyCode = "abce"
	route.Codes["full"] = code
	record.Routes["fused_erhua"] = route
	if err := index.validateRouteLayout(record); err == nil || !strings.Contains(err.Error(), "does not match ID projection") {
		t.Fatalf("expected layout projection mismatch, got %v", err)
	}
}

func TestErhuaFeatureProjectionUsesDerivedIDsAcrossThreeModes(t *testing.T) {
	layout := erhuaYinyuanLayout{FormatVersion: 1, YinyuanIDToKey: map[string]string{
		"N01": "a", "N12": "'", "M10": "f", "M11": "d", "M12": "s", "M23": "I",
	}}
	projection := erhuaSoundProjectionBundle{
		SchemaVersion: 2,
		KeyClasses: []erhuaSoundKeyClass{
			{KeyClassID: "A-R-H", ToneGrade: "high", LayoutKey: "F"},
			{KeyClassID: "A-R-M", ToneGrade: "mid", LayoutKey: "D"},
			{KeyClassID: "A-R-L", ToneGrade: "low", LayoutKey: "S"},
		},
		SoundUnits: []erhuaSoundUnit{
			{SoundUnitID: "R10", BaseYinyuanID: "M10", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "oral_a_rhotic", ToneGrade: "high", RepresentativeIPA: "a˞˥", KeyClassID: "A-R-H", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R11", BaseYinyuanID: "M11", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "oral_a_rhotic", ToneGrade: "mid", RepresentativeIPA: "a˞˦", KeyClassID: "A-R-M", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R12", BaseYinyuanID: "M12", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "oral_a_rhotic", ToneGrade: "low", RepresentativeIPA: "a˞˩", KeyClassID: "A-R-L", AdmissionStatus: "runtime_pilot"},
		},
	}
	index, err := indexErhuaSoundProjection(projection, layout)
	if err != nil {
		t.Fatal(err)
	}
	record := erhuaAliasRecord{
		RecordID: "FEATURE-A", Text: "试码儿", Status: "feature_projection_ready",
		Routes: map[string]erhuaRoute{
			"suffix_compatibility": {
				Status: "available", NumericPinyin: "ma4 er5", Codes: map[string]erhuaModeCode{
					"full":      {LayoutKeyCode: "afds'III", YinyuanIDs: []string{"N01", "M10", "M11", "M12", "N12", "M23", "M23", "M23"}, Length: 8},
					"variable":  {LayoutKeyCode: "afds'I", YinyuanIDs: []string{"N01", "M10", "M11", "M12", "N12", "M23"}, Length: 6},
					"shorthand": {LayoutKeyCode: "afs'I", YinyuanIDs: []string{"N01", "M10", "M12", "N12", "M23"}, Length: 5},
				},
			},
			"fused_erhua": {
				Status: "feature_projection_ready", FeatureRuleID: "TEST-A-RHOTIC",
				AttachedSyllableSourceYinyuanIDs: []string{"N01", "M10", "M11", "M12"},
				FeatureRewrites: []erhuaFeatureRewrite{
					{Position: 2, SourceYinyuanID: "M11", BaseYinyuanID: "M11", Features: erhuaFeatures{Rhotic: true}},
					{Position: 3, SourceYinyuanID: "M12", BaseYinyuanID: "M12", Features: erhuaFeatures{Rhotic: true}},
				},
			},
		},
	}
	promoted, ok, err := projectErhuaYinyuanFeatures(record, index)
	if err != nil {
		t.Fatal(err)
	}
	if !ok || promoted.Status != "dual_route_ready" {
		t.Fatalf("pending record was not promoted: %#v", promoted)
	}
	for _, mode := range erhuaMixedModes {
		if got := promoted.Routes["fused_erhua"].Codes[mode].LayoutKeyCode; got != "afDS" {
			t.Fatalf("%s fused code=%q, want afDS", mode, got)
		}
	}
	if err := validateErhuaRouteCodes(promoted); err != nil {
		t.Fatal(err)
	}
	if err := index.validateRouteLayout(promoted); err != nil {
		t.Fatal(err)
	}
	projected, err := index.projectFusedRoute(promoted)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(projected.SoundUnitIDs, " "); got != "N01 M10 R11 R12" {
		t.Fatalf("projected sounds=%q", got)
	}
}

func TestErhuaFeatureProjectionRejectsMissingExplicitFeatureRewrites(t *testing.T) {
	record := erhuaAliasRecord{RecordID: "NO-HEURISTIC", Status: "feature_projection_ready", Routes: map[string]erhuaRoute{
		"fused_erhua": {Status: "feature_projection_ready", FeatureRuleID: "TEST"},
	}}
	_, ok, err := projectErhuaYinyuanFeatures(record, erhuaSoundProjectionIndex{})
	if ok || err == nil || !strings.Contains(err.Error(), "incomplete Yinyuan-feature route") {
		t.Fatalf("missing explicit feature rewrites must not fall back to surface inference: ok=%t err=%v", ok, err)
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
	makeCode := func(value string, ids []string) erhuaModeCode {
		return erhuaModeCode{LayoutKeyCode: value, YinyuanIDs: append([]string(nil), ids...), Length: len(ids)}
	}
	return erhuaAliasRecord{
		RecordID: id,
		Text:     text,
		Status:   "feature_projection_ready",
		Routes: map[string]erhuaRoute{
			"suffix_compatibility": {
				Status:        "available",
				NumericPinyin: "ming2 bai2 er5",
				Codes: map[string]erhuaModeCode{
					"full": makeCode("abcdabcd'III", []string{
						"N01", "M01", "M02", "M03", "N01", "M01", "M02", "M03", "N12", "M23", "M23", "M23",
					}),
					"variable": makeCode("abcdabcd'I", []string{
						"N01", "M01", "M02", "M03", "N01", "M01", "M02", "M03", "N12", "M23",
					}),
					"shorthand": makeCode("abdabd'I", []string{
						"N01", "M01", "M03", "N01", "M01", "M03", "N12", "M23",
					}),
				},
			},
			"fused_erhua": {
				Status:                           "feature_projection_ready",
				FeatureRuleID:                    "TEST-FEATURE-RULE",
				AttachedSyllableSourceYinyuanIDs: []string{"N01", "M01", "M02", "M03"},
				FeatureRewrites: []erhuaFeatureRewrite{
					{Position: 1, SourceYinyuanID: "M01", BaseYinyuanID: "M01", Features: erhuaFeatures{Rhotic: true}},
					{Position: 2, SourceYinyuanID: "M02", BaseYinyuanID: "M02", Features: erhuaFeatures{Rhotic: true}},
					{Position: 3, SourceYinyuanID: "M03", BaseYinyuanID: "M03", Features: erhuaFeatures{Rhotic: true}},
				},
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
			"N01": "a", "N12": "'", "M01": "b", "M02": "c", "M03": "d", "M04": "e", "M23": "I",
		},
	})
	writeTestJSON(t, projectionPath, erhuaSoundProjectionBundle{
		SchemaVersion: 2,
		KeyClasses: []erhuaSoundKeyClass{
			{KeyClassID: "KEY-H", ToneGrade: "high", CarrierYinyuanID: "M01"},
			{KeyClassID: "KEY-M", ToneGrade: "mid", CarrierYinyuanID: "M02"},
			{KeyClassID: "KEY-L", ToneGrade: "low", CarrierYinyuanID: "M03"},
		},
		SoundUnits: []erhuaSoundUnit{
			{SoundUnitID: "R01", BaseYinyuanID: "M01", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "high", RepresentativeIPA: "a", KeyClassID: "KEY-H", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R02", BaseYinyuanID: "M02", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "mid", RepresentativeIPA: "b", KeyClassID: "KEY-M", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R03", BaseYinyuanID: "M03", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "pilot", ToneGrade: "low", RepresentativeIPA: "c", KeyClassID: "KEY-L", AdmissionStatus: "runtime_pilot"},
			{SoundUnitID: "R04", BaseYinyuanID: "M04", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "research", ToneGrade: "high", RepresentativeIPA: "d", KeyClassID: "KEY-H", AdmissionStatus: "research_only"},
			{SoundUnitID: "R05", BaseYinyuanID: "M05", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "research", ToneGrade: "mid", RepresentativeIPA: "e", KeyClassID: "KEY-M", AdmissionStatus: "research_only"},
			{SoundUnitID: "R06", BaseYinyuanID: "M06", Features: erhuaFeatures{Rhotic: true}, QualityFamily: "research", ToneGrade: "low", RepresentativeIPA: "f", KeyClassID: "KEY-L", AdmissionStatus: "research_only"},
		},
	})
}
