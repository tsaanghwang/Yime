package yimecore

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// These deliberately mixed, entirely synthetic records exercise every ranking
// tie-break. No linguistic fixture, installed index or user source is opened.
func prefixTopKSyntheticEntries() []Entry {
	entries := make([]Entry, 0, 6440)
	bases := []string{"ab", "abx", "ablong", "ac", "ad"}
	texts := []string{"测试", "Ω", "é", "e\u0301", "𠀀", "🙂", "A", "阿", "啊", "同名"}
	for i := 0; i < 6400; i++ {
		entries = append(entries, Entry{
			Code:   fmt.Sprintf("%s%03x", bases[i%len(bases)], (i/5)%509),
			Text:   fmt.Sprintf("%s-%04d", texts[i%len(texts)], i),
			Weight: int64((i*37)%97 - 48),
		})
	}
	entries = append(entries,
		Entry{Code: "a", Text: "synthetic-exact-a", Weight: -1 << 60},
		Entry{Code: "ab", Text: "synthetic-exact-ab", Weight: -1 << 60},
		Entry{Code: "ablong001", Text: "synthetic-exact-long", Weight: -1 << 60},
		Entry{Code: "abzzzzzz", Text: "synthetic-maximum-weight", Weight: 1<<63 - 1},
		Entry{Code: "abzzzzzzz", Text: "synthetic-minimum-weight", Weight: -1 << 63},
		Entry{Code: "abq001", Text: "synthetic-same-text", Weight: 99},
		Entry{Code: "abq002", Text: "synthetic-same-text", Weight: 99},
		Entry{Code: "abs", Text: "synthetic-same-text", Weight: 99},
		Entry{Code: "abq001", Text: "synthetic-same-text", Weight: 3},
	)
	for _, text := range texts {
		entries = append(entries, Entry{Code: "abtie", Text: text, Weight: 99})
	}
	return entries
}

func requirePrefixRecordsEqual(t *testing.T, got, want []record) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("record count changed: got %d, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("rank %d changed: got %#v, want %#v", i, got[i], want[i])
		}
	}
}

func TestFilePrefixTopKMatchesIndependentMemoryOracle(t *testing.T) {
	entries := prefixTopKSyntheticEntries()
	memory, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	if len(memory.records) < 6400 {
		t.Fatal("large-prefix fixture was unexpectedly reduced")
	}
	root := t.TempDir()
	provenance := filepath.Join(root, "synthetic-provenance.json")
	if err := os.WriteFile(provenance, []byte(`{"synthetic":true,"purpose":"prefix top-k equivalence"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	indexPath := filepath.Join(root, "synthetic.yidx")
	if _, err := BuildIndexEntries("full", entries, provenance, indexPath); err != nil {
		t.Fatal(err)
	}
	index, err := OpenFileIndex(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })
	beforeBytes := append([]byte(nil), index.data...)
	beforeDisk, err := os.ReadFile(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	beforeSource := index.SourceID()
	beforePayload := index.payloadHash
	beforeSourceHash := index.sourceHash
	beforeOffsets := append([]uint32(nil), index.offsets...)
	beforeRecords := append([]record(nil), memory.records...)
	limits := []int{1, 5, 10, 64, 65, 128, 512, 4096, len(memory.records) + 100}
	prefixes := []string{"a", "ab", "ac", "ablong", "ablong001", "abq", "abtie", "az", "no-synthetic-match"}
	for _, prefix := range prefixes {
		for _, limit := range limits {
			t.Run(fmt.Sprintf("%s/limit-%d", prefix, limit), func(t *testing.T) {
				// NewIndex keeps the original string insertion oracle. In
				// particular, it does not call any FileIndex top-k helper.
				want := memory.lookup(prefix, limit)
				requirePrefixRecordsEqual(t, index.lookupUncached(prefix, limit), want)
				// Guarantee that this particular key has cache room, then
				// check both cache population and the subsequent hit.
				index.prefixCacheMu.Lock()
				index.prefixCache = nil
				index.prefixRecords = 0
				index.prefixCacheMu.Unlock()
				requirePrefixRecordsEqual(t, index.lookup(prefix, limit), want)
				key := prefixCacheKey{prefix: prefix, limit: limit}
				index.prefixCacheMu.RLock()
				_, cached := index.prefixCache[key]
				index.prefixCacheMu.RUnlock()
				if !cached {
					t.Fatal("synthetic query did not populate its cache entry")
				}
				requirePrefixRecordsEqual(t, index.lookup(prefix, limit), want)
				if index.SourceID() != beforeSource || index.payloadHash != beforePayload || index.sourceHash != beforeSourceHash {
					t.Fatal("lookup changed static source identity")
				}
			})
		}
	}
	if !bytes.Equal(index.data, beforeBytes) || !reflect.DeepEqual(index.offsets, beforeOffsets) || !reflect.DeepEqual(memory.records, beforeRecords) {
		t.Fatal("top-k query changed input payload, offsets or oracle records")
	}
	afterDisk, err := os.ReadFile(indexPath)
	if err != nil || sha256.Sum256(afterDisk) != sha256.Sum256(beforeDisk) {
		t.Fatal("top-k query changed the stored index payload", err)
	}
}
