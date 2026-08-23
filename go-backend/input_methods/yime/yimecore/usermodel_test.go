package yimecore

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func TestUserLearningPromotesSelectedCandidateWithExplainableScore(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "系统首选", Code: "a1", Weight: 1000},
		{Text: "用户选择", Code: "a1", Weight: 900},
	})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	initial := applyCode(t, engine, "a1")
	if initial.State.Candidates[0].Text != "系统首选" {
		t.Fatalf("initial order = %+v", initial.State.Candidates)
	}
	var selectedID string
	for _, candidate := range initial.State.Candidates {
		if candidate.Text == "用户选择" {
			selectedID = candidate.ID
		}
	}
	if selectedID == "" {
		t.Fatal("learned candidate is absent")
	}
	if _, err := engine.Select(selectedID); err != nil {
		t.Fatal(err)
	}
	after := applyCode(t, engine, "a1")
	learned := after.State.Candidates[0]
	if learned.Text != "用户选择" || learned.Score.User != userBoostPerSelection || learned.Score.Static != 900 || learned.Score.Total != 900+userBoostPerSelection {
		t.Fatalf("learned ranking = %+v", learned)
	}
	if !model.Forget("a1", "用户选择") {
		t.Fatal("expected learned candidate to be forgotten")
	}
	engine.Reset()
	forgotten := applyCode(t, engine, "a1")
	if forgotten.State.Candidates[0].Text != "系统首选" {
		t.Fatalf("forget did not restore static order: %+v", forgotten.State.Candidates)
	}
}

func TestUserMutationPersistenceFailureDoesNotCommitOrAdvanceModel(t *testing.T) {
	index, err := NewIndex([]Entry{{Text: "候选", Code: "a1", Weight: 1}})
	if err != nil {
		t.Fatal(err)
	}
	model, err := NewUserModel(index.identity())
	if err != nil {
		t.Fatal(err)
	}
	model.SetMutationWriter(func(UserMutation) error { return errors.New("forced journal failure") })
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyCode(t, engine, "a1")
	result, err := engine.Select(state.State.Candidates[0].ID)
	if err == nil || result.Commit != "" || model.Generation() != 0 {
		t.Fatalf("failed persistence result=%+v err=%v generation=%d", result, err, model.Generation())
	}
	if after := engine.Reset(); after.State.RawInput != "" {
		t.Fatalf("engine failed to remain usable: %+v", after)
	}
}

func TestIdempotentSelectionSurvivesSnapshotAndRejectsReuse(t *testing.T) {
	path := filepath.Join(t.TempDir(), "user-model.json")
	index, err := NewIndex([]Entry{{Text: "甲", Code: "a1", Weight: 10}, {Text: "乙", Code: "a1", Weight: 9}})
	if err != nil {
		t.Fatal(err)
	}
	model, err := OpenUserModel(path, index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	state := applyCode(t, engine, "a1")
	first := state.State.Candidates[0]
	second := state.State.Candidates[1]
	const requestID = "select-request-0001"
	if result, selectErr := engine.SelectIdempotent(first.ID, requestID); selectErr != nil || result.Commit != first.Text {
		t.Fatalf("first selection = %+v, %v", result, selectErr)
	}
	if model.Generation() != 1 {
		t.Fatalf("generation after first selection = %d", model.Generation())
	}
	state = applyCode(t, engine, "a1")
	if result, retryErr := engine.SelectIdempotent(state.State.Candidates[0].ID, requestID); retryErr != nil || result.Commit != first.Text || model.Generation() != 1 {
		t.Fatalf("retry = %+v, %v; generation=%d", result, retryErr, model.Generation())
	}
	state = applyCode(t, engine, "a1")
	var conflictingID string
	for _, candidate := range state.State.Candidates {
		if candidate.Text == second.Text {
			conflictingID = candidate.ID
		}
	}
	if _, conflictErr := engine.SelectIdempotent(conflictingID, requestID); !errors.Is(conflictErr, ErrIdempotencyConflict) || model.Generation() != 1 {
		t.Fatalf("conflict = %v; generation=%d", conflictErr, model.Generation())
	}
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenUserModel(path, index.identity())
	if err != nil {
		t.Fatal(err)
	}
	reopenedEngine, err := NewEngineWithUserModel(index, 9, reopened)
	if err != nil {
		t.Fatal(err)
	}
	state = applyCode(t, reopenedEngine, "a1")
	if _, retryErr := reopenedEngine.SelectIdempotent(state.State.Candidates[0].ID, requestID); retryErr != nil || reopened.Generation() != 1 {
		t.Fatalf("snapshot retry = %v; generation=%d", retryErr, reopened.Generation())
	}
}

func TestUserModelAtomicSaveReopenAndSourceBinding(t *testing.T) {
	path := filepath.Join(t.TempDir(), "user-model.json")
	model, err := OpenUserModel(path, "index-source-a")
	if err != nil {
		t.Fatal(err)
	}
	model.observe("a1", "候选")
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	model.observe("a1", "候选")
	if err := model.Save(); err != nil {
		t.Fatalf("atomic replacement failed: %v", err)
	}
	reopened, err := OpenUserModel(path, "index-source-a")
	if err != nil {
		t.Fatal(err)
	}
	if boost := reopened.candidateBoost("a1", "候选"); boost != 2*userBoostPerSelection {
		t.Fatalf("reopened boost = %d", boost)
	}
	if _, err := OpenUserModel(path, "index-source-b"); !errors.Is(err, ErrCorruptUserModel) {
		t.Fatalf("source mismatch error = %v", err)
	}
}

func TestUserModelV1ToV2MigrationKeepsRollbackAndIdempotency(t *testing.T) {
	directory := t.TempDir()
	v1Path := filepath.Join(directory, "model-v1.json")
	v2Path := filepath.Join(directory, "model-v2.json")
	rollbackPath := filepath.Join(directory, "rollback-v1.json")
	model, err := OpenUserModel(v2Path, "migration-source")
	if err != nil {
		t.Fatal(err)
	}
	if err := model.observeIdempotent("a1", "候选", "", "migration-request-0001"); err != nil {
		t.Fatal(err)
	}
	if err := model.SaveVersion1To(v1Path); err != nil {
		t.Fatal(err)
	}
	legacy, err := OpenUserModel(v1Path, "migration-source")
	if err != nil || legacy.LoadedSchemaVersion() != UserModelSchemaVersion1 {
		t.Fatalf("legacy open = %v schema=%q", err, legacy.LoadedSchemaVersion())
	}
	if err := legacy.Save(); err != nil {
		t.Fatal(err)
	}
	migrated, err := OpenUserModel(v1Path, "migration-source")
	if err != nil || migrated.LoadedSchemaVersion() != UserModelSchemaVersion2 || migrated.Generation() != 1 {
		t.Fatalf("migrated open = %v schema=%q generation=%d", err, migrated.LoadedSchemaVersion(), migrated.Generation())
	}
	if err := migrated.SaveVersion1To(rollbackPath); err != nil {
		t.Fatal(err)
	}
	rollback, err := OpenUserModel(rollbackPath, "migration-source")
	if err != nil || rollback.LoadedSchemaVersion() != UserModelSchemaVersion1 || rollback.Generation() != 1 {
		t.Fatalf("rollback open = %v schema=%q generation=%d", err, rollback.LoadedSchemaVersion(), rollback.Generation())
	}
	if err := rollback.observeIdempotent("a1", "候选", "", "migration-request-0001"); err != nil || rollback.Generation() != 1 {
		t.Fatalf("rollback idempotency = %v generation=%d", err, rollback.Generation())
	}
}

func TestUserModelBackupRestoreAndCorruptionIsolation(t *testing.T) {
	directory := t.TempDir()
	primary := filepath.Join(directory, "primary.json")
	backup := filepath.Join(directory, "backup.json")
	model, err := OpenUserModel(primary, "locked-index")
	if err != nil {
		t.Fatal(err)
	}
	model.observe("a1", "甲")
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	if err := model.SaveTo(backup); err != nil {
		t.Fatal(err)
	}
	model.observe("a1", "乙")
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}
	if err := model.Restore(backup); err != nil {
		t.Fatal(err)
	}
	if model.candidateBoost("a1", "甲") == 0 || model.candidateBoost("a1", "乙") != 0 {
		t.Fatal("restore did not reinstate the validated backup")
	}

	original, err := os.ReadFile(primary)
	if err != nil {
		t.Fatal(err)
	}
	corrupt := append([]byte(nil), original...)
	corrupt[len(corrupt)/2] ^= 1
	if err := os.WriteFile(primary, corrupt, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenUserModel(primary, "locked-index"); !errors.Is(err, ErrCorruptUserModel) {
		t.Fatalf("corruption error = %v", err)
	}
	after, err := os.ReadFile(primary)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(corrupt) {
		t.Fatal("corrupt source was modified instead of isolated")
	}
}

func TestContextTransitionIsExplainablePersistentAndForgottenWithCandidate(t *testing.T) {
	index, err := NewIndex([]Entry{
		{Text: "前文", Code: "c1", Weight: 1000},
		{Text: "系统", Code: "a1", Weight: 1000},
		{Text: "目标", Code: "a1", Weight: 900},
	})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "context.json")
	model, err := OpenUserModel(path, index.identity())
	if err != nil {
		t.Fatal(err)
	}
	engine, err := NewEngineWithUserModel(index, 9, model)
	if err != nil {
		t.Fatal(err)
	}
	context := applyCode(t, engine, "c1").State.Candidates[0]
	if _, err := engine.Select(context.ID); err != nil {
		t.Fatal(err)
	}
	choices := applyCode(t, engine, "a1").State.Candidates
	var target engineapi.Candidate
	for _, candidate := range choices {
		if candidate.Text == "目标" {
			target = candidate
		}
	}
	if _, err := engine.Select(target.ID); err != nil {
		t.Fatal(err)
	}
	if err := model.Save(); err != nil {
		t.Fatal(err)
	}

	reopened, err := OpenUserModel(path, index.identity())
	if err != nil {
		t.Fatal(err)
	}
	contextEngine, err := NewEngineWithUserModel(index, 9, reopened)
	if err != nil {
		t.Fatal(err)
	}
	context = applyCode(t, contextEngine, "c1").State.Candidates[0]
	if _, err := contextEngine.Select(context.ID); err != nil {
		t.Fatal(err)
	}
	withContext := applyCode(t, contextEngine, "a1").State.Candidates[0]
	if withContext.Text != "目标" || withContext.Score.Context != contextBoostPerSelection || withContext.Score.User != userBoostPerSelection {
		t.Fatalf("context score = %+v", withContext)
	}
	contextEngine.ClearContext()
	withoutContext := contextEngine.Reset()
	withoutContext = applyCode(t, contextEngine, "a1")
	if withoutContext.State.Candidates[0].Score.Context != 0 {
		t.Fatalf("context survived ClearContext: %+v", withoutContext.State.Candidates[0])
	}
	if !reopened.Forget("a1", "目标") {
		t.Fatal("expected context target to be forgotten")
	}
	contextEngine.ClearContext()
	context = applyCode(t, contextEngine, "c1").State.Candidates[0]
	if _, err := contextEngine.Select(context.ID); err != nil {
		t.Fatal(err)
	}
	afterForget := applyCode(t, contextEngine, "a1").State.Candidates
	for _, candidate := range afterForget {
		if candidate.Text == "目标" && (candidate.Score.Context != 0 || candidate.Score.User != 0) {
			t.Fatalf("forgotten target retained learned score: %+v", candidate)
		}
	}
}
