package codemode

import (
	"encoding/json"
	"os"
	"testing"
)

// Compare every admitted active syllable with an independent semantic-mode
// derivation, so ASCII remapping cannot silently change abbreviation rules.
func TestGeneratedProjectionMatchesSemanticSyllables(t *testing.T) {
	data, err := os.ReadFile("testdata/canonical_syllables.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Disabled  []string                                             `json:"disabled_syllables"`
		Syllables []struct{ Pinyin, Full, Variable, Shorthand string } `json:"syllables"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Disabled) != 4 || len(fixture.Syllables) != 1733 {
		t.Fatal("canonical inventory coverage changed")
	}
	for _, item := range fixture.Syllables {
		record, err := BuildRecord(item.Full)
		if err != nil {
			t.Fatalf("%s: %v", item.Pinyin, err)
		}
		if record.Variable != item.Variable || record.Shorthand != item.Shorthand {
			t.Fatalf("%s: got %q/%q, semantic projection %q/%q", item.Pinyin, record.Variable, record.Shorthand, item.Variable, item.Shorthand)
		}
	}
	// Disabled M25-M27 share positions only; active owners keep quality 9.
	for _, key := range "[N]" {
		if musicalByKey[key].quality != 9 {
			t.Fatalf("disabled member overwrote %q", key)
		}
	}
	upper, _ := BuildRecord("bAAA")
	lower, _ := BuildRecord("baaa")
	if upper.Variable == lower.Variable {
		t.Fatal("ASCII case was folded")
	}
}
