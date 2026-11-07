package touchbroker

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
)

// Use the shipped descriptors and the exported constructor, never a mock
// Service or an overridable production architecture. Run on both Go targets.
func productionDescriptorFixture(t *testing.T) (name, otherName string, raw, other []byte) {
	t.Helper()
	switch runtime.GOARCH {
	case "amd64":
		name, otherName = "18u-touch-product.json", "18u-touch-product-arm64.json"
	case "arm64":
		name, otherName = "18u-touch-product-arm64.json", "18u-touch-product.json"
	default:
		t.Skip("production descriptor requires amd64 or arm64")
	}
	var err error
	raw, err = os.ReadFile(filepath.Join("../../../tools/yimecore", name))
	if err != nil {
		t.Fatal(err)
	}
	other, err = os.ReadFile(filepath.Join("../../../tools/yimecore", otherName))
	if err != nil {
		t.Fatal(err)
	}
	return
}

func writeProductionDescriptor(t *testing.T, root, name string, raw []byte) {
	t.Helper()
	dir := filepath.Join(root, "tools/yimecore")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), raw, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestNewProductionArchitectureDescriptor(t *testing.T) {
	name, otherName, raw, other := productionDescriptorFixture(t)
	for _, both := range []bool{false, true} {
		label := "package_only_matching_descriptor"
		if both {
			label = "source_tree_both_descriptors"
		}
		t.Run(label, func(t *testing.T) {
			root := t.TempDir()
			writeProductionDescriptor(t, root, name, raw)
			if both {
				writeProductionDescriptor(t, root, otherName, other)
			}
			s, err := NewProduction(root, t.TempDir())
			if err != nil || s == nil {
				t.Fatalf("%s production constructor: %v", runtime.GOARCH, err)
			}
			if s.expected != (Identity{LayoutSHA, DictionarySHA, "variable", keyboardlab.SessionPolicy}) {
				t.Fatal("production identity changed", s.expected)
			}
		})
	}
}

func TestNewProductionRejectsDescriptorMismatch(t *testing.T) {
	name, otherName, raw, other := productionDescriptorFixture(t)
	tests := []struct {
		name, section, field string
		value                any
	}{
		{"schema", "", "schema_version", "foreign"},
		{"product", "identity", "product_key", "YimeCore"},
		{"clsid", "identity", "clsid", "{00000000-0000-0000-0000-000000000000}"},
		{"profile", "identity", "profile", "{00000000-0000-0000-0000-000000000000}"},
		{"architecture", "scope", "architecture", "foreign"},
		{"language", "scope", "language", "EN"},
		{"mode", "scope", "mode", "full"},
		{"learning", "scope", "persistent_learning", true},
		{"layout", "data", "layout_sha256", strings.Repeat("0", 64)},
		{"dictionary", "data", "dictionary_sha256", strings.Repeat("0", 64)},
		{"fallback", "data", "standard_index_fallback", true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var doc map[string]any
			if err := json.Unmarshal(raw, &doc); err != nil {
				t.Fatal(err)
			}
			object := doc
			if tc.section != "" {
				object = doc[tc.section].(map[string]any)
			}
			object[tc.field] = tc.value
			bad, err := json.Marshal(doc)
			if err != nil {
				t.Fatal(err)
			}
			root := t.TempDir()
			writeProductionDescriptor(t, root, name, bad)
			if s, err := NewProduction(root, t.TempDir()); err == nil || s != nil {
				t.Fatal("invalid descriptor accepted")
			}
		})
	}
	for _, tc := range []struct {
		name  string
		files map[string][]byte
	}{
		{"missing", nil},
		{"malformed", map[string][]byte{name: []byte("{")}},
		{"other_architecture_only", map[string][]byte{otherName: other}},
		{"other_architecture_renamed", map[string][]byte{name: other}},
		{"no_fallback_from_wrong_selected", map[string][]byte{name: other, otherName: raw}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			for filename, content := range tc.files {
				writeProductionDescriptor(t, root, filename, content)
			}
			if s, err := NewProduction(root, t.TempDir()); err == nil || s != nil {
				t.Fatal("missing or cross-architecture descriptor accepted")
			}
		})
	}
	for _, paths := range [][2]string{{"relative", t.TempDir()}, {t.TempDir(), "relative"}, {"", ""}} {
		if s, err := NewProduction(paths[0], paths[1]); err == nil || s != nil {
			t.Fatal("relative resource paths accepted")
		}
	}
}

// NewProduction validates the descriptor; resource bytes are loaded lazily on
// open. Exercise that real loader and the source-pinned production identity.
func TestNewProductionRejectsLoadedResourceMismatch(t *testing.T) {
	name, _, raw, _ := productionDescriptorFixture(t)
	for _, mode := range []string{"self_consistent_foreign_dictionary", "changed_dictionary_bytes", "wrong_layout", "missing_data"} {
		t.Run(mode, func(t *testing.T) {
			root, data := fixture(t)
			writeProductionDescriptor(t, root, name, raw)
			switch mode {
			case "changed_dictionary_bytes":
				if err := os.WriteFile(filepath.Join(data, "yime_variable.dict.yaml"), []byte("corrupt\n"), 0600); err != nil {
					t.Fatal(err)
				}
			case "wrong_layout":
				if err := os.WriteFile(filepath.Join(root, "prototypes/touch-terminal/data/physical-layout.json"), []byte(`{"layoutId":"foreign"}`), 0600); err != nil {
					t.Fatal(err)
				}
			case "missing_data":
				data = t.TempDir()
			}
			s, err := NewProduction(root, data)
			if err != nil {
				t.Fatal("valid descriptor rejected before lazy resource load", err)
			}
			c, err := s.newConnection(yimebroker.TrustedClient{ID: "offline-production-resource-test"})
			if err != nil {
				t.Fatal(err)
			}
			defer c.close()
			r := c.dispatch(c.owner, Request{Version: 2, Sequence: 1, Operation: "open", Product: Product, Focus: Focus{"offline-resource-test", 1}})
			if r.OK || r.Commit != nil || c.session != nil {
				t.Fatal("wrong loaded resource admitted into production", r)
			}
			if mode == "self_consistent_foreign_dictionary" && r.Error != "loaded resource identity mismatch" {
				t.Fatal("did not reach source-pinned dictionary check", r)
			}
		})
	}
}
