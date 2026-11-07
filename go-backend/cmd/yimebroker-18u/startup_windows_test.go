//go:build windows && (amd64 || arm64)

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

// Use the real current-process gate and production constructor; replace only
// transport/output. No TIP, pipe or actual input host is started. Dictionary
// loading remains the separate first-open contract, as on the existing x64 path.
func TestBrokerStartupProductionIdentity(t *testing.T) {
	// Emulated execution must fail at the actual process gate, never manufacture
	// a matching architecture. The native evidence runner separately requires an
	// accepted=true Windows API observation, so this refusal is not native proof.
	if gateErr := requireNativeArchitecture(); gateErr != nil {
		var out bytes.Buffer
		deps := productionBrokerDependencies()
		deps.ready = &out
		deps.serve = func(context.Context, yimebroker.NamedPipeConfig, func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error {
			t.Fatal("non-native process reached the listener")
			return nil
		}
		err := runBroker(context.Background(), startupOptions(), runtime.GOOS, runtime.GOARCH, deps)
		if err == nil || err.Error() != gateErr.Error() || out.Len() != 0 {
			t.Fatalf("non-native default startup did not stop at the native gate: %v output=%q", err, out.String())
		}
		return
	}
	selected, other := "18u-touch-product.json", "18u-touch-product-arm64.json"
	if runtime.GOARCH == "arm64" {
		selected, other = other, selected
	}
	read := func(name string) []byte {
		t.Helper()
		raw, err := os.ReadFile(filepath.Join("../../../tools/yimecore", name))
		if err != nil {
			t.Fatal(err)
		}
		return raw
	}
	raw, foreign := read(selected), read(other)
	for _, name := range []string{"matching", "both-descriptors", "product", "layout", "dictionary", "foreign-only", "foreign-renamed", "no-cross-architecture-fallback"} {
		t.Run(name, func(t *testing.T) {
			root, data := t.TempDir(), t.TempDir()
			dir := filepath.Join(root, "tools/yimecore")
			if err := os.MkdirAll(dir, 0700); err != nil {
				t.Fatal(err)
			}
			files := map[string][]byte{selected: raw}
			switch name {
			case "both-descriptors":
				files[other] = foreign
			case "foreign-only":
				files = map[string][]byte{other: foreign}
			case "foreign-renamed":
				files[selected] = foreign
			case "no-cross-architecture-fallback":
				files = map[string][]byte{selected: foreign, other: raw}
			case "product", "layout", "dictionary":
				var descriptor map[string]any
				if err := json.Unmarshal(raw, &descriptor); err != nil {
					t.Fatal(err)
				}
				switch name {
				case "product":
					descriptor["identity"].(map[string]any)["product_key"] = "YimeCore"
				case "layout":
					descriptor["data"].(map[string]any)["layout_sha256"] = "foreign-layout"
				case "dictionary":
					descriptor["data"].(map[string]any)["dictionary_sha256"] = "foreign-dictionary"
				}
				changed, err := json.Marshal(descriptor)
				if err != nil {
					t.Fatal(err)
				}
				files[selected] = changed
			}
			for filename, content := range files {
				if err := os.WriteFile(filepath.Join(dir, filename), content, 0600); err != nil {
					t.Fatal(err)
				}
			}
			var out bytes.Buffer
			listened := false
			deps := productionBrokerDependencies()
			deps.ready = &out
			deps.serve = func(_ context.Context, config yimebroker.NamedPipeConfig, _ func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error {
				listened = true
				if out.Len() != 0 {
					t.Fatal("production constructor reported READY before listening")
				}
				config.OnListening()
				return nil
			}
			options := startupOptions()
			options.root, options.data, options.pid = root, data, uint64(os.Getpid())
			err := runBroker(context.Background(), options, runtime.GOOS, runtime.GOARCH, deps)
			accepted := name == "matching" || name == "both-descriptors"
			wantOutput := ""
			if accepted {
				wantOutput = "READY yimebroker-18u\n"
			}
			if (err == nil) != accepted || listened != accepted || out.String() != wantOutput {
				t.Fatalf("real native/production startup contract: error=%v listener=%v output=%q", err, listened, out.String())
			}
		})
	}
}
