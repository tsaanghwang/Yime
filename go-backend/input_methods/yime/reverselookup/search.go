package reverselookup

import (
	"strings"
)

const maxSearchResults = 200

type Index struct {
	SchemaID      string
	Mode          Mode
	CodeMap       map[string]CodeRecord
	DictLookup    map[string][]string
	UserEntries   []UserPhraseEntry
	MarkedLookup  map[string]string
	ReverseLookup map[string]string
	ActiveColumn  string
}

func (index *Index) SetMode(mode Mode) {
	if index == nil {
		return
	}
	index.Mode = mode
	index.SchemaID = SchemaIDFromMode(mode)
	index.ActiveColumn = CodeColumnFromMode(mode)
	index.ReverseLookup = buildReverseCodeLookup(index.CodeMap, index.ActiveColumn)
}

func buildLookupResult(
	phrase, source, numericPinyin, yimeCode string,
	codeMap map[string]CodeRecord,
	reverseLookup map[string]string,
	markedLookup map[string]string,
	activeColumn string,
) Result {
	code := yimeCode
	numeric := numericPinyin
	if numeric == "" && code != "" {
		if decoded, ok := splitYimeCodeToNumericPinyin(code, reverseLookup); ok {
			numeric = strings.Join(decoded, " ")
		}
	}
	if code == "" && numeric != "" {
		code = pinyinToCode(codeMap, numeric, activeColumn)
	}

	fullCode := ""
	variableCode := ""
	shorthandCode := ""
	if numeric != "" {
		fullCode = pinyinToCode(codeMap, numeric, "full")
		variableCode = pinyinToCode(codeMap, numeric, "variable")
		shorthandCode = pinyinToCode(codeMap, numeric, "shorthand")
	} else if code != "" {
		fullCode = code
		variableCode = code
		shorthandCode = code
	}

	activeCode := ""
	switch activeColumn {
	case "full":
		activeCode = fullCode
	case "shorthand":
		activeCode = shorthandCode
	default:
		activeCode = variableCode
	}
	if activeCode == "" {
		activeCode = code
	}

	return Result{
		Phrase:         phrase,
		Source:         source,
		NumericPinyin:  numeric,
		StandardPinyin: numericPinyinToMarked(numeric, markedLookup),
		ActiveCode:     activeCode,
		FullCode:       fullCode,
		VariableCode:   variableCode,
		ShorthandCode:  shorthandCode,
	}
}

func resolvePhraseLookupMulti(
	phrase string,
	userEntries []UserPhraseEntry,
	dictLookup map[string][]string,
	codeMap map[string]CodeRecord,
	reverseLookup map[string]string,
	markedLookup map[string]string,
	activeColumn string,
) []Result {
	text := strings.TrimSpace(phrase)
	if text == "" {
		return nil
	}

	results := []Result{}
	for _, entry := range userEntries {
		if entry.Phrase == text {
			results = append(results, buildLookupResult(text, "用户词库", entry.Pinyin, "", codeMap, reverseLookup, markedLookup, activeColumn))
		}
	}

	if codes, ok := dictLookup[text]; ok {
		for _, yimeCode := range codes {
			results = append(results, buildLookupResult(text, "系统词库", "", yimeCode, codeMap, reverseLookup, markedLookup, activeColumn))
		}
	} else if joinedCodes := joinCharCodeLookupMulti(text, dictLookup); joinedCodes != nil {
		for _, yimeCode := range joinedCodes {
			results = append(results, buildLookupResult(text, "逐字拼接", "", yimeCode, codeMap, reverseLookup, markedLookup, activeColumn))
		}
	}
	return results
}

func (index *Index) Search(term string, containsMatch bool) []Result {
	if index == nil {
		return nil
	}
	text := strings.TrimSpace(term)
	if text == "" {
		return nil
	}

	results := []Result{}
	seen := map[string]struct{}{}
	addResult := func(item Result) {
		key := item.Phrase + "|" + item.ActiveCode
		if _, ok := seen[key]; ok {
			return
		}
		seen[key] = struct{}{}
		results = append(results, item)
	}

	for _, item := range resolvePhraseLookupMulti(text, index.UserEntries, index.DictLookup, index.CodeMap, index.ReverseLookup, index.MarkedLookup, index.ActiveColumn) {
		addResult(item)
	}
	if len(results) > 0 && !containsMatch {
		return results
	}

	for _, entry := range index.UserEntries {
		if len(results) >= maxSearchResults {
			break
		}
		if entry.Phrase == text {
			continue
		}
		if !containsMatch || !strings.Contains(entry.Phrase, text) {
			continue
		}
		for _, item := range resolvePhraseLookupMulti(entry.Phrase, index.UserEntries, index.DictLookup, index.CodeMap, index.ReverseLookup, index.MarkedLookup, index.ActiveColumn) {
			addResult(item)
			if len(results) >= maxSearchResults {
				break
			}
		}
	}

	if containsMatch {
		for phrase := range index.DictLookup {
			if len(results) >= maxSearchResults {
				break
			}
			if !strings.Contains(phrase, text) {
				continue
			}
			for _, item := range resolvePhraseLookupMulti(phrase, index.UserEntries, index.DictLookup, index.CodeMap, index.ReverseLookup, index.MarkedLookup, index.ActiveColumn) {
				addResult(item)
				if len(results) >= maxSearchResults {
					break
				}
			}
		}
	}
	return results
}
