package reverselookup

import "testing"

func TestDecodeCodeToNumericPinyinIsDeterministicForEquivalentCodes(t *testing.T) {
	codeMap := map[string]CodeRecord{
		"o5": {Full: "same", Variable: "same", Shorthand: "same"},
		"e5": {Full: "same", Variable: "same", Shorthand: "same"},
	}
	for iteration := 0; iteration < 100; iteration++ {
		got, ok := DecodeCodeToNumericPinyin("same", codeMap, ModeFull)
		if !ok || got != "e5" {
			t.Fatalf("iteration %d: got %q, ok=%t; want deterministic e5", iteration, got, ok)
		}
	}
}

func TestBuildReverseCodeLookupPrefersCanonicalUmlautSpelling(t *testing.T) {
	record := CodeRecord{Full: "same", Variable: "same", Shorthand: "same"}
	lookup := buildReverseCodeLookup(map[string]CodeRecord{
		"lü4":  record,
		"lv4":  record,
		"lu:4": record,
	}, "full")
	if got := lookup["same"]; got != "lü4" {
		t.Fatalf("lookup canonical spelling=%q, want lü4", got)
	}
}
