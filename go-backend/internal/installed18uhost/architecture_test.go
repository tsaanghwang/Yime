package installed18uhost

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallationArchitectureAndLegacyDescriptorRefusedBeforeStart(t *testing.T) {
	for _, kind := range []string{"foreign-architecture", "foreign-native-path", "foreign-source-descriptor", "legacy-v2"} {
		t.Run(kind, func(t *testing.T) {
			o := fixture(t)
			path := filepath.Join(o.Root, Descriptor)
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			var m Manifest
			if err := json.Unmarshal(raw, &m); err != nil {
				t.Fatal(err)
			}
			foreignDir, foreignDescriptor := "arm64", "18u-touch-product-arm64.json"
			if NativeDirectory == foreignDir {
				foreignDir, foreignDescriptor = "x64", "18u-touch-product.json"
			}
			switch kind {
			case "foreign-architecture":
				m.Architecture = "native-" + foreignDir
			case "legacy-v2":
				m.Schema = "installed-18u-product-v2"
			default:
				for i := range m.Files {
					old := m.Files[i].Path
					if kind == "foreign-native-path" && old == DLLPath {
						m.Files[i].Path = foreignDir + "/YimeTextService18u.dll"
					}
					if kind == "foreign-source-descriptor" && strings.HasSuffix(old, "/"+ProductDescriptor) {
						m.Files[i].Path = "source/tools/yimecore/" + foreignDescriptor
					}
					if old != m.Files[i].Path {
						content, err := os.ReadFile(filepath.Join(o.Root, filepath.FromSlash(old)))
						if err != nil {
							t.Fatal(err)
						}
						put(t, filepath.Join(o.Root, filepath.FromSlash(m.Files[i].Path)), content)
					}
				}
			}
			raw, err = json.Marshal(m)
			if err != nil {
				t.Fatal(err)
			}
			put(t, path, raw)
			h := sha256.Sum256(raw)
			o.ManifestSHA256 = hex.EncodeToString(h[:])
			r := Run(context.Background(), o, func(context.Context, string, []string, string, io.Writer) (Child, error) {
				t.Fatal("foreign or legacy manifest started a process")
				return nil, nil
			})
			if r.Status == "evidence-consistent" {
				t.Fatal("foreign or legacy manifest accepted")
			}
		})
	}
}
