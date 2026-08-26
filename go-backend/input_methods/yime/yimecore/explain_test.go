package yimecore

import (
	"reflect"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func TestExplainShowsLexiconEdgesGeneratedPathsAndVisibleRanking(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "本", Code: "a", Weight: 100},
		{Text: "地", Code: "b", Weight: 100},
		{Text: "人", Code: "c", Weight: 100},
		{Text: "本地", Code: "ab", Weight: 500},
		{Text: "本地人", Code: "abc", Weight: 800},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "abc")
	if len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "本地人" {
		t.Fatalf("visible candidates=%#v", result.State.Candidates)
	}

	trace := engine.Explain()
	if trace.PreeditSentence == nil || trace.PreeditSentence.Text != result.State.Sentence.Text {
		t.Fatalf("explain preedit sentence = %#v, state = %#v", trace.PreeditSentence, result.State.Sentence)
	}
	if trace.SchemaVersion != DecodeTraceSchemaVersion || trace.Input != "abc" ||
		trace.IndexSourceID != "synthetic-memory-index" {
		t.Fatalf("trace identity=%#v", trace)
	}
	if !hasTraceEdge(trace.Edges, 0, 2, "本地") || !hasTraceEdge(trace.Edges, 0, 3, "本地人") {
		t.Fatalf("trace edges=%#v", trace.Edges)
	}
	if !hasTracePath(trace.RetainedPaths, []string{"本地", "人"}) ||
		!hasTracePath(trace.RetainedPaths, []string{"本", "地", "人"}) {
		t.Fatalf("trace paths=%#v", trace.RetainedPaths)
	}
	if len(trace.VisibleCandidates) == 0 || trace.VisibleCandidates[0].Rank != 1 ||
		trace.VisibleCandidates[0].Candidate.Text != "本地人" {
		t.Fatalf("visible trace=%#v", trace.VisibleCandidates)
	}
}

func TestExplainTracksDynamicResegmentationAfterInputExtension(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "本", Code: "a", Weight: 100},
		{Text: "地", Code: "b", Weight: 100},
		{Text: "人", Code: "c", Weight: 100},
		{Text: "本地", Code: "ab", Weight: 500},
		{Text: "本地人", Code: "abc", Weight: 800},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	first := applyCode(t, engine, "ab")
	if len(first.State.Candidates) == 0 || first.State.Candidates[0].Text != "本地" {
		t.Fatalf("first step=%#v", first.State.Candidates)
	}
	if _, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "c"}); err != nil {
		t.Fatal(err)
	}
	trace := engine.Explain()
	if trace.Input != "abc" || len(trace.VisibleCandidates) == 0 ||
		trace.VisibleCandidates[0].Candidate.Text != "本地人" {
		t.Fatalf("extended trace=%#v", trace)
	}
	if !hasTracePath(trace.RetainedPaths, []string{"本地", "人"}) {
		t.Fatalf("extended input did not retain the resegmented word path: %#v", trace.RetainedPaths)
	}
}

func hasTraceEdge(edges []DecodeEdge, start, end int, text string) bool {
	for _, edge := range edges {
		if edge.Start == start && edge.End == end && edge.Text == text {
			return true
		}
	}
	return false
}

func hasTracePath(paths []DecodePath, texts []string) bool {
	for _, path := range paths {
		got := make([]string, len(path.Segments))
		for i := range path.Segments {
			got[i] = path.Segments[i].Text
		}
		if reflect.DeepEqual(got, texts) {
			return true
		}
	}
	return false
}
