package trainer

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	ProgressFileName = "yime_trainer_progress.json"
	ReportFileName   = "yime_trainer_report.txt"
	ProgressVersion  = 1

	LearningNew      = "new"
	LearningActive   = "learning"
	LearningReview   = "review"
	LearningMastered = "mastered"

	ReviewAll   = "all"
	ReviewWrong = "wrong"
	ReviewToday = "today"
)

type ItemProgress struct {
	ID                  string   `json:"id"`
	SectionType         string   `json:"section_type"`
	Tags                []string `json:"tags,omitempty"`
	State               string   `json:"state"`
	Attempts            int      `json:"attempts"`
	Correct             int      `json:"correct"`
	Incorrect           int      `json:"incorrect"`
	Streak              int      `json:"streak"`
	LastErrorKind       string   `json:"last_error_kind,omitempty"`
	LastErrorSyllable   int      `json:"last_error_syllable,omitempty"`
	LastErrorPosition   string   `json:"last_error_position,omitempty"`
	TotalResponseMillis int64    `json:"total_response_millis"`
	LastPracticed       string   `json:"last_practiced,omitempty"`
	NextReview          string   `json:"next_review,omitempty"`
}

type Progress struct {
	Version   int                      `json:"version"`
	UpdatedAt string                   `json:"updated_at,omitempty"`
	Items     map[string]*ItemProgress `json:"items"`
	RecentIDs []string                 `json:"recent_ids,omitempty"`
}

func NewProgress() Progress {
	return Progress{Version: ProgressVersion, Items: map[string]*ItemProgress{}}
}

func LoadProgress(directory string) (Progress, error) {
	if strings.TrimSpace(directory) == "" {
		return NewProgress(), nil
	}
	payload, err := os.ReadFile(filepath.Join(directory, ProgressFileName))
	if errors.Is(err, os.ErrNotExist) {
		return NewProgress(), nil
	}
	if err != nil {
		return NewProgress(), err
	}
	var progress Progress
	if err := json.Unmarshal(payload, &progress); err != nil {
		return NewProgress(), err
	}
	if progress.Version != ProgressVersion {
		return NewProgress(), fmt.Errorf("不支持练习记录格式 %d，当前需要 %d", progress.Version, ProgressVersion)
	}
	if progress.Items == nil {
		progress.Items = map[string]*ItemProgress{}
	}
	return progress, nil
}

func SaveProgress(directory string, progress Progress) error {
	if strings.TrimSpace(directory) == "" {
		return nil
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	progress.Version = ProgressVersion
	payload, err := json.MarshalIndent(progress, "", "  ")
	if err != nil {
		return err
	}
	payload = append(payload, '\n')
	return os.WriteFile(filepath.Join(directory, ProgressFileName), payload, 0o644)
}

func ClearProgress(directory string) error {
	if strings.TrimSpace(directory) == "" {
		return nil
	}
	for _, name := range []string{ProgressFileName, ReportFileName} {
		err := os.Remove(filepath.Join(directory, name))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}

func (progress *Progress) Record(exercise Exercise, diagnosis Diagnosis, response time.Duration, now time.Time) {
	if progress == nil || strings.TrimSpace(exercise.ID) == "" {
		return
	}
	if progress.Items == nil {
		progress.Items = map[string]*ItemProgress{}
	}
	item := progress.Items[exercise.ID]
	if item == nil {
		item = &ItemProgress{ID: exercise.ID, State: LearningNew}
		progress.Items[exercise.ID] = item
	}
	item.SectionType = exercise.SectionType
	item.Tags = append([]string(nil), exercise.LearningTags...)
	item.Attempts++
	item.TotalResponseMillis += maxInt64(0, response.Milliseconds())
	item.LastPracticed = now.UTC().Format(time.RFC3339)
	if diagnosis.Correct {
		item.Correct++
		item.Streak++
		updateCorrectLearningState(item, now)
	} else {
		item.Incorrect++
		item.Streak = 0
		item.State = LearningActive
		item.LastErrorKind = diagnosis.Kind
		item.LastErrorSyllable = diagnosis.Unit.Syllable
		item.LastErrorPosition = diagnosis.Unit.Position
		item.NextReview = now.UTC().Format(time.RFC3339)
	}
	progress.UpdatedAt = now.UTC().Format(time.RFC3339)
	progress.RecentIDs = append(progress.RecentIDs, exercise.ID)
	if len(progress.RecentIDs) > 20 {
		progress.RecentIDs = append([]string(nil), progress.RecentIDs[len(progress.RecentIDs)-20:]...)
	}
}

func updateCorrectLearningState(item *ItemProgress, now time.Time) {
	accuracy := float64(item.Correct) / float64(item.Attempts)
	var interval time.Duration
	switch {
	case item.Streak >= 5 && item.Attempts >= 5 && accuracy >= 0.9:
		item.State = LearningMastered
		interval = 7 * 24 * time.Hour
	case item.Streak >= 2:
		item.State = LearningReview
		interval = time.Duration(minInt(item.Streak-1, 3)) * 24 * time.Hour
	default:
		item.State = LearningActive
		interval = 10 * time.Minute
	}
	item.NextReview = now.Add(interval).UTC().Format(time.RFC3339)
}

func maxInt64(left, right int64) int64 {
	if left > right {
		return left
	}
	return right
}

func ScheduleExercises(exercises []Exercise, progress Progress, filter string, now time.Time) []Exercise {
	recent := map[string]int{}
	for index, id := range progress.RecentIDs {
		recent[id] = index + 1
	}
	tagAttempts := map[string]int{}
	for _, item := range progress.Items {
		for _, tag := range item.Tags {
			tagAttempts[tag] += item.Attempts
		}
	}
	type scheduled struct {
		exercise Exercise
		priority int64
		order    int
	}
	items := make([]scheduled, 0, len(exercises))
	for order, exercise := range exercises {
		item := progress.Items[exercise.ID]
		if !exerciseMatchesReview(item, filter, now) {
			continue
		}
		priority := int64(100000)
		if item != nil {
			priority += int64(item.Incorrect*5000 - item.Correct*100 - item.Streak*250)
			if due(item, now) {
				priority += 20000
			}
			if item.State == LearningMastered {
				priority -= 30000
			}
		}
		if recentIndex := recent[exercise.ID]; recentIndex > 0 {
			priority -= int64(recentIndex * 1000)
		}
		if len(exercise.LearningTags) > 0 {
			minimumCoverage := int(^uint(0) >> 1)
			for _, tag := range exercise.LearningTags {
				minimumCoverage = minInt(minimumCoverage, tagAttempts[tag])
			}
			priority += int64(5000 / (minimumCoverage + 1))
		}
		items = append(items, scheduled{exercise: exercise, priority: priority, order: order})
	}
	sort.SliceStable(items, func(i, j int) bool {
		if items[i].priority != items[j].priority {
			return items[i].priority > items[j].priority
		}
		return items[i].order < items[j].order
	})
	result := make([]Exercise, 0, len(items))
	for _, item := range items {
		result = append(result, item.exercise)
	}
	return result
}

func exerciseMatchesReview(item *ItemProgress, filter string, now time.Time) bool {
	switch filter {
	case ReviewWrong:
		return item != nil && item.Incorrect > 0 && item.Streak < 3
	case ReviewToday:
		return item != nil && due(item, now)
	default:
		return true
	}
}

func due(item *ItemProgress, now time.Time) bool {
	if item == nil || item.NextReview == "" {
		return false
	}
	value, err := time.Parse(time.RFC3339, item.NextReview)
	return err == nil && !value.After(now)
}

type ReportGroup struct {
	Attempts       int
	Correct        int
	ResponseMillis int64
}

type LearningReport struct {
	Attempts, Correct, Incorrect  int
	AverageResponseMillis         int64
	New, Active, Review, Mastered int
	BySection                     map[string]ReportGroup
	ByTag                         map[string]ReportGroup
	ByErrorPosition               map[string]int
}

func BuildLearningReport(progress Progress) LearningReport {
	report := LearningReport{BySection: map[string]ReportGroup{}, ByTag: map[string]ReportGroup{}, ByErrorPosition: map[string]int{}}
	var responseMillis int64
	for _, item := range progress.Items {
		report.Attempts += item.Attempts
		report.Correct += item.Correct
		report.Incorrect += item.Incorrect
		responseMillis += item.TotalResponseMillis
		switch item.State {
		case LearningMastered:
			report.Mastered++
		case LearningReview:
			report.Review++
		case LearningActive:
			report.Active++
		default:
			report.New++
		}
		group := report.BySection[item.SectionType]
		group.Attempts += item.Attempts
		group.Correct += item.Correct
		group.ResponseMillis += item.TotalResponseMillis
		report.BySection[item.SectionType] = group
		for _, tag := range item.Tags {
			tagGroup := report.ByTag[tag]
			tagGroup.Attempts += item.Attempts
			tagGroup.Correct += item.Correct
			tagGroup.ResponseMillis += item.TotalResponseMillis
			report.ByTag[tag] = tagGroup
		}
		if item.LastErrorPosition != "" {
			report.ByErrorPosition[item.LastErrorPosition] += item.Incorrect
		}
	}
	if report.Attempts > 0 {
		report.AverageResponseMillis = responseMillis / int64(report.Attempts)
	}
	return report
}

func (report LearningReport) Text() string {
	accuracy := float64(0)
	if report.Attempts > 0 {
		accuracy = float64(report.Correct) * 100 / float64(report.Attempts)
	}
	return fmt.Sprintf("累计：%d 题，正确 %d，错误 %d，正确率 %.1f%%，平均反应 %.2f 秒。学习中 %d，待复习 %d，已掌握 %d。",
		report.Attempts, report.Correct, report.Incorrect, accuracy, float64(report.AverageResponseMillis)/1000,
		report.Active, report.Review, report.Mastered)
}

func (report LearningReport) DetailLines() []string {
	lines := []string{}
	modeNames := map[string]string{"mode:variable": "变长", "mode:full": "等长", "mode:shorthand": "省键"}
	for _, tag := range []string{"mode:variable", "mode:full", "mode:shorthand"} {
		group := report.ByTag[tag]
		if group.Attempts == 0 {
			continue
		}
		lines = append(lines, fmt.Sprintf("%s方案：%d 题，正确率 %.1f%%", modeNames[tag], group.Attempts, float64(group.Correct)*100/float64(group.Attempts)))
	}
	type weakness struct {
		Tag      string
		Attempts int
		Accuracy float64
	}
	weaknesses := []weakness{}
	for tag, group := range report.ByTag {
		if group.Attempts < 2 || strings.HasPrefix(tag, "mode:") || strings.HasPrefix(tag, "word:") {
			continue
		}
		weaknesses = append(weaknesses, weakness{Tag: tag, Attempts: group.Attempts, Accuracy: float64(group.Correct) / float64(group.Attempts)})
	}
	sort.Slice(weaknesses, func(i, j int) bool {
		if weaknesses[i].Accuracy != weaknesses[j].Accuracy {
			return weaknesses[i].Accuracy < weaknesses[j].Accuracy
		}
		return weaknesses[i].Attempts > weaknesses[j].Attempts
	})
	if len(weaknesses) > 5 {
		weaknesses = weaknesses[:5]
	}
	for _, value := range weaknesses {
		lines = append(lines, fmt.Sprintf("薄弱项 %s：%d 题，正确率 %.1f%%", value.Tag, value.Attempts, value.Accuracy*100))
	}
	positions := make([]string, 0, len(report.ByErrorPosition))
	for position := range report.ByErrorPosition {
		positions = append(positions, position)
	}
	sort.Slice(positions, func(i, j int) bool {
		if report.ByErrorPosition[positions[i]] != report.ByErrorPosition[positions[j]] {
			return report.ByErrorPosition[positions[i]] > report.ByErrorPosition[positions[j]]
		}
		return positions[i] < positions[j]
	})
	for _, position := range positions {
		lines = append(lines, fmt.Sprintf("错误位置 %s：%d 次", position, report.ByErrorPosition[position]))
	}
	return lines
}

func ExportLearningReport(directory string, progress Progress) (string, error) {
	if strings.TrimSpace(directory) == "" {
		return "", nil
	}
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return "", err
	}
	report := BuildLearningReport(progress)
	lines := append([]string{report.Text()}, report.DetailLines()...)
	path := filepath.Join(directory, ReportFileName)
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\r\n")+"\r\n"), 0o644); err != nil {
		return "", err
	}
	return path, nil
}
