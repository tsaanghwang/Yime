package trainer

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestProgressLifecycleSchedulingAndReport(t *testing.T) {
	now := time.Date(2026, 8, 2, 8, 0, 0, 0, time.UTC)
	exercises := []Exercise{
		{ID: "a", SectionType: SectionKeymap, LearningTags: []string{"yinyuan:N01"}},
		{ID: "b", SectionType: SectionSyllablePractice, LearningTags: []string{"syllable:ma1"}},
		{ID: "c", SectionType: SectionWordPractice, LearningTags: []string{"word:测试"}},
	}
	progress := NewProgress()
	wrong := Diagnosis{Kind: ErrorMissing, ErrorCount: 1, Unit: AnswerUnit{Syllable: 1, Position: "主音"}}
	progress.Record(exercises[1], wrong, 1500*time.Millisecond, now)
	for index := 0; index < 5; index++ {
		progress.Record(exercises[0], Diagnosis{Correct: true}, time.Second, now.Add(time.Duration(index)*time.Minute))
	}
	if progress.Items["a"].State != LearningMastered || progress.Items["b"].State != LearningActive {
		t.Fatalf("states: a=%#v b=%#v", progress.Items["a"], progress.Items["b"])
	}
	wrongOnly := ScheduleExercises(exercises, progress, ReviewWrong, now)
	if len(wrongOnly) != 1 || wrongOnly[0].ID != "b" {
		t.Fatalf("wrong schedule=%#v", wrongOnly)
	}
	all := ScheduleExercises(exercises, progress, ReviewAll, now)
	if len(all) != 3 || all[0].ID != "b" {
		t.Fatalf("adaptive schedule=%#v", all)
	}
	report := BuildLearningReport(progress)
	if report.Attempts != 6 || report.Correct != 5 || report.Incorrect != 1 || report.Mastered != 1 || report.Active != 1 {
		t.Fatalf("report=%#v", report)
	}
	if len(report.DetailLines()) == 0 {
		t.Fatal("learning report omitted tag and error-position detail")
	}
}

func TestProgressStorageIsIsolatedAndClearRemovesOnlyTrainerProgress(t *testing.T) {
	directory := t.TempDir()
	sentinel := filepath.Join(directory, "rime-user-data.sentinel")
	if err := os.WriteFile(sentinel, []byte("must remain"), 0o644); err != nil {
		t.Fatal(err)
	}
	progress := NewProgress()
	progress.Items["x"] = &ItemProgress{ID: "x", State: LearningActive, Attempts: 1, Incorrect: 1}
	if err := SaveProgress(directory, progress); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadProgress(directory)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(progress.Items, loaded.Items) {
		t.Fatalf("loaded=%#v want=%#v", loaded.Items, progress.Items)
	}
	path, err := ExportLearningReport(directory, loaded)
	if err != nil || filepath.Base(path) != ReportFileName {
		t.Fatalf("report export path=%q err=%v", path, err)
	}
	if err := ClearProgress(directory); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(directory, ProgressFileName)); !os.IsNotExist(err) {
		t.Fatalf("progress file still exists: %v", err)
	}
	if _, err := os.Stat(filepath.Join(directory, ReportFileName)); !os.IsNotExist(err) {
		t.Fatalf("exported report still exists after clear: %v", err)
	}
	if payload, err := os.ReadFile(sentinel); err != nil || string(payload) != "must remain" {
		t.Fatalf("clear touched a sibling file: payload=%q err=%v", payload, err)
	}
}

func TestScheduleSuppressesRecentlyRepeatedItems(t *testing.T) {
	exercises := []Exercise{{ID: "old"}, {ID: "recent"}, {ID: "new"}}
	progress := NewProgress()
	progress.RecentIDs = []string{"recent"}
	ordered := ScheduleExercises(exercises, progress, ReviewAll, time.Now())
	ids := []string{ordered[0].ID, ordered[1].ID, ordered[2].ID}
	if reflect.DeepEqual(ids, []string{"old", "recent", "new"}) || ids[2] != "recent" {
		t.Fatalf("recent suppression order=%v", ids)
	}
}

func TestSchedulePrioritizesUndercoveredLearningTags(t *testing.T) {
	exercises := []Exercise{
		{ID: "covered", LearningTags: []string{"yinyuan:N01"}},
		{ID: "uncovered", LearningTags: []string{"yinyuan:N02"}},
	}
	progress := NewProgress()
	progress.Items["history"] = &ItemProgress{ID: "history", Tags: []string{"yinyuan:N01"}, Attempts: 20, Correct: 18}
	ordered := ScheduleExercises(exercises, progress, ReviewAll, time.Now())
	if len(ordered) != 2 || ordered[0].ID != "uncovered" {
		t.Fatalf("coverage-aware order=%#v", ordered)
	}
}

func TestProgressNeverPersistsSubmittedInputText(t *testing.T) {
	directory := t.TempDir()
	progress := NewProgress()
	diagnosis := Diagnosis{Kind: ErrorExtra, ErrorCount: 1, Actual: "PRIVATE-RAW-INPUT", ActualKey: "X"}
	progress.Record(Exercise{ID: "safe-id", SectionType: SectionSyllablePractice}, diagnosis, time.Second, time.Now())
	if err := SaveProgress(directory, progress); err != nil {
		t.Fatal(err)
	}
	payload, err := os.ReadFile(filepath.Join(directory, ProgressFileName))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(payload), "PRIVATE-RAW-INPUT") || strings.Contains(string(payload), "ActualKey") {
		t.Fatalf("progress persisted submitted input: %s", payload)
	}
}
