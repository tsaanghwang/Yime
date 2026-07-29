package settings

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultSchemaIsCoreBackedVariableMode(t *testing.T) {
	if got := ReadConfiguredSchema(""); got != SchemaVariable {
		t.Fatalf("empty configuration must default to %q, got %q", SchemaVariable, got)
	}
	if got := normalizeSchemaID("unknown"); got != SchemaVariable {
		t.Fatalf("unknown schema must normalize to %q, got %q", SchemaVariable, got)
	}
	if got := normalizeSchemaID("yime_core_trial"); got != SchemaVariable {
		t.Fatalf("retired trial selection must migrate to %q, got %q", SchemaVariable, got)
	}
}

func TestAvailableSchemaOptionsFollowPackagedFiles(t *testing.T) {
	sharedDir := t.TempDir()
	for _, name := range []string{
		"yime_variable.schema.yaml",
		"yime_full.schema.yaml",
		"yime_shorthand.schema.yaml",
	} {
		if err := os.WriteFile(filepath.Join(sharedDir, name), []byte("test"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	options := AvailableSchemaOptions(sharedDir)
	if len(options) != 3 || options[0].ID != SchemaVariable {
		t.Fatalf("three-mode runtime options are incomplete: %#v", options)
	}
	for _, option := range options {
		if !option.Enabled {
			t.Fatalf("core-backed mode unexpectedly disabled: %#v", option)
		}
	}
}

func TestApplyConnectsBothCandidateCodeDisplaysToEverySchema(t *testing.T) {
	sharedDir := t.TempDir()
	for _, schemaID := range []string{SchemaVariable, SchemaFull, SchemaShorthand} {
		if err := os.WriteFile(filepath.Join(sharedDir, schemaID+".schema.yaml"), []byte("schema:\n  schema_id: "+schemaID+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	for _, schemaID := range []string{SchemaVariable, SchemaFull, SchemaShorthand} {
		for _, reverseMode := range []string{"yime_pinyin", "key_sequence"} {
			t.Run(schemaID+"/"+reverseMode, func(t *testing.T) {
				userDir := t.TempDir()
				if err := Apply(userDir, sharedDir, schemaID, 7, reverseMode, "vertical", false); err != nil {
					t.Fatalf("Apply failed: %v", err)
				}
				snapshot := LoadSnapshot(userDir, sharedDir)
				if snapshot.SchemaID != schemaID {
					t.Fatalf("configured schema=%q, want %q", snapshot.SchemaID, schemaID)
				}
				if snapshot.ReverseLookupMode != reverseMode {
					t.Fatalf("display mode=%q, want %q", snapshot.ReverseLookupMode, reverseMode)
				}
			})
		}
	}
}

func TestApplyRejectsEveryUnavailableSchemaUniformly(t *testing.T) {
	for _, schemaID := range []string{SchemaVariable, SchemaFull, SchemaShorthand} {
		t.Run(schemaID, func(t *testing.T) {
			if err := Apply(t.TempDir(), t.TempDir(), schemaID, 5, "key_sequence", "vertical", false); err == nil {
				t.Fatalf("Apply accepted unavailable schema %q", schemaID)
			}
		})
	}
}

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
