package reverselookup

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const SourceTruthFileName = "yime_pinyin_reverse_source.tsv"

// SourceTruthLookupKey combines candidate text and the active layout code.
// The code is normalized because Rime dictionary spaces are syllable syntax,
// not runtime keystrokes.
func SourceTruthLookupKey(text, code string) string {
	return strings.TrimSpace(text) + "\x00" + strings.ReplaceAll(strings.TrimSpace(code), " ", "")
}

// LoadSourceTruth loads the partial loss-recovery table and projects every
// canonical numeric-Pinyin row into the requested input mode. Missing tables
// are accepted so older installations keep their deterministic fallback.
func LoadSourceTruth(sharedDir string, mode Mode) (map[string][]string, error) {
	codeMap, err := LoadSharedCodeMap(sharedDir)
	if err != nil {
		return nil, err
	}
	return loadSourceTruth(filepath.Join(sharedDir, SourceTruthFileName), codeMap, mode)
}

func loadSourceTruth(path string, codeMap map[string]CodeRecord, mode Mode) (map[string][]string, error) {
	result := map[string][]string{}
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return result, nil
		}
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		fields := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
		if lineNumber == 1 {
			if len(fields) < 4 || fields[0] != "text" || fields[1] != "source_full_code" || fields[2] != "numeric_pinyin" || fields[3] != "marked_pinyin" {
				return nil, fmt.Errorf("unexpected reverse-Pinyin source header in %s", path)
			}
			continue
		}
		if len(fields) < 4 {
			return nil, fmt.Errorf("reverse-Pinyin source line %d has fewer than four columns", lineNumber)
		}
		text := strings.TrimSpace(fields[0])
		numeric := normalizeNumericTonePinyinSpacing(fields[2])
		if text == "" || numeric == "" {
			return nil, fmt.Errorf("reverse-Pinyin source line %d has empty text or Pinyin", lineNumber)
		}
		activeCode := pinyinToCode(codeMap, numeric, CodeColumnFromMode(mode))
		if activeCode == "" {
			return nil, fmt.Errorf("reverse-Pinyin source line %d cannot encode %q", lineNumber, numeric)
		}
		key := SourceTruthLookupKey(text, activeCode)
		if !containsString(result[key], numeric) {
			result[key] = append(result[key], numeric)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	for key := range result {
		sort.Strings(result[key])
	}
	return result, nil
}
