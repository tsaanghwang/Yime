// Package codemode derives Yime variable and shorthand lookup codes from the
// canonical fixed-length four-code representation.
package codemode

import (
	"fmt"
	"strings"
)

const (
	SyllableCodeLength       = 4
	ApostropheVirtualShouyin = '\''
	LayoutVersion            = "rime-layout-key-trial-v1-2026-07-18"
	LayoutAlphabet           = "1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./JKLUIOM<>NG"
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

// AlignedProjection applies the same position deletions as a Yime code mode to
// another four-rune-per-syllable representation, such as the PUA yinyuan
// glyphs shown in candidate annotations.
type AlignedProjection struct {
	Full      string
	Variable  string
	Shorthand string
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
		variableIndices, shorthandIndices := syllableProjectionIndices(syllable)
		variablePart := selectRunes(syllable, variableIndices)
		variableText := string(variablePart)
		variable.WriteString(variableText)
		variableParts = append(variableParts, variableText)

		shorthandPart := string(selectRunes(syllable, shorthandIndices))
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

// ProjectAligned projects an aligned representation with the exact position
// mask used to derive variable and shorthand codes from fullCode.
func ProjectAligned(fullCode, fullValue string) (AlignedProjection, error) {
	fullCode = strings.ReplaceAll(strings.TrimSpace(fullCode), " ", "")
	if _, err := BuildRecord(fullCode); err != nil {
		return AlignedProjection{}, err
	}
	codeRunes := []rune(fullCode)
	valueRunes := []rune(fullValue)
	if len(valueRunes) != len(codeRunes) {
		return AlignedProjection{}, fmt.Errorf(
			"aligned value length %d does not match full code length %d",
			len(valueRunes),
			len(codeRunes),
		)
	}

	var variable strings.Builder
	var shorthand strings.Builder
	for start := 0; start < len(codeRunes); start += SyllableCodeLength {
		codeSyllable := codeRunes[start : start+SyllableCodeLength]
		valueSyllable := valueRunes[start : start+SyllableCodeLength]
		variableIndices, shorthandIndices := syllableProjectionIndices(codeSyllable)
		variable.WriteString(string(selectRunes(valueSyllable, variableIndices)))
		shorthand.WriteString(string(selectRunes(valueSyllable, shorthandIndices)))
	}
	return AlignedProjection{
		Full:      fullValue,
		Variable:  variable.String(),
		Shorthand: shorthand.String(),
	}, nil
}

// ValidateContinuousInputRecord protects the two dictionary invariants needed
// by Rime sentence composition: every spelling has an explicit syllable split,
// and every projected syllable retains its real or virtual shouyin. Without
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
				return fmt.Errorf("%s syllable %d lost its real or virtual shouyin", field.name, i+1)
			}
		}
	}
	return nil
}

func syllableProjectionIndices(syllable []rune) ([]int, []int) {
	variable := []int{0}
	for index := 1; index < len(syllable); index++ {
		if index == 1 || syllable[index] != syllable[index-1] {
			variable = append(variable, index)
		}
	}
	shorthand := append([]int(nil), variable...)
	if len(variable) == SyllableCodeLength {
		ganyin := []rune{
			syllable[variable[1]],
			syllable[variable[2]],
			syllable[variable[3]],
		}
		if len(omitMiddleTone(ganyin)) == 2 {
			shorthand = []int{variable[0], variable[1], variable[3]}
		}
	}
	return variable, shorthand
}

func selectRunes(values []rune, indices []int) []rune {
	selected := make([]rune, 0, len(indices))
	for _, index := range indices {
		selected = append(selected, values[index])
	}
	return selected
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
