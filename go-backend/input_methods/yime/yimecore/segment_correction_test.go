package yimecore

import (
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
	sentence := findBundleCandidate(state.Candidates, "甲丙")
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
	corrected := findBundleCandidate(replaced.State.Candidates, "乙丙")
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
	corrected = findBundleCandidate(replaced.State.Candidates, "乙丁")
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
