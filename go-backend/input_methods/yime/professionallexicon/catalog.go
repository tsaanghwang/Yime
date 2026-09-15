package professionallexicon

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	CatalogSchema = "yimecore-professional-catalog-v1"
	StateSchema   = "yimecore-professional-state-v1"
)

type FileSpec struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
}

type Pack struct {
	ID         string              `json:"id"`
	Name       string              `json:"name"`
	Provenance string              `json:"provenance"`
	Modes      map[string]FileSpec `json:"modes"`
}

type Catalog struct {
	SchemaVersion string `json:"schema_version"`
	Packs         []Pack `json:"packs"`
}

type State struct {
	SchemaVersion string   `json:"schema_version"`
	Enabled       bool     `json:"enabled"`
	Selected      []string `json:"selected"`
}

type Set struct {
	modules map[string][]yimecore.BundleModule
	indexes []*yimecore.FileIndex
}

func DefaultState() State { return State{SchemaVersion: StateSchema} }

func LoadCatalog(root string) (Catalog, error) {
	path := filepath.Join(root, "catalog.json")
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Catalog{SchemaVersion: CatalogSchema}, nil
	}
	if err != nil {
		return Catalog{}, err
	}
	var catalog Catalog
	if err := decodeStrict(data, &catalog); err != nil {
		return Catalog{}, fmt.Errorf("decode professional catalog: %w", err)
	}
	if catalog.SchemaVersion != CatalogSchema {
		return Catalog{}, fmt.Errorf("unsupported professional catalog schema %q", catalog.SchemaVersion)
	}
	seen := map[string]struct{}{}
	for index, pack := range catalog.Packs {
		if strings.TrimSpace(pack.ID) == "" || strings.TrimSpace(pack.Name) == "" || strings.TrimSpace(pack.Provenance) == "" {
			return Catalog{}, fmt.Errorf("professional pack %d lacks ID, name or provenance", index)
		}
		if _, exists := seen[pack.ID]; exists {
			return Catalog{}, fmt.Errorf("duplicate professional pack ID %q", pack.ID)
		}
		seen[pack.ID] = struct{}{}
		for _, mode := range []string{"full", "variable", "shorthand"} {
			spec, ok := pack.Modes[mode]
			if !ok || strings.TrimSpace(spec.Path) == "" || len(spec.SHA256) != 64 {
				return Catalog{}, fmt.Errorf("professional pack %q lacks a valid %s index", pack.ID, mode)
			}
			if _, err := resolveContained(root, spec.Path); err != nil {
				return Catalog{}, fmt.Errorf("professional pack %q: %w", pack.ID, err)
			}
		}
	}
	return catalog, nil
}

func LoadState(path string) (State, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return DefaultState(), nil
	}
	if err != nil {
		return State{}, err
	}
	var state State
	if err := decodeStrict(data, &state); err != nil {
		return State{}, fmt.Errorf("decode professional state: %w", err)
	}
	if state.SchemaVersion != StateSchema {
		return State{}, fmt.Errorf("unsupported professional state schema %q", state.SchemaVersion)
	}
	return state, nil
}

func SaveState(path string, state State) error {
	state.SchemaVersion = StateSchema
	state.Selected = append([]string(nil), state.Selected...)
	sort.Strings(state.Selected)
	for index := 1; index < len(state.Selected); index++ {
		if state.Selected[index] == state.Selected[index-1] {
			return fmt.Errorf("duplicate selected professional pack %q", state.Selected[index])
		}
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(path, append(data, '\n'))
}

func OpenSelected(root, statePath string) (*Set, error) {
	catalog, err := LoadCatalog(root)
	if err != nil {
		return nil, err
	}
	state, err := LoadState(statePath)
	if err != nil {
		return nil, err
	}
	set := &Set{modules: map[string][]yimecore.BundleModule{"full": {}, "variable": {}, "shorthand": {}}}
	if !state.Enabled {
		return set, nil
	}
	byID := make(map[string]Pack, len(catalog.Packs))
	for _, pack := range catalog.Packs {
		byID[pack.ID] = pack
	}
	selected := append([]string(nil), state.Selected...)
	sort.Strings(selected)
	for _, id := range selected {
		pack, ok := byID[id]
		if !ok {
			set.Close()
			return nil, fmt.Errorf("selected professional pack %q is not installed", id)
		}
		for _, mode := range []string{"full", "variable", "shorthand"} {
			spec := pack.Modes[mode]
			path, _ := resolveContained(root, spec.Path)
			actual, err := hashFile(path)
			if err != nil || !strings.EqualFold(actual, spec.SHA256) {
				set.Close()
				if err != nil {
					return nil, fmt.Errorf("read professional pack %q %s index: %w", id, mode, err)
				}
				return nil, fmt.Errorf("professional pack %q %s SHA-256 mismatch", id, mode)
			}
			index, err := yimecore.OpenResidentFileIndex(path)
			if err != nil {
				set.Close()
				return nil, fmt.Errorf("open professional pack %q %s index: %w", id, mode, err)
			}
			if index.Mode() != mode {
				_ = index.Close()
				set.Close()
				return nil, fmt.Errorf("professional pack %q index mode %q does not match %q", id, index.Mode(), mode)
			}
			set.indexes = append(set.indexes, index)
			set.modules[mode] = append(set.modules[mode], yimecore.BundleModule{ID: "professional:" + id, Index: index})
		}
	}
	return set, nil
}

func (s *Set) Modules(mode string) []yimecore.BundleModule {
	if s == nil {
		return nil
	}
	return append([]yimecore.BundleModule(nil), s.modules[mode]...)
}

func (s *Set) Close() error {
	if s == nil {
		return nil
	}
	var result error
	for _, index := range s.indexes {
		result = errors.Join(result, index.Close())
	}
	s.indexes = nil
	return result
}

func decodeStrict(data []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return errors.New("multiple JSON values")
	}
	return nil
}

func resolveContained(root, relative string) (string, error) {
	if filepath.IsAbs(relative) {
		return "", errors.New("professional index path must be relative")
	}
	root = filepath.Clean(root)
	path := filepath.Join(root, relative)
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errors.New("professional index path escapes its catalog root")
	}
	return path, nil
}

func hashFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:]), nil
}

func writeAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".professional-state-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
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
	return replaceFileAtomically(temporaryPath, path)
}
