package yimecore

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

func writeIndexFixture(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fixture.dict.yaml")
	content := strings.Join([]string{
		"# Rime dictionary",
		"---",
		"name: fixture",
		"version: \"1\"",
		"sort: by_weight",
		"...",
		"一\ta1\t100",
		"一个\ta1 2\t80",
		"一致\ta1 23\t70",
		"重复\tb2\t1",
		"重复\tb2\t9",
		"",
	}, "\n")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestCompactIndexBuildIsDeterministicAndQueryable(t *testing.T) {
	source := writeIndexFixture(t)
	firstPath := filepath.Join(t.TempDir(), "first.yidx")
	secondPath := filepath.Join(t.TempDir(), "second.yidx")
	first, err := BuildIndexFile("full", source, firstPath)
	if err != nil {
		t.Fatal(err)
	}
	second, err := BuildIndexFile("full", source, secondPath)
	if err != nil {
		t.Fatal(err)
	}
	if first.IndexSHA256 != second.IndexSHA256 || first.RecordPayloadSHA256 != second.RecordPayloadSHA256 {
		t.Fatalf("deterministic hashes differ:\nfirst=%+v\nsecond=%+v", first, second)
	}
	if first.ParsedRecords != 5 || first.IndexedRecords != 4 || first.DuplicateRecords != 1 {
		t.Fatalf("unexpected build counts: %+v", first)
	}

	index, err := OpenFileIndex(firstPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })
	if index.Mode() != "full" || index.RecordCount() != 4 {
		t.Fatalf("unexpected index identity: mode=%q records=%d", index.Mode(), index.RecordCount())
	}
	engine, err := NewFileEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "a1")
	if len(result.State.Candidates) != 1 || result.State.Candidates[0].Text != "一" || !result.State.Candidates[0].Exact ||
		result.State.Sentence == nil || result.State.Sentence.Text != "一" {
		t.Fatalf("unexpected compact-index candidates: %+v", result.State.Candidates)
	}

	engine.Reset()
	duplicateResult := applyCode(t, engine, "b2")
	if len(duplicateResult.State.Candidates) != 1 || duplicateResult.State.Candidates[0].Weight != 9 {
		t.Fatalf("duplicate record was not normalized: %+v", duplicateResult.State.Candidates)
	}
}

func TestResidentCompactIndexLoadsCompletePayloadAndMatchesMappedLookup(t *testing.T) {
	source := writeIndexFixture(t)
	path := filepath.Join(t.TempDir(), "resident.yidx")
	if _, err := BuildIndexFile("variable", source, path); err != nil {
		t.Fatal(err)
	}
	mapped, err := OpenFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	defer mapped.Close()
	resident, err := OpenResidentFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	defer resident.Close()
	if mapped.StorageMode() != "mapped" || resident.StorageMode() != "resident" {
		t.Fatalf("storage modes mapped=%q resident=%q", mapped.StorageMode(), resident.StorageMode())
	}
	for _, prefix := range []string{"a", "a1", "b2"} {
		if got, want := resident.lookup(prefix, 10), mapped.lookup(prefix, 10); !reflect.DeepEqual(got, want) {
			t.Fatalf("resident prefix %q differs:\nresident=%+v\nmapped=%+v", prefix, got, want)
		}
	}
}

func TestCompactIndexRejectsPayloadCorruption(t *testing.T) {
	source := writeIndexFixture(t)
	path := filepath.Join(t.TempDir(), "corrupt.yidx")
	if _, err := BuildIndexFile("variable", source, path); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	data[indexFileHeaderSize+recordHeaderSize] ^= 0xff
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenFileIndex(path); err == nil || !strings.Contains(err.Error(), "payload hash mismatch") {
		t.Fatalf("corruption error = %v", err)
	}
}

func TestCompactIndexCandidateIDsRemainStateScoped(t *testing.T) {
	source := writeIndexFixture(t)
	path := filepath.Join(t.TempDir(), "candidate-id.yidx")
	if _, err := BuildIndexFile("shorthand", source, path); err != nil {
		t.Fatal(err)
	}
	index, err := OpenFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })
	engine, err := NewFileEngine(index, 9)
	if err != nil {
		t.Fatal(err)
	}
	result := applyCode(t, engine, "a1")
	oldID := result.State.Candidates[0].ID
	if _, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: "2"}); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Select(oldID); !errors.Is(err, engineapi.ErrUnknownCandidate) {
		t.Fatalf("stale candidate selection error = %v", err)
	}
}

func TestCompactIndexShortPrefixCacheMatchesInMemoryOrdering(t *testing.T) {
	entries := make([]Entry, 0, 100)
	for i := 0; i < 100; i++ {
		entries = append(entries, Entry{Text: "候选" + string(rune(0x4e00+i)), Code: "a1" + benchmarkCode(i), Weight: int64(i)})
	}
	entries = append(entries,
		Entry{Text: "一字节精确", Code: "a", Weight: 1},
		Entry{Text: "二字节精确", Code: "a1", Weight: 1},
	)
	memoryIndex, err := NewIndex(entries)
	if err != nil {
		t.Fatal(err)
	}
	source := filepath.Join(t.TempDir(), "short-prefix.dict.yaml")
	var dictionary strings.Builder
	dictionary.WriteString("# Rime dictionary\n---\nname: short\n...\n")
	for _, entry := range entries {
		fmt.Fprintf(&dictionary, "%s\t%s\t%d\n", entry.Text, entry.Code, entry.Weight)
	}
	if err := os.WriteFile(source, []byte(dictionary.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "short-prefix.yidx")
	if _, err := BuildIndexFile("full", source, path); err != nil {
		t.Fatal(err)
	}
	fileIndex, err := OpenFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = fileIndex.Close() })
	for _, prefix := range []string{"a", "a1"} {
		for _, limit := range []int{9, 10, 19, 28} {
			memoryRecords := memoryIndex.lookup(prefix, limit)
			fileRecords := fileIndex.lookup(prefix, limit)
			if !reflect.DeepEqual(memoryRecords, fileRecords) {
				t.Fatalf("prefix %q limit %d differs:\nmemory=%+v\nfile=%+v", prefix, limit, memoryRecords, fileRecords)
			}
		}
	}
}

func TestCompactIndexShortPrefixesRetainPagingAndOrdering(t *testing.T) {
	entries := make([]Entry, 0, 80)
	for i := 0; i < 40; i++ {
		entries = append(entries,
			Entry{Text: fmt.Sprintf("一字节-%02d", i), Code: "a", Weight: int64(1000 - i)},
			Entry{Text: fmt.Sprintf("二字节-%02d", i), Code: "b1", Weight: int64(1000 - i)},
		)
	}
	source := filepath.Join(t.TempDir(), "paged-short-prefix.dict.yaml")
	var dictionary strings.Builder
	dictionary.WriteString("# Rime dictionary\n---\nname: paged-short-prefix\n...\n")
	for _, entry := range entries {
		fmt.Fprintf(&dictionary, "%s\t%s\t%d\n", entry.Text, entry.Code, entry.Weight)
	}
	if err := os.WriteFile(source, []byte(dictionary.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "paged-short-prefix.yidx")
	if _, err := BuildIndexFile("full", source, path); err != nil {
		t.Fatal(err)
	}
	index, err := OpenFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })

	for _, prefix := range []string{"a", "b1"} {
		engine, err := NewFileEngine(index, 9)
		if err != nil {
			t.Fatal(err)
		}
		first := applyCode(t, engine, prefix).State
		if len(first.Candidates) != 9 || !first.HasNext || first.HasPrevious || first.PageNumber != 0 {
			t.Fatalf("prefix %q first page = %#v", prefix, first)
		}
		firstIDs := make(map[string]struct{}, len(first.Candidates))
		for _, candidate := range first.Candidates {
			firstIDs[candidate.ID] = struct{}{}
		}
		second, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
		if err != nil {
			t.Fatal(err)
		}
		if len(second.State.Candidates) != 9 || !second.State.HasPrevious || second.State.PageNumber != 1 {
			t.Fatalf("prefix %q second page = %#v", prefix, second.State)
		}
		for _, candidate := range second.State.Candidates {
			if _, duplicate := firstIDs[candidate.ID]; duplicate {
				t.Fatalf("prefix %q repeated candidate %q across pages", prefix, candidate.ID)
			}
		}
	}
}
