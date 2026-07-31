package trainer

import (
	"os"
	"path/filepath"
	"reflect"
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
		if len(exercises) != 13 {
			t.Fatalf("mode %s resolved %d exercises, want 13", mode, len(exercises))
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
	ma1 := func(mode reverselookup.Mode) Exercise {
		for _, exercise := range byMode[mode] {
			if exercise.SectionType == SectionSyllableContrast && strings.Contains(exercise.Prompt, "mā") {
				return exercise
			}
		}
		t.Fatalf("mode %s has no ma1 contrast exercise", mode)
		return Exercise{}
	}
	a4 := func(mode reverselookup.Mode) Exercise {
		for _, exercise := range byMode[mode] {
			if exercise.SectionType == SectionSyllableContrast && strings.Contains(exercise.Prompt, "à") {
				return exercise
			}
		}
		t.Fatalf("mode %s has no a4 contrast exercise", mode)
		return Exercise{}
	}
	if ma1(reverselookup.ModeFull).Expected == ma1(reverselookup.ModeVariable).Expected {
		t.Fatal("ma1 must demonstrate the fixed-length versus variable-length projection")
	}
	if a4(reverselookup.ModeVariable).Expected == a4(reverselookup.ModeShorthand).Expected {
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
	var n01 Exercise
	for _, exercise := range exercises {
		if exercise.SectionType == SectionKeymap && strings.Contains(exercise.Detail, "N01") {
			n01 = exercise
			break
		}
	}
	if n01.Expected != resolver.layout.Projection["N01"] {
		t.Fatalf("keymap target %q does not follow current N01 projection %q", n01.Expected, resolver.layout.Projection["N01"])
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

func TestCatalogCoversStableIDsAndKeepsAudioOptional(t *testing.T) {
	dataDir := repositoryDataDir(t)
	catalog, err := LoadCatalog(filepath.Join(dataDir, "trainer", CatalogFileName))
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog.Entries) != 57 {
		t.Fatalf("catalog has %d entries, want 57", len(catalog.Entries))
	}
	m03, ok := catalog.Lookup("M03")
	if !ok {
		t.Fatal("catalog is missing M03")
	}
	if m03.DisplayName != "低调[i]乐音" || m03.RepresentativeIPA != "i˩" {
		t.Fatalf("M03 teaching anchor is incomplete: %#v", m03)
	}
	if !reflect.DeepEqual(m03.CoveredPianyinLevels, []int{3, 2, 1}) {
		t.Fatalf("M03 must cover pianyin levels 3,2,1: %#v", m03.CoveredPianyinLevels)
	}
	if m03.Audio != "" || catalog.AudioPath(m03) != "" {
		t.Fatal("the first catalog must load without an audio asset")
	}
}

func TestSyllableAssociationStartsFromStandardPinyinAndResolvesFourIDs(t *testing.T) {
	dataDir := repositoryDataDir(t)
	lesson, err := Load(filepath.Join(dataDir, "trainer", "foundation.json"))
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	exercises, err := resolver.Resolve(lesson, reverselookup.ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	var yi2 Exercise
	for _, exercise := range exercises {
		if exercise.SectionType == SectionSyllableAssociate && exercise.MarkedPinyin == "yí" {
			yi2 = exercise
			break
		}
	}
	if len(yi2.Segments) != 4 {
		t.Fatalf("yi2 resolved %d segments, want 4: %#v", len(yi2.Segments), yi2)
	}
	wantIDs := []string{"N23", "M03", "M02", "M01"}
	wantNotations := []string{"y", "ɪ̀", "ɪ̄", "ɪ́"}
	for index, want := range wantIDs {
		if yi2.Segments[index].ID != want {
			t.Fatalf("yi2 segment %d is %s, want %s", index, yi2.Segments[index].ID, want)
		}
		if yi2.Segments[index].Key == "" || yi2.Segments[index].DisplayName == "" {
			t.Fatalf("yi2 segment %d lacks active key or teaching name: %#v", index, yi2.Segments[index])
		}
		if yi2.Segments[index].Notation != wantNotations[index] {
			t.Fatalf("yi2 segment %d notation is %q, want %q", index, yi2.Segments[index].Notation, wantNotations[index])
		}
	}
	if !strings.Contains(yi2.Detail, "音元拼音：y + ɪ̀ + ɪ̄ + ɪ́") {
		t.Fatalf("yi2 detail does not expose the standard-pinyin to Yinyuan-pinyin bridge: %q", yi2.Detail)
	}
	if yi2.Expected != "ylkj" {
		t.Fatalf("yi2 full target is %q, want current canonical code ylkj", yi2.Expected)
	}
	if yi2.AudioPath != "" || yi2.AudioDeclared {
		t.Fatal("missing optional syllable audio must not block or masquerade as present")
	}
}

func TestDeclaredMissingAudioDegradesWithoutMutatingLessonDirectory(t *testing.T) {
	tempDir := t.TempDir()
	lessonPath := filepath.Join(tempDir, "lesson.json")
	payload := `{"schema_version":"1.2","id":"audio-optional","title":"audio","sections":[{"id":"keys","type":"keymap","title":"keys","items":[{"yinyuan_id":"M01","audio":"audio/M01.wav"}]}]}`
	if err := os.WriteFile(lessonPath, []byte(payload), 0600); err != nil {
		t.Fatal(err)
	}
	lesson, err := Load(lessonPath)
	if err != nil {
		t.Fatal(err)
	}
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	exercises, err := resolver.Resolve(lesson, reverselookup.ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	if len(exercises) != 1 || !exercises[0].AudioDeclared || exercises[0].AudioPath != "" {
		t.Fatalf("missing optional audio did not degrade cleanly: %#v", exercises)
	}
	entries, err := os.ReadDir(tempDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "lesson.json" {
		t.Fatalf("resolver wrote into the lesson directory: %#v", entries)
	}
}
