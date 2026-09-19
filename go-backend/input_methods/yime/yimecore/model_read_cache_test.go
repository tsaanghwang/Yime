package yimecore

import "testing"

func TestUserModelScoreSequenceReplaysAndInvalidates(t *testing.T) {
	model, err := NewUserModel("score-sequence-test")
	if err != nil {
		t.Fatal(err)
	}
	if err := model.observeWithContext("ab", "甲", "前"); err != nil {
		t.Fatal(err)
	}
	engine := &Engine{userModel: model, rawInput: "ab", previousCommit: "前"}
	engine.syncUserModelReadCache()

	if !engine.beginUserModelScoreSequence() {
		t.Fatal("first score sequence did not start")
	}
	first := engine.userCandidateModelScore("前", "ab", "甲")
	engine.endUserModelScoreSequence()
	if first.user <= 0 || first.context <= 0 || len(engine.modelSequences) != 1 {
		t.Fatalf("first score/cache = %#v, sequences=%d", first, len(engine.modelSequences))
	}

	if !engine.beginUserModelScoreSequence() {
		t.Fatal("replay score sequence did not start")
	}
	// A different identity must fall back to the ordinary score cache instead
	// of consuming the cached score for 甲.
	mismatch := engine.userCandidateModelScore("前", "ab", "乙")
	engine.endUserModelScoreSequence()
	if mismatch != (candidateModelScore{}) {
		t.Fatalf("mismatched identity reused cached score: %#v", mismatch)
	}

	if err := model.observeWithContext("ab", "甲", "前"); err != nil {
		t.Fatal(err)
	}
	engine.syncUserModelReadCache()
	if len(engine.modelSequences) != 0 {
		t.Fatal("model generation change did not invalidate score sequences")
	}
	updated := engine.userCandidateModelScore("前", "ab", "甲")
	if updated.user <= first.user || updated.context <= first.context {
		t.Fatalf("updated score = %#v, first = %#v", updated, first)
	}
}
