package yimebroker

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// BundleGenerationSpec describes one complete, explicit three-mode generation.
// Every contained IndexSpec.Version must equal Version. An absent module list
// means core only; this manager never discovers or enables modules implicitly.
type BundleGenerationSpec struct {
	Version string                    `json:"version"`
	Modes   map[string]BundleModeSpec `json:"modes"`
}

type BundleModeSpec struct {
	Core    IndexSpec          `json:"core"`
	Modules []BundleModuleSpec `json:"modules,omitempty"`
}

type BundleModuleSpec struct {
	ID    string    `json:"id"`
	Index IndexSpec `json:"index"`
}

type BundleEngineBuilder func(mode string, bundle *yimecore.BundleIndex) (engineapi.Engine, error)

type BundleGenerationStats struct {
	ActiveVersion      string            `json:"active_version"`
	ActiveSourceIDs    map[string]string `json:"active_source_ids"`
	ActiveSessions     int               `json:"active_sessions"`
	RetiredGenerations int               `json:"retired_generations"`
	Switches           uint64            `json:"switches"`
	Rejected           uint64            `json:"rejected"`
	Closed             bool              `json:"closed"`
	LoadMode           string            `json:"load_mode"`
}

type bundleGeneration struct {
	version string
	root    string
	bundles map[string]*yimecore.BundleIndex
	indexes []*yimecore.FileIndex
	refs    int
	closed  bool
}

// BundleGenerationManager atomically publishes core AND module indexes for all
// three modes. Staging uses private, hash-verified copies and resident indexes.
// Leased sessions pin their exact generation until their own Close, including
// after a swap or manager Close. It owns no user data or transport connections.
// Callers must admit semantic/provenance records before constructing this spec;
// an allowed module name alone is not evidence of linguistic admission.
type BundleGenerationManager struct {
	mu        sync.Mutex
	builder   BundleEngineBuilder
	validator IndexValidator
	active    *bundleGeneration
	retired   map[*bundleGeneration]struct{}
	versions  map[string]struct{}
	closed    bool
	switches  uint64
	rejected  uint64
}

func OpenBundleGenerationManager(initial BundleGenerationSpec, builder BundleEngineBuilder, validator IndexValidator) (*BundleGenerationManager, error) {
	if builder == nil {
		builder = func(_ string, bundle *yimecore.BundleIndex) (engineapi.Engine, error) {
			return yimecore.NewBundleEngine(bundle, 9)
		}
	}
	m := &BundleGenerationManager{builder: builder, validator: validator, retired: make(map[*bundleGeneration]struct{}), versions: make(map[string]struct{})}
	g, err := m.stage(initial)
	if err != nil {
		return nil, err
	}
	m.active = g
	m.versions[g.version] = struct{}{}
	return m, nil
}

func (m *BundleGenerationManager) NewEngine(mode string) (engineapi.Engine, error) {
	if m == nil {
		return nil, errors.New("bundle generation manager is required")
	}
	m.mu.Lock()
	if m.closed || m.active == nil {
		m.mu.Unlock()
		return nil, errors.New("bundle generation manager is closed")
	}
	g := m.active
	bundle, ok := g.bundles[mode]
	if !ok {
		m.mu.Unlock()
		return nil, fmt.Errorf("unsupported bundle mode %q", mode)
	}
	g.refs++
	m.mu.Unlock()
	engine, err := m.builder(mode, bundle)
	if err != nil || engine == nil {
		if engine != nil {
			_ = closeBundleEngine(engine)
		}
		m.release(g)
		if err == nil {
			err = errors.New("bundle builder returned a nil engine")
		}
		return nil, err
	}
	return &bundleManagedEngine{engine: engine, manager: m, generation: g, sourceID: bundle.SourceID()}, nil
}

func (m *BundleGenerationManager) Swap(spec BundleGenerationSpec) error {
	if m == nil {
		return errors.New("bundle generation manager is required")
	}
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return errors.New("bundle generation manager is closed")
	}
	if _, exists := m.versions[spec.Version]; exists {
		m.rejected++
		m.mu.Unlock()
		return errors.New("bundle generation version was already published")
	}
	m.mu.Unlock()
	g, err := m.stage(spec)
	if err != nil {
		m.mu.Lock()
		m.rejected++
		m.mu.Unlock()
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		_ = g.close()
		return errors.New("bundle generation manager is closed")
	}
	if _, exists := m.versions[g.version]; exists {
		_ = g.close()
		m.rejected++
		return errors.New("bundle generation version was concurrently published")
	}
	old := m.active
	m.active = g
	m.versions[g.version] = struct{}{}
	m.switches++
	if old != nil {
		m.retired[old] = struct{}{}
		m.closeUnusedLocked(old)
	}
	return nil
}

func (m *BundleGenerationManager) Stats() BundleGenerationStats {
	stats := BundleGenerationStats{ActiveSourceIDs: make(map[string]string), LoadMode: "resident"}
	if m == nil {
		return stats
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	stats.Switches, stats.Rejected, stats.Closed = m.switches, m.rejected, m.closed
	if m.active != nil {
		stats.ActiveVersion = m.active.version
		stats.ActiveSessions += m.active.refs
		for mode, bundle := range m.active.bundles {
			stats.ActiveSourceIDs[mode] = bundle.SourceID()
		}
	}
	stats.RetiredGenerations = len(m.retired)
	for g := range m.retired {
		stats.ActiveSessions += g.refs
	}
	return stats
}

func (m *BundleGenerationManager) Close() error {
	if m == nil {
		return nil
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return nil
	}
	m.closed = true
	if m.active != nil {
		g := m.active
		m.active = nil
		m.retired[g] = struct{}{}
		m.closeUnusedLocked(g)
	}
	return nil
}

func validateBundleGenerationSpec(spec BundleGenerationSpec) error {
	if spec.Version == "" || strings.TrimSpace(spec.Version) != spec.Version || strings.ContainsAny(spec.Version, "\x00\r\n\t") {
		return errors.New("bundle generation version is required and must be canonical")
	}
	if len(spec.Modes) != len(supportedIndexModes) {
		return errors.New("exactly full, variable and shorthand bundle modes are required")
	}
	allowed := map[string]bool{"psc-peripheral": true, "explicit-erhua": true, "third-tone-stage5c": true, "particle-a-stage6d": true}
	var expectedIDs []string
	for position, mode := range supportedIndexModes {
		modeSpec, ok := spec.Modes[mode]
		if !ok {
			return fmt.Errorf("bundle mode %q is required", mode)
		}
		if err := validateBundleIndexSpec(modeSpec.Core, spec.Version, mode); err != nil {
			return fmt.Errorf("%s core: %w", mode, err)
		}
		seen := make(map[string]bool)
		ids := make([]string, 0, len(modeSpec.Modules))
		for _, module := range modeSpec.Modules {
			if !allowed[module.ID] || seen[module.ID] {
				return fmt.Errorf("%s has unknown or duplicate module %q", mode, module.ID)
			}
			seen[module.ID] = true
			ids = append(ids, module.ID)
			if err := validateBundleIndexSpec(module.Index, spec.Version, mode); err != nil {
				return fmt.Errorf("%s module %s: %w", mode, module.ID, err)
			}
		}
		sort.Strings(ids)
		if position == 0 {
			expectedIDs = ids
		} else if strings.Join(ids, "\x00") != strings.Join(expectedIDs, "\x00") {
			return errors.New("enabled module sets must match across all three modes")
		}
	}
	return nil
}

func validateBundleIndexSpec(spec IndexSpec, version, mode string) error {
	if spec.Version != version || spec.Mode != mode {
		return errors.New("index generation version and mode must match the complete bundle")
	}
	if !filepath.IsAbs(spec.Path) || strings.TrimSpace(spec.Path) != spec.Path {
		return errors.New("an explicit absolute index path is required")
	}
	digest, err := hex.DecodeString(spec.ExpectedSHA256)
	if err != nil || len(digest) != sha256.Size {
		return errors.New("an exact SHA-256 is required")
	}
	return nil
}

func (m *BundleGenerationManager) stage(spec BundleGenerationSpec) (_ *bundleGeneration, err error) {
	// Retain no caller-owned maps or slices, including across builder callbacks.
	// As with ordinary Go maps, callers must not mutate during this copy itself.
	spec = cloneBundleGenerationSpec(spec)
	if err := validateBundleGenerationSpec(spec); err != nil {
		return nil, err
	}
	root, err := os.MkdirTemp("", "yime-bundle-generation-")
	if err != nil {
		return nil, err
	}
	g := &bundleGeneration{version: spec.Version, root: root, bundles: make(map[string]*yimecore.BundleIndex)}
	defer func() {
		if err != nil {
			_ = g.close()
		}
	}()
	for _, mode := range supportedIndexModes {
		modeSpec := spec.Modes[mode]
		core, openErr := g.stageIndex(modeSpec.Core, mode+"-core.yidx")
		if openErr != nil {
			return nil, fmt.Errorf("stage %s core: %w", mode, openErr)
		}
		modules := make([]yimecore.BundleModule, 0, len(modeSpec.Modules))
		for _, module := range modeSpec.Modules {
			index, openErr := g.stageIndex(module.Index, mode+"-"+module.ID+".yidx")
			if openErr != nil {
				return nil, fmt.Errorf("stage %s module %s: %w", mode, module.ID, openErr)
			}
			modules = append(modules, yimecore.BundleModule{ID: module.ID, Index: index})
		}
		bundle, buildErr := yimecore.NewBundleIndex(core, modules)
		if buildErr != nil {
			return nil, buildErr
		}
		g.bundles[mode] = bundle
	}
	// Builders and validators run only after every file is staged. Nothing is
	// published if even the last mode fails either construction or validation.
	for _, mode := range supportedIndexModes {
		engine, buildErr := m.builder(mode, g.bundles[mode])
		if buildErr != nil || engine == nil {
			if engine != nil {
				_ = closeBundleEngine(engine)
			}
			if buildErr == nil {
				buildErr = errors.New("bundle builder returned a nil engine")
			}
			return nil, fmt.Errorf("stage %s engine: %w", mode, buildErr)
		}
		var validationErr error
		if m.validator != nil {
			validationErr = m.validator(engine)
		}
		closeErr := closeBundleEngine(engine)
		if validationErr != nil || closeErr != nil {
			return nil, fmt.Errorf("stage %s validation: %w", mode, errors.Join(validationErr, closeErr))
		}
	}
	return g, nil
}

func cloneBundleGenerationSpec(spec BundleGenerationSpec) BundleGenerationSpec {
	copySpec := BundleGenerationSpec{Version: spec.Version, Modes: make(map[string]BundleModeSpec, len(spec.Modes))}
	for mode, modeSpec := range spec.Modes {
		modeSpec.Modules = append([]BundleModuleSpec(nil), modeSpec.Modules...)
		copySpec.Modes[mode] = modeSpec
	}
	return copySpec
}

func (g *bundleGeneration) stageIndex(spec IndexSpec, name string) (*yimecore.FileIndex, error) {
	source, err := os.Open(spec.Path)
	if err != nil {
		return nil, err
	}
	defer source.Close()
	info, err := source.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return nil, errors.New("index source must be a regular file")
	}
	path := filepath.Join(g.root, name)
	copyFile, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return nil, err
	}
	digest := sha256.New()
	_, copyErr := io.Copy(io.MultiWriter(copyFile, digest), source)
	closeErr := copyFile.Close()
	if copyErr != nil || closeErr != nil {
		return nil, errors.Join(copyErr, closeErr)
	}
	if !strings.EqualFold(hex.EncodeToString(digest.Sum(nil)), spec.ExpectedSHA256) {
		return nil, errors.New("index SHA-256 does not match the staged bytes")
	}
	index, err := yimecore.OpenResidentFileIndex(path)
	if err != nil {
		return nil, err
	}
	g.indexes = append(g.indexes, index)
	if index.Mode() != spec.Mode {
		return nil, errors.New("staged index mode does not match its specification")
	}
	return index, nil
}

func (g *bundleGeneration) close() error {
	if g.closed {
		return nil
	}
	g.closed = true
	var err error
	for _, index := range g.indexes {
		err = errors.Join(err, index.Close())
	}
	// root is exclusively the exact directory returned by MkdirTemp above,
	// never a caller-supplied path or source directory.
	err = errors.Join(err, os.RemoveAll(g.root))
	return err
}

func (m *BundleGenerationManager) release(g *bundleGeneration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if g.refs > 0 {
		g.refs--
	}
	m.closeUnusedLocked(g)
}

func (m *BundleGenerationManager) closeUnusedLocked(g *bundleGeneration) {
	if g != nil && g != m.active && g.refs == 0 {
		_ = g.close()
		delete(m.retired, g)
	}
}

func closeBundleEngine(engine engineapi.Engine) error {
	if closer, ok := engine.(interface{ Close() error }); ok {
		return closer.Close()
	}
	return nil
}

type bundleManagedEngine struct {
	mu         sync.Mutex
	engine     engineapi.Engine
	manager    *BundleGenerationManager
	generation *bundleGeneration
	sourceID   string
	closed     bool
}

func (e *bundleManagedEngine) Apply(event engineapi.Event) (engineapi.Result, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return engineapi.Result{}, errors.New("bundle engine is closed")
	}
	return e.engine.Apply(event)
}

func (e *bundleManagedEngine) Select(id string) (engineapi.Result, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return engineapi.Result{}, errors.New("bundle engine is closed")
	}
	return e.engine.Select(id)
}

func (e *bundleManagedEngine) SelectIdempotent(id, mutationID string) (engineapi.Result, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.closed {
		if selector, ok := e.engine.(interface {
			SelectIdempotent(string, string) (engineapi.Result, error)
		}); ok {
			return selector.SelectIdempotent(id, mutationID)
		}
	}
	return engineapi.Result{}, errors.New("bundle engine is closed or does not support idempotent selection")
}

func (e *bundleManagedEngine) ForgetCandidate(id string) (engineapi.Result, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.closed {
		if forgetter, ok := e.engine.(engineapi.CandidateForgetter); ok {
			return forgetter.ForgetCandidate(id)
		}
	}
	return engineapi.Result{}, errors.New("bundle engine is closed or does not support forgetting")
}

func (e *bundleManagedEngine) SetCandidateLimit(limit int) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.closed {
		if configurable, ok := e.engine.(interface{ SetCandidateLimit(int) error }); ok {
			return configurable.SetCandidateLimit(limit)
		}
	}
	return errors.New("bundle engine is closed or does not support candidate limits")
}

func (e *bundleManagedEngine) Reset() engineapi.Result {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return engineapi.Result{}
	}
	return e.engine.Reset()
}

func (e *bundleManagedEngine) Close() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil
	}
	e.closed = true
	err := closeBundleEngine(e.engine)
	e.manager.release(e.generation)
	return err
}

func (e *bundleManagedEngine) IndexVersion() string   { return e.generation.version }
func (e *bundleManagedEngine) BundleSourceID() string { return e.sourceID }
