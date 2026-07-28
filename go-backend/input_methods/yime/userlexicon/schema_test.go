package userlexicon

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
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

func TestRefreshRimeDataReplacesStaleGeneratedLexicon(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	sharedFiles := map[string]string{
		"yime_full.dict.yaml":        "new full\n",
		"yime_variable.dict.yaml":    "new variable\n",
		"yime_shorthand.dict.yaml":   "new shorthand\n",
		"yime_lexicon_manifest.json": `{"source_sha256":"new"}` + "\n",
	}
	for name, content := range sharedFiles {
		if err := os.WriteFile(filepath.Join(sharedDir, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(userDir, "yime_full.dict.yaml"), []byte("old full\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "yime_lexicon_manifest.json"), []byte(`{"source_sha256":"old"}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	changed, err := RefreshRimeData(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("stale generated lexicon must request a Rime rebuild")
	}
	for name, want := range sharedFiles {
		got, err := os.ReadFile(filepath.Join(userDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if string(got) != want {
			t.Fatalf("%s was not refreshed: got %q want %q", name, got, want)
		}
	}

	changed, err = RefreshRimeData(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("identical generated lexicon must not force another Rime rebuild")
	}
}

func TestRefreshRimeDataReencodesDerivedUserLexicons(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	for _, name := range generatedLexiconFiles[:3] {
		if err := os.WriteFile(filepath.Join(sharedDir, name), []byte("new dictionary\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_lexicon_manifest.json"), []byte(`{"layout":"new"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte("pinyin_tone\tfull\na1\t'fff\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, SourceFileName), []byte("啊\ta1\t100\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "yime_lexicon_manifest.json"), []byte(`{"layout":"old"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, mode := range schemaModes {
		if err := os.WriteFile(RimeLexiconPath(userDir, mode), []byte("啊\told\t100\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	changed, err := RefreshRimeData(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("layout change must report refreshed data")
	}
	for _, mode := range schemaModes {
		content, err := os.ReadFile(RimeLexiconPath(userDir, mode))
		if err != nil {
			t.Fatal(err)
		}
		if string(content) == "啊\told\t100\n" {
			t.Fatalf("%s derived user lexicon kept the old layout code", mode)
		}
	}
}

func TestRefreshRimeDataRetiresTrialArtifactsAndMigratesSelection(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	files := []string{
		"yime_core_trial.dict.yaml",
		"yime_core_trial_manifest.json",
		"yime_core_trial.schema.yaml",
		filepath.Join("build", "yime_core_trial.prism.bin"),
	}
	for _, name := range files {
		path := filepath.Join(userDir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("retired\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(
		filepath.Join(userDir, "user.yaml"),
		[]byte("var:\n  previously_selected_schema: yime_core_trial\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(userDir, "default.custom.yaml"),
		[]byte("patch:\n  schema_list:\n    - schema: yime_core_trial\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	changed, err := RefreshRimeData(sharedDir, userDir)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("retiring trial data must report changed data")
	}
	for _, name := range files {
		if _, err := os.Stat(filepath.Join(userDir, name)); !os.IsNotExist(err) {
			t.Fatalf("retired artifact still exists: %s", name)
		}
	}
	for _, name := range []string{"user.yaml", "default.custom.yaml"} {
		data, err := os.ReadFile(filepath.Join(userDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(data), "yime_core_trial") ||
			!strings.Contains(string(data), "yime_variable") {
			t.Fatalf("selection was not migrated in %s: %s", name, data)
		}
	}
}

func TestRefreshRimeDataKeepsStaleManifestWhenUserReencodingFails(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	for _, name := range generatedLexiconFiles[:3] {
		if err := os.WriteFile(filepath.Join(sharedDir, name), []byte("new dictionary\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	newManifest := []byte(`{"layout":"new"}`)
	oldManifest := []byte(`{"layout":"old"}`)
	if err := os.WriteFile(filepath.Join(sharedDir, generatedLexiconFiles[3]), newManifest, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte("pinyin_tone\tfull\na1\t'fff\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, SourceFileName), []byte("错\tmissing1\t100\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	manifestPath := filepath.Join(userDir, generatedLexiconFiles[3])
	if err := os.WriteFile(manifestPath, oldManifest, 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := RefreshRimeData(sharedDir, userDir); err == nil {
		t.Fatal("invalid user phrase must fail re-encoding")
	}
	got, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, oldManifest) {
		t.Fatalf("failed refresh must keep stale manifest for retry: got %q", got)
	}
}
