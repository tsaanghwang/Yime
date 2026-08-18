package connectedspeech

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParticleAStage6DRuntimeMaterializesAllSourceScreenedAliases(t *testing.T) {
	repoRoot, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	config := DefaultParticleAStage6DConfig(repoRoot)
	config.OutputDir = t.TempDir()
	manifest, err := RunParticleAStage6DRuntime(config)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("Stage 6D summary: %#v", manifest.Summary)
	if !manifest.Summary.Passed || manifest.Summary.ExcludedCandidateCount != 42 ||
		manifest.Summary.RetainedMedialCandidateCount != 29 ||
		manifest.Summary.EligibleCandidateCount < 6600 || manifest.Summary.FinalCandidateCount < 6500 ||
		manifest.Summary.EligibleOccurrenceCount < manifest.Summary.EligibleCandidateCount ||
		manifest.Summary.KeyChangingCandidateCount+manifest.Summary.SharedKeyCandidateCount != manifest.Summary.EligibleCandidateCount ||
		manifest.Summary.FixedRuntimeWeight != 1 || !manifest.Summary.CanonicalRoutesPreserved {
		t.Fatalf("unexpected Stage 6D summary: %#v", manifest.Summary)
	}
	rowTotal := 0
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join(config.OutputDir, "yime_particle_a_stage6d_"+mode+".dict.yaml")
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		lines := strings.Split(strings.TrimSpace(string(payload)), "\n")
		entries, foundFinal, foundMedial := 0, false, false
		for _, line := range lines {
			fields := strings.Split(line, "\t")
			if len(fields) != 3 {
				continue
			}
			entries++
			if fields[2] != "1" || fields[0] == "你啊我" || fields[0] == "对啊网" {
				t.Fatalf("%s contains invalid or source-excluded runtime row: %q", mode, line)
			}
			foundFinal = foundFinal || fields[0] == "样子啊"
			foundMedial = foundMedial || fields[0] == "走啊走"
		}
		if entries != manifest.Summary.ModeRowCounts[mode] || entries < 5000 || !foundFinal || !foundMedial {
			t.Fatalf("%s entries=%d summary=%d final=%v medial=%v", mode, entries, manifest.Summary.ModeRowCounts[mode], foundFinal, foundMedial)
		}
		rowTotal += entries
	}
	if rowTotal != manifest.Summary.ThreeModeRowCount {
		t.Fatalf("three-mode rows=%d, summary=%d", rowTotal, manifest.Summary.ThreeModeRowCount)
	}
}
