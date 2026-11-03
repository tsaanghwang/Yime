package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMaintenanceMemberBoundary(t *testing.T) {
	for _, name := range []string{"../Setup.ps1", "payload/../../x", "C:/x", "payload\\x", "/x", "payload/x:stream", "payload//x", "payload/x.", "payload/ x", "payload/NUL.txt", "payload/com1", "payload/LPT²", "payload/x\x00", "payload/x*"} {
		if validMember(name) {
			t.Errorf("accepted unsafe member %q", name)
		}
	}
	if !validMember("payload/source/中文/a.json") {
		t.Fatal("ordinary nested member rejected")
	}
}

func TestPlanRequiresCompiledBytesAndCompleteEntry(t *testing.T) {
	p := maintenancePlan{Schema: "yime-native-maintenance-v1", Product: "yimecore-18u", Target: "windows-arm64", SourceCommit: strings.Repeat("a", 40), Shell: shellRecord{Path: shellMember, SHA256: strings.Repeat("c", 64)}, Files: map[string]fileRecord{}}
	for _, name := range []string{"Setup.ps1", "Product.psm1", "product-package.json", "maintenance/preflight.ps1", shellMember} {
		p.Files[name] = fileRecord{Bytes: 1, SHA256: strings.Repeat("c", 64)}
	}
	encode := func(p maintenancePlan) ([]byte, string) {
		b, _ := json.Marshal(p)
		h := sha256.Sum256(b)
		return b, hex.EncodeToString(h[:])
	}
	b, h := encode(p)
	if _, err := parsePlan(b, h); err != nil {
		t.Fatal(err)
	}
	if _, err := parsePlan(b, strings.Repeat("0", 64)); err == nil {
		t.Fatal("accepted changed plan")
	}
	p.Shell.Path = filepath.Join(t.TempDir(), "pwsh.exe")
	b, h = encode(p)
	if _, err := parsePlan(b, h); err == nil {
		t.Fatal("accepted external shell dependency")
	}
	p.Shell.Path = shellMember
	p.Shell.SHA256 = strings.Repeat("b", 64)
	b, h = encode(p)
	if _, err := parsePlan(b, h); err == nil {
		t.Fatal("accepted shell/inventory disagreement")
	}
	p.Shell.SHA256 = strings.Repeat("c", 64)
	delete(p.Files, "Setup.ps1")
	b, h = encode(p)
	if _, err := parsePlan(b, h); err == nil {
		t.Fatal("accepted missing script")
	}
}

func TestVerifyStreamRejectsSameSizeReplacement(t *testing.T) {
	path := filepath.Join(t.TempDir(), "asset")
	if err := os.WriteFile(path, []byte("expected"), 0600); err != nil {
		t.Fatal(err)
	}
	h := sha256.Sum256([]byte("expected"))
	row := fileRecord{Bytes: 8, SHA256: hex.EncodeToString(h[:])}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err = verifyStream(f, row); err != nil {
		t.Fatal(err)
	}
	f.Close()
	if err = os.WriteFile(path, []byte("replaced"), 0600); err != nil {
		t.Fatal(err)
	}
	f, err = os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err = verifyStream(f, row); err == nil {
		t.Fatal("accepted same-size replaced bytes")
	}
}
