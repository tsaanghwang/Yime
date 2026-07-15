package userblocklist

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

const (
	SourceFileName    = "yime_blocklist.txt"
	sourceHeaderLine1 = "# PIME Yime user blocklist"
	sourceHeaderLine2 = "# format: one blocked phrase per line"
	sourceHeaderExample = "# example: 某个不想看到的词"
)

type Entry struct {
	Phrase     string
	LineNumber int
}

func SourcePath(userDir string) string {
	return filepath.Join(userDir, SourceFileName)
}

func EnsureSourceFile(path string) error {
	if _, err := os.Stat(path); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	return WritePhrases(path, nil)
}

func LoadEntries(path string) ([]Entry, error) {
	if err := EnsureSourceFile(path); err != nil {
		return nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	entries := []Entry{}
	seen := map[string]bool{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		phrase, err := NormalizePhrase(line)
		if err != nil {
			continue
		}
		if seen[phrase] {
			continue
		}
		seen[phrase] = true
		entries = append(entries, Entry{Phrase: phrase, LineNumber: lineNumber})
	}
	return entries, scanner.Err()
}

func LoadSet(path string) (map[string]struct{}, error) {
	entries, err := LoadEntries(path)
	if err != nil {
		return nil, err
	}
	set := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		set[entry.Phrase] = struct{}{}
	}
	return set, nil
}

func WritePhrases(path string, phrases []string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	lines := []string{sourceHeaderLine1, sourceHeaderLine2, sourceHeaderExample}
	seen := map[string]bool{}
	for _, raw := range phrases {
		phrase, err := NormalizePhrase(raw)
		if err != nil {
			continue
		}
		if seen[phrase] {
			continue
		}
		seen[phrase] = true
		lines = append(lines, phrase)
	}
	content := strings.Join(lines, "\r\n") + "\r\n"
	return os.WriteFile(path, []byte(content), 0o644)
}

func WriteEntries(path string, entries []Entry) error {
	phrases := make([]string, 0, len(entries))
	for _, entry := range entries {
		phrases = append(phrases, entry.Phrase)
	}
	return WritePhrases(path, phrases)
}

func NormalizePhrase(raw string) (string, error) {
	phrase := strings.TrimSpace(raw)
	if phrase == "" {
		return "", fmt.Errorf("词条不能为空")
	}
	if strings.ContainsAny(phrase, "\t\r\n") {
		return "", fmt.Errorf("词条不能包含制表符或换行")
	}
	if utf8.RuneCountInString(phrase) > 64 {
		return "", fmt.Errorf("词条过长")
	}
	return phrase, nil
}

func IsBlocked(set map[string]struct{}, text string) bool {
	if len(set) == 0 {
		return false
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return false
	}
	_, ok := set[text]
	return ok
}

func FilterEntries(entries []Entry, keyword string) []Entry {
	keyword = strings.TrimSpace(keyword)
	if keyword == "" {
		return append([]Entry(nil), entries...)
	}
	filtered := make([]Entry, 0, len(entries))
	for _, entry := range entries {
		if containsFold(entry.Phrase, keyword) {
			filtered = append(filtered, entry)
		}
	}
	return filtered
}

func UpsertPhrase(path string, phrase string) (bool, error) {
	normalized, err := NormalizePhrase(phrase)
	if err != nil {
		return false, err
	}
	entries, err := LoadEntries(path)
	if err != nil {
		return false, err
	}
	for _, entry := range entries {
		if entry.Phrase == normalized {
			return true, nil
		}
	}
	entries = append(entries, Entry{Phrase: normalized})
	return false, WriteEntries(path, entries)
}

func RemovePhrases(path string, phrases []string) error {
	removeSet := map[string]bool{}
	for _, phrase := range phrases {
		normalized, err := NormalizePhrase(phrase)
		if err != nil {
			continue
		}
		removeSet[normalized] = true
	}
	entries, err := LoadEntries(path)
	if err != nil {
		return err
	}
	remaining := make([]Entry, 0, len(entries))
	for _, entry := range entries {
		if removeSet[entry.Phrase] {
			continue
		}
		remaining = append(remaining, entry)
	}
	return WriteEntries(path, remaining)
}

func ImportPhrases(path string, imported []string) (added int, skipped int, err error) {
	entries, err := LoadEntries(path)
	if err != nil {
		return 0, 0, err
	}
	existing := map[string]bool{}
	for _, entry := range entries {
		existing[entry.Phrase] = true
	}
	for _, raw := range imported {
		phrase, normErr := NormalizePhrase(raw)
		if normErr != nil {
			skipped++
			continue
		}
		if existing[phrase] {
			skipped++
			continue
		}
		existing[phrase] = true
		entries = append(entries, Entry{Phrase: phrase})
		added++
	}
	if err := WriteEntries(path, entries); err != nil {
		return 0, 0, err
	}
	return added, skipped, nil
}

func containsFold(haystack, needle string) bool {
	return strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
}
