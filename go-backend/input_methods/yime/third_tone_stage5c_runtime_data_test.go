package yime

import (
	"path/filepath"
	"strings"
	"testing"
)

type bundledThirdToneStage5CManifest struct {
	ToolVersion  string            `json:"tool_version"`
	OutputSHA256 map[string]string `json:"output_sha256"`
	Summary      struct {
		ApprovedAliasCount       int             `json:"approved_alias_count"`
		ThreeModeRowCount        int             `json:"three_mode_row_count"`
		FixedRuntimeWeight       int             `json:"fixed_runtime_weight"`
		CanonicalRoutesPreserved bool            `json:"canonical_routes_preserved"`
		Gates                    map[string]bool `json:"gates"`
		Passed                   bool            `json:"passed"`
	} `json:"summary"`
}

func TestBundledThirdToneStage5CRuntimeIsCompleteAndLowFrequency(t *testing.T) {
	var manifest bundledThirdToneStage5CManifest
	readJSONFile(t, "yime_third_tone_stage5c_manifest.json", &manifest)
	if manifest.ToolVersion != "connected-speech-third-tone-stage5c-runtime-v1" ||
		manifest.Summary.ApprovedAliasCount != 24 || manifest.Summary.ThreeModeRowCount != 72 ||
		manifest.Summary.FixedRuntimeWeight != 1 || !manifest.Summary.CanonicalRoutesPreserved || !manifest.Summary.Passed {
		t.Fatalf("unexpected Stage 5C manifest: %#v", manifest)
	}
	for gate, passed := range manifest.Summary.Gates {
		if !passed {
			t.Fatalf("Stage 5C gate %s failed", gate)
		}
	}
	wantSurface := map[string]string{
		"full": "bldu ylsz", "variable": "bldu ylsz", "shorthand": "bldu ylsz",
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_third_tone_stage5c_" + mode + ".dict.yaml"
		if got := fileSHA256(t, filepath.Join("data", name)); got != manifest.OutputSHA256[name] {
			t.Fatalf("%s hash mismatch", name)
		}
		entries := readBundledErhuaDictionary(t, filepath.Join("data", name))
		if len(entries) != 24 {
			t.Fatalf("%s entries=%d, want 24", name, len(entries))
		}
		foundTable := false
		for _, entry := range entries {
			if entry.Weight != 1 || len(strings.Fields(entry.Code)) != 2 {
				t.Fatalf("%s invalid low-frequency sentence alias: %#v", name, entry)
			}
			if entry.Text == "表演" && entry.Code == wantSurface[mode] {
				foundTable = true
			}
		}
		if !foundTable {
			t.Fatalf("%s lacks reviewed 表演 surface code %q", name, wantSurface[mode])
		}
	}
}
