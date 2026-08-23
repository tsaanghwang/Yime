package yimebroker

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	userJournalSchema = "yime-user-journal-v1"
	maxJournalRecord  = 1024 * 1024
)

var ErrCorruptUserJournal = errors.New("corrupt Yime user journal")

type DurableUserModelConfig struct {
	SnapshotPath    string
	JournalPath     string
	SourceID        string
	CheckpointEvery int
}

type DurableUserModelStats struct {
	SnapshotGeneration  uint64 `json:"snapshot_generation"`
	JournalGeneration   uint64 `json:"journal_generation"`
	RecoveredMutations  int    `json:"recovered_mutations"`
	TruncatedTailBytes  int64  `json:"truncated_tail_bytes"`
	CheckpointFailures  int    `json:"checkpoint_failures"`
	LastCheckpointError string `json:"last_checkpoint_error,omitempty"`
}

type journalPayload struct {
	SchemaVersion  string                `json:"schema_version"`
	SourceID       string                `json:"source_id"`
	PreviousSHA256 string                `json:"previous_sha256,omitempty"`
	Mutation       yimecore.UserMutation `json:"mutation"`
}

type journalRecord struct {
	journalPayload
	RecordSHA256 string `json:"record_sha256"`
}

type durableRequest struct {
	mutation   *yimecore.UserMutation
	close      bool
	checkpoint bool
	ack        chan error
}

type DurableUserModel struct {
	model           *yimecore.UserModel
	journal         *os.File
	requests        chan durableRequest
	done            chan struct{}
	checkpointEvery int
	sourceID        string
	previousHash    string
	journalGen      uint64
	stats           DurableUserModelStats

	stateMu sync.Mutex
	closed  bool
	statsMu sync.Mutex
}

func OpenDurableUserModel(config DurableUserModelConfig) (*DurableUserModel, error) {
	if strings.TrimSpace(config.SnapshotPath) == "" || strings.TrimSpace(config.JournalPath) == "" || strings.TrimSpace(config.SourceID) == "" {
		return nil, errors.New("snapshot, journal and source ID are required")
	}
	snapshotPath, err := filepath.Abs(config.SnapshotPath)
	if err != nil {
		return nil, err
	}
	journalPath, err := filepath.Abs(config.JournalPath)
	if err != nil {
		return nil, err
	}
	if strings.EqualFold(snapshotPath, journalPath) {
		return nil, errors.New("snapshot and journal paths must differ")
	}
	if config.CheckpointEvery == 0 {
		config.CheckpointEvery = 256
	}
	if config.CheckpointEvery < 1 || config.CheckpointEvery > 1_000_000 {
		return nil, errors.New("checkpoint interval is out of range")
	}
	model, err := yimecore.OpenUserModel(snapshotPath, config.SourceID)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(journalPath), 0o700); err != nil {
		return nil, err
	}
	journal, err := os.OpenFile(journalPath, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	previousHash, journalGeneration, recovered, truncated, err := recoverJournal(journal, model, config.SourceID)
	if err != nil {
		_ = journal.Close()
		return nil, err
	}
	if _, err := journal.Seek(0, io.SeekEnd); err != nil {
		_ = journal.Close()
		return nil, err
	}
	store := &DurableUserModel{
		model: model, journal: journal, requests: make(chan durableRequest, 64), done: make(chan struct{}),
		checkpointEvery: config.CheckpointEvery, sourceID: config.SourceID, previousHash: previousHash, journalGen: journalGeneration,
		stats: DurableUserModelStats{SnapshotGeneration: model.Generation() - uint64(recovered), JournalGeneration: journalGeneration, RecoveredMutations: recovered, TruncatedTailBytes: truncated},
	}
	go store.run()
	model.SetMutationWriter(store.persist)
	return store, nil
}

func (s *DurableUserModel) Model() *yimecore.UserModel { return s.model }

func (s *DurableUserModel) Stats() DurableUserModelStats {
	s.statsMu.Lock()
	defer s.statsMu.Unlock()
	result := s.stats
	result.JournalGeneration = s.journalGen
	return result
}

func (s *DurableUserModel) persist(mutation yimecore.UserMutation) error {
	s.stateMu.Lock()
	if s.closed {
		s.stateMu.Unlock()
		return errors.New("durable user model is closed")
	}
	request := durableRequest{mutation: &mutation, ack: make(chan error, 1)}
	s.requests <- request
	s.stateMu.Unlock()
	return <-request.ack
}

func (s *DurableUserModel) run() {
	defer close(s.done)
	mutationsSinceCheckpoint := 0
	var fatalJournalError error
	for request := range s.requests {
		if request.close {
			var err error
			if request.checkpoint {
				err = s.model.Save()
			}
			if closeErr := s.journal.Close(); err == nil {
				err = closeErr
			}
			if err == nil {
				err = fatalJournalError
			}
			request.ack <- err
			return
		}
		err := fatalJournalError
		if err == nil {
			err = s.append(*request.mutation)
			if err != nil {
				fatalJournalError = err
			}
		}
		request.ack <- err
		if err != nil {
			continue
		}
		mutationsSinceCheckpoint++
		if mutationsSinceCheckpoint >= s.checkpointEvery {
			if checkpointErr := s.model.Save(); checkpointErr != nil {
				s.statsMu.Lock()
				s.stats.CheckpointFailures++
				s.stats.LastCheckpointError = checkpointErr.Error()
				s.statsMu.Unlock()
			}
			mutationsSinceCheckpoint = 0
		}
	}
}

func (s *DurableUserModel) append(mutation yimecore.UserMutation) error {
	s.statsMu.Lock()
	defer s.statsMu.Unlock()
	if mutation.Generation <= s.journalGen {
		return fmt.Errorf("journal generation %d does not advance %d", mutation.Generation, s.journalGen)
	}
	payload := journalPayload{SchemaVersion: userJournalSchema, SourceID: s.sourceID, PreviousSHA256: s.previousHash, Mutation: mutation}
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	digest := sha256.Sum256(payloadBytes)
	record := journalRecord{journalPayload: payload, RecordSHA256: hex.EncodeToString(digest[:])}
	data, err := json.Marshal(record)
	if err != nil {
		return err
	}
	if len(data) > maxJournalRecord {
		return errors.New("user journal record is too large")
	}
	data = append(data, '\n')
	if _, err := s.journal.Write(data); err != nil {
		return err
	}
	if err := s.journal.Sync(); err != nil {
		return err
	}
	s.previousHash = record.RecordSHA256
	s.journalGen = mutation.Generation
	s.stats.JournalGeneration = mutation.Generation
	return nil
}

func (s *DurableUserModel) Close() error { return s.close(true) }

func (s *DurableUserModel) abortForTest() error { return s.close(false) }

func (s *DurableUserModel) close(checkpoint bool) error {
	if s == nil {
		return nil
	}
	s.model.SetMutationWriter(nil)
	s.stateMu.Lock()
	if s.closed {
		s.stateMu.Unlock()
		<-s.done
		return nil
	}
	s.closed = true
	ack := make(chan error, 1)
	s.requests <- durableRequest{close: true, checkpoint: checkpoint, ack: ack}
	s.stateMu.Unlock()
	err := <-ack
	<-s.done
	return err
}

func recoverJournal(file *os.File, model *yimecore.UserModel, sourceID string) (string, uint64, int, int64, error) {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", 0, 0, 0, err
	}
	reader := bufio.NewReaderSize(file, 64*1024)
	previousHash := ""
	journalGeneration := uint64(0)
	recovered := 0
	validOffset := int64(0)
	for {
		line, err := reader.ReadBytes('\n')
		if errors.Is(err, io.EOF) && len(line) > 0 {
			info, statErr := file.Stat()
			if statErr != nil {
				return "", 0, 0, 0, statErr
			}
			truncated := info.Size() - validOffset
			if truncateErr := file.Truncate(validOffset); truncateErr != nil {
				return "", 0, 0, 0, truncateErr
			}
			if syncErr := file.Sync(); syncErr != nil {
				return "", 0, 0, 0, syncErr
			}
			return previousHash, journalGeneration, recovered, truncated, nil
		}
		if errors.Is(err, io.EOF) {
			return previousHash, journalGeneration, recovered, 0, nil
		}
		if err != nil {
			return "", 0, 0, 0, err
		}
		if len(line) > maxJournalRecord+1 {
			return "", 0, 0, 0, fmt.Errorf("%w: record is too large", ErrCorruptUserJournal)
		}
		record, decodeErr := decodeJournalRecord(bytes.TrimSuffix(line, []byte{'\n'}))
		if decodeErr != nil {
			return "", 0, 0, 0, decodeErr
		}
		if record.SourceID != sourceID || record.PreviousSHA256 != previousHash || record.Mutation.Generation <= journalGeneration {
			return "", 0, 0, 0, fmt.Errorf("%w: source, chain or generation mismatch", ErrCorruptUserJournal)
		}
		if record.Mutation.Generation > model.Generation() {
			if applyErr := model.ApplyRecoveredMutation(record.Mutation); applyErr != nil {
				return "", 0, 0, 0, applyErr
			}
			recovered++
		}
		previousHash = record.RecordSHA256
		journalGeneration = record.Mutation.Generation
		validOffset += int64(len(line))
	}
}

func decodeJournalRecord(data []byte) (journalRecord, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var record journalRecord
	if err := decoder.Decode(&record); err != nil {
		return journalRecord{}, fmt.Errorf("%w: decode: %v", ErrCorruptUserJournal, err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return journalRecord{}, fmt.Errorf("%w: %v", ErrCorruptUserJournal, err)
	}
	if record.SchemaVersion != userJournalSchema || record.SourceID == "" || record.RecordSHA256 == "" {
		return journalRecord{}, fmt.Errorf("%w: invalid record header", ErrCorruptUserJournal)
	}
	payloadBytes, err := json.Marshal(record.journalPayload)
	if err != nil {
		return journalRecord{}, err
	}
	digest := sha256.Sum256(payloadBytes)
	if record.RecordSHA256 != hex.EncodeToString(digest[:]) {
		return journalRecord{}, fmt.Errorf("%w: record hash mismatch", ErrCorruptUserJournal)
	}
	return record, nil
}
