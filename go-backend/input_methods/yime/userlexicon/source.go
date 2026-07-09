package userlexicon

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
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
			return nil, fmt.Errorf("用户词库第 %d 行格式应为：词条<TAB>数字标调拼音<TAB>权重", lineNumber)
		}
		phrase := strings.TrimSpace(fields[0])
		pinyin := reverselookup.NormalizeNumericTonePinyinSpacing(fields[1])
		weight := DefaultEntryWeight
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight = strings.TrimSpace(fields[2])
		}
		if phrase == "" || pinyin == "" {
			return nil, fmt.Errorf("用户词库第 %d 行词条和数字标调拼音不能为空", lineNumber)
		}
		if !reverselookup.ValidateNumericTonePinyin(pinyin) {
			return nil, fmt.Errorf("用户词库第 %d 行数字标调拼音格式错误：%s", lineNumber, pinyin)
		}
		if _, err := strconv.Atoi(weight); err != nil {
			return nil, fmt.Errorf("用户词库第 %d 行权重必须是整数", lineNumber)
		}
		entries = append(entries, Entry{Phrase: phrase, Pinyin: pinyin, Weight: weight, LineNumber: lineNumber})
	}
	return entries, scanner.Err()
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
