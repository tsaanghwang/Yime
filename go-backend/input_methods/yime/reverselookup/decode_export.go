package reverselookup

import "strings"

// DecodeCodeToNumericPinyin converts a Yime encoding back to spaced numeric-tone pinyin.
func DecodeCodeToNumericPinyin(code string, codeMap map[string]CodeRecord, mode Mode) (string, bool) {
	code = strings.TrimSpace(code)
	if code == "" || len(codeMap) == 0 {
		return "", false
	}
	lookup := buildReverseCodeLookup(codeMap, CodeColumnFromMode(mode))
	parts, ok := splitYimeCodeToNumericPinyin(code, lookup)
	if !ok || len(parts) == 0 {
		return "", false
	}
	return normalizeNumericTonePinyinSpacing(strings.Join(parts, " ")), true
}
