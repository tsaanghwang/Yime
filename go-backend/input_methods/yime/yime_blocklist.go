package yime

import (
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userblocklist"
)

type blocklistCache struct {
	mu      sync.Mutex
	path    string
	modTime time.Time
	blocked map[string]struct{}
}

var imeBlocklistCache blocklistCache
var imeSystemExclusionCache blocklistCache

const systemCandidateExclusionsFileName = "yime_system_candidate_exclusions.tsv"

var resolveSystemCandidateExclusionsPath = func(ime *IME) string {
	sharedDir := ime.sharedDir()
	if sharedDir == "" {
		return ""
	}
	return filepath.Join(sharedDir, systemCandidateExclusionsFileName)
}

func (ime *IME) blocklistPath() string {
	userDir := ime.userDir()
	if userDir == "" {
		return ""
	}
	return userblocklist.SourcePath(userDir)
}

func (ime *IME) blockedCandidateSet() map[string]struct{} {
	userSet := loadCachedCandidateSet(ime.blocklistPath(), &imeBlocklistCache, userblocklist.LoadSet)
	systemSet := loadCachedCandidateSet(resolveSystemCandidateExclusionsPath(ime), &imeSystemExclusionCache, loadSystemCandidateExclusions)
	if len(systemSet) == 0 {
		return userSet
	}
	if len(userSet) == 0 {
		return systemSet
	}
	merged := make(map[string]struct{}, len(userSet)+len(systemSet))
	for text := range systemSet {
		merged[text] = struct{}{}
	}
	for text := range userSet {
		merged[text] = struct{}{}
	}
	return merged
}

func loadCachedCandidateSet(path string, cache *blocklistCache, loader func(string) (map[string]struct{}, error)) map[string]struct{} {
	if path == "" {
		return nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return nil
	}

	cache.mu.Lock()
	defer cache.mu.Unlock()
	if cache.path == path && !info.ModTime().After(cache.modTime) && cache.blocked != nil {
		return cache.blocked
	}
	set, err := loader(path)
	if err != nil {
		return cache.blocked
	}
	cache.path = path
	cache.modTime = info.ModTime()
	cache.blocked = set
	return set
}

func loadSystemCandidateExclusions(path string) (map[string]struct{}, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	reader.FieldsPerRecord = 5
	header, err := reader.Read()
	if err != nil {
		return nil, err
	}
	header[0] = strings.TrimPrefix(header[0], "\ufeff")
	if strings.Join(header, "\t") != "text\tcategory\tsource_snapshot\tdecision\tnote" {
		return nil, fmt.Errorf("系统候选排除表表头无效")
	}
	result := map[string]struct{}{}
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		text := strings.TrimSpace(row[0])
		if text == "" || row[1] != "unverifiable_particle_a_fragment" || row[2] == "" || row[3] != "exclude_runtime_candidate" || row[4] == "" {
			return nil, fmt.Errorf("系统候选排除行无效: %v", row)
		}
		if _, exists := result[text]; exists {
			return nil, fmt.Errorf("系统候选排除项重复: %s", text)
		}
		result[text] = struct{}{}
	}
	return result, nil
}

func filterBlockedCandidates(candidates []candidateItem, blocked map[string]struct{}) ([]candidateItem, []int) {
	if len(candidates) == 0 || len(blocked) == 0 {
		mapping := make([]int, len(candidates))
		for i := range candidates {
			mapping[i] = i
		}
		return candidates, mapping
	}
	filtered := make([]candidateItem, 0, len(candidates))
	mapping := make([]int, 0, len(candidates))
	for i, candidate := range candidates {
		if userblocklist.IsBlocked(blocked, candidate.Text) {
			continue
		}
		filtered = append(filtered, candidate)
		mapping = append(mapping, i)
	}
	return filtered, mapping
}

func remapCandidateCursor(backendCursor int, indexMap []int) int {
	if len(indexMap) == 0 {
		return 0
	}
	for visibleIndex, backendIndex := range indexMap {
		if backendIndex == backendCursor {
			return visibleIndex
		}
	}
	if backendCursor < 0 {
		return 0
	}
	if backendCursor >= len(indexMap) {
		return len(indexMap) - 1
	}
	return 0
}

func (ime *IME) mapCandidateSelectionIndex(visibleIndex int) (int, bool) {
	if visibleIndex < 0 {
		return 0, false
	}
	if !ime.backendUsesCandidatePaging() {
		visibleIndex += ime.candidatePageStart
	}
	if ime.candidateBackendIndexMap == nil {
		return visibleIndex, true
	}
	if visibleIndex < 0 || visibleIndex >= len(ime.candidateBackendIndexMap) {
		return 0, false
	}
	return ime.candidateBackendIndexMap[visibleIndex], true
}
