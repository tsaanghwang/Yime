package connectedspeech

import (
	"path/filepath"
	"testing"
)

func TestSelectNeutralStage3SamplesCoversRiskAndContext(t *testing.T) {
	aliases := map[string]*neutralStage3Sample{}
	add := func(text, weight, classID, effect string) {
		aliases[text] = &neutralStage3Sample{
			Text: text, NumericPinyin: text, Weight: weight, ContextClasses: classID, RankEffect: effect,
			ModeEffects: map[string]string{"full": effect, "variable": effect, "shorthand": effect},
		}
	}
	add("a", "100", "after_t1_level2", "no_competitor")
	add("b", "90", "after_t2_level3", "would_tie_top")
	add("c", "80", "after_t3_level4", "would_become_top")
	add("d", "70", "after_t4_level1", "below_existing_top")
	add("e", "60", "after_t1_level2", "no_competitor")

	selected := selectNeutralStage3Samples(aliases, 1)
	if len(selected) != 4 {
		t.Fatalf("got %d samples, want four risk/context representatives: %#v", len(selected), selected)
	}
	seenEffects := map[string]bool{}
	seenClasses := map[string]bool{}
	for _, sample := range selected {
		seenEffects[sample.RankEffect] = true
		seenClasses[sample.ContextClasses] = true
	}
	if len(seenEffects) != 4 || len(seenClasses) != 4 {
		t.Fatalf("selection did not cover risk and context: effects=%v classes=%v", seenEffects, seenClasses)
	}
}

func TestNeutralStage3TrialRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultNeutralStage3TrialConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "neutral-tone-stage3-1-rime")
	if _, err := RunNeutralStage3RimeTrial(config); err == nil {
		t.Fatal("expected Stage 3-1 output outside .tmp to be rejected")
	}
}
