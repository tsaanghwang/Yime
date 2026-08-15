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
			testReadyErhuaAlias("A", "明白儿", "abcd", "abc"),
			testReadyErhuaAlias("B", "缺权重儿", "efgh", "efg"),
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
	writeTestJSON(t, aliasesPath, aliases)
	writeTestJSON(t, annotationsPath, annotations)

	manifest, err := RunErhuaMixedRuntime(ErhuaMixedRuntimeConfig{
		DataDir: dataDir, AliasesPath: aliasesPath, AnnotationsPath: annotationsPath, OutputDir: outputDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if manifest.Summary.InheritedWeightRecordCount != 1 || manifest.Summary.DeferredMissingWeightCount != 1 {
		t.Fatalf("unexpected summary: %+v", manifest.Summary)
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
		for _, want := range []string{"明白儿\tabcd\t1200", "明白儿\tabc\t1200"} {
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
	writeTestJSON(t, aliasesPath, erhuaAliasBundle{
		SchemaVersion: 1,
		Counts:        map[string]int{"dual_route_ready": 1},
		Records:       []erhuaAliasRecord{testReadyErhuaAlias("A", "明白儿", "abcd", "abc")},
	})
	writeTestJSON(t, annotationsPath, erhuaAnnotationBundle{
		SchemaVersion: 1,
		Records:       []erhuaAnnotationRecord{testErhuaAnnotation("OTHER", "明白儿")},
	})
	_, err := RunErhuaMixedRuntime(ErhuaMixedRuntimeConfig{
		DataDir: dataDir, AliasesPath: aliasesPath, AnnotationsPath: annotationsPath, OutputDir: filepath.Join(root, "out"),
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
			"suffix_compatibility": {Status: "available", Codes: makeCodes(suffixCode)},
			"fused_erhua":          {Status: "available", Codes: makeCodes(fusedCode)},
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
