package yimecore

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAdmittedEntryIndexUsesSameSerializer(t *testing.T) {
	root := t.TempDir()
	provenance := filepath.Join(root, "owned-source.txt")
	if err := os.WriteFile(provenance, []byte("---\nname: fixture\n...\n审\tabcd\t1\n审\tabcd\t2\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		imported, direct := filepath.Join(root, mode+"-import.yidx"), filepath.Join(root, mode+"-direct.yidx")
		legacy, err := BuildIndexFile(mode, provenance, imported)
		if err != nil {
			t.Fatal(err)
		}
		r, err := BuildIndexEntries(mode, []Entry{{Text: "审", Code: "abcd", Weight: 1}, {Text: "审", Code: "abcd", Weight: 2}}, provenance, direct)
		if err != nil || r.IndexedRecords != 1 || r.DuplicateRecords != 1 {
			t.Fatalf("direct index: %+v %v", r, err)
		}
		if legacy.RecordPayloadSHA256 != r.RecordPayloadSHA256 {
			t.Fatal("entry serializer drifted from E1")
		}
		changed, err := BuildIndexEntries(mode, []Entry{{Text: "审", Code: "abce", Weight: 2}}, provenance, filepath.Join(root, mode+"-changed.yidx"))
		if err != nil {
			t.Fatal(err)
		}
		if changed.SourceSHA256 == r.SourceSHA256 {
			t.Fatal("changed records retained same source identity")
		}
		reordered, err := BuildIndexEntries(mode, []Entry{{Text: "审", Code: "abcd", Weight: 2}, {Text: "审", Code: "abcd", Weight: 1}}, provenance, filepath.Join(root, mode+"-reordered.yidx"))
		if err != nil {
			t.Fatal(err)
		}
		if reordered.IndexSHA256 != r.IndexSHA256 {
			t.Fatal("record order changed canonical identity")
		}
		index, err := OpenFileIndex(direct)
		if err != nil {
			t.Fatal(err)
		}
		if index.Mode() != mode || index.RecordCount() != 1 {
			t.Fatal("entry index metadata")
		}
		index.Close()
	}
	for _, mode := range []string{"", "invalid"} {
		if _, err := BuildIndexEntries(mode, []Entry{{Text: "审", Code: "abcd", Weight: 1}}, provenance, filepath.Join(root, "reject.yidx")); err == nil {
			t.Fatal("unknown mode accepted")
		}
	}
	if _, err := BuildIndexEntries("full", nil, provenance, filepath.Join(root, "empty.yidx")); err == nil {
		t.Fatal("empty admission accepted")
	}
}
