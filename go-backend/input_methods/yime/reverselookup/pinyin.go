package reverselookup

import (
	"strings"
	"unicode/utf8"
)

func normalizeNumericTonePinyin(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "u:", "ü")
	value = strings.ReplaceAll(value, "v", "ü")
	return value
}

func splitCompactNumericTonePinyinToken(token string) []string {
	normalizedToken := strings.TrimSpace(token)
	if normalizedToken == "" {
		return nil
	}
	parts := []string{}
	start := 0
	sawToneDigit := false
	for index, char := range normalizedToken {
		if char < '1' || char > '5' {
			continue
		}
		sawToneDigit = true
		if index == start {
			return []string{normalizedToken}
		}
		parts = append(parts, normalizedToken[start:index+1])
		start = index + 1
	}
	if !sawToneDigit || start != len(normalizedToken) {
		return []string{normalizedToken}
	}
	return parts
}

func normalizeNumericTonePinyinSpacing(rawPinyin string) string {
	parts := []string{}
	for _, token := range strings.Fields(rawPinyin) {
		for _, part := range splitCompactNumericTonePinyinToken(token) {
			normalized := normalizeNumericTonePinyin(part)
			if normalized != "" {
				parts = append(parts, normalized)
			}
		}
	}
	return strings.Join(parts, " ")
}

func markedVowelIndex(syllable []rune) int {
	for i, r := range syllable {
		if r == 'a' || r == 'e' {
			return i
		}
	}
	for i := 0; i < len(syllable)-1; i++ {
		if syllable[i] == 'o' && syllable[i+1] == 'u' {
			return i
		}
	}
	for i := len(syllable) - 1; i >= 0; i-- {
		switch syllable[i] {
		case 'a', 'e', 'i', 'o', 'u', 'ü':
			return i
		}
	}
	return -1
}

func accentVowel(vowel rune, tone int) rune {
	switch vowel {
	case 'a':
		return []rune{'a', 'ā', 'á', 'ǎ', 'à'}[tone]
	case 'e':
		return []rune{'e', 'ē', 'é', 'ě', 'è'}[tone]
	case 'i':
		return []rune{'i', 'ī', 'í', 'ǐ', 'ì'}[tone]
	case 'o':
		return []rune{'o', 'ō', 'ó', 'ǒ', 'ò'}[tone]
	case 'u':
		return []rune{'u', 'ū', 'ú', 'ǔ', 'ù'}[tone]
	case 'ü':
		return []rune{'ü', 'ǖ', 'ǘ', 'ǚ', 'ǜ'}[tone]
	default:
		return vowel
	}
}

func numericSyllableToMarked(syllable string) string {
	normalized := normalizeNumericTonePinyin(syllable)
	if normalized == "" {
		return ""
	}
	runes := []rune(normalized)
	last := runes[len(runes)-1]
	if last < '1' || last > '5' {
		return normalized
	}
	tone := int(last - '0')
	if tone == 5 || len(runes) < 2 {
		if len(runes) < 2 {
			return normalized
		}
		return string(runes[:len(runes)-1])
	}
	base := append([]rune(nil), runes[:len(runes)-1]...)
	index := markedVowelIndex(base)
	if index < 0 {
		return string(base)
	}
	base[index] = accentVowel(base[index], tone)
	return string(base)
}

func numericPinyinToMarked(value string, markedLookup map[string]string) string {
	parts := strings.Fields(value)
	if len(parts) == 0 {
		return ""
	}
	marked := make([]string, 0, len(parts))
	for _, part := range parts {
		normalized := normalizeNumericTonePinyin(part)
		if normalized == "" {
			continue
		}
		if result := markedLookup[normalized]; result != "" {
			marked = append(marked, result)
			continue
		}
		marked = append(marked, numericSyllableToMarked(normalized))
	}
	return strings.Join(marked, " ")
}

func splitYimeCodeToNumericPinyin(code string, lookup map[string]string) ([]string, bool) {
	code = strings.TrimSpace(code)
	if code == "" {
		return nil, false
	}
	memo := map[int][]string{}
	failed := map[int]bool{}
	var decode func(start int) ([]string, bool)
	decode = func(start int) ([]string, bool) {
		if start == len(code) {
			return []string{}, true
		}
		if failed[start] {
			return nil, false
		}
		if cached, ok := memo[start]; ok {
			return append([]string(nil), cached...), true
		}
		for end := len(code); end > start; end-- {
			numeric := lookup[code[start:end]]
			if numeric == "" {
				continue
			}
			suffix, ok := decode(end)
			if !ok {
				continue
			}
			result := make([]string, 0, len(suffix)+1)
			result = append(result, numeric)
			result = append(result, suffix...)
			memo[start] = result
			return append([]string(nil), result...), true
		}
		failed[start] = true
		return nil, false
	}
	return decode(0)
}

func pinyinToCode(codeMap map[string]CodeRecord, pinyin string, column string) string {
	normalized := normalizeNumericTonePinyinSpacing(pinyin)
	if normalized == "" {
		return ""
	}
	var builder strings.Builder
	for _, item := range strings.Fields(normalized) {
		record, ok := codeMap[item]
		if !ok {
			return ""
		}
		builder.WriteString(codeValue(record, column))
	}
	return builder.String()
}

func joinCharCodeLookupMulti(text string, lookup map[string][]string) []string {
	if text == "" {
		return nil
	}
	charResults := make([][]string, 0, utf8.RuneCountInString(text))
	for _, r := range text {
		key := string(r)
		codes, ok := lookup[key]
		if !ok || len(codes) == 0 {
			return nil
		}
		charResults = append(charResults, append([]string(nil), codes...))
	}
	if len(charResults) == 0 {
		return nil
	}
	result := append([]string(nil), charResults[0]...)
	for i := 1; i < len(charResults); i++ {
		next := make([]string, 0, len(result)*len(charResults[i]))
		for _, prefix := range result {
			for _, suffix := range charResults[i] {
				next = append(next, prefix+suffix)
			}
		}
		result = next
	}
	return result
}
