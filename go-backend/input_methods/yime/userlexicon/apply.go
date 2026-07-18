package userlexicon

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

// RimeLexiconPath returns the generated Rime lexicon path for a mode.
func RimeLexiconPath(userDir, mode string) string {
	return filepath.Join(userDir, "custom_phrase_"+mode+".txt")
}

// RebuildRimeLexicon writes the generated Rime lexicon for one mode.
func RebuildRimeLexicon(sourcePath, targetPath string, codeMap map[string]reverselookup.CodeRecord, mode reverselookup.Mode) error {
	entries, err := LoadSourceEntries(sourcePath)
	if err != nil {
		return err
	}
	var content strings.Builder
	content.WriteString(generatedHeaderLine1)
	content.WriteByte('\n')
	content.WriteString(generatedHeaderLine2)
	content.WriteByte('\n')
	for _, entry := range entries {
		code, _, err := reverselookup.EncodeNumericTonePinyin(codeMap, entry.Pinyin, mode)
		if err != nil {
			if entry.LineNumber > 0 {
				return fmt.Errorf("用户词库第 %d 行拼音 %q 无法转换: %w", entry.LineNumber, entry.Pinyin, err)
			}
			return fmt.Errorf("词条 %q 拼音 %q 无法转换: %w", entry.Phrase, entry.Pinyin, err)
		}
		content.WriteString(entry.Phrase)
		content.WriteByte('\t')
		content.WriteString(code)
		content.WriteByte('\t')
		content.WriteString(entry.Weight)
		content.WriteByte('\n')
	}
	return os.WriteFile(targetPath, []byte(content.String()), 0o644)
}

// RebuildAllRimeLexicons regenerates the three derived Rime user lexicons
// from the user-authored numeric-tone Pinyin source and the installed code
// map. The source file is left untouched.
func RebuildAllRimeLexicons(sharedDir, userDir string) error {
	sourcePath := filepath.Join(userDir, SourceFileName)
	if _, err := os.Stat(sourcePath); errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	codeMap, err := reverselookup.LoadSharedCodeMap(sharedDir)
	if err != nil {
		return err
	}
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		if err := RebuildRimeLexicon(sourcePath, RimeLexiconPath(userDir, string(mode)), codeMap, mode); err != nil {
			return fmt.Errorf("rebuild %s user lexicon: %w", mode, err)
		}
	}
	return nil
}
