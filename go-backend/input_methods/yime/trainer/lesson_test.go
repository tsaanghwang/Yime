package trainer

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func repositoryDataDir(t *testing.T) string {
	t.Helper()
	path, err := filepath.Abs(filepath.Join("..", "data"))
	if err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFoundationLessonResolvesAgainstCurrentThreeModeData(t *testing.T) {
	dataDir := repositoryDataDir(t)
	lesson, err := Load(filepath.Join(dataDir, "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}

	byMode := map[reverselookup.Mode][]Exercise{}
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		exercises, err := resolver.Resolve(lesson, mode)
		if err != nil {
			t.Fatalf("mode %s: %v", mode, err)
		}
		if len(exercises) != 9 {
			t.Fatalf("mode %s resolved %d exercises, want 9", mode, len(exercises))
		}
		byMode[mode] = exercises
		for _, exercise := range exercises {
			if strings.TrimSpace(exercise.Expected) == "" {
				t.Fatalf("mode %s has empty target: %#v", mode, exercise)
			}
			if strings.Contains(exercise.Expected, "ma1") || strings.Contains(exercise.Expected, "wo3") {
				t.Fatalf("mode %s leaked placeholder pinyin into target: %#v", mode, exercise)
			}
		}
	}
	if byMode[reverselookup.ModeFull][3].Expected == byMode[reverselookup.ModeVariable][3].Expected {
		t.Fatal("ma1 must demonstrate the fixed-length versus variable-length projection")
	}
	if byMode[reverselookup.ModeVariable][5].Expected == byMode[reverselookup.ModeShorthand][5].Expected {
		t.Fatal("a4 must demonstrate the variable-length versus shorthand projection")
	}
}

func TestKeymapExerciseUsesActiveLayoutProjection(t *testing.T) {
	dataDir := repositoryDataDir(t)
	lesson, err := Load(filepath.Join(dataDir, "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	exercises, err := resolver.Resolve(lesson, reverselookup.ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	if exercises[0].Expected != resolver.layout.Projection["N01"] {
		t.Fatalf("keymap target %q does not follow current N01 projection %q", exercises[0].Expected, resolver.layout.Projection["N01"])
	}
}

func TestLessonValidationRejectsStaleTargetOnlySyllable(t *testing.T) {
	lesson := Lesson{
		SchemaVersion: SchemaVersion,
		ID:            "bad",
		Title:         "bad",
		Sections: []Section{{
			ID:    "syllable",
			Type:  SectionSyllableContrast,
			Title: "syllable",
			Items: []Item{{Prompt: "旧占位题"}},
		}},
	}
	if err := lesson.Validate(); err == nil {
		t.Fatal("expected missing canonical syllable to fail validation")
	}
}

func TestEvaluateKeepsUppercaseLayoutKeysSignificant(t *testing.T) {
	if !Evaluate("Jf", "Jf") {
		t.Fatal("exact target should pass")
	}
	if Evaluate("jf", "Jf") {
		t.Fatal("uppercase layout keys must remain significant")
	}
}
