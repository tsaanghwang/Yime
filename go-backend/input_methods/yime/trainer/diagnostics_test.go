package trainer

import (
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func TestDiagnosisFindsSubstitutionMissingExtraAndCrossSyllableShift(t *testing.T) {
	exercise := Exercise{
		Expected: "abcd",
		AnswerUnits: []AnswerUnit{
			{ExpectedKey: "a", Syllable: 1, Position: "首音", YinyuanID: "N01", DisplayName: "首音一"},
			{ExpectedKey: "b", Syllable: 1, Position: "主音", YinyuanID: "M01", DisplayName: "乐音一"},
			{ExpectedKey: "c", Syllable: 2, Position: "首音", YinyuanID: "N02", DisplayName: "首音二"},
			{ExpectedKey: "d", Syllable: 2, Position: "末音", YinyuanID: "M02", DisplayName: "乐音二"},
		},
	}
	cases := []struct {
		input, kind string
		syllable    int
	}{
		{"abxd", ErrorSubstitution, 2},
		{"abd", ErrorMissing, 2},
		{"abxcd", ErrorExtra, 2},
		{"acd", ErrorMissing, 1},
	}
	for _, test := range cases {
		diagnosis := Diagnose(exercise, test.input)
		if diagnosis.Correct || diagnosis.Kind != test.kind || diagnosis.Unit.Syllable != test.syllable || diagnosis.ErrorCount != 1 {
			t.Fatalf("input %q diagnosis=%#v", test.input, diagnosis)
		}
		if !strings.Contains(diagnosis.Hint(1), "音节") || !strings.Contains(diagnosis.Hint(2), "目标键") || diagnosis.Hint(3) != "完整答案：abcd" {
			t.Fatalf("input %q hints are incomplete: %q / %q / %q", test.input, diagnosis.Hint(1), diagnosis.Hint(2), diagnosis.Hint(3))
		}
	}
	if diagnosis := Diagnose(exercise, "abzz"); diagnosis.ErrorCount != 2 {
		t.Fatalf("multi-key error count=%d want 2", diagnosis.ErrorCount)
	}
}

func TestAllThreeModesProduceAnswerUnitsMatchingProjectedCodes(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []reverselookup.Mode{reverselookup.ModeVariable, reverselookup.ModeFull, reverselookup.ModeShorthand} {
		groups, resolveErr := resolver.ResolveSyllablePracticeGroups(mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		for _, group := range groups {
			for _, exercise := range group.Exercises {
				var answer strings.Builder
				for _, unit := range exercise.AnswerUnits {
					answer.WriteString(unit.ExpectedKey)
					if unit.Syllable != 1 || unit.YinyuanID == "" || unit.Position == "" {
						t.Fatalf("mode %s invalid unit %#v", mode, unit)
					}
				}
				if answer.String() != exercise.Expected {
					t.Fatalf("mode %s %s units=%q expected=%q", mode, exercise.ID, answer.String(), exercise.Expected)
				}
			}
		}
	}
}

func TestFingeringCoversCurrentImportedLayout(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	for id, key := range resolver.layout.Projection {
		assignment := FingeringForKey(key)
		if assignment.Hand == "未指定" || assignment.Finger == "未指定" || assignment.HomeKey == "" {
			t.Fatalf("%s key %q has no fingering: %#v", id, key, assignment)
		}
	}
}
