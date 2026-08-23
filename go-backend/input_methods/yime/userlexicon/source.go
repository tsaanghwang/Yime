package userlexicon

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

const (
	// Imports are interactive desktop operations. Bound them before parsing so
	// a user-selected file cannot force unbounded allocation or disk churn.
	MaxImportFileSize = int64(16 * 1024 * 1024)
	MaxImportEntries  = 100000
)

// ValidateImportFile rejects an import before its contents are allocated.
func ValidateImportFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("导入文件必须是普通文件")
	}
	if info.Size() > MaxImportFileSize {
		return fmt.Errorf("导入文件超过 %d MiB 上限", MaxImportFileSize/(1024*1024))
	}
	return nil
}

// ValidateImportEntryCount bounds the accepted, parsed record set.
func ValidateImportEntryCount(entries []Entry) error {
	if len(entries) > MaxImportEntries {
		return fmt.Errorf("导入词条超过 %d 条上限", MaxImportEntries)
	}
	return nil
}

// EnsureSourceFile creates the source lexicon file with a header when missing.
func EnsureSourceFile(path string) error {
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	return WriteSourceEntries(path, nil)
}

// LoadSourceEntries reads user lexicon entries from the source TSV file.
func LoadSourceEntries(path string) ([]Entry, error) {
	return LoadSourceEntriesWithResolver(path, nil, "")
}

// LoadSourceEntriesWithResolver reads entries and can interpret the second column as
// numeric-tone pinyin or, when a code map is available, as a Yime encoding.
func LoadSourceEntriesWithResolver(path string, codeMap map[string]reverselookup.CodeRecord, mode reverselookup.Mode) ([]Entry, error) {
	if err := EnsureSourceFile(path); err != nil {
		return nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	entries := []Entry{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		entry, ok := parseSourceEntry(fields, lineNumber, codeMap, mode)
		if !ok {
			continue
		}
		entries = append(entries, entry)
	}
	return entries, scanner.Err()
}

func parseSourceEntry(fields []string, lineNumber int, codeMap map[string]reverselookup.CodeRecord, mode reverselookup.Mode) (Entry, bool) {
	weight := DefaultEntryWeight
	if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
		weight = strings.TrimSpace(fields[2])
	}
	if _, err := strconv.Atoi(weight); err != nil {
		return Entry{}, false
	}
	phrase, pinyin, ok := reverselookup.ParseUserPhraseFields(fields, codeMap, mode)
	if !ok {
		return Entry{}, false
	}
	return Entry{Phrase: phrase, Pinyin: pinyin, Weight: weight, LineNumber: lineNumber}, true
}

// WriteSourceEntries writes entries back to the source lexicon file.
func WriteSourceEntries(path string, entries []Entry) error {
	lines := []string{sourceHeaderLine1, sourceHeaderLine2, sourceHeaderExample}
	for _, entry := range entries {
		lines = append(lines, entry.Phrase+"\t"+entry.Pinyin+"\t"+entry.Weight)
	}
	content := strings.Join(lines, "\n") + "\n"
	return writeSourceFileAtomically(path, []byte(content))
}

func writeSourceFileAtomically(path string, content []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(dir, ".yime-user-lexicon-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o644); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(content); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return os.Rename(temporaryPath, path)
	} else if err != nil {
		return err
	}

	backup, err := os.CreateTemp(dir, ".yime-user-lexicon-backup-*.tmp")
	if err != nil {
		return err
	}
	backupPath := backup.Name()
	if err := backup.Close(); err != nil {
		return err
	}
	if err := os.Remove(backupPath); err != nil {
		return err
	}
	defer os.Remove(backupPath)
	if err := os.Rename(path, backupPath); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		_ = os.Rename(backupPath, path)
		return err
	}
	return os.Remove(backupPath)
}

// MergeSourceEntries applies a batch with the same last-write-wins semantics
// as sequential UpsertSourceEntry calls, but performs no filesystem I/O.
func MergeSourceEntries(current, imported []Entry) []Entry {
	result := make([]Entry, len(current))
	indexByPhrase := make(map[string]int, len(current)+len(imported))
	for i, entry := range current {
		result[i] = entry.Clone()
		if _, exists := indexByPhrase[entry.Phrase]; !exists {
			indexByPhrase[entry.Phrase] = i
		}
	}
	for _, entry := range imported {
		if index, exists := indexByPhrase[entry.Phrase]; exists {
			result[index] = entry.Clone()
			continue
		}
		indexByPhrase[entry.Phrase] = len(result)
		result = append(result, entry.Clone())
	}
	return result
}

// UpsertSourceEntry inserts or replaces an entry by phrase key.
func UpsertSourceEntry(path string, entry Entry) (updated bool, err error) {
	entries, err := LoadSourceEntries(path)
	if err != nil {
		return false, err
	}
	result := make([]Entry, 0, len(entries)+1)
	replaced := false
	for _, existing := range entries {
		if existing.Phrase == entry.Phrase {
			if !replaced {
				result = append(result, entry.Clone())
				replaced = true
			}
			continue
		}
		result = append(result, existing)
	}
	if !replaced {
		result = append(result, entry.Clone())
	}
	return replaced, WriteSourceEntries(path, result)
}

// RemoveSourceEntry removes an entry by phrase.
func RemoveSourceEntry(path, phrase string) (bool, error) {
	entries, err := LoadSourceEntries(path)
	if err != nil {
		return false, err
	}
	result := make([]Entry, 0, len(entries))
	removed := false
	for _, entry := range entries {
		if entry.Phrase == phrase {
			removed = true
			continue
		}
		result = append(result, entry)
	}
	if !removed {
		return false, nil
	}
	return true, WriteSourceEntries(path, result)
}

// AssertEntryFields validates basic entry field constraints.
func AssertEntryFields(entry Entry) error {
	if strings.TrimSpace(entry.Phrase) == "" {
		return fmt.Errorf("请输入词条")
	}
	if strings.TrimSpace(entry.Pinyin) == "" {
		return fmt.Errorf("请输入数字标调拼音，例如 zhong1 guo2")
	}
	if strings.TrimSpace(entry.Weight) == "" {
		return fmt.Errorf("请输入权重")
	}
	if strings.ContainsAny(entry.Phrase, "\t\r\n") {
		return fmt.Errorf("词条不能包含制表符或换行")
	}
	if _, err := strconv.Atoi(entry.Weight); err != nil {
		return fmt.Errorf("权重必须是整数")
	}
	return nil
}
