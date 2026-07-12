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
			if got := strings.Count(text, "enable_completion: true"); got != 2 {
				t.Fatalf("schema %s has %d completion-enabled translators, want 2", schemaID, got)
			}
		})
	}
}
