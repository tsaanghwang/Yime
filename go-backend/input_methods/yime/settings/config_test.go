package settings

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadConfiguredPageSizePrefersDefaultCustom(t *testing.T) {
	userDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(userDir, "default.custom.yaml"), []byte("patch:\n  \"menu/page_size\": 8\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := ReadConfiguredPageSize(userDir); got != 8 {
		t.Fatalf("expected page size 8 from default.custom.yaml, got %d", got)
	}
}

func TestReadConfiguredPageSizeFallsBackToSchemaYaml(t *testing.T) {
	userDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(userDir, "user.yaml"), []byte("var:\n  previously_selected_schema: yime_variable\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "yime_variable.schema.yaml"), []byte("schema:\n  schema_id: yime_variable\n\nmenu:\n  page_size: 7\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := ReadConfiguredPageSize(userDir); got != 7 {
		t.Fatalf("expected page size 7 from schema yaml, got %d", got)
	}
}
