// Package yimecore contains the independent Go engine experiment. It must not
// import PIME, librime, cgo or Windows UI packages.
package yimecore

import (
	"fmt"
	"sort"
	"strings"
)

// Entry is the build-time representation accepted by the E0 in-memory index.
// Later stages will replace this representation with a versioned compact file
// while preserving the lookup contract.
type Entry struct {
	Text   string
	Code   string
	Weight int64
}

type record struct {
	text   string
	code   string
	weight int64
	source string
}

// Index is an immutable, deterministic E0 lookup index.
type Index struct {
	records      []record
	maxCodeBytes int
}

// NewIndex validates, normalizes and deterministically orders entries.
func NewIndex(entries []Entry) (*Index, error) {
	records := make([]record, 0, len(entries))
	for i, entry := range entries {
		text := strings.TrimSpace(entry.Text)
		code, err := normalizeCode(entry.Code)
		if err != nil {
			return nil, fmt.Errorf("entry %d: %w", i, err)
		}
		if text == "" {
			return nil, fmt.Errorf("entry %d: empty candidate text", i)
		}
		records = append(records, record{text: text, code: code, weight: entry.Weight})
	}

	// Group duplicate code/text pairs without a million-entry map. The first
	// item in each group carries the highest weight and is retained.
	sort.Slice(records, func(i, j int) bool {
		if records[i].code != records[j].code {
			return records[i].code < records[j].code
		}
		if records[i].text != records[j].text {
			return records[i].text < records[j].text
		}
		return records[i].weight > records[j].weight
	})
	deduplicated := records[:0]
	for _, item := range records {
		if len(deduplicated) > 0 {
			previous := deduplicated[len(deduplicated)-1]
			if previous.code == item.code && previous.text == item.text {
				continue
			}
		}
		deduplicated = append(deduplicated, item)
	}
	records = deduplicated

	// Runtime order supports binary-searching by code and deterministic
	// candidate ranking within one code bucket.
	sort.Slice(records, func(i, j int) bool {
		if records[i].code != records[j].code {
			return records[i].code < records[j].code
		}
		if records[i].weight != records[j].weight {
			return records[i].weight > records[j].weight
		}
		return records[i].text < records[j].text
	})
	maxCodeBytes := 0
	for _, item := range records {
		if len(item.code) > maxCodeBytes {
			maxCodeBytes = len(item.code)
		}
	}
	return &Index{records: records, maxCodeBytes: maxCodeBytes}, nil
}

func (idx *Index) exact(code string, limit int) []record {
	if idx == nil || code == "" || limit <= 0 {
		return nil
	}
	start := sort.Search(len(idx.records), func(i int) bool { return idx.records[i].code >= code })
	result := make([]record, 0, limit)
	for i := start; i < len(idx.records) && idx.records[i].code == code && len(result) < limit; i++ {
		result = append(result, idx.records[i])
	}
	return result
}

func (idx *Index) maximumCodeBytes() int { return idx.maxCodeBytes }

func (idx *Index) identity() string { return "synthetic-memory-index" }

func normalizeCode(code string) (string, error) {
	var normalized strings.Builder
	normalized.Grow(len(code))
	for _, r := range code {
		switch {
		case r == ' ' || r == '\t' || r == '\r' || r == '\n':
			continue
		case r < 0x21 || r > 0x7e:
			return "", fmt.Errorf("code contains non-ASCII-printable character %q", r)
		default:
			normalized.WriteRune(r)
		}
	}
	if normalized.Len() == 0 {
		return "", fmt.Errorf("empty code")
	}
	return normalized.String(), nil
}

func (idx *Index) lookup(prefix string, limit int) []record {
	if idx == nil || prefix == "" || limit <= 0 {
		return nil
	}
	start := sort.Search(len(idx.records), func(i int) bool {
		return idx.records[i].code >= prefix
	})
	top := make([]record, 0, limit)
	for i := start; i < len(idx.records); i++ {
		item := idx.records[i]
		if !strings.HasPrefix(item.code, prefix) {
			break
		}
		top = insertTop(top, item, prefix, limit)
	}
	return top
}

func insertTop(top []record, item record, input string, limit int) []record {
	if len(top) == limit && !better(item, top[len(top)-1], input) {
		return top
	}
	if len(top) < limit {
		top = append(top, item)
	} else {
		top[len(top)-1] = item
	}
	for i := len(top) - 1; i > 0 && better(top[i], top[i-1], input); i-- {
		top[i], top[i-1] = top[i-1], top[i]
	}
	return top
}

func better(left, right record, input string) bool {
	leftExact := left.code == input
	rightExact := right.code == input
	if leftExact != rightExact {
		return leftExact
	}
	if left.weight != right.weight {
		return left.weight > right.weight
	}
	if len(left.code) != len(right.code) {
		return len(left.code) < len(right.code)
	}
	if left.text != right.text {
		return left.text < right.text
	}
	return left.code < right.code
}
