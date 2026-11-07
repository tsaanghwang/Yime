package main

import (
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstalledTSFOutputContracts(t *testing.T) {
	for _, o := range []tk.Output{{Text: "中文😀"}, {Key: "ArrowLeft", Shift: true}, {Text: "a", Ctrl: true}, {Key: "Delete"}, {Key: "Tab"}} {
		text, key, _, err := tsfEdit(o)
		if err != nil || (text == "") == (key == "") {
			t.Fatalf("%+v: %v", o, err)
		}
	}
	for _, o := range []tk.Output{{Text: "c", Ctrl: true}, {Text: "x", Alt: true}, {Key: "Enter", Shift: true}, {Key: "F1"}, {Key: "ArrowUp"}, {}} {
		if _, _, _, err := tsfEdit(o); err == nil {
			t.Fatalf("unsupported output accepted: %+v", o)
		}
	}
}
func TestInstalledFrontendAnchor(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, ".setup")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	write := func(body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(dir, "product-package.json"), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
	}
	hash := strings.Repeat("a", 64)
	body := `{"format":"yime-simple-package-18u-1","product":"yimecore-18u","target":"` + installed18uhost.PackageTarget + `","host_architecture":"` + strings.TrimPrefix(installed18uhost.PackageTarget, "windows-") + `","tsf64_architecture":"` + installed18uhost.NativeDirectory + `","files":[{"path":"installed-18u-product.json","sha256":"` + hash + `"}]}`
	write(body)
	if got, err := installedFrontendAnchor(root); err != nil || got != hash {
		t.Fatalf("%s %v", got, err)
	}
	foreign := "windows-arm64"
	if installed18uhost.PackageTarget == foreign {
		foreign = "windows-amd64"
	}
	for _, bad := range []string{strings.Replace(body, "yimecore-18u", "yimecore", 1), strings.Replace(body, installed18uhost.PackageTarget, foreign, 1), strings.Replace(body, `"host_architecture":"`, `"host_architecture":"foreign-`, 1), strings.Replace(body, `"tsf64_architecture":"`, `"tsf64_architecture":"foreign-`, 1), strings.Replace(body, hash, "bad", 1), `{}`} {
		write(bad)
		if _, err := installedFrontendAnchor(root); err == nil {
			t.Fatal("invalid anchor accepted")
		}
	}
}
func TestInstalledBuildRejectsLegacyEntry(t *testing.T) {
	old := installedTSFOnly
	installedTSFOnly = "1"
	defer func() { installedTSFOnly = old }()
	for _, o := range []options{{Host: true}, {EnglishOnly: true}, {OwnTSFDemo: true}, {HostSmoke: true}, {Smoke: true}, {Shot: "x"}} {
		if err := prepareInstalledFrontend(&o, "unused"); err == nil {
			t.Fatalf("legacy entry accepted: %+v", o)
		}
	}
	for _, o := range []options{{Preview: true}, {CheckPackage: true}, {CheckData: true}} {
		if err := prepareInstalledFrontend(&o, "unused"); err != nil || o.InstalledTSF {
			t.Fatalf("offline entry: %v", err)
		}
	}
}
