package yimecore

import (
	"errors"
	"fmt"
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

func TestFirstSyllableExactCandidatesExcludeMultiCharacterItems(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "a1")
	if len(result.State.Candidates) != 1 {
		t.Fatalf("candidate count = %d, want only the exact single character: %#v", len(result.State.Candidates), result.State.Candidates)
	}
	for i := range result.State.Candidates {
		if !result.State.Candidates[i].Exact || result.State.Candidates[i].Code != "a1" {
			t.Fatalf("candidate %d is not an exact same-code item: %+v", i, result.State.Candidates)
		}
	}
	if result.State.Candidates[0].Text != "一" {
		t.Fatalf("top candidate = %q, want 一", result.State.Candidates[0].Text)
	}
	if result.State.Sentence == nil || result.State.Sentence.Text != "一" {
		t.Fatalf("top exact match did not enter the independent sentence: %#v", result.State)
	}
}

func TestFirstPrefixNodePublishesVisibleCandidates(t *testing.T) {
	engine := testEngine(t)
	result := applyCode(t, engine, "a")
	if len(result.State.Candidates) != 1 || result.State.Candidates[0].Text != "一" {
		t.Fatalf("first-key prefix candidates missing or misordered: %#v", result.State.Candidates)
	}
	for i := range result.State.Candidates {
		if result.State.Candidates[i].Exact || result.State.Candidates[i].Code == "a" {
			t.Fatalf("first-key candidate %d is not a prefix completion: %+v", i, result.State.Candidates)
		}
	}
	if result.State.Sentence == nil || result.State.Sentence.Exact || result.State.Sentence.Text != "一" ||
		result.State.Sentence.Code != "a1" {
		t.Fatalf("prefix node lost its single temporary sentence prediction: %#v", result.State)
	}
	selected, err := engine.Select(result.State.Candidates[0].ID)
	if err != nil || selected.Commit != "一" || selected.State.RawInput != "" {
		t.Fatalf("first-key prefix candidate was not selectable: result=%#v err=%v", selected, err)
	}
}

func TestFirstSyllableSingleCharactersKeepTheirOwnPages(t *testing.T) {
	entries := make([]Entry, 0, 27)
	for index := 0; index < 20; index++ {
		entries = append(entries, Entry{Text: fmt.Sprintf("高频多字-%02d", index), Code: "ab", Weight: int64(10_000 - index)})
	}
	for index, text := range []string{"甲", "乙", "丙", "丁", "戊", "己", "庚"} {
		entries = append(entries, Entry{Text: text, Code: "ab", Weight: int64(100 - index)})
	}
	index, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 5)
	if err != nil {
		t.Fatal(err)
	}
	first := applyCode(t, engine, "ab").State
	if len(first.Candidates) != 5 || !first.HasNext {
		t.Fatalf("first single-character page = %#v", first)
	}
	for _, candidate := range first.Candidates {
		if !isSingleCharacter(candidate.Text) {
			t.Fatalf("multi-character item leaked onto first page: %#v", candidate)
		}
	}
	second, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
	if err != nil || len(second.State.Candidates) != 2 || second.State.HasNext {
		t.Fatalf("second single-character page = %#v err=%v", second.State, err)
	}
}

func TestLexicalPhraseRanksBeforeHigherScoringGeneratedSentence(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "词典短语", Code: "ab", Weight: 1},
		{Text: "甲", Code: "a", Weight: 1_000_000},
		{Text: "乙", Code: "b", Weight: 1_000_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	if len(result.State.Candidates) != 1 || result.State.Candidates[0].Text != "词典短语" ||
		len(result.State.Candidates[0].Segments) != 0 {
		t.Fatalf("lexical phrase did not stay first: %#v", result.State.Candidates)
	}
	if result.State.Sentence == nil || result.State.Sentence.Text != "词典短语" || len(result.State.Sentence.Segments) != 0 {
		t.Fatalf("lexical phrase did not own the sentence row: %#v", result.State)
	}
}

func TestLexicalPrefixDoesNotFollowExactCandidates(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "低频精确词", Code: "ab", Weight: 1},
		{Text: "高频整词", Code: "abc", Weight: 1000},
		{Text: "甲", Code: "a", Weight: 1_000_000},
		{Text: "乙", Code: "b", Weight: 1_000_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	if len(result.State.Candidates) != 1 || result.State.Candidates[0].Text != "低频精确词" ||
		!result.State.Candidates[0].Exact || len(result.State.Candidates[0].Segments) != 0 {
		t.Fatalf("visible exact candidate mismatch: %#v", result.State.Candidates)
	}
	if result.State.Sentence == nil || result.State.Sentence.Text != "低频精确词" {
		t.Fatalf("exact lexical entry did not outrank generated/predicted paths: %#v", result.State)
	}
}

func TestLexicalExactPagesExcludePrefixDescendants(t *testing.T) {
	entries := make([]Entry, 0, 13)
	for i := 0; i < 12; i++ {
		entries = append(entries, Entry{Text: fmt.Sprintf("同码-%02d", i), Code: "a", Weight: int64(100 - i)})
	}
	entries = append(entries, Entry{Text: "高分预测", Code: "ab", Weight: 1_000_000})
	index, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	first := applyCode(t, engine, "a").State
	if len(first.Candidates) != 9 || !first.HasNext {
		t.Fatalf("first exact page = %#v", first)
	}
	for _, candidate := range first.Candidates {
		if !candidate.Exact {
			t.Fatalf("prediction appeared before the exact pool was exhausted: %#v", first.Candidates)
		}
	}
	second, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
	if err != nil {
		t.Fatal(err)
	}
	if len(second.State.Candidates) != 3 || second.State.HasNext {
		t.Fatalf("second page = %#v", second.State)
	}
	for i := 0; i < 3; i++ {
		if !second.State.Candidates[i].Exact || second.State.Candidates[i].Code != "a" {
			t.Fatalf("second-page exact candidate %d was displaced: %#v", i, second.State.Candidates)
		}
	}
}

func TestHigherScoringLexicalExactKeepsPriorityDuringSentenceComposition(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "高频精确词", Code: "ab", Weight: 1000},
		{Text: "低频预测词", Code: "abc", Weight: 1},
		{Text: "甲", Code: "a", Weight: 1_000_000},
		{Text: "乙", Code: "b", Weight: 1_000_000},
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "ab")
	if len(result.State.Candidates) == 0 || result.State.Candidates[0].Text != "高频精确词" ||
		!result.State.Candidates[0].Exact {
		t.Fatalf("strong lexical exact candidate lost priority: %#v", result.State.Candidates)
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
