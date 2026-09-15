package candidateannotation

import (
	"testing"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

type configurableEngine struct {
	limit int
}

func (e *configurableEngine) Apply(engineapi.Event) (engineapi.Result, error) {
	return engineapi.Result{}, nil
}
func (e *configurableEngine) Select(string) (engineapi.Result, error) { return engineapi.Result{}, nil }
func (e *configurableEngine) Reset() engineapi.Result                 { return engineapi.Result{} }
func (e *configurableEngine) SetCandidateLimit(limit int) error {
	e.limit = limit
	return nil
}

func TestAnnotationEngineForwardsCandidateLimit(t *testing.T) {
	inner := &configurableEngine{}
	wrapped, err := Wrap(inner, &Resolver{})
	if err != nil {
		t.Fatal(err)
	}
	if err := wrapped.(interface{ SetCandidateLimit(int) error }).SetCandidateLimit(7); err != nil {
		t.Fatal(err)
	}
	if inner.limit != 7 {
		t.Fatalf("candidate limit = %d, want 7", inner.limit)
	}
}

func TestResolverProvidesThreeCandidateEncodingForms(t *testing.T) {
	resolver, err := Load("../data", "full")
	if err != nil {
		t.Fatal(err)
	}
	candidate := engineapi.Candidate{Text: "一", Code: "yjkl"}
	resolver.Annotate(&candidate)
	if candidate.Annotations.KeySequence != "yjkl" {
		t.Fatalf("key sequence = %q", candidate.Annotations.KeySequence)
	}
	if candidate.Annotations.StandardPinyin != "yì" {
		t.Fatalf("standard Pinyin = %q, want yì", candidate.Annotations.StandardPinyin)
	}
	if utf8.RuneCountInString(candidate.Annotations.Yinyuan) != 4 {
		t.Fatalf("full yinyuan sequence = %q", candidate.Annotations.Yinyuan)
	}
}

func TestResolverLeavesAmbiguousCompressedPronunciationBlank(t *testing.T) {
	resolver, err := Load("../data", "variable")
	if err != nil {
		t.Fatal(err)
	}
	ambiguous := ""
	for code, values := range resolver.numericByCode {
		if len(values) > 1 {
			ambiguous = code
			break
		}
	}
	if ambiguous == "" {
		t.Fatal("variable annotation fixture has no ambiguous code")
	}
	candidate := engineapi.Candidate{Text: "不存在的测试候选", Code: ambiguous}
	resolver.Annotate(&candidate)
	if candidate.Annotations.KeySequence != ambiguous {
		t.Fatalf("key sequence = %q", candidate.Annotations.KeySequence)
	}
	if candidate.Annotations.StandardPinyin != "" || candidate.Annotations.Yinyuan != "" {
		t.Fatalf("ambiguous compressed code was guessed: %#v", candidate.Annotations)
	}
}
