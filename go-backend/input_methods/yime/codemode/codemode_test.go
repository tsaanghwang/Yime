package codemode

import (
	"strings"
	"testing"
)

func TestBuildRecordDerivesAllModes(t *testing.T) {
	tests := []struct {
		full, variable, shorthand string
	}{
		{"'fff", "'f", "'f"},
		{"ffff", "ff", "ff"},
		{"'sdf", "'sdf", "'sf"},
		{"qfff", "qf", "qf"},
		{"qsdf", "qsdf", "qsf"},
		{"'ffj", "'fj", "'fj"},
		{"qffjqfds", "qfjqfds", "qfjqfs"},
		{"qfff'sdf", "qf'sdf", "qf'sf"},
	}
	for _, test := range tests {
		got, err := BuildRecord(test.full)
		if err != nil {
			t.Fatalf("BuildRecord(%q): %v", test.full, err)
		}
		if got.Full != test.full || got.Variable != test.variable || got.Shorthand != test.shorthand {
			t.Fatalf("BuildRecord(%q) = %#v, want variable=%q shorthand=%q", test.full, got, test.variable, test.shorthand)
		}
		wantFullSpelling := strings.Join(splitEvery(test.full, SyllableCodeLength), " ")
		if strings.ReplaceAll(got.FullSpelling, " ", "") != got.Full ||
			strings.ReplaceAll(got.VariableSpelling, " ", "") != got.Variable ||
			strings.ReplaceAll(got.ShorthandSpelling, " ", "") != got.Shorthand ||
			got.FullSpelling != wantFullSpelling {
			t.Fatalf("BuildRecord(%q) spelling fields = %#v", test.full, got)
		}
	}
}

func splitEvery(value string, size int) []string {
	runes := []rune(value)
	parts := make([]string, 0, len(runes)/size)
	for start := 0; start < len(runes); start += size {
		parts = append(parts, string(runes[start:start+size]))
	}
	return parts
}

func TestBuildRecordRejectsIncompleteSyllable(t *testing.T) {
	if _, err := BuildRecord("abc"); err == nil {
		t.Fatal("expected incomplete four-code syllable to fail")
	}
}

func TestBuildRecordAcceptsScriptDictionarySyllableSpaces(t *testing.T) {
	got, err := BuildRecord("qffj qfds")
	if err != nil {
		t.Fatal(err)
	}
	if got.Full != "qffjqfds" || got.FullSpelling != "qffj qfds" || got.VariableSpelling != "qfj qfds" {
		t.Fatalf("unexpected record: %#v", got)
	}
}

func TestValidateContinuousInputRecordRejectsLostVirtualInitial(t *testing.T) {
	record, err := BuildRecord("'sdf qffj")
	if err != nil {
		t.Fatal(err)
	}
	record.Shorthand = strings.TrimPrefix(record.Shorthand, "'")
	record.ShorthandSpelling = strings.TrimPrefix(record.ShorthandSpelling, "'")
	if err := ValidateContinuousInputRecord(record); err == nil {
		t.Fatal("expected continuous-input validation to reject a syllable without its initial")
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
