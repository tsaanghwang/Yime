package connectedspeech

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNeutralStage3FullBatchRejectsOutputOutsideTemporaryRoot(t *testing.T) {
	root := t.TempDir()
	config := DefaultNeutralStage3FullBatchConfig(root)
	config.OutputDir = filepath.Join(root, "reports", "neutral-tone-stage3-2-full-batch")
	if _, err := RunNeutralStage3FullBatchAudit(config); err == nil {
		t.Fatal("expected Stage 3-2 output outside .tmp to be rejected")
	}
}

func TestNeutralPrefixImpactSeparatesBothExactPrefixDirections(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.dict.yaml")
	content := "---\nname: old\n...\nold-short\ta\t10\nold-long\tabcd\t9\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	mappings := []neutralFullBatchMapping{
		{Text: "new-text", Code: "a b", Weight: "8", SourceKey: "one"},
		{Text: "old-long", Code: "ac", Weight: "7", SourceKey: "two"},
	}
	stats, _, impacts, err := auditNeutralPrefixImpact("full", mappings, path)
	if err != nil {
		t.Fatal(err)
	}
	if stats.OldExactPrefixCodesAffected != 1 || stats.NewAliasRecordsAtOldPrefix != 2 || stats.MaxNewCandidatesAtOldPrefix != 2 {
		t.Fatalf("unexpected old-prefix impact: %#v", stats)
	}
	if stats.NewExactPrefixCodes != 1 || stats.OldLongerCodesAffected != 1 {
		t.Fatalf("unexpected new-prefix impact: %#v", stats)
	}
	if stats.NetNewVisibleTextRelations != 1 || stats.OldPrefixesWithNetNewText != 1 || stats.MaxNetNewTextAtOldPrefix != 1 {
		t.Fatalf("same-text baseline completion was not deducted: %#v", stats)
	}
	if stats.OldPrefixesWithNewInTop5 != 1 || stats.MaxNewInStaticTop5 != 1 {
		t.Fatalf("unexpected static top-5 estimate: %#v", stats)
	}
	if !impacts["ab"].HasOldExactPrefix || !impacts["ab"].IsExactPrefixOfOldLongerCode || !impacts["ab"].HasNetNewTextAtOldPrefix {
		t.Fatalf("missing per-new-code prefix classification: %#v", impacts["ab"])
	}
}

func TestNormalizeTypedCodeRemovesSyllableDelimiters(t *testing.T) {
	if got := normalizeTypedCode("ab cd\tef"); got != "abcdef" {
		t.Fatalf("got %q, want abcdef", got)
	}
}

func TestNeutralStage3FullBatchRequiresInheritedWeights(t *testing.T) {
	if allNeutralBatchWeightsPresent([]*neutralStage3Sample{{Weight: "100"}, {Weight: "0"}}) != true {
		t.Fatal("valid inherited weights were rejected")
	}
	if allNeutralBatchWeightsPresent([]*neutralStage3Sample{{Weight: "fabricated"}}) {
		t.Fatal("non-numeric weight was accepted")
	}
}

func TestNeutralStage3FullBatchSmokeSelectionIsBounded(t *testing.T) {
	samples := make([]*neutralStage3Sample, 20)
	for index := range samples {
		samples[index] = &neutralStage3Sample{Text: string(rune('a' + index)), Weight: "1", Surface: map[string]string{"full": "a", "variable": "a", "shorthand": "a"}}
	}
	if got := len(selectNeutralBatchSmokeCases(samples)); got != 12 {
		t.Fatalf("got %d smoke cases, want 12", got)
	}
}
