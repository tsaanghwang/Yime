package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManifestRequiresCurrentLayoutAllModesAndDisabledIDs(t *testing.T) {
	root := t.TempDir()
	valid := dataManifest{SchemaVersion: 1, LayoutProjectionSHA256: "current", DisabledYinyuanIDs: []string{"M27", "M25", "M26"}, Scope: "immutable_source_runtime_experiment", DictionarySHA256: map[string]string{}}
	for _, mode := range modes {
		valid.DictionarySHA256["yime_"+mode+".dict.yaml"] = strings.Repeat("a", 64)
	}
	for _, tc := range []struct {
		name      string
		change    func(*dataManifest)
		wantError bool
	}{
		{"matching", func(*dataManifest) {}, false},
		{"old-layout", func(m *dataManifest) { m.LayoutProjectionSHA256 = "old" }, true},
		{"enabled-reserved-id", func(m *dataManifest) { m.DisabledYinyuanIDs = []string{"M25", "M26"} }, true},
		{"incomplete-mode", func(m *dataManifest) { delete(m.DictionarySHA256, "yime_full.dict.yaml") }, true},
		{"old-manifest-version", func(m *dataManifest) { m.SchemaVersion = 0 }, true},
		{"limited-preview-corpus", func(m *dataManifest) { m.Limit = 100 }, true},
		{"invalid-digest", func(m *dataManifest) { m.DictionarySHA256["yime_full.dict.yaml"] = strings.Repeat("z", 64) }, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			data, _ := json.Marshal(valid)
			var manifest dataManifest
			if err := json.Unmarshal(data, &manifest); err != nil {
				t.Fatal(err)
			}
			tc.change(&manifest)
			data, _ = json.Marshal(manifest)
			if err := os.WriteFile(filepath.Join(root, "ascii_keyboard_manifest.json"), data, 0600); err != nil {
				t.Fatal(err)
			}
			_, err := loadManifest(root, "current")
			if (err != nil) != tc.wantError {
				t.Fatalf("error %v wantError %v", err, tc.wantError)
			}
		})
	}
}
