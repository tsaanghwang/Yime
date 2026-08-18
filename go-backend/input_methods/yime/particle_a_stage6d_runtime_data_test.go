package yime

import (
	"path/filepath"
	"strings"
	"testing"
)

type bundledParticleAStage6DManifest struct {
	ToolVersion  string            `json:"tool_version"`
	OutputSHA256 map[string]string `json:"output_sha256"`
	Summary      struct {
		ExcludedCandidateCount       int             `json:"excluded_candidate_count"`
		EligibleCandidateCount       int             `json:"eligible_candidate_count"`
		EligibleOccurrenceCount      int             `json:"eligible_occurrence_count"`
		RetainedMedialCandidateCount int             `json:"retained_medial_candidate_count"`
		FinalCandidateCount          int             `json:"final_candidate_count"`
		KeyChangingCandidateCount    int             `json:"key_changing_candidate_count"`
		SharedKeyCandidateCount      int             `json:"shared_key_candidate_count"`
		MaterializedCandidateCount   int             `json:"materialized_candidate_count"`
		ModeRowCounts                map[string]int  `json:"mode_row_counts"`
		ThreeModeRowCount            int             `json:"three_mode_row_count"`
		FixedRuntimeWeight           int             `json:"fixed_runtime_weight"`
		CanonicalRoutesPreserved     bool            `json:"canonical_routes_preserved"`
		Gates                        map[string]bool `json:"gates"`
		Passed                       bool            `json:"passed"`
	} `json:"summary"`
}

func TestBundledParticleAStage6DRuntimeCoversAllSourceScreenedCandidates(t *testing.T) {
	var manifest bundledParticleAStage6DManifest
	readJSONFile(t, "yime_particle_a_stage6d_manifest.json", &manifest)
	excluded, err := loadSystemCandidateExclusions(filepath.Join("data", systemCandidateExclusionsFileName))
	if err != nil {
		t.Fatal(err)
	}
	if manifest.ToolVersion != "connected-speech-particle-a-stage6d-runtime-v2" ||
		manifest.Summary.ExcludedCandidateCount != 42 || manifest.Summary.EligibleCandidateCount != 6679 ||
		manifest.Summary.EligibleOccurrenceCount != 6680 || manifest.Summary.RetainedMedialCandidateCount != 29 ||
		manifest.Summary.FinalCandidateCount != 6651 || manifest.Summary.KeyChangingCandidateCount != 5618 ||
		manifest.Summary.SharedKeyCandidateCount != 1061 || manifest.Summary.MaterializedCandidateCount != 5618 ||
		manifest.Summary.ThreeModeRowCount != 16854 ||
		manifest.Summary.FixedRuntimeWeight != 1 || !manifest.Summary.CanonicalRoutesPreserved || !manifest.Summary.Passed {
		t.Fatalf("unexpected Stage 6D manifest: %#v", manifest)
	}
	for gate, passed := range manifest.Summary.Gates {
		if !passed {
			t.Fatalf("Stage 6D gate %s failed", gate)
		}
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_particle_a_stage6d_" + mode + ".dict.yaml"
		if got := fileSHA256(t, filepath.Join("data", name)); got != manifest.OutputSHA256[name] {
			t.Fatalf("%s hash mismatch", name)
		}
		entries := readBundledErhuaDictionary(t, filepath.Join("data", name))
		if len(entries) != 5618 || manifest.Summary.ModeRowCounts[mode] != 5618 {
			t.Fatalf("%s entries=%d, want 5618", name, len(entries))
		}
		foundFinal, foundMedial := false, false
		for _, entry := range entries {
			if entry.Weight != 1 || !strings.Contains(entry.Text, "啊") {
				t.Fatalf("%s invalid Stage 6D alias: %#v", name, entry)
			}
			if entry.Text == "样子啊" {
				foundFinal = true
			}
			if entry.Text == "走啊走" {
				foundMedial = true
			}
			if _, blocked := excluded[entry.Text]; entry.Text == "情况啊" || blocked {
				t.Fatalf("%s materialized a shared-key or source-excluded record", name)
			}
		}
		if !foundFinal || !foundMedial {
			t.Fatalf("%s lacks final/medial all-scope samples", name)
		}
	}
}
