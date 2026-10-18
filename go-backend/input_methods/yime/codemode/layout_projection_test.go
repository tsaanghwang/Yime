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
		Erhua     []struct{ Family, Full, Variable, Shorthand string } `json:"synthetic_erhua_contraction_cases"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Disabled) != 0 || len(fixture.Syllables) != 1737 {
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
	if len(fixture.Erhua) != 135 {
		t.Fatal("derived contraction coverage must contain five families x 27 triples")
	}
	for _, item := range fixture.Erhua {
		record, err := BuildRecord(item.Full)
		if err != nil || record.Variable != item.Variable || record.Shorthand != item.Shorthand {
			t.Fatalf("synthetic derived %s/%q: %#v, %v; want %q/%q", item.Family, item.Full, record, err, item.Variable, item.Shorthand)
		}
	}
	// The former shared groups now have independent active carriers.
	for _, key := range "[\\]" {
		if musicalByKey[key].quality != 9 {
			t.Fatalf("wrong quality for independent carrier %q", key)
		}
	}
	upper, _ := BuildRecord("bAAA")
	lower, _ := BuildRecord("baaa")
	if upper.Variable == lower.Variable {
		t.Fatal("ASCII case was folded")
	}
}
