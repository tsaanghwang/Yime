package trainer

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

const DefaultUnlockAccuracy = 0.90
const CurriculumFileName = "curriculum.json"

type CurriculumConfig struct {
	FormatVersion int               `json:"format_version"`
	Stages        []CurriculumStage `json:"stages"`
}

type CurriculumStage struct {
	ID               string   `json:"id"`
	Title            string   `json:"title"`
	SectionTypes     []string `json:"section_types"`
	RequiredAnswers  int      `json:"required_answers"`
	RequiredAccuracy float64  `json:"required_accuracy"`
	AnswerVisible    bool     `json:"answer_visible"`
}

func LoadCurriculum(path string) ([]CurriculumStage, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var config CurriculumConfig
	if err := json.Unmarshal(payload, &config); err != nil {
		return nil, err
	}
	if config.FormatVersion != 1 || len(config.Stages) == 0 {
		return nil, fmt.Errorf("课程阶段配置格式无效")
	}
	seen := map[string]bool{}
	for _, stage := range config.Stages {
		if strings.TrimSpace(stage.ID) == "" || strings.TrimSpace(stage.Title) == "" || seen[stage.ID] ||
			len(stage.SectionTypes) == 0 || stage.RequiredAnswers <= 0 || stage.RequiredAccuracy <= 0 || stage.RequiredAccuracy > 1 {
			return nil, fmt.Errorf("课程阶段 %q 配置无效", stage.ID)
		}
		seen[stage.ID] = true
	}
	return config.Stages, nil
}

type StageStatus struct {
	Stage     CurriculumStage
	Unlocked  bool
	Completed bool
	Attempts  int
	Correct   int
	Accuracy  float64
}

func DefaultCurriculum() []CurriculumStage {
	return []CurriculumStage{
		{ID: "yinyuan", Title: "音元认键", SectionTypes: []string{SectionKeymap}, RequiredAnswers: 20, RequiredAccuracy: DefaultUnlockAccuracy, AnswerVisible: true},
		{ID: "segments", Title: "首音／干音分段", SectionTypes: []string{SectionSyllableComposition}, RequiredAnswers: 20, RequiredAccuracy: DefaultUnlockAccuracy, AnswerVisible: true},
		{ID: "syllables", Title: "单音节编码", SectionTypes: []string{SectionSyllablePractice}, RequiredAnswers: 30, RequiredAccuracy: DefaultUnlockAccuracy},
		{ID: "words", Title: "连续字词", SectionTypes: []string{SectionWordPractice, SectionCommonWords}, RequiredAnswers: 20, RequiredAccuracy: DefaultUnlockAccuracy},
		{ID: "sentences", Title: "短句连续输入", SectionTypes: []string{SectionSentencePractice}, RequiredAnswers: 15, RequiredAccuracy: DefaultUnlockAccuracy},
		{ID: "candidates", Title: "隔离候选实战", SectionTypes: []string{SectionCandidatePractice}, RequiredAnswers: 10, RequiredAccuracy: DefaultUnlockAccuracy},
	}
}

func EvaluateCurriculum(progress Progress, stages []CurriculumStage) []StageStatus {
	statuses := make([]StageStatus, 0, len(stages))
	previousCompleted := true
	for _, stage := range stages {
		status := StageStatus{Stage: stage, Unlocked: previousCompleted}
		sectionTypes := map[string]bool{}
		for _, sectionType := range stage.SectionTypes {
			sectionTypes[sectionType] = true
		}
		for _, item := range progress.Items {
			if sectionTypes[item.SectionType] {
				status.Attempts += item.Attempts
				status.Correct += item.Correct
			}
		}
		if status.Attempts > 0 {
			status.Accuracy = float64(status.Correct) / float64(status.Attempts)
		}
		status.Completed = status.Attempts >= stage.RequiredAnswers && status.Accuracy >= stage.RequiredAccuracy
		statuses = append(statuses, status)
		previousCompleted = previousCompleted && status.Completed
	}
	return statuses
}

func RecommendedStage(statuses []StageStatus) StageStatus {
	for _, status := range statuses {
		if status.Unlocked && !status.Completed {
			return status
		}
	}
	if len(statuses) > 0 {
		return statuses[len(statuses)-1]
	}
	return StageStatus{}
}

func (resolver *Resolver) Curriculum() []CurriculumStage {
	if resolver == nil || len(resolver.curriculum) == 0 {
		return DefaultCurriculum()
	}
	return append([]CurriculumStage(nil), resolver.curriculum...)
}
