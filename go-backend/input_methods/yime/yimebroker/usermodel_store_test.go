package yimebroker

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestDurableUserModelRecoversJournalAndTruncatesTornTail(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "系统", Code: "a1", Weight: 1000},
		{Text: "学习", Code: "a1", Weight: 900},
	})
	if err != nil {
		t.Fatal(err)
	}
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "durable-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := yimecore.NewEngineWithUserModel(index, 9, store.Model())
	if err != nil {
		t.Fatal(err)
	}
	state := applyTestCode(t, engine, "a1")
	var target string
	for _, candidate := range state.Candidates {
		if candidate.Text == "学习" {
			target = candidate.ID
		}
	}
	const requestID = "durable-request-0001"
	if _, err := engine.SelectIdempotent(target, requestID); err != nil {
		t.Fatal(err)
	}
	if store.Stats().JournalGeneration != 1 {
		t.Fatalf("journal stats = %+v", store.Stats())
	}
	if err := store.abortForTest(); err != nil {
		t.Fatal(err)
	}
	if err := appendFile(journal, []byte(`{"schema_version":"partial`)); err != nil {
		t.Fatal(err)
	}

	recovered, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "durable-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	stats := recovered.Stats()
	if stats.RecoveredMutations != 1 || stats.TruncatedTailBytes == 0 || recovered.Model().Generation() != 1 {
		t.Fatalf("recovery stats = %+v generation=%d", stats, recovered.Model().Generation())
	}
	recoveredEngine, err := yimecore.NewEngineWithUserModel(index, 9, recovered.Model())
	if err != nil {
		t.Fatal(err)
	}
	if first := applyTestCode(t, recoveredEngine, "a1").Candidates[0].Text; first != "学习" {
		t.Fatalf("recovered ranking = %q", first)
	}
	retryState := applyTestCode(t, recoveredEngine, "a1")
	if _, err := recoveredEngine.SelectIdempotent(retryState.Candidates[0].ID, requestID); err != nil || recovered.Model().Generation() != 1 {
		t.Fatalf("recovered retry error=%v generation=%d", err, recovered.Model().Generation())
	}
	if err := recovered.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestDurableSentenceLearningUsesOneJournalRecordAndRecoversAllObservations(t *testing.T) {
	const sourceID = "durable-sentence-test"
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "甲", Code: "ab", Weight: 100}, {Text: "乙", Code: "ab", Weight: 90},
		{Text: "丙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: sourceID, CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	engine, err := yimecore.NewEngineWithUserModel(index, 9, store.Model())
	if err != nil {
		t.Fatal(err)
	}
	state := applyTestCode(t, engine, "abcd")
	if state.Sentence == nil || len(state.Sentence.Segments) != 2 {
		t.Fatalf("sentence missing: %#v", state)
	}
	first := state.Sentence.Segments[0]
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: state.Sentence.ID,
		SegmentStart: first.Start, SegmentEnd: first.End,
	})
	if err != nil {
		t.Fatal(err)
	}
	var replacementID string
	for _, candidate := range focused.State.Candidates {
		if candidate.Text == "乙" {
			replacementID = candidate.ID
			break
		}
	}
	replaced, err := engine.SelectIdempotent(replacementID, "pending-segment-choice")
	if err != nil || replaced.State.Sentence == nil || replaced.State.Sentence.Text != "乙丙" ||
		store.Model().Generation() != 0 {
		t.Fatalf("pending segment selection failed: result=%#v err=%v generation=%d",
			replaced, err, store.Model().Generation())
	}
	const requestID = "durable-sentence-commit"
	committed, err := engine.SelectIdempotent(replaced.State.Sentence.ID, requestID)
	if err != nil || committed.Commit != "乙丙" || store.Model().Generation() != 1 {
		t.Fatalf("durable sentence commit failed: result=%#v err=%v generation=%d",
			committed, err, store.Model().Generation())
	}
	journalData, err := os.ReadFile(journal)
	if err != nil || bytes.Count(journalData, []byte{'\n'}) != 1 {
		t.Fatalf("sentence commit did not use one journal record: err=%v data=%q", err, journalData)
	}
	if err := store.abortForTest(); err != nil {
		t.Fatal(err)
	}

	recovered, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: sourceID, CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer recovered.Close()
	if recovered.Model().Generation() != 1 ||
		!hasLearnedRecord(recovered.Model().LearnedRecords(), "ab", "乙") ||
		!hasLearnedRecord(recovered.Model().LearnedRecords(), "abcd", "乙丙") {
		t.Fatalf("recovered sentence observations incomplete: generation=%d records=%#v",
			recovered.Model().Generation(), recovered.Model().LearnedRecords())
	}
	recoveredEngine, err := yimecore.NewEngineWithUserModel(index, 9, recovered.Model())
	if err != nil {
		t.Fatal(err)
	}
	retry := applyTestCode(t, recoveredEngine, "abcd")
	if retry.Sentence == nil {
		t.Fatalf("recovered sentence missing: %#v", retry)
	}
	if _, err := recoveredEngine.SelectIdempotent(retry.Sentence.ID, requestID); !errors.Is(err, yimecore.ErrIdempotencyConflict) ||
		recovered.Model().Generation() != 1 {
		t.Fatalf("changed recovered observations did not conflict: err=%v generation=%d",
			err, recovered.Model().Generation())
	}
	if err := recovered.Close(); err != nil {
		t.Fatal(err)
	}
	snapshotData, err := os.ReadFile(snapshot)
	if err != nil || !bytes.Contains(snapshotData, []byte(`"observations"`)) {
		t.Fatalf("snapshot lost ordered idempotency observations: err=%v data=%s", err, snapshotData)
	}
	reopened, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: sourceID, CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatalf("checkpointed sentence model did not reopen: %v", err)
	}
	defer reopened.Close()
	reopenedEngine, err := yimecore.NewEngineWithUserModel(index, 9, reopened.Model())
	if err != nil {
		t.Fatal(err)
	}
	retry = applyTestCode(t, reopenedEngine, "abcd")
	if _, err := reopenedEngine.SelectIdempotent(retry.Sentence.ID, requestID); !errors.Is(err, yimecore.ErrIdempotencyConflict) ||
		reopened.Model().Generation() != 1 {
		t.Fatalf("checkpointed changed observations did not conflict: err=%v generation=%d", err, reopened.Model().Generation())
	}
}

func hasLearnedRecord(records []yimecore.LearnedRecord, code, text string) bool {
	for _, record := range records {
		if record.Code == code && record.Text == text {
			return true
		}
	}
	return false
}

func TestDurableUserModelCompactsJournalAndCreatesV1Rollback(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	rollback := filepath.Join(directory, "model.v1.rollback")
	seed, err := yimecore.OpenUserModel(snapshot, "compact-test")
	if err != nil {
		t.Fatal(err)
	}
	if err := seed.SaveVersion1To(snapshot); err != nil {
		t.Fatal(err)
	}
	var stages []CompactionStage
	var stagesMu sync.Mutex
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, RollbackSnapshotPath: rollback, SourceID: "compact-test",
		CheckpointEvery: 100, CompactEvery: 3, CompactionStageHook: func(stage CompactionStage) {
			stagesMu.Lock()
			stages = append(stages, stage)
			stagesMu.Unlock()
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	for generation := 1; generation <= 3; generation++ {
		mutation := yimecore.UserMutation{Generation: uint64(generation), Kind: yimecore.UserMutationSelect, Code: "a1", Text: "候选", RequestID: fmt.Sprintf("compact-request-%04d", generation)}
		if err := store.persist(mutation); err != nil {
			t.Fatal(err)
		}
		if err := store.Model().ApplyRecoveredMutation(mutation); err != nil {
			t.Fatal(err)
		}
		store.commit()
	}
	deadline := time.Now().Add(2 * time.Second)
	for store.Stats().Compactions == 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	stats := store.Stats()
	if stats.Compactions != 1 || stats.SnapshotGeneration != 3 || stats.MigratedFromSchema != yimecore.UserModelSchemaVersion1 {
		t.Fatalf("compaction stats = %+v", stats)
	}
	info, err := os.Stat(journal)
	if err != nil || info.Size() != 0 {
		t.Fatalf("compacted journal info=%v err=%v", info, err)
	}
	stagesMu.Lock()
	gotStages := append([]CompactionStage(nil), stages...)
	stagesMu.Unlock()
	wantStages := []CompactionStage{CompactionAfterSnapshot, CompactionAfterJournalClose, CompactionAfterJournalReplace}
	if !reflect.DeepEqual(gotStages, wantStages) {
		t.Fatalf("compaction stages = %v", gotStages)
	}
	rollbackModel, err := yimecore.OpenUserModel(rollback, "compact-test")
	if err != nil || rollbackModel.LoadedSchemaVersion() != yimecore.UserModelSchemaVersion1 || rollbackModel.Generation() != 0 {
		t.Fatalf("rollback model error=%v schema=%q generation=%d", err, rollbackModel.LoadedSchemaVersion(), rollbackModel.Generation())
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenDurableUserModel(DurableUserModelConfig{SnapshotPath: snapshot, JournalPath: journal, SourceID: "compact-test", CompactEvery: 3})
	if err != nil {
		t.Fatal(err)
	}
	if reopened.Model().Generation() != 3 || reopened.Stats().RecoveredMutations != 0 {
		t.Fatalf("reopened generation=%d stats=%+v", reopened.Model().Generation(), reopened.Stats())
	}
	if err := reopened.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestDurableUserModelConcurrentCommitAndCheckpointDoesNotDeadlock(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	index, err := yimecore.NewIndex([]yimecore.Entry{
		{Text: "甲", Code: "ab", Weight: 100},
		{Text: "乙", Code: "cd", Weight: 100},
	})
	if err != nil {
		t.Fatal(err)
	}
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "concurrent-checkpoint",
		CheckpointEvery: 1, CompactEvery: 1_000_000,
	})
	if err != nil {
		t.Fatal(err)
	}

	const goroutines = 4
	const commitsPerGoroutine = 40
	done := make(chan error, goroutines)
	for worker := 0; worker < goroutines; worker++ {
		go func(worker int) {
			engine, engineErr := yimecore.NewEngineWithUserModel(index, 9, store.Model())
			if engineErr != nil {
				done <- engineErr
				return
			}
			code := "ab"
			if worker%2 != 0 {
				code = "cd"
			}
			for iteration := 0; iteration < commitsPerGoroutine; iteration++ {
				state := applyCodeWithoutTesting(engine, code)
				if state.err != nil {
					done <- state.err
					return
				}
				if len(state.result.State.Candidates) == 0 {
					done <- errors.New("concurrent engine returned no candidates")
					return
				}
				if _, selectErr := engine.Select(state.result.State.Candidates[0].ID); selectErr != nil {
					done <- selectErr
					return
				}
			}
			done <- nil
		}(worker)
	}
	for worker := 0; worker < goroutines; worker++ {
		select {
		case workerErr := <-done:
			if workerErr != nil {
				t.Fatal(workerErr)
			}
		case <-time.After(10 * time.Second):
			t.Fatal("concurrent selection and checkpoint deadlocked")
		}
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "concurrent-checkpoint",
		CheckpointEvery: 1,
	})
	if err != nil {
		t.Fatalf("reopen after concurrent checkpoints: %v", err)
	}
	defer reopened.Close()
	wantGeneration := uint64(goroutines * commitsPerGoroutine)
	if reopened.Model().Generation() != wantGeneration {
		t.Fatalf("reopened generation=%d want=%d", reopened.Model().Generation(), wantGeneration)
	}
}

type applyResult struct {
	result engineapi.Result
	err    error
}

func applyCodeWithoutTesting(engine *yimecore.Engine, code string) applyResult {
	var result engineapi.Result
	for _, value := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(value)})
		if err != nil {
			return applyResult{err: err}
		}
	}
	return applyResult{result: result}
}

func TestDurableUserModelRejectsCompleteJournalCorruption(t *testing.T) {
	directory := t.TempDir()
	snapshot := filepath.Join(directory, "model.json")
	journal := filepath.Join(directory, "model.journal")
	store, err := OpenDurableUserModel(DurableUserModelConfig{
		SnapshotPath: snapshot, JournalPath: journal, SourceID: "corrupt-test", CheckpointEvery: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	store.Model().SetMutationWriter(nil)
	store.Model().SetMutationWriter(store.persist)
	mutation := yimecore.UserMutation{Generation: 1, Kind: yimecore.UserMutationSelect, Code: "a1", Text: "候选"}
	if err := store.persist(mutation); err != nil {
		t.Fatal(err)
	}
	if err := store.abortForTest(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(journal)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)/2] ^= 1
	if err := os.WriteFile(journal, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenDurableUserModel(DurableUserModelConfig{SnapshotPath: snapshot, JournalPath: journal, SourceID: "corrupt-test"}); !errors.Is(err, ErrCorruptUserJournal) {
		t.Fatalf("corrupt journal error = %v", err)
	}
}

func TestDecodeJournalRecordAcceptsVersion1(t *testing.T) {
	payload := journalPayload{
		SchemaVersion: userJournalSchemaV1,
		SourceID:      "legacy-journal-test",
		Mutation: yimecore.UserMutation{
			Generation: 1, Kind: yimecore.UserMutationSelect, Code: "a1", Text: "候选",
		},
	}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(payloadBytes)
	recordBytes, err := json.Marshal(journalRecord{
		journalPayload: payload, RecordSHA256: hex.EncodeToString(digest[:]),
	})
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := decodeJournalRecord(recordBytes)
	if err != nil || decoded.SchemaVersion != userJournalSchemaV1 || decoded.Mutation.Text != "候选" {
		t.Fatalf("legacy journal decode failed: record=%#v err=%v", decoded, err)
	}
}

func applyTestCode(t *testing.T, engine engineapi.Engine, code string) engineapi.State {
	t.Helper()
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result.State
}

func appendFile(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	return file.Sync()
}
