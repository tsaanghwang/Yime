//go:build windows

package main

import (
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/trainer"
)

func sampleLayoutMetrics() layoutMetrics {
	return layoutMetrics{
		lineHeight: 24, detailLines: 3, contentTextWidth: 760,
		inputLabelWidth: 400, inputWidth: 280,
		mode: selectorMetrics{80, 110}, section: selectorMetrics{90, 180},
		font: selectorMetrics{55, 100}, background: selectorMetrics{55, 120},
		segment:  selectorMetrics{90, 120},
		category: selectorMetrics{90, 120}, group: selectorMetrics{55, 180},
		nextWidth: 96, restartWidth: 112,
		revealWidth: 112, playWidth: 112,
	}
}

func TestTrainerDisplayOffersFourFontSizesAndThreeBackgrounds(t *testing.T) {
	wantFontLabels := []string{"常规", "中等", "大号", "特大"}
	if len(trainerFontOptions) != len(wantFontLabels) {
		t.Fatalf("font options=%d want %d", len(trainerFontOptions), len(wantFontLabels))
	}
	lastPoint := int32(0)
	for index, want := range wantFontLabels {
		if trainerFontOptions[index].label != want || trainerFontOptions[index].point <= lastPoint {
			t.Fatalf("font option %d=%#v", index, trainerFontOptions[index])
		}
		lastPoint = trainerFontOptions[index].point
	}
	if len(trainerBackgroundOptions) != 3 {
		t.Fatalf("background options=%d want 3", len(trainerBackgroundOptions))
	}
	if trainerFontOptions[1].value != trainer.FontSizeMedium || trainerBackgroundOptions[0].value != trainer.BackgroundSoftGray {
		t.Fatalf("UI defaults are not represented by the expected options")
	}
}

func TestTrainerLayoutGrowsWithLongestTextAndFontHeight(t *testing.T) {
	metrics := sampleLayoutMetrics()
	base := calculateTrainerLayout(metrics)
	metrics.contentTextWidth += 420
	wider := calculateTrainerLayout(metrics)
	if wider.clientWidth <= base.clientWidth {
		t.Fatalf("longer single-line text did not widen client: base=%d wider=%d", base.clientWidth, wider.clientWidth)
	}
	metrics = sampleLayoutMetrics()
	metrics.lineHeight = 38
	taller := calculateTrainerLayout(metrics)
	if taller.clientHeight <= base.clientHeight {
		t.Fatalf("larger font did not increase client height: base=%d taller=%d", base.clientHeight, taller.clientHeight)
	}
}

func TestTrainerLayoutKeepsRowsInsideContentSizedWindow(t *testing.T) {
	metrics := sampleLayoutMetrics()
	layout := calculateTrainerLayout(metrics)
	selectors := []rect{layout.modeLabel, layout.modeCombo, layout.sectionLabel, layout.sectionCombo,
		layout.fontLabel, layout.fontCombo, layout.backgroundLabel, layout.backgroundCombo}
	lastRight := int32(0)
	for index, box := range selectors {
		if box.Left < lastRight || box.Right > layout.clientWidth {
			t.Fatalf("selector %d overlaps or exceeds client: %#v width=%d", index, box, layout.clientWidth)
		}
		lastRight = box.Right
	}
	if layout.detail.Bottom-layout.detail.Top < metrics.detailLines*metrics.lineHeight {
		t.Fatalf("detail height cannot show explicit lines: %#v", layout.detail)
	}
	inputRow := []rect{layout.input, layout.next, layout.restart}
	lastRight = 0
	for index, box := range inputRow {
		if box.Left < lastRight || box.Right > layout.clientWidth {
			t.Fatalf("input control %d overlaps or exceeds client: %#v", index, box)
		}
		lastRight = box.Right
	}
	if layout.progress.Top <= layout.modeLabel.Top || layout.score.Bottom > layout.clientHeight {
		t.Fatalf("vertical rows exceed client: progress=%#v score=%#v height=%d", layout.progress, layout.score, layout.clientHeight)
	}
}

func TestTrainerLayoutAddsLinkedExerciseFilterRow(t *testing.T) {
	metrics := sampleLayoutMetrics()
	withoutFilters := calculateTrainerLayout(metrics)
	metrics.showSegment = true
	metrics.showCategory = true
	metrics.showGroup = true
	withFilters := calculateTrainerLayout(metrics)
	if !withFilters.showSegment || !withFilters.showCategory || !withFilters.showGroup ||
		withFilters.segmentCombo.Right <= withFilters.segmentCombo.Left ||
		withFilters.categoryCombo.Right <= withFilters.categoryCombo.Left ||
		withFilters.groupCombo.Right <= withFilters.groupCombo.Left {
		t.Fatalf("exercise filters were not placed: %#v", withFilters)
	}
	if withFilters.clientHeight <= withoutFilters.clientHeight {
		t.Fatalf("group selector row did not grow the client: without=%d with=%d", withoutFilters.clientHeight, withFilters.clientHeight)
	}
	if withoutFilters.showSegment || withoutFilters.showCategory || withoutFilters.showGroup {
		t.Fatal("ordinary exercise layout unexpectedly shows linked filters")
	}
}

func TestSplitDisplayLinesPreservesExplicitRowsWithoutAutomaticWrapping(t *testing.T) {
	got := splitDisplayLines("第一行\r\n第二行很长")
	if len(got) != 2 || got[0] != "第一行" || got[1] != "第二行很长" {
		t.Fatalf("splitDisplayLines=%#v", got)
	}
}

func TestKeymapStartsWithAnswerVisible(t *testing.T) {
	if !defaultAnswerVisible(trainer.SectionKeymap) {
		t.Fatal("keymap practice must show the target key by default")
	}
	if defaultAnswerVisible(trainer.SectionSyllableAssociate) {
		t.Fatal("non-keymap practice must keep its answer hidden initially")
	}
	if !defaultAnswerVisible(trainer.SectionSyllableComposition) {
		t.Fatal("syllable composition must reuse the visible target-key practice flow")
	}
	if defaultAnswerVisible(trainer.SectionSyllablePractice) {
		t.Fatal("syllable practice should test recall before revealing its answer")
	}
}

func TestSyllablePracticeSelectsExercisesFromCurrentShouyinGroup(t *testing.T) {
	state := appState{
		lesson: trainer.Lesson{Sections: []trainer.Section{{Type: trainer.SectionSyllablePractice}}},
		syllableGroups: []trainer.ExerciseGroup{
			{ID: "syllables-n01", Exercises: []trainer.Exercise{{NumericPinyin: "ba1"}}},
			{ID: "syllables-n02", Exercises: []trainer.Exercise{{NumericPinyin: "pa1"}}},
		},
		sectionIndex:       0,
		syllableGroupIndex: 1,
	}
	if !state.selectedSectionIsSyllablePractice() {
		t.Fatal("syllable practice section was not recognized")
	}
	items := state.currentExercises()
	if len(items) != 1 || items[0].NumericPinyin != "pa1" {
		t.Fatalf("current syllable group exercises=%#v", items)
	}
}

func TestWordAndSentencePracticeUseLaunchSamples(t *testing.T) {
	word := trainer.Exercise{Prompt: "边做边试"}
	sentence := trainer.Exercise{Prompt: "工欲善其事"}
	state := appState{
		lesson: trainer.Lesson{Sections: []trainer.Section{
			{Type: trainer.SectionWordPractice},
			{Type: trainer.SectionSentencePractice},
		}},
		wordGroups: []trainer.ExerciseGroup{
			{Title: "双音词语", Exercises: []trainer.Exercise{{Prompt: "中国"}}},
			{Title: "三音词语", Exercises: []trainer.Exercise{{Prompt: "输入法"}}},
			{Title: "四音词语", Exercises: []trainer.Exercise{word}},
			{Title: "单音节字", Exercises: []trainer.Exercise{{Prompt: "音"}}},
		},
		wordGroupIndex:    2,
		sentenceExercises: []trainer.Exercise{sentence},
	}
	if got := state.currentExercises(); len(got) != 1 || got[0].Prompt != word.Prompt {
		t.Fatalf("word current exercises=%#v", got)
	}
	state.sectionIndex = 1
	if got := state.currentExercises(); len(got) != 1 || got[0].Prompt != sentence.Prompt {
		t.Fatalf("sentence current exercises=%#v", got)
	}
}

func TestEnterSubmissionAdvancesAndWrapsWithinCurrentGroup(t *testing.T) {
	accepted, correct, next, wrapped := submissionTransition("J", "J", 1, 4)
	if !accepted || !correct || next != 2 || wrapped {
		t.Fatalf("ordinary transition=(%v,%v,%d,%v)", accepted, correct, next, wrapped)
	}
	accepted, correct, next, wrapped = submissionTransition("x", "J", 3, 4)
	if !accepted || correct || next != 0 || !wrapped {
		t.Fatalf("wrapping transition=(%v,%v,%d,%v)", accepted, correct, next, wrapped)
	}
	accepted, _, next, _ = submissionTransition("  ", "J", 2, 4)
	if accepted || next != 2 {
		t.Fatalf("blank transition accepted=%v next=%d", accepted, next)
	}
}
