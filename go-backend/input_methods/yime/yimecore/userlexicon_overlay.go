package yimecore

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type overlayIndex struct {
	base    *FileIndex
	lexicon *Index
}

// NewFileEngineWithUserLexicon layers a trial-private generated user lexicon
// over the immutable system index. New sessions read the latest file while
// engines held by active compositions retain their original overlay.
func NewFileEngineWithUserLexicon(index *FileIndex, candidateLimit int,
	userLexiconPath string, model *UserModel) (*Engine, error) {
	if index == nil {
		return nil, errors.New("index is required")
	}
	entries, err := readUserLexicon(userLexiconPath)
	if err != nil {
		return nil, err
	}
	var source lookupIndex = index
	if len(entries) > 0 {
		lexicon, buildErr := NewIndex(entries)
		if buildErr != nil {
			return nil, fmt.Errorf("build user lexicon overlay: %w", buildErr)
		}
		source = &overlayIndex{base: index, lexicon: lexicon}
	}
	engine, err := newEngine(source, candidateLimit)
	if err != nil {
		return nil, err
	}
	if model != nil {
		engine.userModel = model
	}
	return engine, nil
}

func readUserLexicon(path string) ([]Entry, error) {
	if strings.TrimSpace(path) == "" {
		return nil, nil
	}
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("open user lexicon: %w", err)
	}
	defer file.Close()
	entries := make([]Entry, 0, 128)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			return nil, errors.New("user lexicon row has fewer than two fields")
		}
		weight := int64(0)
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight, err = strconv.ParseInt(strings.TrimSpace(fields[2]), 10, 64)
			if err != nil {
				return nil, fmt.Errorf("invalid user lexicon weight: %w", err)
			}
		}
		entries = append(entries, Entry{Text: strings.TrimSpace(fields[0]),
			Code: strings.TrimSpace(fields[1]), Weight: weight})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}

func (idx *overlayIndex) lookup(prefix string, limit int) []record {
	return mergeOverlayRecords(idx.base.lookup(prefix, limit), idx.lexicon.lookup(prefix, limit))
}

func (idx *overlayIndex) exact(code string, limit int) []record {
	return mergeOverlayRecords(idx.base.exact(code, limit), idx.lexicon.exact(code, limit))
}

func (idx *overlayIndex) maximumCodeBytes() int {
	if idx.lexicon.maximumCodeBytes() > idx.base.maximumCodeBytes() {
		return idx.lexicon.maximumCodeBytes()
	}
	return idx.base.maximumCodeBytes()
}

func (idx *overlayIndex) identity() string { return idx.base.identity() }

func mergeOverlayRecords(primary, secondary []record) []record {
	result := make([]record, 0, len(primary)+len(secondary))
	seen := make(map[string]struct{}, cap(result))
	for _, group := range [][]record{primary, secondary} {
		for _, item := range group {
			key := item.code + "\x1f" + item.text
			if _, exists := seen[key]; exists {
				continue
			}
			seen[key] = struct{}{}
			result = append(result, item)
		}
	}
	return result
}
