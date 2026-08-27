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
	if err != nil || replaced.Commit != "" || replaced.State.ActiveSegment != nil {
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
	state := applyBundleCode(t, engine, "abcd")
	if state.Sentence == nil || state.Sentence.Text != "之识" {
		t.Fatalf("initial static sentence = %#v", state.Sentence)
	}
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
			if selectErr != nil || replaced.Commit != "" || replaced.State.ActiveSegment != nil ||
				replaced.State.RawInput != "abcdef" || replaced.State.Sentence == nil ||
				len(replaced.State.Sentence.Segments) != len(choices) {
				t.Fatalf("cycle %d segment %d replacement failed: result=%#v err=%v",
					cycle+1, segmentIndex, replaced, selectErr)
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

	t.Run("cover system", func(t *testing.T) {
		index, err := NewIndex([]Entry{
			{Text: "这事", Code: "ab", Weight: 1000},
			{Text: "这是", Code: "ab", Weight: 900},
			{Text: "这", Code: "a", Weight: 800},
			{Text: "事", Code: "b", Weight: 800},
			{Text: "是", Code: "b", Weight: 700},
			{Text: "是一套", Code: "bcd", Weight: 600},
			{Text: "一", Code: "c", Weight: 800},
			{Text: "套", Code: "d", Weight: 800},
			{Text: "套子", Code: "de", Weight: 500},
			{Text: "子", Code: "e", Weight: 800},
			{Text: "系统", Code: "fg", Weight: 500},
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
		if state.Sentence == nil || !reflect.DeepEqual(segmentTexts(state.Sentence.Segments), []string{"这事", "一", "套子", "系统"}) {
			t.Fatalf("initial cover-system sentence = %#v", state.Sentence)
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
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"这", "是一套", "子", "系统"}) {
			t.Fatalf("first cover-system recomposition = %#v, err=%v", recomposed.State.Sentence, err)
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
			!reflect.DeepEqual(segmentTexts(recomposed.State.Sentence.Segments), []string{"这", "是", "一", "套子", "系统"}) {
			t.Fatalf("second cover-system recomposition = %#v, err=%v", recomposed.State.Sentence, err)
		}
		if _, err = engine.SelectIdempotent(recomposed.State.Sentence.ID, "commit-cover-system"); err != nil {
			t.Fatal(err)
		}
		reentered := applyBundleCode(t, engine, "abcdefg")
		if reentered.Sentence == nil ||
			!reflect.DeepEqual(segmentTexts(reentered.Sentence.Segments), []string{"这", "是", "一", "套子", "系统"}) {
			t.Fatalf("learned cover-system segmentation = %#v", reentered.Sentence)
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
