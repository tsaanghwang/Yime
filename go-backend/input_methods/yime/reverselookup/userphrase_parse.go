package reverselookup

import "strings"

// ParseUserPhraseFields interprets a user phrase TSV row as phrase + numeric-tone pinyin.
// When pinyin validation fails, the second field may be decoded as a Yime encoding.
func ParseUserPhraseFields(fields []string, codeMap map[string]CodeRecord, mode Mode) (phrase, pinyin string, ok bool) {
	if len(fields) < 2 {
		return "", "", false
	}
	phrase = strings.TrimSpace(fields[0])
	rawField := strings.TrimSpace(fields[1])
	if phrase == "" || rawField == "" {
		return "", "", false
	}
	pinyin = NormalizeNumericTonePinyinSpacing(rawField)
	if !ValidateNumericTonePinyin(pinyin) && len(codeMap) > 0 && mode != "" {
		if decoded, decodedOK := DecodeCodeToNumericPinyin(rawField, codeMap, mode); decodedOK {
			pinyin = decoded
		}
	}
	if !ValidateNumericTonePinyin(pinyin) {
		return "", "", false
	}
	return phrase, pinyin, true
}
