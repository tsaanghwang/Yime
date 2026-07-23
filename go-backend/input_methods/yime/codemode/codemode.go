// Package codemode derives Yime variable and shorthand lookup codes from the
// canonical fixed-length four-code representation.
package codemode

import (
	"fmt"
	"strings"
)

const (
	SyllableCodeLength = 4
	VirtualInitial     = '\''
	LayoutVersion      = "rime-layout-key-trial-v1-2026-07-18"
	LayoutAlphabet     = "1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG"
)

// Record contains all runtime representations derived from one canonical code.
type Record struct {
	Full      string
	Variable  string
	Shorthand string
	// *Spelling keeps the same codes split at syllable boundaries for
	// script_translator.  Runtime keystrokes remain delimiter-free; spaces are
	// dictionary syntax that let librime build a syllable graph and complete an
	// unfinished final syllable after an already valid sentence prefix.
	FullSpelling      string
	VariableSpelling  string
	ShorthandSpelling string
}

type musicalMetadata struct {
	quality int
	tone    int
}

// Each triple is high, middle, low for one musical-quality group. These are
// Rime layout-key projections of M01-M33, not a second lexicon source.
var musicalGroups = []string{
	"jkl", "uio", "m,.", "fds", "rew", "vcx", "JKL", "UIO", "M<>", "aNz", ";G/",
}

var musicalByKey = buildMusicalMetadata()
var layoutKeySet = buildLayoutKeySet()

func buildLayoutKeySet() map[rune]bool {
	result := make(map[rune]bool, len([]rune(LayoutAlphabet)))
	for _, key := range LayoutAlphabet {
		result[key] = true
	}
	return result
}

func buildMusicalMetadata() map[rune]musicalMetadata {
	result := make(map[rune]musicalMetadata, len(musicalGroups)*3)
	for quality, group := range musicalGroups {
		keys := []rune(group)
		for tone, key := range keys {
			result[key] = musicalMetadata{quality: quality, tone: tone}
		}
	}
	return result
}

// BuildRecord derives all modes from a canonical code containing one or more
// complete four-code syllables.
func BuildRecord(full string) (Record, error) {
	// Rime script dictionaries write spaces between syllables.  The canonical
	// fixed-length value and older table dictionaries do not.  Accept both
	// representations at this boundary and rebuild the authoritative split
	// below from groups of four codes.
	full = strings.ReplaceAll(strings.TrimSpace(full), " ", "")
	if full == "" {
		return Record{}, fmt.Errorf("等长码不能为空")
	}
	runes := []rune(full)
	if len(runes)%SyllableCodeLength != 0 {
		return Record{}, fmt.Errorf("等长码长度必须是 %d 的倍数，实际为 %d：%q", SyllableCodeLength, len(runes), full)
	}
	for _, key := range runes {
		if !layoutKeySet[key] {
			return Record{}, fmt.Errorf("等长码包含布局外字符 %q", key)
		}
	}
	var variable strings.Builder
	var shorthand strings.Builder
	fullParts := make([]string, 0, len(runes)/SyllableCodeLength)
	variableParts := make([]string, 0, len(runes)/SyllableCodeLength)
	shorthandParts := make([]string, 0, len(runes)/SyllableCodeLength)
	for start := 0; start < len(runes); start += SyllableCodeLength {
		syllable := runes[start : start+SyllableCodeLength]
		fullParts = append(fullParts, string(syllable))
		// The first position is a real or virtual initial and must remain an
		// explicit syllable boundary. Only adjacent identical yinyuan that
		// compose the three-position ganyin are merged.
		initial := syllable[:1]
		variableGanyin := mergeAdjacent(syllable[1:])
		variablePart := append(append([]rune(nil), initial...), variableGanyin...)
		variableText := string(variablePart)
		variable.WriteString(variableText)
		variableParts = append(variableParts, variableText)

		// Shorthand is derived from the variable result: retain its initial and
		// apply only the middle-tone omission rule to its ganyin.
		initial = variablePart[:1]
		ganyin := variablePart[1:]
		shorthandPart := string(initial) + string(omitMiddleTone(ganyin))
		shorthand.WriteString(shorthandPart)
		shorthandParts = append(shorthandParts, shorthandPart)
	}
	record := Record{
		Full: full, Variable: variable.String(), Shorthand: shorthand.String(),
		FullSpelling:      strings.Join(fullParts, " "),
		VariableSpelling:  strings.Join(variableParts, " "),
		ShorthandSpelling: strings.Join(shorthandParts, " "),
	}
	if err := ValidateContinuousInputRecord(record); err != nil {
		return Record{}, err
	}
	return record, nil
}

// ValidateContinuousInputRecord protects the two dictionary invariants needed
// by Rime sentence composition: every spelling has an explicit syllable split,
// and every projected syllable retains its real or virtual initial. Without
// both, completion can keep working while multi-syllable sentence paths vanish.
func ValidateContinuousInputRecord(record Record) error {
	full := []rune(record.Full)
	if len(full) == 0 || len(full)%SyllableCodeLength != 0 {
		return fmt.Errorf("continuous input requires a non-empty full code divisible by %d", SyllableCodeLength)
	}
	wantSyllables := len(full) / SyllableCodeLength
	type spellingField struct {
		name     string
		code     string
		spelling string
	}
	fields := []spellingField{
		{"full", record.Full, record.FullSpelling},
		{"variable", record.Variable, record.VariableSpelling},
		{"shorthand", record.Shorthand, record.ShorthandSpelling},
	}
	for _, field := range fields {
		parts := strings.Fields(field.spelling)
		if len(parts) != wantSyllables {
			return fmt.Errorf("%s spelling has %d syllables, want %d", field.name, len(parts), wantSyllables)
		}
		if strings.Join(parts, "") != field.code {
			return fmt.Errorf("%s spelling does not reconstruct its runtime code", field.name)
		}
		for i, part := range parts {
			runes := []rune(part)
			if len(runes) == 0 || runes[0] != full[i*SyllableCodeLength] {
				return fmt.Errorf("%s syllable %d lost its real or virtual initial", field.name, i+1)
			}
		}
	}
	return nil
}

func mergeAdjacent(input []rune) []rune {
	merged := make([]rune, 0, len(input))
	for _, item := range input {
		if len(merged) == 0 || merged[len(merged)-1] != item {
			merged = append(merged, item)
		}
	}
	return merged
}

func omitMiddleTone(ganyin []rune) []rune {
	if len(ganyin) != 3 {
		return append([]rune(nil), ganyin...)
	}
	first, firstOK := musicalByKey[ganyin[0]]
	middle, middleOK := musicalByKey[ganyin[1]]
	last, lastOK := musicalByKey[ganyin[2]]
	if !firstOK || !middleOK || !lastOK || first.quality != middle.quality || middle.quality != last.quality {
		return append([]rune(nil), ganyin...)
	}
	if (first.tone == 0 && middle.tone == 1 && last.tone == 2) ||
		(first.tone == 2 && middle.tone == 1 && last.tone == 0) {
		return []rune{ganyin[0], ganyin[2]}
	}
	return append([]rune(nil), ganyin...)
}
