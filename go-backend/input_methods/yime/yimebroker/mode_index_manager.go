package yimebroker

import (
	"errors"
	"fmt"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

var supportedIndexModes = []string{"full", "variable", "shorthand"}

type ModeIndexEngineBuilder func(mode string, index *yimecore.FileIndex) (engineapi.Engine, error)

// ModeIndexManager composes one generation-leased IndexManager per Yime code
// mode. A control operation changes only the active pointer for its target
// mode; engines already leased by open sessions remain on their generation.
type ModeIndexManager struct {
	managers map[string]*IndexManager
}

func OpenModeIndexManager(initial map[string]IndexSpec, builder ModeIndexEngineBuilder, validator IndexValidator) (*ModeIndexManager, error) {
	return openModeIndexManager(initial, builder, validator, false)
}

// OpenResidentModeIndexManager loads all three system-lexicon indexes into
// resident memory before serving sessions. Transactional replacements use the
// same policy, while already-open sessions retain their original generation.
func OpenResidentModeIndexManager(initial map[string]IndexSpec, builder ModeIndexEngineBuilder, validator IndexValidator) (*ModeIndexManager, error) {
	return openModeIndexManager(initial, builder, validator, true)
}

func openModeIndexManager(initial map[string]IndexSpec, builder ModeIndexEngineBuilder, validator IndexValidator, resident bool) (*ModeIndexManager, error) {
	if builder == nil {
		builder = func(_ string, index *yimecore.FileIndex) (engineapi.Engine, error) {
			return yimecore.NewFileEngine(index, 9)
		}
	}
	group := &ModeIndexManager{managers: make(map[string]*IndexManager, len(supportedIndexModes))}
	for _, mode := range supportedIndexModes {
		spec, ok := initial[mode]
		if !ok || spec.Mode != mode {
			_ = group.Close()
			return nil, fmt.Errorf("initial %s index specification is required", mode)
		}
		modeName := mode
		openManager := OpenIndexManager
		if resident {
			openManager = OpenResidentIndexManager
		}
		manager, err := openManager(spec, func(index *yimecore.FileIndex) (engineapi.Engine, error) {
			return builder(modeName, index)
		}, validator)
		if err != nil {
			_ = group.Close()
			return nil, fmt.Errorf("open %s index manager: %w", mode, err)
		}
		group.managers[mode] = manager
	}
	return group, nil
}

func (m *ModeIndexManager) NewEngine(mode string) (engineapi.Engine, error) {
	manager := m.manager(mode)
	if manager == nil {
		return nil, fmt.Errorf("unsupported session mode %q", mode)
	}
	return manager.NewEngine()
}

func (m *ModeIndexManager) Swap(spec IndexSpec) error {
	manager := m.manager(spec.Mode)
	if manager == nil {
		return fmt.Errorf("unsupported index mode %q", spec.Mode)
	}
	return manager.Swap(spec)
}

func (m *ModeIndexManager) Rollback(mode string) error {
	manager := m.manager(mode)
	if manager == nil {
		return fmt.Errorf("unsupported index mode %q", mode)
	}
	return manager.Rollback()
}

func (m *ModeIndexManager) ModeStats(mode string) (IndexManagerStats, error) {
	manager := m.manager(mode)
	if manager == nil {
		return IndexManagerStats{}, fmt.Errorf("unsupported index mode %q", mode)
	}
	return manager.Stats(), nil
}

func (m *ModeIndexManager) Stats() map[string]IndexManagerStats {
	result := make(map[string]IndexManagerStats, len(supportedIndexModes))
	if m == nil {
		return result
	}
	for _, mode := range supportedIndexModes {
		if manager := m.managers[mode]; manager != nil {
			result[mode] = manager.Stats()
		}
	}
	return result
}

func (m *ModeIndexManager) Close() error {
	if m == nil {
		return nil
	}
	var closeErr error
	for _, mode := range supportedIndexModes {
		if manager := m.managers[mode]; manager != nil {
			if err := manager.Close(); err != nil {
				closeErr = errors.Join(closeErr, err)
			}
		}
	}
	return closeErr
}

func (m *ModeIndexManager) manager(mode string) *IndexManager {
	if m == nil {
		return nil
	}
	return m.managers[mode]
}
