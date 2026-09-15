package reverselookup

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
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
	sourceTruth, err := loadSourceTruth(filepath.Join(sharedDir, SourceTruthFileName), codeMap, mode)
	if err != nil {
		return nil, err
	}
	erhuaLookup, err := loadErhuaSource(filepath.Join(sharedDir, ErhuaSourceFileName))
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
		SourceTruth:  sourceTruth,
		ErhuaLookup:  erhuaLookup,
	}
	index.SetMode(mode)
	_ = saveCachedIndex(sharedDir, userDir, index)
	return index, nil
}

// LoadYimeCore reuses the established reverse-lookup model while sourcing
// system words from this branch's validated .yidx package. It never consults
// production Rime/PIME paths.
func LoadYimeCore(sharedDir, userDir, indexRoot string, mode Mode) (*Index, error) {
	if sharedDir == "" || indexRoot == "" {
		return nil, fmt.Errorf("shared data and YimeCore index directories are required")
	}
	if mode == "" {
		mode = ModeVariable
	}
	codeMapPath, markedPath, userPhrasePath, _, schemaID := dataPaths(sharedDir, userDir, mode)
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
	fileIndex, err := yimecore.OpenFileIndex(filepath.Join(indexRoot, string(mode)+".yidx"))
	if err != nil {
		return nil, err
	}
	defer fileIndex.Close()
	dictLookup := make(map[string][]string, fileIndex.RecordCount())
	if err := fileIndex.VisitEntries(func(entry yimecore.Entry) bool {
		codes := dictLookup[entry.Text]
		if !containsString(codes, entry.Code) {
			dictLookup[entry.Text] = append(codes, entry.Code)
		}
		return true
	}); err != nil {
		return nil, err
	}
	sourceTruth, err := loadSourceTruth(filepath.Join(sharedDir, SourceTruthFileName), codeMap, mode)
	if err != nil {
		return nil, err
	}
	erhuaLookup, err := loadErhuaSource(filepath.Join(sharedDir, ErhuaSourceFileName))
	if err != nil {
		return nil, err
	}
	index := &Index{SchemaID: schemaID, Mode: mode, CodeMap: codeMap,
		DictLookup: dictLookup, UserEntries: userEntries, MarkedLookup: markedLookup,
		SourceTruth: sourceTruth, ErhuaLookup: erhuaLookup}
	index.SetMode(mode)
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
