package candidatefilter

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userblocklist"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type fakeEngine struct {
	state engineapi.State
	limit int
}

func (e *fakeEngine) Apply(engineapi.Event) (engineapi.Result, error) {
	return engineapi.Result{State: e.state}, nil
}
func (e *fakeEngine) Select(id string) (engineapi.Result, error) {
	return engineapi.Result{State: e.state, Commit: id}, nil
}
func (e *fakeEngine) SelectIdempotent(id, _ string) (engineapi.Result, error) {
	return e.Select(id)
}
func (e *fakeEngine) ForgetCandidate(string) (engineapi.Result, error) {
	return engineapi.Result{State: e.state}, nil
}
func (e *fakeEngine) Reset() engineapi.Result { return engineapi.Result{State: e.state} }
func (e *fakeEngine) IndexVersion() string    { return "test-v1" }
func (e *fakeEngine) SetCandidateLimit(limit int) error {
	e.limit = limit
	return nil
}

func TestIndependentSentenceRemainsSelectableAfterFiltering(t *testing.T) {
	path := filepath.Join(t.TempDir(), userblocklist.SourceFileName)
	inner := &fakeEngine{state: engineapi.State{
		Sentence: &engineapi.Candidate{ID: "sentence", Text: "三项已验证"},
	}}
	wrapped, err := Wrap(inner, path)
	if err != nil {
		t.Fatal(err)
	}
	result, err := wrapped.Apply(engineapi.Event{})
	if err != nil || result.State.Sentence == nil || len(result.State.Candidates) != 0 {
		t.Fatalf("independent sentence snapshot=%#v err=%v", result.State, err)
	}
	selected, err := wrapped.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	}).SelectIdempotent(result.State.Sentence.ID, "sentence-mutation")
	if err != nil || selected.Commit != "sentence" {
		t.Fatalf("independent sentence selection=%#v err=%v", selected, err)
	}
}

func TestFilteredMultiSegmentSentenceCanBeCorrectedAndCommitted(t *testing.T) {
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "三象", Code: "ab", Weight: 100},
		{Text: "三项", Code: "ab", Weight: 90},
		{Text: "已验证", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	inner, err := yimecore.NewEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	wrapped, err := Wrap(inner, filepath.Join(t.TempDir(), userblocklist.SourceFileName))
	if err != nil {
		t.Fatal(err)
	}
	var result engineapi.Result
	for _, code := range "abcd" {
		result, err = wrapped.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(code)})
		if err != nil {
			t.Fatal(err)
		}
	}
	if result.State.Sentence == nil || result.State.Sentence.Text != "三象已验证" ||
		len(result.State.Sentence.Segments) != 2 {
		t.Fatalf("multi-segment sentence=%#v", result.State.Sentence)
	}
	sentence := result.State.Sentence
	for _, segment := range sentence.Segments {
		result, err = wrapped.Apply(engineapi.Event{
			Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
			SegmentStart: segment.Start, SegmentEnd: segment.End,
		})
		if err != nil || result.State.ActiveSegment == nil || len(result.State.Candidates) == 0 {
			t.Fatalf("segment %q focus=%#v err=%v", segment.Text, result.State, err)
		}
	}
	first := sentence.Segments[0]
	result, err = wrapped.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	var replacement *engineapi.Candidate
	for index := range result.State.Candidates {
		if result.State.Candidates[index].Text == "三项" {
			replacement = &result.State.Candidates[index]
			break
		}
	}
	if replacement == nil {
		t.Fatalf("segment replacement missing: %#v", result.State.Candidates)
	}
	selector := wrapped.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	})
	result, err = selector.SelectIdempotent(replacement.ID, "segment-mutation")
	if err != nil || result.Commit != "" || result.State.Sentence == nil ||
		result.State.Sentence.Text != "三项已验证" {
		t.Fatalf("segment correction=%#v err=%v", result, err)
	}
	result, err = selector.SelectIdempotent(result.State.Sentence.ID, "sentence-mutation")
	if err != nil || result.Commit != "三项已验证" || result.State.RawInput != "" {
		t.Fatalf("corrected sentence commit=%#v err=%v", result, err)
	}
}

func TestFilterReloadsBlocklistAndRejectsStaleCandidate(t *testing.T) {
	path := filepath.Join(t.TempDir(), userblocklist.SourceFileName)
	inner := &fakeEngine{state: engineapi.State{Candidates: []engineapi.Candidate{
		{ID: "keep", Text: "保留"}, {ID: "hide", Text: "隐藏"},
	}, Sentence: &engineapi.Candidate{ID: "sentence", Text: "隐藏"}}}
	wrapped, err := Wrap(inner, path)
	if err != nil {
		t.Fatal(err)
	}
	first, err := wrapped.Apply(engineapi.Event{})
	if err != nil || len(first.State.Candidates) != 2 {
		t.Fatalf("initial result=%#v err=%v", first, err)
	}
	if err := userblocklist.WritePhrases(path, []string{"隐藏"}); err != nil {
		t.Fatal(err)
	}
	second, err := wrapped.Apply(engineapi.Event{})
	if err != nil || len(second.State.Candidates) != 1 || second.State.Candidates[0].Text != "保留" || second.State.Sentence != nil {
		t.Fatalf("filtered result=%#v err=%v", second, err)
	}
	selector := wrapped.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	})
	if _, err := selector.SelectIdempotent("hide", "mutation"); !errors.Is(err, engineapi.ErrUnknownCandidate) {
		t.Fatalf("stale blocked selection error=%v", err)
	}
	if _, err := selector.SelectIdempotent("sentence", "sentence-mutation"); !errors.Is(err, engineapi.ErrUnknownCandidate) {
		t.Fatalf("blocked sentence selection error=%v", err)
	}
	if wrapped.(interface{ IndexVersion() string }).IndexVersion() != "test-v1" {
		t.Fatal("filter did not preserve index version")
	}
	if err := wrapped.(interface{ SetCandidateLimit(int) error }).SetCandidateLimit(6); err != nil || inner.limit != 6 {
		t.Fatalf("filter did not forward candidate limit: limit=%d err=%v", inner.limit, err)
	}
}
