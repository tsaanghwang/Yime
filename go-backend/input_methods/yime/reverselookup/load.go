package reverselookup

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/EasyIME/pime-go/input_methods/yime/codemode"
)

func loadCodeMap(path string) (map[string]CodeRecord, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("找不到拼音编码表：%s", path)
	}
	defer file.Close()

	codeMap := map[string]CodeRecord{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		if lineNumber == 1 {
			continue
		}
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		key := normalizeNumericTonePinyin(fields[0])
		derived, err := codemode.BuildRecord(fields[1])
		if err != nil {
			return nil, fmt.Errorf("拼音编码表第 %d 行等长码无效: %w", lineNumber, err)
		}
		record := CodeRecord{
			Full:      derived.Full,
			Variable:  derived.Variable,
			Shorthand: derived.Shorthand,
		}
		codeMap[key] = record
		if strings.Contains(key, "ü") {
			codeMap[strings.ReplaceAll(key, "ü", "v")] = record
			codeMap[strings.ReplaceAll(key, "ü", "u:")] = record
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return codeMap, nil
}

func loadDictLookupMulti(path string) (map[string][]string, error) {
	lookup := map[string][]string{}
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return lookup, nil
		}
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	inData := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !inData {
			if line == "..." {
				inData = true
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		text := strings.TrimSpace(fields[0])
		code := strings.TrimSpace(fields[1])
		if text == "" || code == "" {
			continue
		}
		codes := lookup[text]
		if !containsString(codes, code) {
			lookup[text] = append(codes, code)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return lookup, nil
}

func loadUserPhraseEntries(path string, codeMap map[string]CodeRecord, mode Mode) ([]UserPhraseEntry, error) {
	entries := []UserPhraseEntry{}
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return entries, nil
		}
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		phrase, pinyin, ok := ParseUserPhraseFields(fields, codeMap, mode)
		if !ok {
			continue
		}
		entries = append(entries, UserPhraseEntry{Phrase: phrase, Pinyin: pinyin})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}

func loadNumericToMarkedLookup(path string) (map[string]string, error) {
	lookup := map[string]string{}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return lookup, nil
		}
		return nil, err
	}
	raw := map[string]string{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return lookup, nil
	}
	for key, value := range raw {
		normalizedKey := normalizeNumericTonePinyin(key)
		value = strings.TrimSpace(value)
		if normalizedKey == "" || value == "" {
			continue
		}
		lookup[normalizedKey] = value
	}
	return lookup, nil
}

func buildReverseCodeLookup(codeMap map[string]CodeRecord, column string) map[string]string {
	lookup := map[string]string{}
	for numeric, record := range codeMap {
		code := codeValue(record, column)
		if code == "" {
			continue
		}
		if _, exists := lookup[code]; !exists {
			lookup[code] = numeric
		}
	}
	return lookup
}

func dataPaths(sharedDir, userDir string, mode Mode) (codeMapPath, markedPath, userPhrasePath, dictPath string, schemaID string) {
	schemaID = SchemaIDFromMode(mode)
	codeMapPath = filepath.Join(sharedDir, "yime_pinyin_codes.tsv")
	markedPath = filepath.Join(sharedDir, "pinyin_normalized.json")
	userPhrasePath = filepath.Join(userDir, "yime_user_phrases.txt")
	dictPath = resolveDictPath(sharedDir, userDir, schemaID)
	return
}

func resolveDictPath(sharedDir, userDir, schemaID string) string {
	candidates := []string{
		filepath.Join(sharedDir, schemaID+".dict.yaml"),
	}
	if userDir != "" {
		candidates = append(candidates, filepath.Join(userDir, schemaID+".dict.yaml"))
	}
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && info.Size() > 0 {
			return candidate
		}
	}
	if len(candidates) > 0 {
		return candidates[0]
	}
	return ""
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
