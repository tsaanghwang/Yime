package yimecore

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func TestFileIndexSHA256BindsLoadedBytesWithoutChangingSourceIdentity(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "synthetic-provenance.json")
	path := filepath.Join(root, "fixture.yidx")
	if err := os.WriteFile(source, []byte("synthetic"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := BuildIndexEntries("variable", []Entry{{Text: "合成", Code: "ab", Weight: 1}}, source, path); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	expected := hex.EncodeToString(sum[:])
	var identity string
	for _, open := range []func(string) (*FileIndex, error){OpenFileIndex, OpenResidentFileIndex} {
		index, err := open(path)
		if err != nil {
			t.Fatal(err)
		}
		if index.SHA256() != expected {
			t.Fatal("loaded complete bytes not pinned")
		}
		if identity != "" && identity != index.SourceID() {
			t.Fatal("storage mode altered learning identity")
		}
		identity = index.SourceID()
		if err := index.Close(); err != nil {
			t.Fatal(err)
		}
		if index.SHA256() != expected || index.SourceID() != identity {
			t.Fatal("close altered immutable evidence")
		}
	}
}
