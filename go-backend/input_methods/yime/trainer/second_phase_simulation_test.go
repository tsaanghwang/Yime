package trainer

import (
	"math/rand"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func TestSecondPhaseHeadlessSimulationCoversAllSectionsAndModesWithoutPIMEWrites(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	dictPath := filepath.Join(resolver.runtimeDataDir, "yime_full.dict.yaml")
	dictBefore := digestFile(t, dictPath)
	set, err := resolver.SelectRuntimePracticeSet(rand.New(rand.NewSource(2026080201)))
	if err != nil {
		t.Fatal(err)
	}
	keymap, err := resolver.ResolveKeymapGroups()
	if err != nil {
		t.Fatal(err)
	}
	fingering, err := resolver.ResolveFingeringDrills()
	if err != nil {
		t.Fatal(err)
	}
	composition, err := resolver.ResolveGanyinCompositionGroups()
	if err != nil {
		t.Fatal(err)
	}

	progress := NewProgress()
	now := time.Date(2026, 8, 2, 10, 0, 0, 0, time.UTC)
	sectionSeen := map[string]bool{}
	modeSeen := map[reverselookup.Mode]bool{}
	baseExercises := []Exercise{keymap[0].Exercises[0], fingering[0].Exercises[0], composition[0].ToneGroups[0].Exercises[0]}
	for _, exercise := range baseExercises {
		simulateCorrectAndWrongAttempt(t, &progress, exercise, now)
		sectionSeen[exercise.SectionType] = true
	}
	for _, mode := range []reverselookup.Mode{reverselookup.ModeVariable, reverselookup.ModeFull, reverselookup.ModeShorthand} {
		syllables, resolveErr := resolver.ResolveSyllablePracticeGroups(mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		words, resolveErr := resolver.ResolveWordPracticeGroups(set, mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		sentences, resolveErr := resolver.ResolveSentencePractice(set, mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		candidates, resolveErr := resolver.ResolveCandidatePractice(set, mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		for _, exercise := range []Exercise{syllables[0].Exercises[0], words[0].Exercises[0], sentences[0], candidates[0]} {
			simulateCorrectAndWrongAttempt(t, &progress, exercise, now)
			sectionSeen[exercise.SectionType] = true
		}
		modeSeen[mode] = true
	}
	for _, sectionType := range []string{SectionKeymap, SectionSyllableComposition, SectionSyllablePractice, SectionWordPractice, SectionSentencePractice, SectionCandidatePractice} {
		if !sectionSeen[sectionType] {
			t.Fatalf("headless session missed section %s", sectionType)
		}
	}
	if len(modeSeen) != 3 {
		t.Fatalf("headless session modes=%v", modeSeen)
	}

	directory := t.TempDir()
	sentinel := filepath.Join(directory, "pime-rime-must-not-change")
	if err := os.WriteFile(sentinel, []byte("unchanged"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := SaveProgress(directory, progress); err != nil {
		t.Fatal(err)
	}
	if report := BuildLearningReport(progress); report.Attempts == 0 || len(report.BySection) < 6 {
		t.Fatalf("simulation report incomplete: %#v", report)
	}
	if payload, err := os.ReadFile(sentinel); err != nil || string(payload) != "unchanged" {
		t.Fatalf("trainer simulation touched PIME/Rime sentinel: payload=%q err=%v", payload, err)
	}
	if dictAfter := digestFile(t, dictPath); dictAfter != dictBefore {
		t.Fatalf("trainer simulation modified system dictionary: before=%x after=%x", dictBefore, dictAfter)
	}
}

func simulateCorrectAndWrongAttempt(t *testing.T, progress *Progress, exercise Exercise, now time.Time) {
	t.Helper()
	if exercise.ID == "" || exercise.Expected == "" || len(exercise.AnswerUnits) == 0 {
		t.Fatalf("simulation exercise is incomplete: %#v", exercise)
	}
	correct := Diagnose(exercise, exercise.Expected)
	if !correct.Correct {
		t.Fatalf("exact answer failed diagnosis: %#v", correct)
	}
	wrong := Diagnose(exercise, exercise.Expected+"~")
	if wrong.Correct || wrong.ErrorCount == 0 {
		t.Fatalf("wrong answer escaped diagnosis: %#v", wrong)
	}
	progress.Record(exercise, correct, 900*time.Millisecond, now)
	progress.Record(exercise, wrong, 1100*time.Millisecond, now.Add(time.Second))
}
