package yime

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSystemAndUserDictionariesEnableCompletion(t *testing.T) {
	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		t.Run(schemaID, func(t *testing.T) {
			path := filepath.Join("data", schemaID+".schema.yaml")
			content, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read schema %s: %v", path, err)
			}

			text := string(content)
			if strings.Contains(text, "enable_completion: false") {
				t.Fatalf("schema %s disables completion for one of its dictionaries", schemaID)
			}
			if got := strings.Count(text, "enable_completion: true"); got != 4 {
				t.Fatalf("schema %s has %d completion-enabled translators, want 4", schemaID, got)
			}
		})
	}
}

func TestAllSchemasEnableSentenceComposition(t *testing.T) {
	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		t.Run(schemaID, func(t *testing.T) {
			path := filepath.Join("data", schemaID+".schema.yaml")
			content, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read schema %s: %v", path, err)
			}

			text := string(content)
			if got := strings.Count(text, "enable_sentence: true"); got != 2 {
				t.Fatalf("schema %s has %d sentence-enabled translators, want 2", schemaID, got)
			}
			if got := strings.Count(text, "sentence_over_completion: true"); got != 2 {
				t.Fatalf("schema %s has %d translators preferring sentences over completion, want 2", schemaID, got)
			}
			if got := strings.Count(text, "enable_sentence: false"); got != 2 {
				t.Fatalf("schema %s has %d sentence-disabled translators, want the explicit-erhua and PSC peripheral overlays", schemaID, got)
			}
			for _, section := range []string{"erhua_mixed:", "psc_peripheral:"} {
				overlay := strings.Index(text, section)
				if overlay < 0 || !strings.Contains(text[overlay:], "enable_sentence: false") {
					t.Fatalf("schema %s does not disable sentences in %s", schemaID, section)
				}
			}
		})
	}
}

func TestAllSchemasKeepNavigatorBeforeEditor(t *testing.T) {
	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		t.Run(schemaID, func(t *testing.T) {
			path := filepath.Join("data", schemaID+".schema.yaml")
			content, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("read schema %s: %v", path, err)
			}

			text := string(content)
			selector := strings.Index(text, "    - selector")
			navigator := strings.Index(text, "    - navigator")
			editor := strings.Index(text, "    - express_editor")
			if selector < 0 || navigator < 0 || editor < 0 {
				t.Fatalf("schema %s must include selector, navigator, and express_editor", schemaID)
			}
			if !(selector < navigator && navigator < editor) {
				t.Fatalf("schema %s processor order must remain selector -> navigator -> express_editor", schemaID)
			}
		})
	}
}
