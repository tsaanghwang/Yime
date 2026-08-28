package yimecore

import (
	"fmt"
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

func TestExplainSeparatesGeneratedSentenceScoreSources(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "甲", Code: "a", Weight: 100},
		{Text: "乙", Code: "b", Weight: 200},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	if err := model.observeBatchIdempotent([]UserObservation{
		{Code: "a", Text: "甲"},
		{Code: "b", Text: "乙", PreviousText: "甲"},
	}, "explain-score-sources"); err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	trace := engine.Explain()
	if result.State.Sentence == nil || trace.PreeditSentence == nil || len(trace.RetainedPaths) == 0 {
		t.Fatalf("generated sentence explanation is missing: state=%#v trace=%#v", result.State, trace)
	}
	wantStatic := int64(100 + 200 - 2*generatedSegmentPenalty)
	for label, score := range map[string]engineapi.Score{
		"state":    result.State.Sentence.Score,
		"preedit":  trace.PreeditSentence.Score,
		"retained": trace.RetainedPaths[0].Score,
	} {
		if score.Static != wantStatic || score.User != 2*userBoostPerSelection ||
			score.Context != contextBoostPerSelection ||
			score.Total != wantStatic+2*userBoostPerSelection+contextBoostPerSelection {
			t.Fatalf("%s score attribution = %#v", label, score)
		}
	}
}

func TestExplainReportsSegmentCandidateLimitPressure(t *testing.T) {
	entries := make([]Entry, segmentCandidateLimit+1)
	for i := range entries {
		entries[i] = Entry{Text: fmt.Sprintf("候选%d", i), Code: "a", Weight: int64(1000 - i)}
	}
	index, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	applyCode(t, engine, "a")
	trace := engine.Explain()
	if len(trace.Edges) != segmentCandidateLimit || len(trace.SegmentLimitPressure) != 1 {
		t.Fatalf("limit pressure trace=%#v", trace)
	}
	pressure := trace.SegmentLimitPressure[0]
	if pressure.Start != 0 || pressure.End != 1 || pressure.Code != "a" ||
		pressure.Limit != segmentCandidateLimit || pressure.CandidateCountAtLeast != segmentCandidateLimit+1 {
		t.Fatalf("limit pressure=%#v", pressure)
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
