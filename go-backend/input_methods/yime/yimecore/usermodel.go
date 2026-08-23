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
	"strings"
	"sync"
)

const (
	userModelSchemaVersion   = "yime-user-model-v1"
	userBoostPerSelection    = int64(1_000_000_000_000)
	contextBoostPerSelection = int64(500_000_000_000)
	maximumUserModelItems    = 1_000_000
	maximumSelectionCount    = uint64(1_000_000_000)
)

var ErrCorruptUserModel = errors.New("corrupt Yime user model")

// UserModel is an independent, session-shareable selection-frequency model.
// It never mutates the static index and performs no I/O on the key path.
type UserModel struct {
	mu         sync.RWMutex
	path       string
	sourceID   string
	generation uint64
	selections map[candidateIdentity]uint64
	contexts   map[contextIdentity]uint64
}

type candidateIdentity struct {
	code string
	text string
}

type contextIdentity struct {
	previous string
	candidateIdentity
}

type userModelPayload struct {
	SchemaVersion string            `json:"schema_version"`
	SourceID      string            `json:"source_id"`
	Generation    uint64            `json:"generation"`
	Selections    map[string]uint64 `json:"selections"`
	Contexts      map[string]uint64 `json:"contexts,omitempty"`
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
	return &UserModel{sourceID: sourceID, selections: make(map[candidateIdentity]uint64), contexts: make(map[contextIdentity]uint64)}, nil
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
	return model, nil
}

func (m *UserModel) candidateBoost(code, text string) int64 {
	if m == nil {
		return 0
	}
	m.mu.RLock()
	count := m.selections[candidateIdentity{code: code, text: text}]
	m.mu.RUnlock()
	if count > uint64(math.MaxInt64/userBoostPerSelection) {
		return math.MaxInt64
	}
	return int64(count) * userBoostPerSelection
}

func (m *UserModel) observe(code, text string) {
	m.observeWithContext(code, text, "")
}

func (m *UserModel) contextBoost(previousText, code, text string) int64 {
	if m == nil || previousText == "" {
		return 0
	}
	m.mu.RLock()
	count := m.contexts[contextIdentity{previous: previousText, candidateIdentity: candidateIdentity{code: code, text: text}}]
	m.mu.RUnlock()
	if count > uint64(math.MaxInt64/contextBoostPerSelection) {
		return math.MaxInt64
	}
	return int64(count) * contextBoostPerSelection
}

func (m *UserModel) observeWithContext(code, text, previousText string) {
	if m == nil || code == "" || text == "" {
		return
	}
	key := candidateIdentity{code: code, text: text}
	m.mu.Lock()
	if m.selections[key] < maximumSelectionCount {
		m.selections[key]++
	}
	if previousText != "" {
		contextKey := contextIdentity{previous: previousText, candidateIdentity: key}
		if m.contexts[contextKey] < maximumSelectionCount {
			m.contexts[contextKey]++
		}
	}
	m.generation++
	m.mu.Unlock()
}

// Forget removes all learned preference for one candidate.
func (m *UserModel) Forget(code, text string) bool {
	if m == nil {
		return false
	}
	key := candidateIdentity{code: code, text: text}
	m.mu.Lock()
	_, found := m.selections[key]
	if found {
		delete(m.selections, key)
		for contextKey := range m.contexts {
			if contextKey.candidateIdentity == key {
				delete(m.contexts, contextKey)
			}
		}
		m.generation++
	}
	m.mu.Unlock()
	return found
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

// Restore validates a backup against this model's source identity, publishes
// it atomically to the primary path, and only then updates in-memory state.
func (m *UserModel) Restore(backupPath string) error {
	if m == nil || m.path == "" {
		return fmt.Errorf("user model has no persistence path")
	}
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
	if err := writeUserModelFile(m.path, payload); err != nil {
		return err
	}
	m.mu.Lock()
	m.generation = payload.Generation
	m.selections = selections
	m.contexts = contexts
	m.mu.Unlock()
	return nil
}

func (m *UserModel) writeSnapshot(path string) error {
	m.mu.RLock()
	payload := userModelPayload{
		SchemaVersion: userModelSchemaVersion,
		SourceID:      m.sourceID,
		Generation:    m.generation,
		Selections:    encodeSelectionCounts(m.selections),
		Contexts:      encodeContextCounts(m.contexts),
	}
	m.mu.RUnlock()
	return writeUserModelFile(path, payload)
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
	if file.SchemaVersion != userModelSchemaVersion || file.SourceID != sourceID || len(file.Selections)+len(file.Contexts) > maximumUserModelItems {
		return userModelPayload{}, fmt.Errorf("%w: schema, source identity or item count mismatch", ErrCorruptUserModel)
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
