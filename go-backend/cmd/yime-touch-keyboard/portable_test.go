package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"testing"
)

func portableFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	r := portableResources{SchemaVersion: 1, Scope: "isolated-cn134-portable-resources", Files: map[string]string{}}
	for _, name := range []string{"data/dictionary", "font.ttf", "prototypes/touch-terminal/desktop/profiles/main-only.json"} {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		body := []byte("fixture:" + name)
		if err := os.WriteFile(path, body, 0600); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(body)
		r.Files[name] = hex.EncodeToString(sum[:])
	}
	body, _ := json.Marshal(r)
	if err := os.WriteFile(filepath.Join(root, "resources.json"), body, 0600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(body)
	return root, hex.EncodeToString(sum[:])
}

func TestPortableDefaultDoesNotOverrideExplicitGeometry(t *testing.T) {
	root, _ := portableFixture(t)
	var inventory portableResources
	path := filepath.Join(root, "resources.json")
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(body, &inventory); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"prototypes/touch-terminal/data/physical-layout.json", "prototypes/touch-terminal/desktop/profiles/main-only.json"} {
		body, err := os.ReadFile(filepath.Join("..", "..", "..", filepath.FromSlash(name)))
		if err != nil {
			t.Fatal(err)
		}
		target := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(target, body, 0600); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(body)
		inventory.Files[name] = hex.EncodeToString(sum[:])
	}
	body, err = json.Marshal(inventory)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, body, 0600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(body)
	for _, tc := range []struct {
		args  []string
		width float64
		keys  int
	}{
		{nil, 18, 100},
		{[]string{"--numeric-zones", "both"}, 24.75, 134},
		{[]string{"--remove-gutters=false"}, 24.75, 134},
		{[]string{"--numeric-zones", "both", "--remove-gutters"}, 24, 134},
	} {
		o := options{}
		flags := flag.NewFlagSet("portable", flag.ContinueOnError)
		flags.StringVar(&o.Zones, "numeric-zones", "both", "")
		flags.BoolVar(&o.Gutters, "remove-gutters", false, "")
		if err := flags.Parse(tc.args); err != nil {
			t.Fatal(err)
		}
		o.GeometryExplicit = hasGeometryOptions(flags)
		if err := preparePortable(&o, root, hex.EncodeToString(sum[:])); err != nil {
			t.Fatal(err)
		}
		board, err := load(o)
		if err != nil {
			t.Fatal(err)
		}
		if board.Bounds.Width != tc.width || len(board.Keys) != tc.keys {
			t.Fatalf("%v: width=%v keys=%d", tc.args, board.Bounds.Width, len(board.Keys))
		}
	}
}

func TestPortableRejectsMissingChangedAndRewrittenInventory(t *testing.T) {
	for _, kind := range []string{"missing", "changed", "inventory"} {
		t.Run(kind, func(t *testing.T) {
			root, expected := portableFixture(t)
			if _, err := verifyPortableResources(root, expected); err != nil {
				t.Fatal(err)
			}
			path := filepath.Join(root, "font.ttf")
			if kind == "missing" {
				if err := os.Remove(path); err != nil {
					t.Fatal(err)
				}
			} else {
				if kind == "inventory" {
					path = filepath.Join(root, "resources.json")
				}
				if err := os.WriteFile(path, []byte("changed"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := verifyPortableResources(root, expected); err == nil {
				t.Fatal("bad package accepted")
			}
		})
	}
}

func TestPortableDefaultsAndNoExternalResourceFallback(t *testing.T) {
	root, expected := portableFixture(t)
	o := options{Zones: "both"}
	if err := preparePortable(&o, root, expected); err != nil {
		t.Fatal(err)
	}
	if !o.Host || o.Root != root || o.DataDir != filepath.Join(root, "data") || o.Profile != filepath.Join(root, "prototypes/touch-terminal/desktop/profiles/main-only.json") {
		t.Fatalf("wrong defaults: %+v", o)
	}
	for _, alternative := range []options{{Zones: "both", Preview: true}, {Zones: "both", CheckPackage: true}, {Zones: "both", EnglishOnly: true}, {Zones: "both", Smoke: true}} {
		if err := preparePortable(&alternative, root, expected); err != nil {
			t.Fatal(err)
		}
		if alternative.Host {
			t.Fatal("diagnostic/preview/English route opened host mode")
		}
	}
	outside := t.TempDir()
	for _, invalid := range []options{{Root: outside}, {DataDir: outside}, {Profile: filepath.Join(outside, "profile.json")}, {Profile: "../outside.json"}} {
		if err := preparePortable(&invalid, root, expected); err == nil {
			t.Fatalf("external resource accepted: %+v", invalid)
		}
	}
	if err := preparePortable(&options{CheckPackage: true}, root, ""); err == nil {
		t.Fatal("source build claimed complete package")
	}
}
