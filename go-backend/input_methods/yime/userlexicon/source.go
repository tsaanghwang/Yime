package userlexicon

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

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
	return os.WriteFile(path, []byte(content), 0o644)
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
