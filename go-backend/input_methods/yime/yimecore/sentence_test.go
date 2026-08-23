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
	if len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "幅幅" {
		t.Fatalf("generated candidates = %+v", result.State.Candidates)
	}
	candidate := result.State.Candidates[0]
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
	if len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "幅啊" {
		t.Fatalf("boundary candidates = %+v", result.State.Candidates)
	}
	segments := result.State.Candidates[0].Segments
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
	if count != 1 || result.State.Candidates[0].Text != "幅幅" || len(result.State.Candidates[0].Segments) != 0 {
		t.Fatalf("direct/generated merge = %+v", result.State.Candidates)
	}
}

func TestSentenceSnapshotsDeepCopySegmentPaths(t *testing.T) {
	engine := sentenceEngine(t)
	first := applyCode(t, engine, "bjbj")
	first.State.Candidates[0].Segments[0].Text = "已修改"
	second := engine.Reset()
	second = applyCode(t, engine, "bjbj")
	if second.State.Candidates[0].Segments[0].Text != "幅" {
		t.Fatalf("snapshot mutated engine path: %+v", second.State.Candidates[0])
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
	if !reflect.DeepEqual(incrementalResult.State.Candidates, freshResult.State.Candidates) {
		t.Fatalf("incremental lattice differs after backspace:\nincremental=%+v\nfresh=%+v", incrementalResult.State.Candidates, freshResult.State.Candidates)
	}
}
