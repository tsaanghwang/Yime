package yimecore

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"
)

// BundleModule names one already-reviewed, independently removable E4 input
// overlay. The index remains immutable and is owned by the caller.
type BundleModule struct {
	ID    string
	Index *FileIndex
}

type bundleSource struct {
	id       string
	index    *FileIndex
	priority int
}

// BundleIndex merges a canonical core index with an explicit set of overlay
// indexes. It does not infer connected-speech behavior or read Rime imports.
type BundleIndex struct {
	mode         string
	sources      []bundleSource
	maxCodeBytes int
	sourceID     string
}

// NewBundleIndex validates and deterministically orders a core index plus the
// explicitly enabled modules. Omitting one module is the complete rollback
// mechanism for that module.
func NewBundleIndex(core *FileIndex, modules []BundleModule) (*BundleIndex, error) {
	if core == nil {
		return nil, fmt.Errorf("core index is required")
	}
	mode := core.Mode()
	ordered := append([]BundleModule(nil), modules...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i].ID < ordered[j].ID })
	sources := make([]bundleSource, 0, len(ordered)+1)
	sources = append(sources, bundleSource{id: "core", index: core})
	seen := map[string]struct{}{"core": {}}
	maxCodeBytes := core.maximumCodeBytes()
	for i, module := range ordered {
		id := strings.TrimSpace(module.ID)
		if id == "" || strings.ContainsAny(id, "\x00\r\n\t") {
			return nil, fmt.Errorf("module %d has an invalid ID", i)
		}
		if _, exists := seen[id]; exists {
			return nil, fmt.Errorf("duplicate module ID %q", id)
		}
		if module.Index == nil {
			return nil, fmt.Errorf("module %q index is required", id)
		}
		if module.Index.Mode() != mode {
			return nil, fmt.Errorf("module %q mode %q does not match core mode %q", id, module.Index.Mode(), mode)
		}
		seen[id] = struct{}{}
		sources = append(sources, bundleSource{id: id, index: module.Index, priority: len(sources)})
		if size := module.Index.maximumCodeBytes(); size > maxCodeBytes {
			maxCodeBytes = size
		}
	}

	hasher := sha256.New()
	hasher.Write([]byte("yime-bundle-v1\x00" + mode + "\x00"))
	for _, source := range sources {
		hasher.Write([]byte(source.id + "\x00" + source.index.identity() + "\x00"))
	}
	return &BundleIndex{
		mode: mode, sources: sources, maxCodeBytes: maxCodeBytes,
		sourceID: "yime-bundle-v1:" + mode + ":" + hex.EncodeToString(hasher.Sum(nil)),
	}, nil
}

func (idx *BundleIndex) lookup(prefix string, limit int) []record {
	return idx.merge(prefix, limit, false)
}

func (idx *BundleIndex) exact(code string, limit int) []record {
	return idx.merge(code, limit, true)
}

func (idx *BundleIndex) merge(input string, limit int, exact bool) []record {
	if idx == nil || input == "" || limit <= 0 {
		return nil
	}
	type selected struct {
		record
		priority int
	}
	byCandidate := make(map[string]selected, len(idx.sources)*limit)
	for _, source := range idx.sources {
		var records []record
		if exact {
			records = source.index.exact(input, limit)
		} else {
			records = source.index.lookup(input, limit)
		}
		for _, item := range records {
			item.source = source.id + "@" + source.index.identity()
			key := item.code + "\x1f" + item.text
			current, exists := byCandidate[key]
			if !exists || item.weight > current.weight || (item.weight == current.weight && source.priority < current.priority) {
				byCandidate[key] = selected{record: item, priority: source.priority}
			}
		}
	}
	merged := make([]selected, 0, len(byCandidate))
	for _, item := range byCandidate {
		merged = append(merged, item)
	}
	sort.Slice(merged, func(i, j int) bool {
		if better(merged[i].record, merged[j].record, input) {
			return true
		}
		if better(merged[j].record, merged[i].record, input) {
			return false
		}
		return merged[i].priority < merged[j].priority
	})
	if len(merged) > limit {
		merged = merged[:limit]
	}
	result := make([]record, len(merged))
	for i := range merged {
		result[i] = merged[i].record
	}
	return result
}

func (idx *BundleIndex) maximumCodeBytes() int { return idx.maxCodeBytes }
func (idx *BundleIndex) identity() string      { return idx.sourceID }

// SourceID binds later user data and evidence to the exact enabled bundle.
func (idx *BundleIndex) SourceID() string { return idx.identity() }
