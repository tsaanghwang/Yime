package professionallexicon

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestProfessionalCatalogLoadsOnlySelectedVerifiedPacks(t *testing.T) {
	root := t.TempDir()
	pack := Pack{ID: "approved-medical", Name: "医学", Provenance: "reviewed fixture", Modes: map[string]FileSpec{}}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		source := filepath.Join(root, mode+".dict.yaml")
		path := filepath.Join(root, mode+".yidx")
		if err := os.WriteFile(source, []byte("---\nname: fixture\nversion: \"1\"\n...\n术语\tab\t10\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := yimecore.BuildIndexFile(mode, source, path); err != nil {
			t.Fatal(err)
		}
		hash, _ := hashFile(path)
		pack.Modes[mode] = FileSpec{Path: filepath.Base(path), SHA256: hash}
	}
	catalogData, _ := json.Marshal(Catalog{SchemaVersion: CatalogSchema, Packs: []Pack{pack}})
	if err := os.WriteFile(filepath.Join(root, "catalog.json"), catalogData, 0o600); err != nil {
		t.Fatal(err)
	}
	statePath := filepath.Join(t.TempDir(), "professional.json")
	if err := SaveState(statePath, State{Enabled: true, Selected: []string{pack.ID}}); err != nil {
		t.Fatal(err)
	}
	set, err := OpenSelected(root, statePath)
	if err != nil {
		t.Fatal(err)
	}
	defer set.Close()
	for _, mode := range []string{"full", "variable", "shorthand"} {
		modules := set.Modules(mode)
		if len(modules) != 1 || modules[0].ID != "professional:"+pack.ID {
			t.Fatalf("%s modules=%#v", mode, modules)
		}
	}
}

func TestProfessionalCatalogAllowsNoApprovedPacksAndRejectsEscape(t *testing.T) {
	root := t.TempDir()
	set, err := OpenSelected(root, filepath.Join(root, "state.json"))
	if err != nil || len(set.Modules("variable")) != 0 {
		t.Fatalf("empty catalog set=%#v err=%v", set, err)
	}
	bad := Catalog{SchemaVersion: CatalogSchema, Packs: []Pack{{
		ID: "bad", Name: "bad", Provenance: "fixture",
		Modes: map[string]FileSpec{
			"full":      {Path: `..\full.yidx`, SHA256: string(make([]byte, 64))},
			"variable":  {Path: "variable.yidx", SHA256: string(make([]byte, 64))},
			"shorthand": {Path: "shorthand.yidx", SHA256: string(make([]byte, 64))},
		},
	}}}
	data, _ := json.Marshal(bad)
	if err := os.WriteFile(filepath.Join(root, "catalog.json"), data, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadCatalog(root); err == nil {
		t.Fatal("escaping professional index path was accepted")
	}
}

func TestSaveStateAtomicallyReplacesExistingState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "professional.json")
	if err := SaveState(path, State{Enabled: true, Selected: []string{"first"}}); err != nil {
		t.Fatal(err)
	}
	if err := SaveState(path, State{Enabled: false, Selected: []string{"second"}}); err != nil {
		t.Fatal(err)
	}
	state, err := LoadState(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.Enabled || len(state.Selected) != 1 || state.Selected[0] != "second" {
		t.Fatalf("replaced state=%#v", state)
	}
}
