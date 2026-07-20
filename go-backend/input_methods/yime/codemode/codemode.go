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
	full = strings.TrimSpace(full)
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
	for start := 0; start < len(runes); start += SyllableCodeLength {
		syllable := runes[start : start+SyllableCodeLength]
		variablePart := mergeAdjacent(syllable)
		variable.WriteString(string(variablePart))

		// Keep the real or virtual initial as an explicit syllable boundary in
		// every derived mode. In particular, zero-initial syllables retain '\'',
		// allowing Rime's sentence translator to segment concatenated codes.
		initial := variablePart[:1]
		ganyin := variablePart[1:]
		shorthand.WriteString(string(initial))
		shorthand.WriteString(string(omitMiddleTone(ganyin)))
	}
	return Record{Full: full, Variable: variable.String(), Shorthand: shorthand.String()}, nil
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
