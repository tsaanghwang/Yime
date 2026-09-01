package yimecore

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

const (
	UserModelSchemaVersion1    = "yime-user-model-v1"
	UserModelSchemaVersion2    = "yime-user-model-v2"
	UserModelSchemaVersion3    = "yime-user-model-v3"
	UserModelSchemaVersion4    = "yime-user-model-v4"
	userModelSchemaVersion1    = UserModelSchemaVersion1
	userModelSchemaVersion2    = UserModelSchemaVersion2
	userModelSchemaVersion3    = UserModelSchemaVersion3
	userModelSchemaVersion4    = UserModelSchemaVersion4
	userModelSchemaVersion     = userModelSchemaVersion4
	userBoostPerSelection      = int64(1_000_000_000_000)
	contextBoostPerSelection   = int64(500_000_000_000)
	userPenaltyPerRejection    = int64(500_000_000_000)
	contextPenaltyPerRejection = int64(250_000_000_000)
	maximumContextSelections   = uint64(8)
	maximumRejections          = uint64(8)
	maximumUserModelItems      = 1_000_000
	maximumSelectionCount      = uint64(1_000_000_000)
)

var ErrCorruptUserModel = errors.New("corrupt Yime user model")
var ErrIdempotencyConflict = errors.New("user mutation idempotency conflict")

// UserModel is an independent, session-shareable selection-frequency model.
// It never mutates the static index and performs no I/O on the key path.
type UserModel struct {
	mutationMu        sync.Mutex
	mu                sync.RWMutex
	path              string
	sourceID          string
	generation        uint64
	selections        map[candidateIdentity]uint64
	contexts          map[contextIdentity]uint64
	rejections        map[candidateIdentity]uint64
	contextRejections map[contextIdentity]uint64
	rerankerWeights   map[string]int64
	appliedRequests   map[string]UserMutation
	mutationWriter    func(UserMutation) error
	mutationCommitted func()
	loadedSchema      string
}

type UserMutation struct {
	Generation    uint64            `json:"generation"`
	Kind          string            `json:"kind"`
	Code          string            `json:"code"`
	Text          string            `json:"text"`
	PreviousText  string            `json:"previous_text,omitempty"`
	RequestID     string            `json:"request_id,omitempty"`
	Observations  []UserObservation `json:"observations,omitempty"`
	RerankerDelta map[string]int64  `json:"reranker_delta,omitempty"`
}

type UserObservation struct {
	Code         string `json:"code"`
	Text         string `json:"text"`
	PreviousText string `json:"previous_text,omitempty"`
	Rejected     bool   `json:"rejected,omitempty"`
}

type LearnedRecord struct {
	Code       string `json:"code"`
	Text       string `json:"text"`
	Selections uint64 `json:"selections"`
}

const (
	UserMutationSelect = "select"
	UserMutationForget = "forget"
)

type candidateIdentity struct {
	code string
	text string
}

type contextIdentity struct {
	previous string
	candidateIdentity
}

type userModelPayload struct {
	SchemaVersion     string                  `json:"schema_version"`
	SourceID          string                  `json:"source_id"`
	Generation        uint64                  `json:"generation"`
	Selections        map[string]uint64       `json:"selections"`
	Contexts          map[string]uint64       `json:"contexts,omitempty"`
	Rejections        map[string]uint64       `json:"rejections,omitempty"`
	ContextRejections map[string]uint64       `json:"context_rejections,omitempty"`
	RerankerWeights   map[string]int64        `json:"reranker_weights,omitempty"`
	AppliedRequests   map[string]UserMutation `json:"applied_requests,omitempty"`
}

type userModelFile struct {
	userModelPayload
	PayloadSHA256 string `json:"payload_sha256"`
}

// NewUserModel creates an in-memory model. Call SaveTo to persist it.
func NewUserModel(sourceID string) (*UserModel, error) {
	if strings.TrimSpace(sourceID) == "" {
		return nil, fmt.Errorf("user model source ID is required")
	}
	return &UserModel{
		sourceID: sourceID, selections: make(map[candidateIdentity]uint64), contexts: make(map[contextIdentity]uint64),
		rejections: make(map[candidateIdentity]uint64), contextRejections: make(map[contextIdentity]uint64),
		rerankerWeights: make(map[string]int64),
		appliedRequests: make(map[string]UserMutation), loadedSchema: userModelSchemaVersion,
	}, nil
}

// OpenUserModel opens or initializes a model at path. Invalid data is
// rejected without modifying, deleting or renaming the original file.
func OpenUserModel(path, sourceID string) (*UserModel, error) {
	if strings.TrimSpace(path) == "" {
		return nil, fmt.Errorf("user model path is required")
	}
	model, err := NewUserModel(sourceID)
	if err != nil {
		return nil, err
	}
	model.path = filepath.Clean(path)
	payload, err := readUserModelFile(model.path, sourceID)
	if errors.Is(err, os.ErrNotExist) {
		return model, nil
	}
	if err != nil {
		return nil, err
	}
	model.generation = payload.Generation
	model.selections, err = decodeSelectionCounts(payload.Selections)
	if err != nil {
		return nil, err
	}
	model.contexts, err = decodeContextCounts(payload.Contexts)
	if err != nil {
		return nil, err
	}
	model.rejections, err = decodeSelectionCounts(payload.Rejections)
	if err != nil {
		return nil, err
	}
	model.contextRejections, err = decodeContextCounts(payload.ContextRejections)
	if err != nil {
		return nil, err
	}
	model.rerankerWeights = cloneInt64Map(payload.RerankerWeights)
	model.appliedRequests = cloneMutations(payload.AppliedRequests)
	model.loadedSchema = payload.SchemaVersion
	return model, nil
}

func (m *UserModel) candidateBoost(code, text string) int64 {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	identity := candidateIdentity{code: code, text: text}
	count := m.selections[identity]
	rejections := m.rejections[identity]
	m.mu.RUnlock()
	return signedLearningBoost(count, rejections, userBoostPerSelection, userPenaltyPerRejection)
}

func (m *UserModel) learnedCandidates(code string, limit int) []candidateIdentity {
	if m == nil || code == "" || limit <= 0 {
		return nil
	}
	type learnedCandidate struct {
		identity candidateIdentity
		count    uint64
	}
	m.mu.RLock()
	learned := make([]learnedCandidate, 0)
	for identity, count := range m.selections {
		if identity.code == code && count > 0 {
			learned = append(learned, learnedCandidate{identity: identity, count: count})
		}
	}
	m.mu.RUnlock()
	sort.Slice(learned, func(i, j int) bool {
		if learned[i].count != learned[j].count {
			return learned[i].count > learned[j].count
		}
		return learned[i].identity.text < learned[j].identity.text
	})
	if len(learned) > limit {
		learned = learned[:limit]
	}
	result := make([]candidateIdentity, len(learned))
	for index := range learned {
		result[index] = learned[index].identity
	}
	return result
}

func (m *UserModel) observe(code, text string) {
	_ = m.observeWithContext(code, text, "")
}

func (m *UserModel) contextBoost(previousText, code, text string) int64 {
	if m == nil || previousText == "" {
		return 0
	}
	m.mu.RLock()
	identity := contextIdentity{previous: previousText, candidateIdentity: candidateIdentity{code: code, text: text}}
	count := m.contexts[identity]
	rejections := m.contextRejections[identity]
	m.mu.RUnlock()
	if count > maximumContextSelections {
		count = maximumContextSelections
	}
	return signedLearningBoost(count, rejections, contextBoostPerSelection, contextPenaltyPerRejection)
}

func signedLearningBoost(selections, rejections uint64, selectionWeight, rejectionWeight int64) int64 {
	if selections > uint64(math.MaxInt64/selectionWeight) {
		selections = uint64(math.MaxInt64 / selectionWeight)
	}
	if rejections > maximumRejections {
		rejections = maximumRejections
	}
	return saturatingAdd(int64(selections)*selectionWeight, -int64(rejections)*rejectionWeight)
}

func (m *UserModel) observeWithContext(code, text, previousText string) error {
	return m.observeIdempotent(code, text, previousText, "")
}

func (m *UserModel) observeIdempotent(code, text, previousText, requestID string) error {
	return m.observeBatchIdempotent([]UserObservation{{
		Code: code, Text: text, PreviousText: previousText,
	}}, requestID)
}

func (m *UserModel) observeBatchIdempotent(observations []UserObservation, requestID string) error {
	return m.observeBatchWithRerankerIdempotent(observations, nil, requestID)
}

func (m *UserModel) observeBatchWithRerankerIdempotent(observations []UserObservation, rerankerDelta map[string]int64, requestID string) error {
	if m == nil || len(observations) == 0 {
		return nil
	}
	for _, observation := range observations {
		if observation.Code == "" || observation.Text == "" {
			return nil
		}
	}
	primary := observations[len(observations)-1]
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	m.mu.Lock()
	if existing, found := m.appliedRequests[requestID]; requestID != "" && found {
		requested := UserMutation{Kind: UserMutationSelect, Code: primary.Code, Text: primary.Text,
			PreviousText: primary.PreviousText, Observations: observations, RerankerDelta: rerankerDelta}
		if equivalentSelectionMutation(existing, requested) {
			m.mu.Unlock()
			return nil
		}
		m.mu.Unlock()
		return ErrIdempotencyConflict
	}
	if requestID != "" && len(m.appliedRequests) >= maximumUserModelItems {
		m.mu.Unlock()
		return errors.New("user mutation request ledger is full")
	}
	mutation := UserMutation{Generation: m.generation + 1, Kind: UserMutationSelect,
		Code: primary.Code, Text: primary.Text, PreviousText: primary.PreviousText, RequestID: requestID,
		RerankerDelta: cloneInt64Map(rerankerDelta)}
	if len(observations) > 1 {
		mutation.Observations = append([]UserObservation(nil), observations...)
	}
	writer := m.mutationWriter
	committed := m.mutationCommitted
	m.mu.Unlock()
	if writer != nil {
		if err := writer(mutation); err != nil {
			return err
		}
	}
	m.mu.Lock()
	m.applySelectionMutationLocked(mutation)
	m.generation++
	if requestID != "" {
		m.appliedRequests[requestID] = mutation
	}
	m.mu.Unlock()
	if committed != nil {
		committed()
	}
	return nil
}

// Forget removes all learned preference for one candidate.
func (m *UserModel) Forget(code, text string) bool {
	found, _ := m.ForgetWithError(code, text)
	return found
}

func (m *UserModel) ForgetWithError(code, text string) (bool, error) {
	if m == nil {
		return false, nil
	}
	key := candidateIdentity{code: code, text: text}
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	m.mu.Lock()
	_, selected := m.selections[key]
	_, rejected := m.rejections[key]
	found := selected || rejected
	for contextKey := range m.contexts {
		if contextKey.candidateIdentity == key {
			found = true
		}
	}
	for contextKey := range m.contextRejections {
		if contextKey.candidateIdentity == key {
			found = true
		}
	}
	if found {
		mutation := UserMutation{Generation: m.generation + 1, Kind: UserMutationForget, Code: code, Text: text}
		writer := m.mutationWriter
		committed := m.mutationCommitted
		m.mu.Unlock()
		if writer != nil {
			if err := writer(mutation); err != nil {
				return false, err
			}
		}
		m.mu.Lock()
		delete(m.selections, key)
		delete(m.rejections, key)
		for contextKey := range m.contexts {
			if contextKey.candidateIdentity == key {
				delete(m.contexts, contextKey)
			}
		}
		for contextKey := range m.contextRejections {
			if contextKey.candidateIdentity == key {
				delete(m.contextRejections, contextKey)
			}
		}
		m.generation++
		m.mu.Unlock()
		if committed != nil {
			committed()
		}
		return true, nil
	}
	m.mu.Unlock()
	return found, nil
}

func (m *UserModel) SetMutationWriter(writer func(UserMutation) error) {
	m.SetMutationHooks(writer, nil)
}

// SetMutationHooks installs the durable persist and post-apply boundaries as one
// transaction. The committed hook runs only after the journaled mutation has
// been applied to the in-memory model, so checkpoints cannot publish older state
// and then compact away the only durable mutation record.
func (m *UserModel) SetMutationHooks(writer func(UserMutation) error, committed func()) {
	if m == nil {
		return
	}
	m.mutationMu.Lock()
	m.mu.Lock()
	m.mutationWriter = writer
	m.mutationCommitted = committed
	m.mu.Unlock()
	m.mutationMu.Unlock()
}

func (m *UserModel) SourceID() string {
	if m == nil {
		return ""
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.sourceID
}

func (m *UserModel) Generation() uint64 {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.generation
}

func (m *UserModel) LoadedSchemaVersion() string {
	if m == nil {
		return ""
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.loadedSchema
}

// LearnedRecords returns a stable copy suitable for management and audit tools.
func (m *UserModel) LearnedRecords() []LearnedRecord {
	if m == nil {
		return nil
	}
	m.mu.RLock()
	records := make([]LearnedRecord, 0, len(m.selections))
	for identity, count := range m.selections {
		if count > 0 {
			records = append(records, LearnedRecord{Code: identity.code, Text: identity.text, Selections: count})
		}
	}
	m.mu.RUnlock()
	sort.Slice(records, func(i, j int) bool {
		if records[i].Selections != records[j].Selections {
			return records[i].Selections > records[j].Selections
		}
		if records[i].Text != records[j].Text {
			return records[i].Text < records[j].Text
		}
		return records[i].Code < records[j].Code
	})
	return records
}

func (m *UserModel) ApplyRecoveredMutation(mutation UserMutation) error {
	if m == nil {
		return fmt.Errorf("%w: nil recovered model", ErrCorruptUserModel)
	}
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	m.mu.Lock()
	defer m.mu.Unlock()
	if mutation.Generation != m.generation+1 || mutation.Code == "" || mutation.Text == "" ||
		!validMutationObservations(mutation) {
		return fmt.Errorf("%w: invalid recovered mutation", ErrCorruptUserModel)
	}
	if mutation.RequestID != "" {
		if existing, found := m.appliedRequests[mutation.RequestID]; found &&
			!equivalentSelectionMutation(existing, mutation) {
			return fmt.Errorf("%w: recovered request conflict", ErrCorruptUserModel)
		}
	}
	key := candidateIdentity{code: mutation.Code, text: mutation.Text}
	switch mutation.Kind {
	case UserMutationSelect:
		m.applySelectionMutationLocked(mutation)
	case UserMutationForget:
		if len(mutation.Observations) != 0 {
			return fmt.Errorf("%w: forget mutation contains observations", ErrCorruptUserModel)
		}
		delete(m.selections, key)
		delete(m.rejections, key)
		for contextKey := range m.contexts {
			if contextKey.candidateIdentity == key {
				delete(m.contexts, contextKey)
			}
		}
		for contextKey := range m.contextRejections {
			if contextKey.candidateIdentity == key {
				delete(m.contextRejections, contextKey)
			}
		}
	default:
		return fmt.Errorf("%w: unknown mutation kind", ErrCorruptUserModel)
	}
	if mutation.RequestID != "" {
		m.appliedRequests[mutation.RequestID] = mutation
	}
	m.generation = mutation.Generation
	return nil
}

func (m *UserModel) applySelectionMutationLocked(mutation UserMutation) {
	observations := mutation.Observations
	if len(observations) == 0 {
		observations = []UserObservation{{
			Code: mutation.Code, Text: mutation.Text, PreviousText: mutation.PreviousText,
		}}
	}
	for _, observation := range observations {
		key := candidateIdentity{code: observation.Code, text: observation.Text}
		contextKey := contextIdentity{previous: observation.PreviousText, candidateIdentity: key}
		if observation.Rejected {
			if m.rejections[key] < maximumRejections {
				m.rejections[key]++
			}
			if observation.PreviousText != "" && m.contextRejections[contextKey] < maximumRejections {
				m.contextRejections[contextKey]++
			}
			continue
		}
		if m.selections[key] < maximumSelectionCount {
			m.selections[key]++
		}
		decrementCount(m.rejections, key)
		if observation.PreviousText != "" {
			if m.contexts[contextKey] < maximumContextSelections {
				m.contexts[contextKey]++
			}
			decrementCount(m.contextRejections, contextKey)
		}
	}
	m.applyRerankerDeltaLocked(mutation.RerankerDelta)
}

func decrementCount[Key comparable](counts map[Key]uint64, key Key) {
	if counts[key] <= 1 {
		delete(counts, key)
		return
	}
	counts[key]--
}

func validMutationObservations(mutation UserMutation) bool {
	if !validRerankerDelta(mutation.RerankerDelta) {
		return false
	}
	if mutation.Kind != UserMutationSelect {
		return len(mutation.Observations) == 0 && len(mutation.RerankerDelta) == 0
	}
	for _, observation := range mutation.Observations {
		if observation.Code == "" || observation.Text == "" {
			return false
		}
	}
	if len(mutation.Observations) == 0 {
		return true
	}
	primary := mutation.Observations[len(mutation.Observations)-1]
	return !primary.Rejected && primary.Code == mutation.Code && primary.Text == mutation.Text &&
		primary.PreviousText == mutation.PreviousText
}

func equivalentSelectionMutation(left, right UserMutation) bool {
	if left.Kind != UserMutationSelect || right.Kind != UserMutationSelect ||
		left.Code != right.Code || left.Text != right.Text ||
		!equalInt64Maps(left.RerankerDelta, right.RerankerDelta) {
		return false
	}
	leftObservations := canonicalMutationObservations(left)
	rightObservations := canonicalMutationObservations(right)
	if len(leftObservations) != len(rightObservations) {
		return false
	}
	for index := range leftObservations {
		if leftObservations[index] != rightObservations[index] {
			return false
		}
	}
	return true
}

func canonicalMutationObservations(mutation UserMutation) []UserObservation {
	if len(mutation.Observations) != 0 {
		return mutation.Observations
	}
	return []UserObservation{{
		Code: mutation.Code, Text: mutation.Text, PreviousText: mutation.PreviousText,
	}}
}

// Save writes the current model through a same-directory temporary file and
// an atomic platform replace. The model must have been opened from a path.
func (m *UserModel) Save() error {
	if m == nil || m.path == "" {
		return fmt.Errorf("user model has no persistence path")
	}
	return m.writeSnapshot(m.path)
}

// SaveTo writes a deterministic snapshot to an explicit path, suitable for
// backup without changing the model's primary path.
func (m *UserModel) SaveTo(path string) error {
	if m == nil || strings.TrimSpace(path) == "" {
		return fmt.Errorf("user model backup path is required")
	}
	return m.writeSnapshot(filepath.Clean(path))
}

// SaveVersion1To writes the E5-F-compatible schema for rollback from later schemas.
func (m *UserModel) SaveVersion1To(path string) error {
	if m == nil || strings.TrimSpace(path) == "" {
		return fmt.Errorf("user model rollback path is required")
	}
	return m.writeSnapshotVersion(filepath.Clean(path), userModelSchemaVersion1)
}

// Restore validates a backup against this model's source identity, publishes
// it atomically to the primary path, and only then updates in-memory state.
func (m *UserModel) Restore(backupPath string) error {
	if m == nil || m.path == "" {
		return fmt.Errorf("user model has no persistence path")
	}
	m.mutationMu.Lock()
	defer m.mutationMu.Unlock()
	payload, err := readUserModelFile(backupPath, m.sourceID)
	if err != nil {
		return err
	}
	selections, err := decodeSelectionCounts(payload.Selections)
	if err != nil {
		return err
	}
	contexts, err := decodeContextCounts(payload.Contexts)
	if err != nil {
		return err
	}
	rejections, err := decodeSelectionCounts(payload.Rejections)
	if err != nil {
		return err
	}
	contextRejections, err := decodeContextCounts(payload.ContextRejections)
	if err != nil {
		return err
	}
	rerankerWeights := cloneInt64Map(payload.RerankerWeights)
	payload.SchemaVersion = userModelSchemaVersion
	if err := writeUserModelFile(m.path, payload); err != nil {
		return err
	}
	m.mu.Lock()
	m.generation = payload.Generation
	m.selections = selections
	m.contexts = contexts
	m.rejections = rejections
	m.contextRejections = contextRejections
	m.rerankerWeights = rerankerWeights
	m.appliedRequests = cloneMutations(payload.AppliedRequests)
	m.loadedSchema = userModelSchemaVersion
	m.mu.Unlock()
	return nil
}

func (m *UserModel) writeSnapshot(path string) error {
	return m.writeSnapshotVersion(path, userModelSchemaVersion)
}

func (m *UserModel) writeSnapshotVersion(path, schemaVersion string) error {
	if schemaVersion != userModelSchemaVersion1 && schemaVersion != userModelSchemaVersion2 &&
		schemaVersion != userModelSchemaVersion3 && schemaVersion != userModelSchemaVersion4 {
		return fmt.Errorf("unsupported user model schema %q", schemaVersion)
	}
	m.mu.RLock()
	payload := userModelPayload{
		SchemaVersion:   schemaVersion,
		SourceID:        m.sourceID,
		Generation:      m.generation,
		Selections:      encodeSelectionCounts(m.selections),
		Contexts:        encodeContextCounts(m.contexts),
		AppliedRequests: cloneMutations(m.appliedRequests),
	}
	if schemaVersion == userModelSchemaVersion3 || schemaVersion == userModelSchemaVersion4 {
		payload.Rejections = encodeSelectionCounts(m.rejections)
		payload.ContextRejections = encodeContextCounts(m.contextRejections)
		payload.RerankerWeights = cloneInt64Map(m.rerankerWeights)
	} else {
		for requestID, mutation := range payload.AppliedRequests {
			mutation.Observations = nil
			mutation.RerankerDelta = nil
			payload.AppliedRequests[requestID] = mutation
		}
	}
	m.mu.RUnlock()
	if err := writeUserModelFile(path, payload); err != nil {
		return err
	}
	if path == m.path && schemaVersion == userModelSchemaVersion {
		m.mu.Lock()
		m.loadedSchema = schemaVersion
		m.mu.Unlock()
	}
	return nil
}

func writeUserModelFile(path string, payload userModelPayload) error {
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	digest := sha256.Sum256(payloadBytes)
	file := userModelFile{userModelPayload: payload, PayloadSHA256: hex.EncodeToString(digest[:])}
	data, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".yime-user-model-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	removeTemporary := true
	defer func() {
		if removeTemporary {
			_ = os.Remove(temporaryPath)
		}
	}()
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := replaceFileAtomically(temporaryPath, path); err != nil {
		return err
	}
	removeTemporary = false
	return nil
}

func readUserModelFile(path, sourceID string) (userModelPayload, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return userModelPayload{}, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var file userModelFile
	if err := decoder.Decode(&file); err != nil {
		return userModelPayload{}, fmt.Errorf("%w: decode: %v", ErrCorruptUserModel, err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return userModelPayload{}, fmt.Errorf("%w: %v", ErrCorruptUserModel, err)
	}
	if (file.SchemaVersion != userModelSchemaVersion1 && file.SchemaVersion != userModelSchemaVersion2 &&
		file.SchemaVersion != userModelSchemaVersion3 && file.SchemaVersion != userModelSchemaVersion4) || file.SourceID != sourceID ||
		len(file.Selections)+len(file.Contexts)+len(file.Rejections)+len(file.ContextRejections)+len(file.RerankerWeights)+len(file.AppliedRequests) > maximumUserModelItems {
		return userModelPayload{}, fmt.Errorf("%w: schema, source identity or item count mismatch", ErrCorruptUserModel)
	}
	if file.SchemaVersion != userModelSchemaVersion3 && file.SchemaVersion != userModelSchemaVersion4 &&
		(len(file.Rejections) != 0 || len(file.ContextRejections) != 0 || len(file.RerankerWeights) != 0) {
		return userModelPayload{}, fmt.Errorf("%w: legacy schema contains v3 fields", ErrCorruptUserModel)
	}
	if file.SchemaVersion != userModelSchemaVersion3 && file.SchemaVersion != userModelSchemaVersion4 {
		for _, mutation := range file.AppliedRequests {
			if len(mutation.Observations) != 0 || len(mutation.RerankerDelta) != 0 {
				return userModelPayload{}, fmt.Errorf("%w: legacy schema contains extended mutation", ErrCorruptUserModel)
			}
		}
	}
	for key, count := range file.Selections {
		if key == "" || count > maximumSelectionCount {
			return userModelPayload{}, fmt.Errorf("%w: invalid selection record", ErrCorruptUserModel)
		}
	}
	for key, count := range file.Contexts {
		if key == "" || count > maximumSelectionCount {
			return userModelPayload{}, fmt.Errorf("%w: invalid context record", ErrCorruptUserModel)
		}
	}
	for key, count := range file.Rejections {
		if key == "" || count > maximumRejections {
			return userModelPayload{}, fmt.Errorf("%w: invalid rejection record", ErrCorruptUserModel)
		}
	}
	for key, count := range file.ContextRejections {
		if key == "" || count > maximumRejections {
			return userModelPayload{}, fmt.Errorf("%w: invalid context rejection record", ErrCorruptUserModel)
		}
	}
	for feature, weight := range file.RerankerWeights {
		if feature == "" || weight == 0 || weight > maximumRerankerWeight || weight < -maximumRerankerWeight {
			return userModelPayload{}, fmt.Errorf("%w: invalid reranker weight", ErrCorruptUserModel)
		}
	}
	for requestID, mutation := range file.AppliedRequests {
		if requestID == "" || mutation.RequestID != requestID || mutation.Generation == 0 ||
			mutation.Kind == "" || mutation.Code == "" || mutation.Text == "" ||
			!validMutationObservations(mutation) {
			return userModelPayload{}, fmt.Errorf("%w: invalid applied request", ErrCorruptUserModel)
		}
	}
	payload := file.userModelPayload
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return userModelPayload{}, err
	}
	digest := sha256.Sum256(payloadBytes)
	if file.PayloadSHA256 != hex.EncodeToString(digest[:]) {
		return userModelPayload{}, fmt.Errorf("%w: payload hash mismatch", ErrCorruptUserModel)
	}
	return payload, nil
}

func cloneMutations(source map[string]UserMutation) map[string]UserMutation {
	result := make(map[string]UserMutation, len(source))
	for key, mutation := range source {
		mutation.Observations = append([]UserObservation(nil), mutation.Observations...)
		mutation.RerankerDelta = cloneInt64Map(mutation.RerankerDelta)
		result[key] = mutation
	}
	return result
}

func cloneInt64Map(source map[string]int64) map[string]int64 {
	if len(source) == 0 {
		return nil
	}
	result := make(map[string]int64, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}

func equalInt64Maps(left, right map[string]int64) bool {
	if len(left) != len(right) {
		return false
	}
	for key, value := range left {
		if right[key] != value {
			return false
		}
	}
	return true
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return fmt.Errorf("trailing JSON value")
		}
		return err
	}
	return nil
}

func encodeSelectionCounts(source map[candidateIdentity]uint64) map[string]uint64 {
	result := make(map[string]uint64, len(source))
	for key, count := range source {
		result[key.code+"\x1f"+key.text] = count
	}
	return result
}

func encodeContextCounts(source map[contextIdentity]uint64) map[string]uint64 {
	result := make(map[string]uint64, len(source))
	for key, count := range source {
		result[key.previous+"\x1e"+key.code+"\x1f"+key.text] = count
	}
	return result
}

func decodeSelectionCounts(source map[string]uint64) (map[candidateIdentity]uint64, error) {
	result := make(map[candidateIdentity]uint64, len(source))
	for key, count := range source {
		parts := strings.SplitN(key, "\x1f", 2)
		if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
			return nil, fmt.Errorf("%w: invalid candidate identity", ErrCorruptUserModel)
		}
		result[candidateIdentity{code: parts[0], text: parts[1]}] = count
	}
	return result, nil
}

func decodeContextCounts(source map[string]uint64) (map[contextIdentity]uint64, error) {
	result := make(map[contextIdentity]uint64, len(source))
	for key, count := range source {
		contextParts := strings.SplitN(key, "\x1e", 2)
		if len(contextParts) != 2 || contextParts[0] == "" {
			return nil, fmt.Errorf("%w: invalid context identity", ErrCorruptUserModel)
		}
		candidateParts := strings.SplitN(contextParts[1], "\x1f", 2)
		if len(candidateParts) != 2 || candidateParts[0] == "" || candidateParts[1] == "" {
			return nil, fmt.Errorf("%w: invalid context candidate identity", ErrCorruptUserModel)
		}
		identity := contextIdentity{previous: contextParts[0], candidateIdentity: candidateIdentity{code: candidateParts[0], text: candidateParts[1]}}
		result[identity] = count
	}
	return result, nil
}
