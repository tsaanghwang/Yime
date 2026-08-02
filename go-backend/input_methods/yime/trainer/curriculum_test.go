package trainer

import (
	"path/filepath"
	"testing"
)

func TestCurriculumUnlocksSequentiallyButKeepsStagesAddressable(t *testing.T) {
	stages := DefaultCurriculum()
	progress := NewProgress()
	statuses := EvaluateCurriculum(progress, stages)
	if len(statuses) != 6 || !statuses[0].Unlocked || statuses[1].Unlocked || RecommendedStage(statuses).Stage.ID != "yinyuan" {
		t.Fatalf("initial curriculum=%#v", statuses)
	}
	progress.Items["keymap"] = &ItemProgress{ID: "keymap", SectionType: SectionKeymap, Attempts: 20, Correct: 18, State: LearningReview}
	statuses = EvaluateCurriculum(progress, stages)
	if !statuses[0].Completed || !statuses[1].Unlocked || RecommendedStage(statuses).Stage.ID != "segments" {
		t.Fatalf("post-keymap curriculum=%#v", statuses)
	}
	if statuses[5].Stage.ID != "candidates" {
		t.Fatal("candidate practice is missing from the default curriculum")
	}
}

func TestCurriculumThresholdsLoadFromTrainerData(t *testing.T) {
	stages, err := LoadCurriculum(filepath.Join(repositoryDataDir(t), "trainer", CurriculumFileName))
	if err != nil {
		t.Fatal(err)
	}
	if len(stages) != 6 || stages[0].RequiredAnswers != 20 || stages[0].RequiredAccuracy != 0.90 || !stages[0].AnswerVisible {
		t.Fatalf("loaded stages=%#v", stages)
	}
}
