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

type lexiconFileSignature struct {
	exists           bool
	size             int64
	modifiedUnixNano int64
}

// NewFileEngineWithUserLexicon layers a trial-private generated user lexicon
// over the immutable system index. Active compositions retain their original
// overlay; an idle engine adopts a later file before the next composition.
func NewFileEngineWithUserLexicon(index *FileIndex, candidateLimit int,
	userLexiconPath string, model *UserModel) (*Engine, error) {
	if index == nil {
		return nil, errors.New("index is required")
	}
	source, signature, err := loadUserLexiconOverlay(index, userLexiconPath)
	if err != nil {
		return nil, err
	}
	engine, err := newEngine(source, candidateLimit)
	if err != nil {
		return nil, err
	}
	engine.userLexiconBase = index
	engine.userLexiconPath = userLexiconPath
	engine.userLexiconFile = signature
	if model != nil {
		engine.userModel = model
	}
	return engine, nil
}

func loadUserLexiconOverlay(index *FileIndex, path string) (lookupIndex, lexiconFileSignature, error) {
	entries, signature, err := readUserLexicon(path)
	if err != nil {
		return nil, lexiconFileSignature{}, err
	}
	if len(entries) == 0 {
		return index, signature, nil
	}
	lexicon, err := NewIndex(entries)
	if err != nil {
		return nil, lexiconFileSignature{}, fmt.Errorf("build user lexicon overlay: %w", err)
	}
	return &overlayIndex{base: index, lexicon: lexicon}, signature, nil
}

func statUserLexicon(path string) (lexiconFileSignature, error) {
	if strings.TrimSpace(path) == "" {
		return lexiconFileSignature{}, nil
	}
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return lexiconFileSignature{}, nil
	}
	if err != nil {
		return lexiconFileSignature{}, fmt.Errorf("stat user lexicon: %w", err)
	}
	return lexiconFileSignature{exists: true, size: info.Size(), modifiedUnixNano: info.ModTime().UnixNano()}, nil
}

func (e *Engine) reloadUserLexiconIfChanged() error {
	if e.userLexiconBase == nil || strings.TrimSpace(e.userLexiconPath) == "" {
		return nil
	}
	signature, err := statUserLexicon(e.userLexiconPath)
	if err != nil {
		return err
	}
	// The Windows writer briefly moves the old file aside before renaming the
	// replacement. Keep the current generation if an input event lands there.
	if signature == e.userLexiconFile || (!signature.exists && e.userLexiconFile.exists) {
		return nil
	}
	source, loadedSignature, err := loadUserLexiconOverlay(e.userLexiconBase, e.userLexiconPath)
	if err != nil {
		return err
	}
	if signature.exists && !loadedSignature.exists {
		return nil
	}
	e.index = source
	e.userLexiconFile = loadedSignature
	e.exactCache = nil
	e.resetSentenceComposer()
	return nil
}

func readUserLexicon(path string) ([]Entry, lexiconFileSignature, error) {
	if strings.TrimSpace(path) == "" {
		return nil, lexiconFileSignature{}, nil
	}
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, lexiconFileSignature{}, nil
	}
	if err != nil {
		return nil, lexiconFileSignature{}, fmt.Errorf("open user lexicon: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, lexiconFileSignature{}, fmt.Errorf("stat open user lexicon: %w", err)
	}
	signature := lexiconFileSignature{exists: true, size: info.Size(), modifiedUnixNano: info.ModTime().UnixNano()}
	entries := make([]Entry, 0, 128)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			return nil, lexiconFileSignature{}, errors.New("user lexicon row has fewer than two fields")
		}
		weight := int64(0)
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight, err = strconv.ParseInt(strings.TrimSpace(fields[2]), 10, 64)
			if err != nil {
				return nil, lexiconFileSignature{}, fmt.Errorf("invalid user lexicon weight: %w", err)
			}
		}
		entries = append(entries, Entry{Text: strings.TrimSpace(fields[0]),
			Code: strings.TrimSpace(fields[1]), Weight: weight})
	}
	if err := scanner.Err(); err != nil {
		return nil, lexiconFileSignature{}, err
	}
	return entries, signature, nil
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
