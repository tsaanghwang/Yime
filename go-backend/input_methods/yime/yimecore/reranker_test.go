package yimecore

import (
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func TestLinearRerankerIsOptionalAndOnlyReordersRetainedEqualShapePaths(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "铜", Code: "a", Weight: 100},
		{Text: "银", Code: "a", Weight: 90},
		{Text: "行", Code: "b", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel("reranker-test")
	if err != nil {
		t.Fatal(err)
	}
	model.rerankerWeights["segment\x1fa\x1f银"] = 1_000
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	if got := applyCode(t, engine, "ab").State.Sentence.Text; got != "铜行" {
		t.Fatalf("disabled reranker changed static order: %q", got)
	}
	engine.Reset()
	if err := engine.SetLinearRerankerEnabled(true); err != nil {
		t.Fatal(err)
	}
	state := applyCode(t, engine, "ab").State
	if got := state.Sentence.Text; got != "银行" {
		t.Fatalf("enabled reranker did not reorder retained paths: %q", got)
	}
	if state.Sentence.Score.Reranker != 1_000 {
		t.Fatalf("reranker score is not explainable: %#v", state.Sentence.Score)
	}
}

func TestLinearRerankerCorrectionIsBoundedAndPersists(t *testing.T) {
	path := filepath.Join(t.TempDir(), "model.json")
	model, err := OpenUserModel(path, "reranker-persistence-test")
	if err != nil {
		t.Fatal(err)
	}
	rejected := []engineapi.Segment{{Text: "铜", Code: "a"}, {Text: "行", Code: "b"}}
	selected := []engineapi.Segment{{Text: "银", Code: "a"}, {Text: "行", Code: "b"}}
	delta := rerankerCorrectionDelta(rejected, selected)
	observations := []UserObservation{{Code: "ab", Text: "铜行", Rejected: true}, {Code: "ab", Text: "银行"}}
	for count := 0; count < 12; count++ {
		if err := model.observeBatchWithRerankerIdempotent(observations, delta, ""); err != nil {
			t.Fatal(err)
		}
	}
	const discriminatingFeatures = 3
	if got := model.sentenceRerankerScore(selected); got != discriminatingFeatures*maximumRerankerWeight {
		t.Fatalf("selected reranker score=%d", got)
	}
	if got := model.sentenceRerankerScore(rejected); got != -discriminatingFeatures*maximumRerankerWeight {
		t.Fatalf("rejected reranker score=%d", got)
	}
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenUserModel(path, "reranker-persistence-test")
	if err != nil {
		t.Fatal(err)
	}
	if got := reopened.sentenceRerankerScore(selected); got != discriminatingFeatures*maximumRerankerWeight {
		t.Fatalf("persisted reranker score=%d", got)
	}
	backup := filepath.Join(t.TempDir(), "backup.json")
	if err := reopened.SaveTo(backup); err != nil {
		t.Fatal(err)
	}
	reopened.rerankerWeights = make(map[string]int64)
	if err := reopened.Restore(backup); err != nil {
		t.Fatal(err)
	}
	if got := reopened.sentenceRerankerScore(selected); got != discriminatingFeatures*maximumRerankerWeight {
		t.Fatalf("restored reranker score=%d", got)
	}
}

func TestRecoveredCorrectionMutationRestoresRerankerDelta(t *testing.T) {
	model, err := NewUserModel("reranker-journal-test")
	if err != nil {
		t.Fatal(err)
	}
	rejected := []engineapi.Segment{{Text: "铜", Code: "a"}, {Text: "行", Code: "b"}}
	selected := []engineapi.Segment{{Text: "银", Code: "a"}, {Text: "行", Code: "b"}}
	mutation := UserMutation{
		Generation: 1, Kind: UserMutationSelect, Code: "ab", Text: "银行", RequestID: "journal-correction-1",
		Observations:  []UserObservation{{Code: "ab", Text: "铜行", Rejected: true}, {Code: "ab", Text: "银行"}},
		RerankerDelta: rerankerCorrectionDelta(rejected, selected),
	}
	if err := model.ApplyRecoveredMutation(mutation); err != nil {
		t.Fatal(err)
	}
	if selectedScore, rejectedScore := model.sentenceRerankerScore(selected), model.sentenceRerankerScore(rejected); selectedScore <= rejectedScore {
		t.Fatalf("recovered reranker did not prefer correction: selected=%d rejected=%d", selectedScore, rejectedScore)
	}
	if model.Generation() != 1 {
		t.Fatalf("recovered generation=%d", model.Generation())
	}
}
