package yimecore

import (
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func documentSentenceEngine(t *testing.T) *Engine {
	t.Helper()
	index, err := NewIndex([]Entry{
		{Text: "文档", Code: "=oca]fd/", Weight: 10_000},
		{Text: "文当", Code: "=oca]fd/", Weight: 8_000},
		{Text: "文档吧", Code: "=oca]fd/b", Weight: 9_000},
		{Text: "文", Code: "=oca", Weight: 7_000},
		{Text: "闻", Code: "=oca", Weight: 6_000},
		{Text: "档", Code: "]fd/", Weight: 7_000},
		{Text: "党", Code: "]fd/", Weight: 6_000},
		{Text: "保", Code: "bso", Weight: 7_000},
		{Text: "保存", Code: "bso5", Weight: 9_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	return engine
}

func TestDocumentExactSameCodeCandidatesExcludeLongerCompletions(t *testing.T) {
	engine := documentSentenceEngine(t)
	state := applyCode(t, engine, "=oca]fd/").State
	if len(state.Candidates) != 2 || state.Candidates[0].Text != "文档" || state.Candidates[1].Text != "文当" {
		t.Fatalf("exact same-code ordering = %#v", state.Candidates)
	}
	for _, candidate := range state.Candidates {
		if !candidate.Exact || candidate.Code != state.RawInput {
			t.Fatalf("exact candidates lost priority: %#v", state.Candidates)
		}
	}
	if state.Sentence == nil || state.Sentence.ID != state.Candidates[0].ID || state.Sentence.Text != "文档" {
		t.Fatalf("top exact word did not enter preedit: %#v", state)
	}
}

func TestDocumentPrefixPublishesCandidatesAndInvalidBranchStaysEmpty(t *testing.T) {
	engine := documentSentenceEngine(t)
	prefix := applyCode(t, engine, "=oca]f").State
	if len(prefix.Candidates) != 3 || prefix.Candidates[0].Text != "文档" || prefix.Candidates[0].Exact ||
		prefix.Sentence == nil || prefix.Sentence.Text != "文档" || prefix.Sentence.Exact {
		t.Fatalf("prefix prediction contract = %#v", prefix)
	}
	engine.Reset()
	invalid := applyCode(t, engine, "=oca]fd/x").State
	if len(invalid.Candidates) != 0 || invalid.Sentence != nil {
		t.Fatalf("invalid branch did not become visibly empty: %#v", invalid)
	}
}

func TestIncompleteSentenceSegmentPublishesVisibleCandidates(t *testing.T) {
	engine := documentSentenceEngine(t)
	state := applyCode(t, engine, "=oca]fd/bs").State
	if state.Sentence == nil || len(state.Sentence.Segments) != 2 {
		t.Fatalf("temporary sentence missing: %#v", state)
	}
	segment := state.Sentence.Segments[1]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: segment.Start, SegmentEnd: segment.End,
	})
	if err != nil || focused.State.ActiveSegment == nil || len(focused.State.Candidates) != 2 ||
		findBundleCandidate(focused.State.Candidates, "保") == nil ||
		findBundleCandidate(focused.State.Candidates, "保存") == nil {
		t.Fatalf("incomplete final-segment candidates = %#v err=%v", focused.State, err)
	}
	completion := findBundleCandidate(focused.State.Candidates, "保存")
	replaced, err := engine.Select(completion.ID)
	if err != nil || replaced.Commit != "" || replaced.State.RawInput != "=oca]fd/bs" ||
		replaced.State.Sentence == nil || replaced.State.Sentence.Text != "文档保存" {
		t.Fatalf("incomplete final-segment completion was not selectable: result=%#v err=%v", replaced, err)
	}
}

func TestDocumentWholePhraseThenWordFirstFallback(t *testing.T) {
	engine := documentSentenceEngine(t)
	exactPhrase := applyCode(t, engine, "=oca]fd/b").State
	if len(exactPhrase.Candidates) != 1 || exactPhrase.Candidates[0].Text != "文档吧" ||
		exactPhrase.Sentence == nil || exactPhrase.Sentence.ID != exactPhrase.Candidates[0].ID {
		t.Fatalf("whole phrase did not dominate: %#v", exactPhrase)
	}

	engine.Reset()
	temporary := applyCode(t, engine, "=oca]fd/bso").State
	if len(temporary.Candidates) != 0 || temporary.Sentence == nil || temporary.Sentence.Text != "文档保" ||
		len(temporary.Sentence.Segments) != 2 || temporary.Sentence.Segments[0].Text != "文档" {
		t.Fatalf("word-first temporary sentence = %#v", temporary)
	}
	completed, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "5"})
	if err != nil || completed.State.Sentence == nil || completed.State.Sentence.Text != "文档保存" ||
		len(completed.State.Candidates) != 0 || len(completed.State.Sentence.Segments) != 2 {
		t.Fatalf("two-word sentence convergence = %#v err=%v", completed.State, err)
	}
}

func TestSelectedFirstSegmentSurvivesContinuedInput(t *testing.T) {
	engine := documentSentenceEngine(t)
	state := applyCode(t, engine, "=oca]fd/bso").State
	if state.Sentence == nil {
		t.Fatal("temporary sentence missing")
	}
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	replacement := findBundleCandidate(focused.State.Candidates, "文当")
	if err != nil || len(focused.State.Candidates) != 2 || replacement == nil ||
		findBundleCandidate(focused.State.Candidates, "文档吧") != nil {
		t.Fatalf("first segment alternatives = %#v err=%v", focused.State, err)
	}
	selected, err := engine.Select(replacement.ID)
	if err != nil || selected.Commit != "" || selected.State.Sentence == nil || selected.State.Sentence.Text != "文当保" {
		t.Fatalf("segment selection committed or disappeared: %#v err=%v", selected, err)
	}
	continued, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "5"})
	if err != nil || continued.State.Sentence == nil || continued.State.Sentence.Text != "文当保存" {
		t.Fatalf("selected segment did not survive continued input: %#v err=%v", continued.State, err)
	}
}
