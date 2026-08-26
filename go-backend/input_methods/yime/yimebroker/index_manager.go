package yimebroker

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type IndexSpec struct {
	Version        string `json:"version"`
	Mode           string `json:"mode"`
	Path           string `json:"path"`
	ExpectedSHA256 string `json:"expected_sha256"`
}

type IndexEngineBuilder func(*yimecore.FileIndex) (engineapi.Engine, error)
type IndexValidator func(engineapi.Engine) error

type IndexManagerStats struct {
	ActiveVersion   string `json:"active_version"`
	ActiveSourceID  string `json:"active_source_id"`
	ActiveSHA256    string `json:"active_sha256"`
	PreviousVersion string `json:"previous_version,omitempty"`
	ActiveSessions  int    `json:"active_sessions"`
	Switches        uint64 `json:"switches"`
	Rollbacks       uint64 `json:"rollbacks"`
	Rejected        uint64 `json:"rejected"`
	LoadMode        string `json:"load_mode"`
}

type indexGeneration struct {
	spec     IndexSpec
	index    *yimecore.FileIndex
	sourceID string
	refs     int
	closed   bool
}

type IndexManager struct {
	mu        sync.Mutex
	builder   IndexEngineBuilder
	validator IndexValidator
	active    *indexGeneration
	previous  *indexGeneration
	retired   map[*indexGeneration]struct{}
	closed    bool
	stats     IndexManagerStats
	resident  bool
}

type managedEngine struct {
	engine     engineapi.Engine
	manager    *IndexManager
	generation *indexGeneration
	closeOnce  sync.Once
}

func OpenIndexManager(initial IndexSpec, builder IndexEngineBuilder, validator IndexValidator) (*IndexManager, error) {
	return openIndexManager(initial, builder, validator, false)
}

// OpenResidentIndexManager keeps every accepted index generation fully loaded
// in process memory. Swaps and rollbacks retain the same loading policy.
func OpenResidentIndexManager(initial IndexSpec, builder IndexEngineBuilder, validator IndexValidator) (*IndexManager, error) {
	return openIndexManager(initial, builder, validator, true)
}

func openIndexManager(initial IndexSpec, builder IndexEngineBuilder, validator IndexValidator, resident bool) (*IndexManager, error) {
	if builder == nil {
		builder = func(index *yimecore.FileIndex) (engineapi.Engine, error) { return yimecore.NewFileEngine(index, 9) }
	}
	manager := &IndexManager{builder: builder, validator: validator, retired: make(map[*indexGeneration]struct{}), resident: resident}
	generation, err := manager.load(initial)
	if err != nil {
		return nil, err
	}
	manager.active = generation
	manager.updateStatsLocked()
	return manager, nil
}

func (m *IndexManager) NewEngine() (engineapi.Engine, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed || m.active == nil {
		return nil, errors.New("index manager is closed")
	}
	engine, err := m.builder(m.active.index)
	if err != nil {
		return nil, err
	}
	m.active.refs++
	m.updateStatsLocked()
	return &managedEngine{engine: engine, manager: m, generation: m.active}, nil
}

func (m *IndexManager) Swap(spec IndexSpec) error {
	generation, err := m.load(spec)
	if err != nil {
		m.mu.Lock()
		m.stats.Rejected++
		m.mu.Unlock()
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		_ = generation.index.Close()
		return errors.New("index manager is closed")
	}
	if m.active != nil && generation.spec.Version == m.active.spec.Version {
		_ = generation.index.Close()
		m.stats.Rejected++
		return errors.New("index version is already active")
	}
	oldPrevious := m.previous
	m.previous = m.active
	m.active = generation
	m.stats.Switches++
	if oldPrevious != nil {
		m.retired[oldPrevious] = struct{}{}
		m.closeIfUnusedLocked(oldPrevious)
	}
	m.updateStatsLocked()
	return nil
}

func (m *IndexManager) Rollback() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed || m.previous == nil {
		return errors.New("no previous index generation is available")
	}
	m.active, m.previous = m.previous, m.active
	m.stats.Rollbacks++
	m.updateStatsLocked()
	return nil
}

func (m *IndexManager) Stats() IndexManagerStats {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.updateStatsLocked()
	return m.stats
}

func (m *IndexManager) Close() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return nil
	}
	m.closed = true
	generations := []*indexGeneration{m.active, m.previous}
	m.active = nil
	m.previous = nil
	for _, generation := range generations {
		if generation != nil {
			m.retired[generation] = struct{}{}
			m.closeIfUnusedLocked(generation)
		}
	}
	return nil
}

func (m *IndexManager) load(spec IndexSpec) (*indexGeneration, error) {
	if strings.TrimSpace(spec.Version) == "" || strings.TrimSpace(spec.Mode) == "" || strings.TrimSpace(spec.Path) == "" || len(spec.ExpectedSHA256) != 64 {
		return nil, errors.New("index version, mode, path and SHA-256 are required")
	}
	actualHash, err := hashIndexFile(spec.Path)
	if err != nil {
		return nil, err
	}
	if !strings.EqualFold(actualHash, spec.ExpectedSHA256) {
		return nil, fmt.Errorf("index SHA-256 mismatch: expected %s, got %s", spec.ExpectedSHA256, actualHash)
	}
	var index *yimecore.FileIndex
	if m.resident {
		index, err = yimecore.OpenResidentFileIndex(spec.Path)
	} else {
		index, err = yimecore.OpenFileIndex(spec.Path)
	}
	if err != nil {
		return nil, err
	}
	if index.Mode() != spec.Mode {
		_ = index.Close()
		return nil, fmt.Errorf("index mode %q does not match %q", index.Mode(), spec.Mode)
	}
	openedHash, err := hashIndexFile(spec.Path)
	if err != nil || !strings.EqualFold(openedHash, spec.ExpectedSHA256) {
		_ = index.Close()
		if err != nil {
			return nil, err
		}
		return nil, errors.New("index changed while it was being opened")
	}
	if m.validator != nil {
		engine, buildErr := m.builder(index)
		if buildErr != nil {
			_ = index.Close()
			return nil, buildErr
		}
		if validateErr := m.validator(engine); validateErr != nil {
			if closer, ok := engine.(interface{ Close() error }); ok {
				_ = closer.Close()
			}
			_ = index.Close()
			return nil, fmt.Errorf("index validation failed: %w", validateErr)
		}
		if closer, ok := engine.(interface{ Close() error }); ok {
			_ = closer.Close()
		}
	}
	spec.Path = filepath.Clean(spec.Path)
	spec.ExpectedSHA256 = strings.ToLower(actualHash)
	return &indexGeneration{spec: spec, index: index, sourceID: index.SourceID()}, nil
}

func (m *IndexManager) release(generation *indexGeneration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if generation.refs > 0 {
		generation.refs--
	}
	m.closeIfUnusedLocked(generation)
	m.updateStatsLocked()
}

func (m *IndexManager) closeIfUnusedLocked(generation *indexGeneration) {
	if generation == nil || generation.closed || generation.refs != 0 {
		return
	}
	if generation == m.active || generation == m.previous {
		return
	}
	_ = generation.index.Close()
	generation.closed = true
	delete(m.retired, generation)
}

func (m *IndexManager) updateStatsLocked() {
	m.stats.ActiveVersion = ""
	m.stats.ActiveSourceID = ""
	m.stats.ActiveSHA256 = ""
	m.stats.PreviousVersion = ""
	m.stats.ActiveSessions = 0
	if m.resident {
		m.stats.LoadMode = "resident"
	} else {
		m.stats.LoadMode = "mapped"
	}
	if m.active != nil {
		m.stats.ActiveVersion = m.active.spec.Version
		m.stats.ActiveSourceID = m.active.sourceID
		m.stats.ActiveSHA256 = m.active.spec.ExpectedSHA256
		m.stats.ActiveSessions += m.active.refs
	}
	if m.previous != nil {
		m.stats.PreviousVersion = m.previous.spec.Version
		m.stats.ActiveSessions += m.previous.refs
	}
	for generation := range m.retired {
		m.stats.ActiveSessions += generation.refs
	}
}

func (e *managedEngine) Apply(event engineapi.Event) (engineapi.Result, error) {
	return e.engine.Apply(event)
}

func (e *managedEngine) Select(candidateID string) (engineapi.Result, error) {
	return e.engine.Select(candidateID)
}

func (e *managedEngine) SelectIdempotent(candidateID, mutationID string) (engineapi.Result, error) {
	if selector, ok := e.engine.(interface {
		SelectIdempotent(string, string) (engineapi.Result, error)
	}); ok {
		return selector.SelectIdempotent(candidateID, mutationID)
	}
	return engineapi.Result{}, errors.New("managed engine does not support idempotent selection")
}

func (e *managedEngine) ForgetCandidate(candidateID string) (engineapi.Result, error) {
	if forgetter, ok := e.engine.(engineapi.CandidateForgetter); ok {
		return forgetter.ForgetCandidate(candidateID)
	}
	return engineapi.Result{}, errors.New("managed engine does not support candidate forgetting")
}

func (e *managedEngine) Reset() engineapi.Result { return e.engine.Reset() }

func (e *managedEngine) Close() error {
	e.closeOnce.Do(func() {
		if closer, ok := e.engine.(interface{ Close() error }); ok {
			_ = closer.Close()
		}
		e.manager.release(e.generation)
	})
	return nil
}

func (e *managedEngine) IndexVersion() string { return e.generation.spec.Version }

func hashIndexFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

// IndexFileSHA256 returns the hash used by transactional index specifications.
func IndexFileSHA256(path string) (string, error) { return hashIndexFile(path) }
