package yimecore

import (
	"errors"
	"reflect"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func TestSegmentCorrectionPreservesOtherSegmentsUntilExplicitSentenceCommit(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100}, {Text: "丁", Code: "cd", Weight: 90},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	sentence := state.Sentence
	if sentence != nil && sentence.Text != "甲丙" {
		sentence = nil
	}
	if sentence == nil || len(sentence.Segments) != 2 {
		t.Fatalf("initial sentence missing: %#v", state)
	}

	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: sentence.Segments[0].Start, SegmentEnd: sentence.Segments[0].End,
	})
	if err != nil || focused.State.ActiveSegment == nil || focused.State.RawInput != "abcd" {
		t.Fatalf("focus failed: result=%#v err=%v", focused, err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "乙")
	if replacement == nil {
		t.Fatalf("first-segment replacement missing: %#v", focused.State)
	}
	replaced, err := engine.Select(replacement.ID)
	if err != nil || replaced.Commit != "" || replaced.State.ActiveSegment == nil ||
		replaced.State.ActiveSegment.Text != "丙" {
		t.Fatalf("segment selection committed early: result=%#v err=%v", replaced, err)
	}
	corrected := replaced.State.Sentence
	if corrected == nil || len(corrected.Segments) != 2 || corrected.Segments[1].Text != "丙" {
		t.Fatalf("suffix was not preserved: %#v", replaced.State)
	}

	focused, err = engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: corrected.ID,
		SegmentStart: corrected.Segments[1].Start, SegmentEnd: corrected.Segments[1].End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement = findBundleCandidate(focused.State.Candidates, "丁")
	if replacement == nil {
		t.Fatalf("final-segment replacement missing: %#v", focused.State)
	}
	replaced, err = engine.Select(replacement.ID)
	if err != nil || replaced.Commit != "" {
		t.Fatalf("second segment selection committed early: result=%#v err=%v", replaced, err)
	}
	corrected = replaced.State.Sentence
	if corrected == nil {
		t.Fatalf("two corrections were not retained: %#v", replaced.State)
	}
	committed, err := engine.Select(corrected.ID)
	if err != nil || committed.Commit != "乙丁" || committed.State.RawInput != "" {
		t.Fatalf("explicit sentence commit failed: result=%#v err=%v", committed, err)
	}
}

func TestPublishedSentenceRemainsSelectableUntilAnotherSnapshotIsPublished(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100},
		{Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	published := applyBundleCode(t, engine, "abcd").Sentence
	if published == nil || published.Text != "甲丙" {
		t.Fatalf("initial published sentence = %#v", published)
	}

	engine.segmentChoices = map[segmentSpan]record{
		{start: 0, end: 2}: {text: "乙", code: "ab", weight: 90, source: index.identity()},
	}
	engine.resetSentenceComposer()
	engine.refresh()
	if engine.sentence == nil || engine.sentence.Text != "乙丙" || engine.sentence.ID == published.ID {
		t.Fatalf("internal refresh did not replace the current sentence: %#v", engine.sentence)
	}

	committed, err := engine.Select(published.ID)
	if err != nil || committed.Commit != "甲丙" || committed.State.RawInput != "" {
		t.Fatalf("last published sentence became stale: result=%#v err=%v", committed, err)
	}
}

func TestSegmentSelectionLearnsOnlyAfterExplicitSentenceCommit(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "之", Code: "ab", Weight: 100}, {Text: "知", Code: "ab", Weight: 90},
		{Text: "识", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	if err := engine.SetLinearRerankerEnabled(true); err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	if state.Sentence == nil || state.Sentence.Text != "之识" {
		t.Fatalf("initial static sentence = %#v", state.Sentence)
	}
	originalSegments := append([]engineapi.Segment(nil), state.Sentence.Segments...)
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "知")
	if replacement == nil {
		t.Fatalf("word replacement missing: %#v", focused.State.Candidates)
	}
	replaced, err := engine.SelectIdempotent(replacement.ID, "segment-word-selection")
	if err != nil || replaced.Commit != "" || replaced.State.Sentence == nil || replaced.State.Sentence.Text != "知识" {
		t.Fatalf("word replacement committed or failed: result=%#v err=%v", replaced, err)
	}
	if model.Generation() != 0 {
		t.Fatalf("segment replacement learned before commit: generation=%d", model.Generation())
	}
	if len(model.rerankerWeights) != 0 {
		t.Fatalf("segment replacement trained reranker before commit: %#v", model.rerankerWeights)
	}

	engine.Reset()
	notLearned := applyBundleCode(t, engine, "abcd").Sentence
	if notLearned == nil || notLearned.Text != "之识" {
		t.Fatalf("cancelled replacement changed following sentence: %#v", notLearned)
	}

	first = notLearned.Segments[0]
	focused, err = engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: notLearned.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement = findBundleCandidate(focused.State.Candidates, "知")
	if replacement == nil {
		t.Fatalf("word replacement missing after reset: %#v", focused.State.Candidates)
	}
	replaced, err = engine.SelectIdempotent(replacement.ID, "segment-word-selection")
	if err != nil || replaced.State.Sentence == nil || replaced.State.Sentence.Text != "知识" {
		t.Fatalf("second word replacement failed: result=%#v err=%v", replaced, err)
	}
	committed, err := engine.SelectIdempotent(replaced.State.Sentence.ID, "sentence-commit")
	if err != nil || committed.Commit != "知识" || model.Generation() != 1 {
		t.Fatalf("sentence commit did not atomically learn: result=%#v err=%v generation=%d",
			committed, err, model.Generation())
	}
	records := model.LearnedRecords()
	if findLearnedRecord(records, "ab", "知") == nil ||
		findLearnedRecord(records, "abcd", "知识") == nil {
		t.Fatalf("committed segment and sentence were not learned together: %#v", records)
	}
	if boost := model.contextBoost("知", "cd", "识"); boost != contextBoostPerSelection {
		t.Fatalf("adjacent segment pairing was not learned: boost=%d", boost)
	}
	if boost := model.candidateBoost("abcd", "之识"); boost != -userPenaltyPerRejection {
		t.Fatalf("replaced sentence rejection was not learned: boost=%d", boost)
	}
	if correctedScore, originalScore := model.sentenceRerankerScore(replaced.State.Sentence.Segments), model.sentenceRerankerScore(originalSegments); correctedScore <= originalScore {
		t.Fatalf("explicit correction did not train pairwise reranker: corrected=%d original=%d", correctedScore, originalScore)
	}

	learned := applyBundleCode(t, engine, "abcd").Sentence
	if learned == nil || learned.Text != "知识" || learned.Segments[0].Text != "知" {
		t.Fatalf("committed word did not tune the following sentence: %#v", learned)
	}
}

func TestSentenceLearningPersistenceFailureAppliesNoPartialObservation(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	var attempted UserMutation
	model.SetMutationWriter(func(mutation UserMutation) error {
		attempted = mutation
		return errors.New("forced sentence journal failure")
	})
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	if state.Sentence == nil || len(state.Sentence.Segments) != 2 {
		t.Fatalf("sentence missing: %#v", state)
	}
	result, err := engine.SelectIdempotent(state.Sentence.ID, "failed-sentence-commit")
	if err == nil || result.Commit != "" || model.Generation() != 0 ||
		len(model.LearnedRecords()) != 0 {
		t.Fatalf("failed sentence persistence partially applied: result=%#v err=%v generation=%d records=%#v",
			result, err, model.Generation(), model.LearnedRecords())
	}
	if len(attempted.Observations) != 3 || attempted.Code != "abcd" || attempted.Text != "甲丙" {
		t.Fatalf("sentence was not offered as one batch mutation: %#v", attempted)
	}
}

func TestClearDiscardsPendingSegmentLearning(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "乙")
	if replacement == nil {
		t.Fatalf("replacement missing: %#v", focused.State.Candidates)
	}
	if _, err := engine.SelectIdempotent(replacement.ID, "pending-before-clear"); err != nil {
		t.Fatal(err)
	}
	cleared, err := engine.Apply(engineapi.Event{Operation: engineapi.Clear})
	if err != nil || cleared.State.RawInput != "" || model.Generation() != 0 ||
		len(model.LearnedRecords()) != 0 {
		t.Fatalf("Clear persisted pending learning: result=%#v err=%v generation=%d records=%#v",
			cleared, err, model.Generation(), model.LearnedRecords())
	}
	remaining := applyBundleCode(t, engine, "abcd").Sentence
	if remaining == nil || remaining.Text != "甲丙" {
		t.Fatalf("Clear did not discard pending segment choice: %#v", remaining)
	}
}

func findLearnedRecord(records []LearnedRecord, code, text string) *LearnedRecord {
	for index := range records {
		if records[index].Code == code && records[index].Text == text {
			return &records[index]
		}
	}
	return nil
}

func TestSegmentFocusRejectsUnknownCandidateOrRangeWithoutMutation(t *testing.T) {
	index, err := NewIndex([]Entry{{Text: "甲", Code: "ab", Weight: 1}, {Text: "乙", Code: "cd", Weight: 1}})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	before := applyBundleCode(t, engine, "abcd")
	if _, err := engine.Apply(engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: "missing", SegmentStart: 0, SegmentEnd: 2}); err != engineapi.ErrInvalidEvent {
		t.Fatalf("unknown candidate error = %v", err)
	}
	after := engine.snapshot()
	if after.RawInput != before.RawInput || after.ActiveSegment != nil || len(after.Candidates) != len(before.Candidates) {
		t.Fatalf("invalid focus mutated state: before=%#v after=%#v", before, after)
	}
}

func TestFocusedSentenceRowCommitsWhileSegmentChoicesAreVisible(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	sentence := state.Sentence
	if sentence == nil || len(sentence.Segments) != 2 {
		t.Fatalf("initial sentence missing: %#v", state)
	}
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: sentence.Segments[0].Start, SegmentEnd: sentence.Segments[0].End,
	})
	if err != nil || focused.State.ActiveSegment == nil || len(focused.State.Candidates) != 2 {
		t.Fatalf("first-word sequence missing: result=%#v err=%v", focused, err)
	}
	committed, err := engine.Select(sentence.ID)
	if err != nil || committed.Commit != "甲丙" || committed.State.RawInput != "" {
		t.Fatalf("focused sentence row did not commit: result=%#v err=%v", committed, err)
	}
}

func TestFocusedSentenceCanMoveDirectlyBetweenEditableSegments(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100}, {Text: "丁", Code: "cd", Weight: 90},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	sentence := state.Sentence
	if sentence == nil {
		t.Fatalf("sentence missing: %#v", state)
	}
	_, err = engine.Apply(engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: sentence.Segments[0].Start, SegmentEnd: sentence.Segments[0].End})
	if err != nil {
		t.Fatal(err)
	}
	focused, err := engine.Apply(engineapi.Event{Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: sentence.Segments[1].Start, SegmentEnd: sentence.Segments[1].End})
	if err != nil || focused.State.ActiveSegment == nil ||
		focused.State.ActiveSegment.Start != sentence.Segments[1].Start ||
		findBundleCandidate(focused.State.Candidates, "丁") == nil {
		t.Fatalf("direct segment switch failed: result=%#v err=%v", focused, err)
	}
}

func TestCompleteSentenceSegmentsPublishOnlyExactAlternatives(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "甲长", Code: "abx", Weight: 1000},
		{Text: "丙", Code: "cd", Weight: 100}, {Text: "丁", Code: "cd", Weight: 90},
		{Text: "丙长", Code: "cdy", Weight: 1000},
		{Text: "戊", Code: "ef", Weight: 100}, {Text: "己", Code: "ef", Weight: 90},
		{Text: "末段补全", Code: "efz", Weight: 1000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	if state.Sentence == nil || len(state.Sentence.Segments) != 3 {
		t.Fatalf("three-segment sentence missing: %#v", state)
	}
	for segmentIndex, forbidden := range []string{"甲长", "丙长", "末段补全"} {
		segment := state.Sentence.Segments[segmentIndex]
		focused, focusErr := engine.Apply(engineapi.Event{
			Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
			SegmentStart: segment.Start, SegmentEnd: segment.End,
		})
		if focusErr != nil || focused.State.ActiveSegment == nil ||
			findBundleCandidate(focused.State.Candidates, forbidden) != nil {
			t.Fatalf("non-final segment %d exposed longer completion: state=%#v err=%v",
				segmentIndex, focused.State, focusErr)
		}
		for _, candidate := range focused.State.Candidates {
			if !candidate.Exact || candidate.Code != segment.Code {
				t.Fatalf("non-final segment %d candidate is not exact: %#v", segmentIndex, candidate)
			}
		}
	}
}

func TestSegmentCorrectionLongSessionKeepsFirstMiddleAndFinalSegments(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100}, {Text: "丁", Code: "cd", Weight: 90},
		{Text: "戊", Code: "ef", Weight: 100}, {Text: "己", Code: "ef", Weight: 90},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	if state.Sentence == nil || len(state.Sentence.Segments) != 3 {
		t.Fatalf("initial three-segment sentence missing: %#v", state)
	}

	wanted := []string{"甲", "丙", "戊"}
	choices := [][2]string{{"甲", "乙"}, {"丙", "丁"}, {"戊", "己"}}
	for cycle := 0; cycle < 25; cycle++ {
		for segmentIndex := range choices {
			sentence := state.Sentence
			if sentence == nil || len(sentence.Segments) != len(choices) {
				t.Fatalf("cycle %d segment %d lost sentence: %#v", cycle+1, segmentIndex, state)
			}
			segment := sentence.Segments[segmentIndex]
			focused, focusErr := engine.Apply(engineapi.Event{
				Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
				SegmentStart: segment.Start, SegmentEnd: segment.End,
			})
			if focusErr != nil || focused.Commit != "" || focused.State.ActiveSegment == nil ||
				focused.State.ActiveSegment.Start != segment.Start ||
				focused.State.ActiveSegment.End != segment.End || focused.State.RawInput != "abcdef" {
				t.Fatalf("cycle %d segment %d focus failed: result=%#v err=%v",
					cycle+1, segmentIndex, focused, focusErr)
			}

			wanted[segmentIndex] = choices[segmentIndex][(cycle+segmentIndex+1)%2]
			replacement := findBundleCandidate(focused.State.Candidates, wanted[segmentIndex])
			if replacement == nil {
				t.Fatalf("cycle %d segment %d replacement %q missing: %#v",
					cycle+1, segmentIndex, wanted[segmentIndex], focused.State.Candidates)
			}
			replaced, selectErr := engine.Select(replacement.ID)
			if selectErr != nil || replaced.Commit != "" ||
				replaced.State.RawInput != "abcdef" || replaced.State.Sentence == nil ||
				len(replaced.State.Sentence.Segments) != len(choices) {
				t.Fatalf("cycle %d segment %d replacement failed: result=%#v err=%v",
					cycle+1, segmentIndex, replaced, selectErr)
			}
			if segmentIndex+1 < len(choices) {
				next := replaced.State.Sentence.Segments[segmentIndex+1]
				if replaced.State.ActiveSegment == nil ||
					replaced.State.ActiveSegment.Start != next.Start ||
					replaced.State.ActiveSegment.End != next.End {
					t.Fatalf("cycle %d segment %d did not advance: %#v",
						cycle+1, segmentIndex, replaced.State)
				}
			} else if replaced.State.ActiveSegment != nil || len(replaced.State.Candidates) != 0 {
				t.Fatalf("cycle %d final segment did not become commit-ready: %#v",
					cycle+1, replaced.State)
			}
			for index, text := range wanted {
				if replaced.State.Sentence.Segments[index].Text != text {
					t.Fatalf("cycle %d segment %d changed segment %d: got %#v want %q",
						cycle+1, segmentIndex, index, replaced.State.Sentence.Segments, text)
				}
			}
			state = replaced.State
		}
	}

	committed, err := engine.Select(state.Sentence.ID)
	wantedCommit := wanted[0] + wanted[1] + wanted[2]
	if err != nil || committed.Commit != wantedCommit || committed.State.RawInput != "" ||
		committed.State.Sentence != nil || committed.State.ActiveSegment != nil {
		t.Fatalf("long-session sentence commit failed: result=%#v err=%v", committed, err)
	}
}

func TestRecursiveResegmentationLongSessionKeepsFirstMiddleAndFinalState(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "正是这", Code: "abc", Weight: 10_000},
		{Text: "正是", Code: "ab", Weight: 900},
		{Text: "正视", Code: "ab", Weight: 800},
		{Text: "这", Code: "c", Weight: 700},
		{Text: "个", Code: "d", Weight: 700},
		{Text: "这个", Code: "cd", Weight: 8_000},
		{Text: "问题", Code: "ef", Weight: 700},
		{Text: "问提", Code: "ef", Weight: 600},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.observe("abcdef", "正是这个问题")
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}

	for cycle := 1; cycle <= 25; cycle++ {
		engine.Reset()
		state := applyBundleCode(t, engine, "abcdef")
		if state.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"正是这", "个", "问题"}) {
			t.Fatalf("cycle %d initial learned sentence = %#v", cycle, state.Sentence)
		}

		first := state.Sentence.Segments[0]
		focused, focusErr := engine.Apply(engineapi.Event{
			Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
			SegmentStart: first.Start, SegmentEnd: first.End,
		})
		if focusErr != nil || focused.Commit != "" || focused.State.ActiveSegment == nil ||
			focused.State.ActiveSegment.Text != "正是" ||
			!reflect.DeepEqual(segmentTexts(focused.State.Sentence.Segments), []string{"正是", "这", "个", "问题"}) {
			t.Fatalf("cycle %d first segment did not expand authoritatively: result=%#v err=%v",
				cycle, focused, focusErr)
		}
		firstReplacement := findBundleCandidate(focused.State.Candidates, "正视")
		if firstReplacement == nil {
			t.Fatalf("cycle %d first replacement missing: %#v", cycle, focused.State.Candidates)
		}
		recomposed, selectErr := engine.Select(firstReplacement.ID)
		if selectErr != nil || recomposed.Commit != "" || recomposed.State.ActiveSegment == nil ||
			recomposed.State.ActiveSegment.Text != "这个" ||
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"正视", "这个", "问题"}) ||
			findBundleCandidate(recomposed.State.Candidates, "正是这个问题") != nil {
			t.Fatalf("cycle %d first replacement did not recompose and advance: result=%#v err=%v",
				cycle, recomposed, selectErr)
		}

		middle := *recomposed.State.ActiveSegment
		expanded, expandErr := engine.Apply(engineapi.Event{
			Operation: engineapi.FocusSegment, CandidateID: recomposed.State.Sentence.ID,
			SegmentStart: middle.Start, SegmentEnd: middle.End,
		})
		if expandErr != nil || expanded.Commit != "" || expanded.State.ActiveSegment == nil ||
			expanded.State.ActiveSegment.Text != "这" ||
			!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"正视", "这", "个", "问题"}) {
			t.Fatalf("cycle %d middle segment did not recursively expand: result=%#v err=%v",
				cycle, expanded, expandErr)
		}
		middleCandidate := findBundleCandidate(expanded.State.Candidates, "这")
		if middleCandidate == nil {
			t.Fatalf("cycle %d middle candidate missing: %#v", cycle, expanded.State.Candidates)
		}
		advanced, selectErr := engine.Select(middleCandidate.ID)
		if selectErr != nil || advanced.Commit != "" || advanced.State.ActiveSegment == nil ||
			advanced.State.ActiveSegment.Text != "个" {
			t.Fatalf("cycle %d middle selection did not advance: result=%#v err=%v",
				cycle, advanced, selectErr)
		}
		individualCandidate := findBundleCandidate(advanced.State.Candidates, "个")
		if individualCandidate == nil {
			t.Fatalf("cycle %d individual middle candidate missing: %#v", cycle, advanced.State.Candidates)
		}
		advanced, selectErr = engine.Select(individualCandidate.ID)
		if selectErr != nil || advanced.Commit != "" || advanced.State.ActiveSegment == nil ||
			advanced.State.ActiveSegment.Text != "问题" ||
			!reflect.DeepEqual(segmentTexts(advanced.State.Sentence.Segments), []string{"正视", "这个", "问题"}) {
			t.Fatalf("cycle %d tail focus did not follow middle selection: result=%#v err=%v",
				cycle, advanced, selectErr)
		}

		finalReplacement := findBundleCandidate(advanced.State.Candidates, "问提")
		if finalReplacement == nil {
			t.Fatalf("cycle %d final replacement missing: %#v", cycle, advanced.State.Candidates)
		}
		ready, selectErr := engine.Select(finalReplacement.ID)
		if selectErr != nil || ready.Commit != "" || ready.State.ActiveSegment != nil ||
			len(ready.State.Candidates) != 0 || ready.State.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(ready.State.Sentence.Segments), []string{"正视", "这个", "问提"}) {
			t.Fatalf("cycle %d final replacement did not become commit-ready: result=%#v err=%v",
				cycle, ready, selectErr)
		}
	}
}

func TestConstructionResegmentationRewritesCompleteSentencePath(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "文档", Code: "ab", Weight: 10_000},
		{Text: "保存在", Code: "cde", Weight: 2_000},
		{Text: "保存", Code: "cd", Weight: 30_000},
		{Text: "在", Code: "e", Weight: 100_000_000},
		{Text: "保", Code: "c", Weight: 90_000_000},
		{Text: "存在", Code: "de", Weight: 300_000},
		{Text: "哪", Code: "f", Weight: 100_000_000},
		{Text: "里", Code: "g", Weight: 100_000_000},
		{Text: "哪里", Code: "fg", Weight: 135_154},
		{Text: "目录中", Code: "hij", Weight: 2_000},
		{Text: "目录", Code: "hi", Weight: 23_582},
		{Text: "中", Code: "j", Weight: 100_000_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}

	for _, test := range []struct {
		name       string
		input      string
		wantBefore []string
		wantAfter  []string
	}{
		{
			name:       "where suffix",
			input:      "abcdefg",
			wantBefore: []string{"文档", "保存在", "哪", "里"},
			wantAfter:  []string{"文档", "保存", "在", "哪里"},
		},
		{
			name:       "directory suffix",
			input:      "abcdehij",
			wantBefore: []string{"文档", "保存在", "目录中"},
			wantAfter:  []string{"文档", "保存", "在", "目录", "中"},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			engine.Reset()
			applyBundleCode(t, engine, test.input)
			segments := make([]engineapi.Segment, 0, len(test.wantBefore))
			start := 0
			for _, text := range test.wantBefore {
				var match record
				found := false
				for end := start + 1; end <= len(test.input); end++ {
					for _, candidate := range engine.index.exact(test.input[start:end], segmentCandidateLimit) {
						if candidate.text == text {
							match = candidate
							segments = append(segments, engineapi.Segment{
								Start: start, End: end, Text: text, Code: candidate.code,
							})
							start = end
							found = true
							break
						}
					}
					if found {
						break
					}
				}
				if !found {
					t.Fatalf("fixture segment %q has no exact source record after %#v", text, match)
				}
			}
			surface := ""
			for _, segment := range segments {
				surface += segment.Text
			}
			engine.sentence = &engineapi.Candidate{
				ID: "construction-fixture\x1f" + test.input, Text: surface,
				Code: test.input, Exact: true, Segments: segments,
			}
			state := engine.snapshot()
			if state.Sentence == nil || !reflect.DeepEqual(segmentTexts(state.Sentence.Segments), test.wantBefore) {
				t.Fatalf("initial segmentation = %#v, want %v", state.Sentence, test.wantBefore)
			}
			middle := state.Sentence.Segments[1]
			expanded, expandErr := engine.Apply(engineapi.Event{
				Operation: engineapi.ExpandSegment, CandidateID: state.Sentence.ID,
				SegmentStart: middle.Start, SegmentEnd: middle.End,
			})
			if expandErr != nil || expanded.State.Sentence == nil ||
				!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), test.wantAfter) {
				t.Fatalf("expanded segmentation = %#v, want %v, err=%v",
					expanded.State.Sentence, test.wantAfter, expandErr)
			}
			if expanded.State.ActiveSegment == nil || expanded.State.ActiveSegment.Text != "保存" {
				t.Fatalf("first child was not focused after expansion: %#v", expanded.State)
			}
			if expanded.State.Sentence.Score.Static != expanded.State.Sentence.Weight ||
				expanded.State.Sentence.Score.Total != expanded.State.Sentence.Score.Static+
					expanded.State.Sentence.Score.Context {
				t.Fatalf("expanded score attribution = %#v", expanded.State.Sentence)
			}
		})
	}
}

func TestConstructionResegmentationRejectsUnregisteredRightSlot(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "文档", Code: "ab", Weight: 10_000},
		{Text: "保存在", Code: "cde", Weight: 2_000},
		{Text: "保存", Code: "cd", Weight: 30_000},
		{Text: "在", Code: "e", Weight: 100_000_000},
		{Text: "桌面", Code: "fg", Weight: 20_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdefg")
	if state.Sentence == nil || !reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"文档", "保存在", "桌面"}) {
		t.Fatalf("initial unregistered construction = %#v", state.Sentence)
	}
	middle := state.Sentence.Segments[1]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: middle.Start, SegmentEnd: middle.End,
	})
	if err != nil || focused.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(focused.State.Sentence.Segments), []string{"文档", "保存在", "桌面"}) ||
		focused.State.ActiveSegment == nil || focused.State.ActiveSegment.Text != "保存在" {
		t.Fatalf("unregistered right slot was rewritten: result=%#v err=%v", focused, err)
	}
}

func TestRecursiveSegmentExpansionOpensExactWholeWord(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "文档保存", Code: "abcd", Weight: 100_000},
		{Text: "文档", Code: "ab", Weight: 10_000},
		{Text: "保存", Code: "cd", Weight: 9_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcd")
	if state.Sentence == nil || len(state.Sentence.Segments) != 0 {
		t.Fatalf("exact whole word should start collapsed: %#v", state)
	}

	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: 0, SegmentEnd: len(state.RawInput),
	})
	if err != nil || focused.State.Sentence == nil || len(focused.State.Sentence.Segments) != 0 ||
		focused.State.ActiveSegment == nil || focused.State.ActiveSegment.Text != "文档保存" {
		t.Fatalf("exact whole-word focus expanded the word: result=%#v err=%v", focused, err)
	}

	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.ExpandSegment, CandidateID: focused.State.Sentence.ID,
		SegmentStart: 0, SegmentEnd: len(state.RawInput),
	})
	if err != nil || expanded.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"文档", "保存"}) ||
		expanded.State.ActiveSegment == nil || expanded.State.ActiveSegment.Text != "文档" {
		t.Fatalf("exact whole-word expansion failed: result=%#v err=%v", expanded, err)
	}
}

func TestExplicitStandaloneWordExpansionAllowsUnlearnedCharacterCombination(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "合理", Code: "hwer\\l", Weight: 195_065},
		{Text: "合", Code: "hwer", Weight: 104_220_652},
		{Text: "何", Code: "hwer", Weight: 103_392_144},
		{Text: "理", Code: "\\l", Weight: 104_237_342},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "hwer\\l")
	if state.Sentence == nil || state.Sentence.Text != "合理" || len(state.Sentence.Segments) != 0 {
		t.Fatalf("standalone word should start collapsed: %#v", state.Sentence)
	}

	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.ExpandSegment, CandidateID: state.Sentence.ID,
		SegmentStart: 0, SegmentEnd: len(state.RawInput),
	})
	if err != nil || expanded.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"合", "理"}) ||
		expanded.State.ActiveSegment == nil || expanded.State.ActiveSegment.Text != "合" {
		t.Fatalf("standalone word expansion failed: result=%#v err=%v", expanded, err)
	}
	replacement := findBundleCandidate(expanded.State.Candidates, "何")
	if replacement == nil {
		t.Fatalf("character alternative missing after expansion: %#v", expanded.State.Candidates)
	}

	replaced, err := engine.Select(replacement.ID)
	if err != nil || replaced.State.Sentence == nil || replaced.State.Sentence.Text != "何理" ||
		!reflect.DeepEqual(segmentTexts(replaced.State.Sentence.Segments), []string{"何", "理"}) {
		t.Fatalf("unlearned character combination failed: result=%#v err=%v", replaced, err)
	}
	committed, err := engine.SelectIdempotent(replaced.State.Sentence.ID, "commit-unlearned-he-li")
	if err != nil || committed.Commit != "何理" || committed.State.RawInput != "" {
		t.Fatalf("unlearned character combination did not commit: result=%#v err=%v", committed, err)
	}
}

func TestExpandedStaticWordCollapsesAgainAfterUnchangedChildrenAreConfirmed(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "权利", Code: "ab", Weight: 1_000},
		{Text: "权力", Code: "ab", Weight: 900},
		{Text: "权", Code: "a", Weight: 800},
		{Text: "利", Code: "b", Weight: 800},
		{Text: "力", Code: "b", Weight: 700},
		{Text: "不是", Code: "cd", Weight: 1_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}

	state := applyBundleCode(t, engine, "abcdab")
	if state.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"权利", "不是", "权利"}) {
		t.Fatalf("initial sentence = %#v", state.Sentence)
	}
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "权力")
	if replacement == nil {
		t.Fatalf("权力 replacement missing: %#v", focused.State.Candidates)
	}
	replaced, err := engine.Select(replacement.ID)
	if err != nil || replaced.State.Sentence == nil || replaced.State.Sentence.Text != "权力不是权利" {
		t.Fatalf("权力 replacement failed: result=%#v err=%v", replaced, err)
	}
	committed, err := engine.SelectIdempotent(replaced.State.Sentence.ID, "commit-whole-power")
	if err != nil || committed.Commit != "权力不是权利" {
		t.Fatalf("whole-word sentence commit failed: result=%#v err=%v", committed, err)
	}

	reentered := applyBundleCode(t, engine, "abcdab")
	if reentered.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"权力", "不是", "权利"}) {
		t.Fatalf("learned whole-word sentence = %#v", reentered.Sentence)
	}
	first = reentered.Sentence.Segments[0]
	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.ExpandSegment, CandidateID: reentered.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil || expanded.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"权", "力", "不是", "权利"}) {
		t.Fatalf("权力 expansion failed: result=%#v err=%v", expanded, err)
	}

	engine.Reset()
	reentered = applyBundleCode(t, engine, "abcdab")
	if reentered.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"权力", "不是", "权利"}) {
		t.Fatalf("unconfirmed expansion persisted: %#v", reentered.Sentence)
	}
	first = reentered.Sentence.Segments[0]
	expanded, err = engine.Apply(engineapi.Event{
		Operation: engineapi.ExpandSegment, CandidateID: reentered.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, text := range []string{"权", "力"} {
		child := findBundleCandidate(expanded.State.Candidates, text)
		if child == nil {
			t.Fatalf("expanded child %q missing: %#v", text, expanded.State.Candidates)
		}
		expanded, err = engine.Select(child.ID)
		if err != nil {
			t.Fatal(err)
		}
	}
	if expanded.State.Sentence == nil || expanded.State.Sentence.Text != "权力不是权利" ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"权力", "不是", "权利"}) {
		t.Fatalf("confirmed children changed sentence: %#v", expanded.State.Sentence)
	}
	committed, err = engine.SelectIdempotent(expanded.State.Sentence.ID, "commit-expanded-power")
	if err != nil || committed.Commit != "权力不是权利" {
		t.Fatalf("expanded sentence commit failed: result=%#v err=%v", committed, err)
	}

	reentered = applyBundleCode(t, engine, "abcdab")
	if reentered.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"权力", "不是", "权利"}) {
		t.Fatalf("confirmed unchanged children permanently split the word: %#v", reentered.Sentence)
	}
}

func TestLearnedLongSegmentExpansionReleasesRightSideForRecomposition(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "正是这", Code: "abc", Weight: 10_000},
		{Text: "正是", Code: "ab", Weight: 900},
		{Text: "正视", Code: "ab", Weight: 800},
		{Text: "这", Code: "c", Weight: 700},
		{Text: "个", Code: "d", Weight: 700},
		{Text: "这个", Code: "cd", Weight: 8_000},
		{Text: "问题", Code: "ef", Weight: 700},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.observe("abcdef", "正是这个问题")
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	if state.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"正是这", "个", "问题"}) {
		t.Fatalf("learned high-weight segmentation = %#v", state.Sentence)
	}

	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil || focused.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(focused.State.Sentence.Segments), []string{"正是", "这", "个", "问题"}) {
		t.Fatalf("learned long segment focus did not expand = %#v, err=%v", focused.State.Sentence, err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "正视")
	if replacement == nil {
		t.Fatalf("正视 is absent after focus expansion: %#v", focused.State.Candidates)
	}
	recomposed, err := engine.Select(replacement.ID)
	if err != nil || recomposed.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"正视", "这个", "问题"}) ||
		recomposed.State.ActiveSegment == nil || recomposed.State.ActiveSegment.Text != "这个" ||
		findBundleCandidate(recomposed.State.Candidates, "这个") == nil ||
		findBundleCandidate(recomposed.State.Candidates, "正是这个问题") != nil {
		t.Fatalf("right side did not recompose across the old boundary: %#v, err=%v",
			recomposed.State, err)
	}
	middleCandidate := findBundleCandidate(recomposed.State.Candidates, "这个")
	advanced, err := engine.Select(middleCandidate.ID)
	if err != nil || advanced.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(advanced.State.Sentence.Segments), []string{"正视", "这个", "问题"}) ||
		advanced.State.ActiveSegment == nil || advanced.State.ActiveSegment.Text != "问题" ||
		findBundleCandidate(advanced.State.Candidates, "问题") == nil {
		t.Fatalf("middle selection did not advance to final segment: %#v, err=%v", advanced.State, err)
	}
	finalCandidate := findBundleCandidate(advanced.State.Candidates, "问题")
	ready, err := engine.Select(finalCandidate.ID)
	if err != nil || ready.Commit != "" || ready.State.Sentence == nil ||
		ready.State.Sentence.Text != "正视这个问题" || ready.State.ActiveSegment != nil ||
		len(ready.State.Candidates) != 0 {
		t.Fatalf("final segment did not leave the corrected sentence ready: %#v, err=%v", ready, err)
	}
	committed, err := engine.Select(ready.State.Sentence.ID)
	if err != nil || committed.Commit != "正视这个问题" || committed.State.RawInput != "" {
		t.Fatalf("corrected sentence commit failed: %#v, err=%v", committed, err)
	}
}

func TestAutomaticallyAdvancedSegmentExpandsOnSingleFocus(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "正是这", Code: "abc", Weight: 10_000},
		{Text: "正是", Code: "ab", Weight: 900},
		{Text: "正视", Code: "ab", Weight: 800},
		{Text: "这", Code: "c", Weight: 700},
		{Text: "个", Code: "d", Weight: 700},
		{Text: "这个", Code: "cd", Weight: 8_000},
		{Text: "问题", Code: "ef", Weight: 700},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.observe("abcdef", "正是这个问题")
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "正视")
	if replacement == nil {
		t.Fatal("正视 is absent after focus expansion")
	}
	recomposed, err := engine.Select(replacement.ID)
	if err != nil || recomposed.State.ActiveSegment == nil ||
		recomposed.State.ActiveSegment.Text != "这个" {
		t.Fatalf("这个 was not automatically focused: %#v, err=%v", recomposed.State, err)
	}

	middle := *recomposed.State.ActiveSegment
	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: recomposed.State.Sentence.ID,
		SegmentStart: middle.Start, SegmentEnd: middle.End,
	})
	if err != nil || expanded.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"正视", "这", "个", "问题"}) {
		t.Fatalf("single focus did not recursively expand 这个: %#v, err=%v", expanded.State, err)
	}
}

func TestFinalSegmentPromotesOnlyMatchingExactSentenceCandidate(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "正是这", Code: "abc", Weight: 10_000},
		{Text: "正是", Code: "ab", Weight: 900},
		{Text: "正视", Code: "ab", Weight: 800},
		{Text: "这", Code: "c", Weight: 700},
		{Text: "个", Code: "d", Weight: 700},
		{Text: "这个", Code: "cd", Weight: 8_000},
		{Text: "问题", Code: "ef", Weight: 700},
		{Text: "正视这个问题", Code: "abcdef", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.observe("abcdef", "正是这个问题")
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	if state.Sentence == nil || len(state.Sentence.Segments) != 3 ||
		state.Sentence.Text != "正是这个问题" {
		t.Fatalf("learned starting sentence = %#v", state.Sentence)
	}
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "正视")
	if replacement == nil {
		t.Fatal("正视 is absent after focus expansion")
	}
	advanced, err := engine.Select(replacement.ID)
	if err != nil || advanced.State.ActiveSegment == nil ||
		advanced.State.ActiveSegment.Text != "这个" {
		t.Fatalf("selection did not advance to 这个: %#v, err=%v", advanced.State, err)
	}
	middle := findBundleCandidate(advanced.State.Candidates, "这个")
	advanced, err = engine.Select(middle.ID)
	if err != nil || advanced.State.ActiveSegment == nil ||
		advanced.State.ActiveSegment.Text != "问题" {
		t.Fatalf("selection did not advance to 问题: %#v, err=%v", advanced.State, err)
	}
	last := findBundleCandidate(advanced.State.Candidates, "问题")
	ready, err := engine.Select(last.ID)
	if err != nil || ready.State.ActiveSegment != nil || len(ready.State.Candidates) != 1 ||
		!ready.State.Candidates[0].Exact || ready.State.Candidates[0].Code != "abcdef" ||
		ready.State.Candidates[0].Text != "正视这个问题" {
		t.Fatalf("matching exact sentence was not exclusively promoted: %#v, err=%v", ready.State, err)
	}
	committed, err := engine.Select(ready.State.Candidates[0].ID)
	if err != nil || committed.Commit != "正视这个问题" || committed.State.RawInput != "" {
		t.Fatalf("promoted exact sentence did not commit: %#v, err=%v", committed, err)
	}
}

func TestLearnedSegmentExpansionPreservesExplicitSuffixCorrection(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "正是这", Code: "abc", Weight: 10_000},
		{Text: "正是", Code: "ab", Weight: 900},
		{Text: "正视", Code: "ab", Weight: 800},
		{Text: "这", Code: "c", Weight: 700},
		{Text: "个", Code: "d", Weight: 700},
		{Text: "这个", Code: "cd", Weight: 8_000},
		{Text: "问题", Code: "ef", Weight: 700},
		{Text: "问提", Code: "ef", Weight: 600},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.observe("abcdef", "正是这个问题")
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyBundleCode(t, engine, "abcdef")
	suffix := state.Sentence.Segments[2]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: suffix.Start, SegmentEnd: suffix.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement := findBundleCandidate(focused.State.Candidates, "问提")
	if replacement == nil {
		t.Fatalf("suffix replacement missing: %#v", focused.State.Candidates)
	}
	corrected, err := engine.Select(replacement.ID)
	if err != nil || corrected.State.Sentence == nil {
		t.Fatalf("suffix correction failed: result=%#v err=%v", corrected, err)
	}

	first := corrected.State.Sentence.Segments[0]
	focused, err = engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: corrected.State.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.ExpandSegment, CandidateID: focused.State.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	replacement = findBundleCandidate(expanded.State.Candidates, "正视")
	if replacement == nil {
		t.Fatalf("prefix replacement missing: %#v", expanded.State.Candidates)
	}
	recomposed, err := engine.Select(replacement.ID)
	if err != nil || recomposed.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"正视", "这个", "问提"}) {
		t.Fatalf("explicit suffix correction was lost: %#v, err=%v", recomposed.State.Sentence, err)
	}
}

func TestExplicitSegmentExpansionRecomposesAcrossFormerWordBoundaries(t *testing.T) {
	t.Run("research life", func(t *testing.T) {
		index, err := NewIndex([]Entry{
			{Text: "研究生", Code: "abc", Weight: 1000},
			{Text: "研究", Code: "ab", Weight: 900},
			{Text: "生", Code: "c", Weight: 800},
			{Text: "名", Code: "d", Weight: 1000},
			{Text: "命", Code: "d", Weight: 900},
			{Text: "生命", Code: "cd", Weight: 700},
			{Text: "问题", Code: "ef", Weight: 600},
		})
		if err != nil {
			t.Fatal(err)
		}
		model, err := NewUserModel(index.identity())
		if err != nil {
			t.Fatal(err)
		}
		engine, err := NewEngineWithUserModel(index, 9, model)
		if err != nil {
			t.Fatal(err)
		}
		state := applyBundleCode(t, engine, "abcdef")
		if state.Sentence == nil || !reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"研究生", "名", "问题"}) {
			t.Fatalf("initial research sentence = %#v", state.Sentence)
		}
		first := state.Sentence.Segments[0]
		expanded, err := engine.Apply(engineapi.Event{
			Operation: engineapi.ExpandSegment, CandidateID: state.Sentence.ID,
			SegmentStart: first.Start, SegmentEnd: first.End,
		})
		if err != nil || expanded.State.ActiveSegment == nil ||
			!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"研究", "生", "名", "问题"}) {
			t.Fatalf("expanded research sentence = %#v, err=%v", expanded.State, err)
		}
		confirmed := findBundleCandidate(expanded.State.Candidates, "研究")
		if confirmed == nil {
			t.Fatalf("expanded first child is not selectable: %#v", expanded.State.Candidates)
		}
		recomposed, err := engine.Select(confirmed.ID)
		if err != nil || recomposed.State.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"研究", "生命", "问题"}) {
			t.Fatalf("recomposed research sentence = %#v, err=%v", recomposed.State.Sentence, err)
		}
		if _, err = engine.SelectIdempotent(recomposed.State.Sentence.ID, "commit-research-life"); err != nil {
			t.Fatal(err)
		}
		reentered := applyBundleCode(t, engine, "abcdef")
		if reentered.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"研究", "生命", "问题"}) {
			t.Fatalf("learned research segmentation = %#v", reentered.Sentence)
		}
	})

	t.Run("static lexicon words", func(t *testing.T) {
		index, err := NewIndex([]Entry{
			{Text: "这事", Code: "ab", Weight: 1000},
			{Text: "这是", Code: "ab", Weight: 900},
			{Text: "这", Code: "a", Weight: 800},
			{Text: "事", Code: "b", Weight: 800},
			{Text: "是", Code: "b", Weight: 700},
			{Text: "是一套", Code: "bcd", Weight: 600},
			{Text: "一", Code: "c", Weight: 800},
			{Text: "一套", Code: "cd", Weight: 700},
			{Text: "套", Code: "d", Weight: 800},
			{Text: "套子", Code: "de", Weight: 500},
			{Text: "子", Code: "e", Weight: 800},
			{Text: "系统", Code: "fg", Weight: 500},
			{Text: "子系统", Code: "efg", Weight: 400},
		})
		if err != nil {
			t.Fatal(err)
		}
		model, err := NewUserModel(index.identity())
		if err != nil {
			t.Fatal(err)
		}
		engine, err := NewEngineWithUserModel(index, 9, model)
		if err != nil {
			t.Fatal(err)
		}
		state := applyBundleCode(t, engine, "abcdefg")
		if state.Sentence == nil || !reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"这事", "一套", "子系统"}) {
			t.Fatalf("initial static-lexicon sentence = %#v", state.Sentence)
		}
		first := state.Sentence.Segments[0]
		expanded, err := engine.Apply(engineapi.Event{
			Operation: engineapi.ExpandSegment, CandidateID: state.Sentence.ID,
			SegmentStart: first.Start, SegmentEnd: first.End,
		})
		if err != nil {
			t.Fatal(err)
		}
		confirmed := findBundleCandidate(expanded.State.Candidates, "这")
		if confirmed == nil {
			t.Fatalf("expanded first child is not selectable: %#v", expanded.State.Candidates)
		}
		recomposed, err := engine.Select(confirmed.ID)
		if err != nil || recomposed.State.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"这", "是一套", "子系统"}) {
			t.Fatalf("first static-lexicon recomposition = %#v, err=%v", recomposed.State.Sentence, err)
		}
		compound := recomposed.State.Sentence.Segments[1]
		expanded, err = engine.Apply(engineapi.Event{
			Operation: engineapi.ExpandSegment, CandidateID: recomposed.State.Sentence.ID,
			SegmentStart: compound.Start, SegmentEnd: compound.End,
		})
		if err != nil {
			t.Fatal(err)
		}
		confirmed = findBundleCandidate(expanded.State.Candidates, "是")
		if confirmed == nil {
			t.Fatalf("expanded second child is not selectable: %#v", expanded.State.Candidates)
		}
		recomposed, err = engine.Select(confirmed.ID)
		if err != nil || recomposed.State.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"这是", "一套", "子系统"}) {
			t.Fatalf("second static-lexicon recomposition = %#v, err=%v", recomposed.State.Sentence, err)
		}
		if _, err = engine.SelectIdempotent(recomposed.State.Sentence.ID, "commit-static-lexicon-words"); err != nil {
			t.Fatal(err)
		}
		reentered := applyBundleCode(t, engine, "abcdefg")
		if reentered.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"这是", "一套", "子系统"}) {
			t.Fatalf("learned static-lexicon segmentation = %#v", reentered.Sentence)
		}
	})
}

func segmentTexts(segments []engineapi.Segment) []string {
	texts := make([]string, len(segments))
	for index := range segments {
		texts[index] = segments[index].Text
	}
	return texts
}
