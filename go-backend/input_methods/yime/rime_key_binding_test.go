package yime

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestYimeSchemasDoNotImportPrintablePagingBindings(t *testing.T) {
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join("data", "yime_"+mode+".schema.yaml")
		payload, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		content := string(payload)
		start := strings.Index(content, "key_binder:\n")
		if start < 0 {
			t.Fatalf("%s has no key_binder section", path)
		}
		section := content[start:]
		if strings.Contains(section, "import_preset: default") {
			t.Fatalf("%s imports default key bindings that consume printable layout keys", path)
		}
		if !strings.Contains(section, "bindings: []") {
			t.Fatalf("%s must explicitly define an empty native key binding set", path)
		}
	}
}
