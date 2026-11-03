package installed18uhost

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func desktopFixture(t *testing.T) Options {
	o := fixture(t)
	raw, e := os.ReadFile(filepath.Join(o.Root, Descriptor))
	if e != nil {
		t.Fatal(e)
	}
	var m Manifest
	if json.Unmarshal(raw, &m) != nil {
		t.Fatal("fixture JSON")
	}
	m.Schema = "installed-18u-product-v2"
	m.Language = ""
	m.Mode = ""
	m.Languages = []string{"CN", "EN"}
	m.Modes = []string{"full", "variable", "shorthand"}
	m.Capabilities = []string{"installed-tsf-frontend", "composition", "candidates", "literal", "host-editing"}
	m.Autostart = true
	for _, path := range []string{FrontendPath, "source/prototypes/touch-terminal/encoding/manual_key_layout.resolved.json", "source/prototypes/touch-terminal/desktop/profiles/main-only.json", "source/go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf"} {
		raw := []byte("synthetic desktop resource")
		put(t, filepath.Join(o.Root, filepath.FromSlash(path)), raw)
		sum := sha256.Sum256(raw)
		m.Files = append(m.Files, File{Path: path, Bytes: int64(len(raw)), SHA256: hex.EncodeToString(sum[:])})
	}
	raw, _ = json.Marshal(m)
	put(t, filepath.Join(o.Root, Descriptor), raw)
	sum := sha256.Sum256(raw)
	o.ManifestSHA256 = hex.EncodeToString(sum[:])
	return o
}
func TestDesktopRequiresCompleteVersionTwo(t *testing.T) {
	old := fixture(t)
	if _, e := VerifyDesktopInstallation(old.Root, old.ManifestSHA256); e == nil {
		t.Fatal("legacy controlled host enabled desktop")
	}
	o := desktopFixture(t)
	if _, e := VerifyDesktopInstallation(o.Root, o.ManifestSHA256); e != nil {
		t.Fatal(e)
	}
	raw, _ := os.ReadFile(filepath.Join(o.Root, Descriptor))
	var m Manifest
	_ = json.Unmarshal(raw, &m)
	m.Modes = []string{"variable"}
	raw, _ = json.Marshal(m)
	put(t, filepath.Join(o.Root, Descriptor), raw)
	sum := sha256.Sum256(raw)
	if _, e := VerifyDesktopInstallation(o.Root, hex.EncodeToString(sum[:])); e == nil {
		t.Fatal("partial desktop capabilities accepted")
	}
}
