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

// ModuleCoverageReport is an exhaustive direct-path audit of one reviewed
// overlay. It distinguishes low-weight paths that require later pages from
// paths that are inaccessible or shadowed by another source.
type ModuleCoverageReport struct {
	ModuleID                       string   `json:"module_id"`
	IndexedRecords                 int      `json:"indexed_records"`
	ReachableRecords               int      `json:"reachable_records"`
	DirectFirstPageRecords         int      `json:"direct_first_page_records"`
	DirectLaterPageRecords         int      `json:"direct_later_page_records"`
	MaximumDirectPageNumber        int      `json:"maximum_direct_page_number"`
	ExactTextRetainedAfterDisable  int      `json:"exact_text_retained_after_disable"`
	InaccessibleOrShadowedExamples []string `json:"inaccessible_or_shadowed_examples,omitempty"`
	Passed                         bool     `json:"passed"`
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

// AuditModuleCoverage checks every code/text/weight record in one enabled
// module against the merged bundle and then against the bundle with that
// module omitted. This is an offline experiment audit, not a runtime rule
// evaluator.
func (idx *BundleIndex) AuditModuleCoverage(moduleID string, pageSize int) (ModuleCoverageReport, error) {
	if idx == nil {
		return ModuleCoverageReport{}, fmt.Errorf("bundle index is required")
	}
	if pageSize <= 0 {
		return ModuleCoverageReport{}, fmt.Errorf("page size must be positive")
	}
	var module *bundleSource
	for i := range idx.sources {
		if idx.sources[i].id == moduleID && moduleID != "core" {
			module = &idx.sources[i]
			break
		}
	}
	if module == nil {
		return ModuleCoverageReport{}, fmt.Errorf("enabled module %q was not found", moduleID)
	}
	report := ModuleCoverageReport{ModuleID: moduleID, IndexedRecords: module.index.RecordCount()}
	enabledCache := make(map[string][]record)
	disabledCache := make(map[string][]record)
	for position := 0; position < module.index.RecordCount(); position++ {
		codeBytes, textBytes, weight, err := module.index.recordAt(position)
		if err != nil {
			return ModuleCoverageReport{}, fmt.Errorf("read module %q record %d: %w", moduleID, position, err)
		}
		code, text := string(codeBytes), string(textBytes)
		enabled, exists := enabledCache[code]
		if !exists {
			enabled = idx.exactAllExcept(code, "")
			enabledCache[code] = enabled
		}
		ordinal := -1
		for i, candidate := range enabled {
			if candidate.code == code && candidate.text == text && candidate.weight == weight && strings.HasPrefix(candidate.source, moduleID+"@") {
				ordinal = i
				break
			}
		}
		if ordinal < 0 {
			if len(report.InaccessibleOrShadowedExamples) < 20 {
				report.InaccessibleOrShadowedExamples = append(report.InaccessibleOrShadowedExamples, text+"\t"+code)
			}
		} else {
			report.ReachableRecords++
			page := ordinal / pageSize
			if page == 0 {
				report.DirectFirstPageRecords++
			} else {
				report.DirectLaterPageRecords++
			}
			if page > report.MaximumDirectPageNumber {
				report.MaximumDirectPageNumber = page
			}
		}
		disabled, exists := disabledCache[code]
		if !exists {
			disabled = idx.exactAllExcept(code, moduleID)
			disabledCache[code] = disabled
		}
		for _, candidate := range disabled {
			if candidate.code == code && candidate.text == text {
				report.ExactTextRetainedAfterDisable++
				break
			}
		}
	}
	report.Passed = report.IndexedRecords > 0 && report.ReachableRecords == report.IndexedRecords
	return report, nil
}

func (idx *BundleIndex) exactAllExcept(code, excludedModule string) []record {
	type selected struct {
		record
		priority int
	}
	byCandidate := make(map[string]selected)
	for _, source := range idx.sources {
		if source.id == excludedModule {
			continue
		}
		for _, item := range source.index.exactAll(code) {
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
		if better(merged[i].record, merged[j].record, code) {
			return true
		}
		if better(merged[j].record, merged[i].record, code) {
			return false
		}
		return merged[i].priority < merged[j].priority
	})
	result := make([]record, len(merged))
	for i := range merged {
		result[i] = merged[i].record
	}
	return result
}
