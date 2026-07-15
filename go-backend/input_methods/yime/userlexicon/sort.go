package userlexicon

import (
	"sort"
	"strconv"
)

type SortField int

const (
	SortByPhrase SortField = iota
	SortByPinyin
	SortByWeight
)

// SortEntries returns a sorted copy of entries.
func SortEntries(entries []Entry, field SortField, descending bool) []Entry {
	sorted := append([]Entry(nil), entries...)
	sort.Slice(sorted, func(i, j int) bool {
		less := false
		switch field {
		case SortByPinyin:
			if sorted[i].Pinyin != sorted[j].Pinyin {
				less = sorted[i].Pinyin < sorted[j].Pinyin
			} else {
				less = sorted[i].Phrase < sorted[j].Phrase
			}
		case SortByWeight:
			left, _ := strconv.ParseInt(sorted[i].Weight, 10, 64)
			right, _ := strconv.ParseInt(sorted[j].Weight, 10, 64)
			if left != right {
				less = left < right
			} else {
				less = sorted[i].Phrase < sorted[j].Phrase
			}
		default:
			if sorted[i].Phrase != sorted[j].Phrase {
				less = sorted[i].Phrase < sorted[j].Phrase
			} else {
				less = sorted[i].Pinyin < sorted[j].Pinyin
			}
		}
		if descending {
			return !less
		}
		return less
	})
	return sorted
}

// FilterEntries returns entries matching a keyword in phrase, pinyin, or weight.
func FilterEntries(entries []Entry, keyword string) []Entry {
	if keyword == "" {
		return append([]Entry(nil), entries...)
	}
	filtered := make([]Entry, 0, len(entries))
	for _, entry := range entries {
		if containsFold(entry.Phrase, keyword) || containsFold(entry.Pinyin, keyword) || containsFold(entry.Weight, keyword) {
			filtered = append(filtered, entry)
		}
	}
	return filtered
}

func containsFold(haystack, needle string) bool {
	if needle == "" {
		return true
	}
	return len(haystack) >= len(needle) && indexFold(haystack, needle) >= 0
}

func indexFold(haystack, needle string) int {
	// Simple case-insensitive contains for ASCII lexicon fields.
	lowerHaystack := toLowerASCII(haystack)
	lowerNeedle := toLowerASCII(needle)
	return indexString(lowerHaystack, lowerNeedle)
}

func toLowerASCII(value string) string {
	b := []byte(value)
	for i := range b {
		if b[i] >= 'A' && b[i] <= 'Z' {
			b[i] += 'a' - 'A'
		}
	}
	return string(b)
}

func indexString(haystack, needle string) int {
	n := len(needle)
	if n == 0 {
		return 0
	}
	for i := 0; i+n <= len(haystack); i++ {
		if haystack[i:i+n] == needle {
			return i
		}
	}
	return -1
}
