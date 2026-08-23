package yimecore

import (
	"errors"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func testEngine(t *testing.T) *Engine {
	t.Helper()
	index, err := NewIndex([]Entry{
		{Text: "一", Code: "a1", Weight: 100},
		{Text: "一个", Code: "a12", Weight: 80},
		{Text: "一致", Code: "a1 23", Weight: 70},
		{Text: "低权重精确", Code: "a1", Weight: 1},
		{Text: "重复", Code: "b2", Weight: 1},
		{Text: "重复", Code: "b2", Weight: 9},
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

func applyCode(t *testing.T, engine *Engine, code string) engineapi.Result {
	t.Helper()
	var result engineapi.Result
	for _, r := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(r)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result
}

func TestDigitsRemainCompositionCode(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "a1")
	if result.State.RawInput != "a1" {
		t.Fatalf("raw input = %q, want a1", result.State.RawInput)
	}
	if len(result.State.Candidates) == 0 || !result.State.Candidates[0].Exact {
		t.Fatalf("expected exact candidate after digit composition: %+v", result.State.Candidates)
	}
}

func TestExactCandidatesRankBeforePrefixCompletions(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "a1")
	if len(result.State.Candidates) != 4 {
		t.Fatalf("candidate count = %d, want 4", len(result.State.Candidates))
	}
	for i := 0; i < 2; i++ {
		if !result.State.Candidates[i].Exact {
			t.Fatalf("candidate %d should be exact: %+v", i, result.State.Candidates)
		}
	}
	if result.State.Candidates[0].Text != "一" {
		t.Fatalf("top candidate = %q, want 一", result.State.Candidates[0].Text)
	}
}

func TestBackspaceClearAndSelection(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "a12")
	if len(result.State.Candidates) == 0 {
		t.Fatal("expected candidate")
	}
	selected := result.State.Candidates[0]
	result, err := engine.Select(selected.ID)
	if err != nil {
		t.Fatal(err)
	}
	if result.Commit != "一个" || result.State.RawInput != "" || len(result.State.Candidates) != 0 {
		t.Fatalf("unexpected selection result: %+v", result)
	}

	applyCode(t, engine, "a12")
	result, err = engine.Apply(engineapi.Event{Operation: engineapi.Backspace})
	if err != nil {
		t.Fatal(err)
	}
	if result.State.RawInput != "a1" {
		t.Fatalf("after backspace raw input = %q, want a1", result.State.RawInput)
	}
	result, err = engine.Apply(engineapi.Event{Operation: engineapi.Clear})
	if err != nil {
		t.Fatal(err)
	}
	if result.State.RawInput != "" || len(result.State.Candidates) != 0 {
		t.Fatalf("clear did not reset state: %+v", result.State)
	}
}

func TestDuplicateEntryKeepsHighestWeight(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "b2")
	if len(result.State.Candidates) != 1 || result.State.Candidates[0].Weight != 9 {
		t.Fatalf("duplicate normalization failed: %+v", result.State.Candidates)
	}
}

func TestInvalidEventsDoNotMutateSession(t *testing.T) {
	engine := testEngine(t)
	applyCode(t, engine, "a")
	_, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "两"})
	if !errors.Is(err, engineapi.ErrInvalidEvent) {
		t.Fatalf("invalid code error = %v", err)
	}
	if state := engine.Reset().State; state.RawInput != "" {
		t.Fatalf("reset state = %+v", state)
	}
	_, err = engine.Select("missing")
	if !errors.Is(err, engineapi.ErrUnknownCandidate) {
		t.Fatalf("unknown candidate error = %v", err)
	}
}

func BenchmarkSessionReplay(b *testing.B) {
	entries := make([]Entry, 0, 20000)
	for i := 0; i < 20000; i++ {
		entries = append(entries, Entry{
			Text:   "候选",
			Code:   benchmarkCode(i),
			Weight: int64(i % 1000),
		})
	}
	entries = append(entries, Entry{Text: "目标", Code: "a1234", Weight: 10000})
	index, err := NewIndex(entries)
	if err != nil {
		b.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		b.Fatal(err)
	}
	events := []engineapi.Event{
		{Operation: engineapi.AppendCode, Code: "a"},
		{Operation: engineapi.AppendCode, Code: "1"},
		{Operation: engineapi.AppendCode, Code: "2"},
		{Operation: engineapi.AppendCode, Code: "3"},
		{Operation: engineapi.AppendCode, Code: "4"},
		{Operation: engineapi.Clear},
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for _, event := range events {
			if _, err := engine.Apply(event); err != nil {
				b.Fatal(err)
			}
		}
	}
}

func benchmarkCode(value int) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	buf := []byte{'a', '0', '0', '0', '0'}
	for i := len(buf) - 1; i >= 1; i-- {
		buf[i] = alphabet[value%len(alphabet)]
		value /= len(alphabet)
	}
	return string(buf)
}
