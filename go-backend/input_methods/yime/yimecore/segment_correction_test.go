package yimecore

import (
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

func TestOnlyFinalSentenceSegmentPublishesPrefixCompletions(t *testing.T) {
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
	for segmentIndex, forbidden := range []string{"甲长", "丙长"} {
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
	final := state.Sentence.Segments[2]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: final.Start, SegmentEnd: final.End,
	})
	if err != nil || findBundleCandidate(focused.State.Candidates, "末段补全") == nil {
		t.Fatalf("final segment lost prefix completion: state=%#v err=%v", focused.State, err)
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
				Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
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

	expanded, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: 0, SegmentEnd: len(state.RawInput),
	})
	if err != nil || expanded.State.Sentence == nil ||
		!reflect.DeepEqual(segmentTexts(expanded.State.Sentence.Segments), []string{"文档", "保存"}) ||
		expanded.State.ActiveSegment == nil || expanded.State.ActiveSegment.Text != "文档" {
		t.Fatalf("exact whole-word expansion failed: result=%#v err=%v", expanded, err)
	}
}

func segmentTexts(segments []engineapi.Segment) []string {
	texts := make([]string, len(segments))
	for index := range segments {
		texts[index] = segments[index].Text
	}
	return texts
}
