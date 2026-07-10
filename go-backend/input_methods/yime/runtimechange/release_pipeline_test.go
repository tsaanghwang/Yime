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
	buildScript := read(filepath.Join(root, "go-backend", "build.bat"))
	installer := read(filepath.Join(root, "installer", "installer.nsi"))
	signer := read(filepath.Join(root, "tools", "sign-release.ps1"))
	verifier := read(filepath.Join(root, "tools", "verify-release-signatures.ps1"))
	signFile := read(filepath.Join(root, "tools", "sign-file.ps1"))

	for _, fragment := range []string{"tags: ['v*']", "Import release signing certificate", "sign-release.ps1 -RequireComplete", "verify-release-signatures.ps1 -IncludeInstaller", "YIME-unsigned-test-installer", "installer/YIME-*-setup.exe"} {
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
	for _, fragment := range []string{"SignerCertificate.Thumbprint", "TimeStamperCertificate", "YIME_SIGN_CERT_SHA1"} {
		if !strings.Contains(verifier, fragment) {
			t.Fatalf("release signature verifier is missing %q", fragment)
		}
	}
	if count := strings.Count(buildScript, "--icon input_methods\\yime\\icon.ico"); count != 8 {
		t.Fatalf("expected all 8 Go executables to embed the Yime icon, got %d", count)
	}
	if !strings.Contains(buildScript, `for /r "%PACKAGE_DIR%\input_methods" %%F in (*.go)`) {
		t.Fatal("package build must recursively remove copied Go source files")
	}
	for _, fragment := range []string{`if not defined GOCACHE set "GOCACHE=%PIME_ROOT%\.tmp\go-cache"`, `if not defined GOTMPDIR set "GOTMPDIR=%PIME_ROOT%\.tmp\go-tmp"`} {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("build.bat is missing workspace-local Go cache default %q", fragment)
		}
	}
	if !strings.Contains(ci, "Remove-Item -LiteralPath $pfxPath") {
		t.Fatal("release CI must remove the temporary PFX after import")
	}
	for _, fragment := range []string{"1.2.840.113549.1.1.1", "1.3.6.1.5.5.7.3.3", "HasPrivateKey", "NotAfter"} {
		if !strings.Contains(signFile, fragment) {
			t.Fatalf("sign-file.ps1 is missing certificate validation %q", fragment)
		}
	}
}
