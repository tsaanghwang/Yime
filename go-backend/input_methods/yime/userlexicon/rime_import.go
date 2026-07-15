package userlexicon

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
)

// HydrateSourceIfEmpty imports user phrases from generated Rime lexicon files when the
// editable source file has no entries yet.
func HydrateSourceIfEmpty(userDir string, mode reverselookup.Mode, codeMap map[string]reverselookup.CodeRecord) (bool, error) {
	if userDir == "" {
		return false, nil
	}
	sourcePath := filepath.Join(userDir, SourceFileName)
	entries, err := LoadSourceEntriesWithResolver(sourcePath, codeMap, mode)
	if err != nil {
		return false, err
	}
	if len(entries) > 0 {
		return false, nil
	}
	imported, err := importEntriesFromRimeLexicons(userDir, mode, codeMap)
	if err != nil {
		return false, err
	}
	if len(imported) == 0 {
		return false, nil
	}
	if err := WriteSourceEntries(sourcePath, imported); err != nil {
		return false, err
	}
	return true, nil
}

func importEntriesFromRimeLexicons(userDir string, mode reverselookup.Mode, codeMap map[string]reverselookup.CodeRecord) ([]Entry, error) {
	paths := []string{
		RimeLexiconPath(userDir, string(mode)),
		filepath.Join(userDir, "custom_phrase.txt"),
	}
	for _, path := range paths {
		entries, err := parseRimeLexiconSourceEntries(path, mode, codeMap)
		if err != nil {
			return nil, err
		}
		if len(entries) > 0 {
			return entries, nil
		}
	}
	return nil, nil
}

func parseRimeLexiconSourceEntries(path string, mode reverselookup.Mode, codeMap map[string]reverselookup.CodeRecord) ([]Entry, error) {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	defer file.Close()

	entries := []Entry{}
	seen := map[string]struct{}{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		phrase := strings.TrimSpace(fields[0])
		code := strings.TrimSpace(fields[1])
		weight := DefaultEntryWeight
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight = strings.TrimSpace(fields[2])
		}
		if phrase == "" || code == "" {
			continue
		}
		pinyin, ok := reverselookup.DecodeCodeToNumericPinyin(code, codeMap, mode)
		if !ok || pinyin == "" {
			continue
		}
		if _, exists := seen[phrase]; exists {
			continue
		}
		seen[phrase] = struct{}{}
		entries = append(entries, Entry{Phrase: phrase, Pinyin: pinyin, Weight: weight})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}
