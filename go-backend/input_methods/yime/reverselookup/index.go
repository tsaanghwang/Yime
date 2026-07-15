package reverselookup

import (
	"fmt"
	"os"
	"path/filepath"
)

func Load(sharedDir, userDir string, mode Mode) (*Index, error) {
	if sharedDir == "" {
		return nil, fmt.Errorf("shared data directory is empty")
	}
	if mode == "" {
		mode = ModeVariable
	}
	schemaID := SchemaIDFromMode(mode)
	if cached, ok := loadCachedIndex(sharedDir, userDir, schemaID); ok {
		cached.SetMode(mode)
		return cached, nil
	}

	codeMapPath, markedPath, userPhrasePath, dictPath, _ := dataPaths(sharedDir, userDir, mode)

	codeMap, err := loadCodeMap(codeMapPath)
	if err != nil {
		return nil, err
	}
	markedLookup, err := loadNumericToMarkedLookup(markedPath)
	if err != nil {
		return nil, err
	}
	userEntries, err := loadUserPhraseEntries(userPhrasePath, codeMap, mode)
	if err != nil {
		return nil, err
	}
	dictLookup, err := loadDictLookupMulti(dictPath)
	if err != nil {
		return nil, err
	}

	index := &Index{
		SchemaID:     schemaID,
		Mode:         mode,
		CodeMap:      codeMap,
		DictLookup:   dictLookup,
		UserEntries:  userEntries,
		MarkedLookup: markedLookup,
	}
	index.SetMode(mode)
	_ = saveCachedIndex(sharedDir, userDir, index)
	return index, nil
}

func WarmCache(sharedDir, userDir string, mode Mode) {
	if sharedDir == "" {
		return
	}
	if mode == "" {
		mode = ModeVariable
	}
	schemaID := SchemaIDFromMode(mode)
	if _, ok := loadCachedIndex(sharedDir, userDir, schemaID); ok {
		return
	}
	_, _ = Load(sharedDir, userDir, mode)
}

func DefaultCacheDir() string {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		return ""
	}
	return filepath.Join(localAppData, "PIME", "Cache")
}
