package runtimechange

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestReleasePipelineSignsPayloadInstallerAndUninstaller(t *testing.T) {
	read := func(path string) string {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}
	root := filepath.Clean(filepath.Join("..", "..", "..", ".."))
	ci := read(filepath.Join(root, ".github", "workflows", "ci.yaml"))
	installer := read(filepath.Join(root, "installer", "installer.nsi"))
	signer := read(filepath.Join(root, "tools", "sign-release.ps1"))
	verifier := read(filepath.Join(root, "tools", "verify-release-signatures.ps1"))

	for _, fragment := range []string{"tags: ['v*']", "Import release signing certificate", "sign-release.ps1 -RequireComplete", "verify-release-signatures.ps1 -IncludeInstaller"} {
		if !strings.Contains(ci, fragment) {
			t.Fatalf("CI release signing chain is missing %q", fragment)
		}
	}
	for _, fragment := range []string{"!finalize", "!uninstfinalize", "sign-file.ps1"} {
		if !strings.Contains(installer, fragment) {
			t.Fatalf("NSIS signing hooks are missing %q", fragment)
		}
	}
	for _, fragment := range []string{"PIMELauncher.exe", "PIMETextService.dll", "rime_deployer.exe", "rime.dll"} {
		if !strings.Contains(signer, fragment) {
			t.Fatalf("release payload signer is missing %q", fragment)
		}
	}
	if !strings.Contains(verifier, "Get-AuthenticodeSignature") || !strings.Contains(verifier, "Valid") {
		t.Fatal("release signature verifier must reject non-valid signatures")
	}
}
