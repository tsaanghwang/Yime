package keyboardlab

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// Runtime owns verified experimental dictionaries, disposable indexes and all
// sessions that reference them. No installed product or writable user data is used.
type Runtime struct {
	LayoutID  string
	Builds    map[string]yimecore.IndexBuildResult
	Sessions  *Service
	indices   map[string]*yimecore.FileIndex
	indexRoot string
	once      sync.Once
	closeErr  error
}

// OpenRuntime loads all three modes and binds their hashes to both the physical
// layout and the compiled experimental projection. An empty dataDir selects only
// the explicit root's .generated/ascii-keyboard-134/data; there is no fallback.
func OpenRuntime(root, dataDir string) (_ *Runtime, err error) {
	root, err = filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	if dataDir == "" {
		dataDir = filepath.Join(root, ".generated", "ascii-keyboard-134", "data")
	}
	data, err := os.ReadFile(filepath.Join(root, "prototypes", "touch-terminal", "data", "physical-layout.json"))
	if err != nil {
		return nil, fmt.Errorf("read generated physical keyboard layout: %w", err)
	}
	var layout struct {
		LayoutID string `json:"layoutId"`
	}
	if json.Unmarshal(data, &layout) != nil || layout.LayoutID == "" {
		return nil, errors.New("generated physical keyboard layout requires layoutId")
	}
	manifest, err := loadManifest(dataDir, layout.LayoutID)
	if err != nil {
		return nil, err
	}
	r := &Runtime{LayoutID: layout.LayoutID, indices: make(map[string]*yimecore.FileIndex), Builds: make(map[string]yimecore.IndexBuildResult)}
	r.indexRoot, err = os.MkdirTemp("", "yime-keyboard-lab-")
	if err != nil {
		return nil, err
	}
	defer func() {
		if err != nil {
			err = errors.Join(err, r.Close())
		}
	}()
	for _, mode := range modes {
		source := filepath.Join(dataDir, "yime_"+mode+".dict.yaml")
		output := filepath.Join(r.indexRoot, mode+".yidx")
		build, err := yimecore.BuildIndexFile(mode, source, output)
		if err != nil {
			return nil, fmt.Errorf("compile %s dictionary: %w", mode, err)
		}
		if build.SourceSHA256 != manifest.DictionarySHA256[filepath.Base(source)] {
			return nil, fmt.Errorf("%s dictionary differs from layout-bound experimental manifest; regenerate data", mode)
		}
		index, err := yimecore.OpenFileIndex(output)
		if err != nil {
			return nil, err
		}
		r.indices[mode], r.Builds[mode] = index, build
	}
	r.Sessions = NewService(r.LayoutID, func(mode string) (engineapi.Engine, error) {
		index, ok := r.indices[mode]
		if !ok {
			return nil, errors.New("unknown input mode")
		}
		return yimecore.NewFileEngine(index, 9)
	})
	return r, nil
}

// Close drains session mutations before closing mapped indexes. It is idempotent.
func (r *Runtime) Close() error {
	r.once.Do(func() {
		if r.Sessions != nil {
			r.Sessions.Close()
		}
		for _, index := range r.indices {
			r.closeErr = errors.Join(r.closeErr, index.Close())
		}
		if r.indexRoot != "" {
			r.closeErr = errors.Join(r.closeErr, os.RemoveAll(r.indexRoot))
		}
	})
	return r.closeErr
}
