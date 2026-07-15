package yime

import (
	"os"
	"sync"
	"time"

	"github.com/EasyIME/pime-go/input_methods/yime/userblocklist"
)

type blocklistCache struct {
	mu      sync.Mutex
	path    string
	modTime time.Time
	blocked map[string]struct{}
}

var imeBlocklistCache blocklistCache

func (ime *IME) blocklistPath() string {
	userDir := ime.userDir()
	if userDir == "" {
		return ""
	}
	return userblocklist.SourcePath(userDir)
}

func (ime *IME) blockedCandidateSet() map[string]struct{} {
	path := ime.blocklistPath()
	if path == "" {
		return nil
	}
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return nil
	}

	imeBlocklistCache.mu.Lock()
	defer imeBlocklistCache.mu.Unlock()
	if imeBlocklistCache.path == path && !info.ModTime().After(imeBlocklistCache.modTime) && imeBlocklistCache.blocked != nil {
		return imeBlocklistCache.blocked
	}
	set, err := userblocklist.LoadSet(path)
	if err != nil {
		return imeBlocklistCache.blocked
	}
	imeBlocklistCache.path = path
	imeBlocklistCache.modTime = info.ModTime()
	imeBlocklistCache.blocked = set
	return set
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
	if len(ime.candidateBackendIndexMap) == 0 {
		return visibleIndex, true
	}
	if visibleIndex < 0 || visibleIndex >= len(ime.candidateBackendIndexMap) {
		return 0, false
	}
	return ime.candidateBackendIndexMap[visibleIndex], true
}
