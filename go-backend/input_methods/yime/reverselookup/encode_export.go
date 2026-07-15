package reverselookup

import (
	"fmt"
	"path/filepath"
	"strings"
	"unicode/utf8"
)

// LoadSharedCodeMap loads yime_pinyin_codes.tsv from a shared runtime directory.
func LoadSharedCodeMap(sharedDir string) (map[string]CodeRecord, error) {
	return loadCodeMap(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"))
}

// NormalizeNumericTonePinyinSpacing normalizes numeric-tone pinyin spacing.
func NormalizeNumericTonePinyinSpacing(rawPinyin string) string {
	return normalizeNumericTonePinyinSpacing(rawPinyin)
}

// ValidateNumericTonePinyin reports whether pinyin uses valid numeric-tone syllables.
func ValidateNumericTonePinyin(pinyin string) bool {
	parts := strings.Fields(pinyin)
	if len(parts) == 0 {
		return false
	}
	for _, part := range parts {
		runes := []rune(part)
		if len(runes) < 2 {
			return false
		}
		last := runes[len(runes)-1]
		if last < '1' || last > '5' {
			return false
		}
		for _, char := range runes[:len(runes)-1] {
			if (char >= 'a' && char <= 'z') || char == 'ü' {
				continue
			}
			return false
		}
	}
	return true
}

// EncodeNumericTonePinyin converts numeric-tone pinyin to a Yime code for the given mode.
func EncodeNumericTonePinyin(codeMap map[string]CodeRecord, pinyin string, mode Mode) (string, int, error) {
	normalized := normalizeNumericTonePinyinSpacing(pinyin)
	if normalized == "" {
		return "", 0, fmt.Errorf("数字标调拼音不能为空")
	}
	parts := strings.Fields(normalized)
	for _, part := range parts {
		if !ValidateNumericTonePinyin(part) {
			return "", 0, fmt.Errorf("数字标调拼音格式错误：%s。请使用 zhong1 guo2 或 zhong1guo2 这样的格式", part)
		}
		key := normalizeNumericTonePinyin(part)
		if _, ok := codeMap[key]; !ok {
			return "", 0, fmt.Errorf("找不到拼音：%s。请检查拼音和声调数字", part)
		}
	}
	code := pinyinToCode(codeMap, normalized, CodeColumnFromMode(mode))
	if strings.TrimSpace(code) == "" {
		return "", 0, fmt.Errorf("拼音未生成有效音元编码")
	}
	return code, len(parts), nil
}

// PhraseSyllableCount returns the Unicode text element count of phrase text.
func PhraseSyllableCount(phrase string) int {
	return utf8.RuneCountInString(phrase)
}

// ValidateEntryForMode checks phrase syllable count matches pinyin and encoding succeeds.
func ValidateEntryForMode(codeMap map[string]CodeRecord, phrase, pinyin string, mode Mode) error {
	_, syllables, err := EncodeNumericTonePinyin(codeMap, pinyin, mode)
	if err != nil {
		return err
	}
	textElements := PhraseSyllableCount(phrase)
	if textElements != syllables {
		return fmt.Errorf("词条字数（%d）和拼音音节数（%d）不一致", textElements, syllables)
	}
	return nil
}
