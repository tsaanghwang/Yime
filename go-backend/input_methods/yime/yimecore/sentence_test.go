package yimecore

import (
	"reflect"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func sentenceEngine(t *testing.T, extra ...Entry) *Engine {
	t.Helper()
	entries := []Entry{
		{Text: "幅", Code: "bj", Weight: 1000},
		{Text: "逼", Code: "bj", Weight: 100},
		{Text: "啊", Code: "f", Weight: 900},
		{Text: "阿", Code: "f", Weight: 90},
	}
	entries = append(entries, extra...)
	index, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	return engine
}

func TestSentenceComposerBuildsPositionPreservingPath(t *testing.T) {
	engine := sentenceEngine(t)
	result := applyCode(t, engine, "bjbj")
	if len(result.State.Candidates) != 0 || result.State.Sentence == nil || result.State.Sentence.Text != "幅幅" {
		t.Fatalf("generated sentence state = %+v", result.State)
	}
	candidate := *result.State.Sentence
	if !candidate.Exact || len(candidate.Segments) != 2 {
		t.Fatalf("generated candidate lacks path: %+v", candidate)
	}
	wantSpans := [][2]int{{0, 2}, {2, 4}}
	gotSpans := make([][2]int, 0, len(candidate.Segments))
	for _, segment := range candidate.Segments {
		gotSpans = append(gotSpans, [2]int{segment.Start, segment.End})
		if segment.SourceID != "synthetic-memory-index" {
			t.Fatalf("segment source = %q", segment.SourceID)
		}
	}
	if !reflect.DeepEqual(gotSpans, wantSpans) {
		t.Fatalf("segment spans = %v, want %v", gotSpans, wantSpans)
	}
	selected, err := engine.Select(candidate.ID)
	if err != nil || selected.Commit != "幅幅" || selected.State.RawInput != "" {
		t.Fatalf("sentence selection = %+v, %v", selected, err)
	}
}

func TestSentenceComposerRetainsApostropheAsExplicitBoundary(t *testing.T) {
	engine := sentenceEngine(t)
	result := applyCode(t, engine, "bj'f")
	if result.State.Sentence == nil || result.State.Sentence.Text != "幅啊" {
		t.Fatalf("boundary sentence = %+v", result.State)
	}
	segments := result.State.Sentence.Segments
	if len(segments) != 2 || segments[0].Start != 0 || segments[0].End != 2 || segments[1].Start != 3 || segments[1].End != 4 {
		t.Fatalf("boundary spans = %+v", segments)
	}
}

func TestDirectExactCandidatePrecedesAndDeduplicatesGeneratedSentence(t *testing.T) {
	engine := sentenceEngine(t, Entry{Text: "幅幅", Code: "bjbj", Weight: 1})
	result := applyCode(t, engine, "bjbj")
	count := 0
	for _, candidate := range result.State.Candidates {
		if candidate.Text == "幅幅" {
			count++
		}
	}
	if count != 1 || result.State.Candidates[0].Text != "幅幅" || len(result.State.Candidates[0].Segments) != 0 ||
		result.State.Sentence == nil || result.State.Sentence.ID != result.State.Candidates[0].ID {
		t.Fatalf("direct/generated merge = %+v", result.State.Candidates)
	}
}

func TestSentenceSnapshotsDeepCopySegmentPaths(t *testing.T) {
	engine := sentenceEngine(t)
	first := applyCode(t, engine, "bjbj")
	first.State.Sentence.Segments[0].Text = "已修改"
	second := engine.Reset()
	second = applyCode(t, engine, "bjbj")
	if second.State.Sentence == nil || second.State.Sentence.Segments[0].Text != "幅" {
		t.Fatalf("snapshot mutated engine path: %+v", second.State.Sentence)
	}
}

func TestIncrementalLatticeBackspaceAndDivergentAppendMatchFreshSession(t *testing.T) {
	incremental := sentenceEngine(t)
	applyCode(t, incremental, "bjbj")
	for i := 0; i < 2; i++ {
		if _, err := incremental.Apply(engineapi.Event{Operation: engineapi.Backspace}); err != nil {
			t.Fatal(err)
		}
	}
	incrementalResult := applyCode(t, incremental, "f")

	fresh := sentenceEngine(t)
	freshResult := applyCode(t, fresh, "bjf")
	if !reflect.DeepEqual(incrementalResult.State, freshResult.State) {
		t.Fatalf("incremental lattice differs after backspace:\nincremental=%+v\nfresh=%+v", incrementalResult.State, freshResult.State)
	}
}

func TestIncompleteSecondTermInheritsCompletedSearchTreePath(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "前词", Code: "ab", Weight: 1000},
		{Text: "后词", Code: "cdef", Weight: 900},
		{Text: "候选", Code: "cdeg", Weight: 800},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	for _, key := range "cde" {
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
		if findCandidateText(result.State.Candidates, "前词后词") != nil {
			t.Fatalf("incomplete second term %q leaked a future-code candidate: %#v", result.State.RawInput, result.State.Candidates)
		}
		if result.State.Sentence == nil || result.State.Sentence.Text != "前词后词" || result.State.Sentence.Exact {
			t.Fatalf("incomplete second term %q lost its single temporary sentence: %#v", result.State.RawInput, result.State)
		}
		if !hasTracePath(engine.Explain().RetainedPaths, []string{"前词", "后词"}) {
			t.Fatalf("incomplete second term %q lost its internal inherited path", result.State.RawInput)
		}
	}
	result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "f"})
	if err != nil {
		t.Fatal(err)
	}
	completed := result.State.Sentence
	if completed == nil || !completed.Exact || completed.Code != "abcdef" || len(completed.Segments) != 2 {
		t.Fatalf("completed inherited sentence = %#v", result.State)
	}

	engine.Reset()
	invalid := applyCode(t, engine, "abz")
	if len(invalid.State.Candidates) != 0 || invalid.State.Sentence != nil {
		t.Fatalf("invalid second-term branch inherited stale state: %#v", invalid.State)
	}
}

func TestVariableCandidateSortingSentenceStaysCommittable(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "候选", Code: "hreo1.sz", Weight: 12989},
		{Text: "排序", Code: "psdj1m,.", Weight: 4081},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "hreo1.sz")
	for _, key := range "psdj1m,." {
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
		if result.State.Sentence == nil || result.State.Sentence.Text != "候选排序" {
			t.Fatalf("input %q lost its temporary sentence: %#v", result.State.RawInput, result.State)
		}
	}
	candidate := result.State.Sentence
	if candidate == nil || !candidate.Exact || candidate.Code != "hreo1.szpsdj1m,." {
		t.Fatalf("completed candidate-sorting sentence = %#v", result.State.Candidates)
	}
	selected, err := engine.Select(candidate.ID)
	if err != nil || selected.Commit != "候选排序" || selected.State.RawInput != "" {
		t.Fatalf("candidate-sorting selection = %+v, %v", selected, err)
	}
}

func TestGeneratedSentenceKeepsFewerSystemLexiconSegmentsFirst(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲乙", Code: "ab", Weight: 1},
		{Text: "丙", Code: "c", Weight: 1},
		{Text: "高", Code: "a", Weight: 1_000_000},
		{Text: "分", Code: "b", Weight: 1_000_000},
		{Text: "词", Code: "c", Weight: 1_000_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "abc")
	if len(result.State.Candidates) != 0 || result.State.Sentence == nil || result.State.Sentence.Text != "甲乙词" ||
		len(result.State.Sentence.Segments) != 2 {
		t.Fatalf("generated sentence ranking ignored the shorter system path: %#v", result.State)
	}
	if !hasTracePath(engine.Explain().RetainedPaths, []string{"高", "分", "词"}) {
		t.Fatal("non-visible alternative path was not retained by the decoder")
	}
}

func findCandidateText(candidates []engineapi.Candidate, text string) *engineapi.Candidate {
	for index := range candidates {
		if candidates[index].Text == text {
			return &candidates[index]
		}
	}
	return nil
}
