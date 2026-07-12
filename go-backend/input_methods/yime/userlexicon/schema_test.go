package userlexicon

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSyncRimeSchemasRefreshesAllModes(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	for _, mode := range schemaModes {
		name := "yime_" + mode + ".schema.yaml"
		shared := []byte("schema_id: yime_" + mode + "\nuser_dict: custom_phrase_" + mode + "\n")
		if err := os.WriteFile(filepath.Join(sharedDir, name), shared, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name), []byte("user_dict: custom_phrase\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	if err := SyncRimeSchemas(sharedDir, userDir); err != nil {
		t.Fatal(err)
	}
	for _, mode := range schemaModes {
		name := "yime_" + mode + ".schema.yaml"
		got, err := os.ReadFile(filepath.Join(userDir, name))
		if err != nil {
			t.Fatal(err)
		}
		want := "schema_id: yime_" + mode + "\nuser_dict: custom_phrase_" + mode + "\n"
		if string(got) != want {
			t.Fatalf("%s was not refreshed: %q", name, got)
		}
	}
}

func TestRefreshRimeSchemasReportsOnlyContentChanges(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	for _, mode := range schemaModes {
		name := "yime_" + mode + ".schema.yaml"
		if err := os.WriteFile(filepath.Join(sharedDir, name), []byte("schema: "+mode+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	changed, err := RefreshRimeSchemas(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("first refresh must report changed schemas")
	}

	changed, err = RefreshRimeSchemas(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("identical schemas must not force a Rime rebuild")
	}

	path := filepath.Join(sharedDir, "yime_variable.schema.yaml")
	if err := os.WriteFile(path, []byte("schema: variable-v2\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	changed, err = RefreshRimeSchemas(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("updated shared schema must request a Rime rebuild")
	}
}
