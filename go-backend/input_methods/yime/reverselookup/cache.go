package reverselookup

import (
	"encoding/gob"
	"fmt"
	"os"
	"path/filepath"
)

const cacheVersion = 1

type cacheHeader struct {
	Version     int
	SchemaID    string
	SourceTimes map[string]int64
}

type cachePayload struct {
	Header       cacheHeader
	CodeMap      map[string]CodeRecord
	DictLookup   map[string][]string
	UserEntries  []UserPhraseEntry
	MarkedLookup map[string]string
}

func cachePath(schemaID string) string {
	cacheDir := DefaultCacheDir()
	if cacheDir == "" {
		return ""
	}
	return filepath.Join(cacheDir, fmt.Sprintf("reverse_lookup_%s.gob", schemaID))
}

func sourceTimes(sharedDir, userDir, schemaID string) (map[string]int64, error) {
	codeMapPath := filepath.Join(sharedDir, "yime_pinyin_codes.tsv")
	markedPath := filepath.Join(sharedDir, "pinyin_normalized.json")
	userPhrasePath := filepath.Join(userDir, "yime_user_phrases.txt")
	dictPath := resolveDictPath(sharedDir, userDir, schemaID)
	paths := []string{codeMapPath, markedPath, userPhrasePath, dictPath}
	times := make(map[string]int64, len(paths))
	for _, path := range paths {
		info, err := os.Stat(path)
		if err != nil {
			if os.IsNotExist(err) {
				times[path] = 0
				continue
			}
			return nil, err
		}
		times[path] = info.ModTime().UnixNano()
	}
	return times, nil
}

func loadCachedIndex(sharedDir, userDir, schemaID string) (*Index, bool) {
	path := cachePath(schemaID)
	if path == "" {
		return nil, false
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer file.Close()

	var payload cachePayload
	if err := gob.NewDecoder(file).Decode(&payload); err != nil {
		return nil, false
	}
	if payload.Header.Version != cacheVersion || payload.Header.SchemaID != schemaID {
		return nil, false
	}
	currentTimes, err := sourceTimes(sharedDir, userDir, schemaID)
	if err != nil {
		return nil, false
	}
	for path, modTime := range currentTimes {
		if payload.Header.SourceTimes[path] != modTime {
			return nil, false
		}
	}
	if len(payload.DictLookup) == 0 {
		dictPath := resolveDictPath(sharedDir, userDir, schemaID)
		if info, err := os.Stat(dictPath); err == nil && info.Size() > 0 {
			return nil, false
		}
	}

	index := &Index{
		SchemaID:     schemaID,
		CodeMap:      payload.CodeMap,
		DictLookup:   payload.DictLookup,
		UserEntries:  payload.UserEntries,
		MarkedLookup: payload.MarkedLookup,
	}
	return index, true
}

func saveCachedIndex(sharedDir, userDir string, index *Index) error {
	if index == nil || index.SchemaID == "" {
		return nil
	}
	path := cachePath(index.SchemaID)
	if path == "" {
		return nil
	}
	times, err := sourceTimes(sharedDir, userDir, index.SchemaID)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	payload := cachePayload{
		Header: cacheHeader{
			Version:     cacheVersion,
			SchemaID:    index.SchemaID,
			SourceTimes: times,
		},
		CodeMap:      index.CodeMap,
		DictLookup:   index.DictLookup,
		UserEntries:  index.UserEntries,
		MarkedLookup: index.MarkedLookup,
	}
	return gob.NewEncoder(file).Encode(payload)
}
