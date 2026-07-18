package codemode

import "testing"

func TestBuildRecordDerivesAllModes(t *testing.T) {
	tests := []struct {
		full, variable, shorthand string
	}{
		{"'fff", "f", "f"},
		{"'sdf", "sdf", "sf"},
		{"qfff", "qf", "qf"},
		{"qsdf", "qsdf", "qsf"},
		{"'ffj", "fj", "fj"},
		{"qffjqfds", "qfjqfds", "qfjqfs"},
	}
	for _, test := range tests {
		got, err := BuildRecord(test.full)
		if err != nil {
			t.Fatalf("BuildRecord(%q): %v", test.full, err)
		}
		if got.Full != test.full || got.Variable != test.variable || got.Shorthand != test.shorthand {
			t.Fatalf("BuildRecord(%q) = %#v, want variable=%q shorthand=%q", test.full, got, test.variable, test.shorthand)
		}
	}
}

func TestBuildRecordRejectsIncompleteSyllable(t *testing.T) {
	if _, err := BuildRecord("abc"); err == nil {
		t.Fatal("expected incomplete four-code syllable to fail")
	}
}

func TestBuildRecordAcceptsEveryLayoutKeyAndRejectsUnknownCharacters(t *testing.T) {
	for _, key := range LayoutAlphabet {
		if _, err := BuildRecord(string([]rune{key, key, key, key})); err != nil {
			t.Fatalf("layout key %q rejected: %v", key, err)
		}
	}
	if _, err := BuildRecord("~~~~"); err == nil {
		t.Fatal("expected characters outside LayoutAlphabet to be rejected")
	}
}
