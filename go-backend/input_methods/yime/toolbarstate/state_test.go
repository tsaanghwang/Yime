package toolbarstate

import (
	"path/filepath"
	"testing"
)

func TestUpdateWritesCompleteVersionedStateAndSkipsUnchangedRevision(t *testing.T) {
	path := filepath.Join(t.TempDir(), FileName)
	first, err := Update(path, "toolbar", func(state *State) bool {
		state.ASCII = true
		state.FullShape = true
		state.ASCIIPunctuation = true
		state.Traditionalization = true
		state.SchemaID = "yime_full"
		state.Vertical = true
		state.OrientationSet = true
		state.HiddenButtons = []string{"punctuation", "unicode"}
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	if first.Version != FormatVersion || first.Revision == 0 ||
		first.UpdatedAt == "" || first.Source != "toolbar" {
		t.Fatalf("incomplete state metadata: %#v", first)
	}

	second, err := Update(path, "backend", func(state *State) bool {
		return false
	})
	if err != nil {
		t.Fatal(err)
	}
	if second.Revision != first.Revision {
		t.Fatalf("unchanged state advanced revision: %d -> %d", first.Revision, second.Revision)
	}

	got, err := Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if !got.ASCII || !got.FullShape || !got.ASCIIPunctuation ||
		!got.Traditionalization || got.SchemaID != "yime_full" ||
		!got.Vertical || !got.OrientationSet || len(got.HiddenButtons) != 2 {
		t.Fatalf("state file is incomplete: %#v", got)
	}
}
