package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func readBuildScript(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestBuildScriptKeepsGoExecutableHashesStableAndSupportsSigning(t *testing.T) {
	script := readBuildScript(t, "build.bat")

	required := []string{
		`if exist "%PIME_ROOT%\version.txt" set /p APP_VERSION=<"%PIME_ROOT%\version.txt"`,
		`set "GO_REPRO_FLAGS=-trimpath -buildvcs=false"`,
		`go build %GO_REPRO_FLAGS%`,
		`YIME_SIGN_CERT_SHA1`,
		`:sign_go_binaries`,
	}
	for _, fragment := range required {
		if !strings.Contains(script, fragment) {
			t.Fatalf("build.bat is missing reproducible-build/signing guard %q", fragment)
		}
	}

	if strings.Contains(script, "git describe --tags --always --dirty") {
		t.Fatal("build.bat must not inject each Git commit into every executable hash")
	}
	if count := strings.Count(script, "go build %GO_REPRO_FLAGS%"); count != 9 {
		t.Fatalf("expected all 9 Go executables to use reproducible flags, got %d", count)
	}
}

func TestBuildScriptFindsGoWinresOutsidePATH(t *testing.T) {
	script := readBuildScript(t, "build.bat")

	required := []string{
		`where.exe go-winres.exe`,
		`go env GOPATH`,
		`\bin\go-winres.exe`,
		`"%GO_WINRES%" simply`,
	}
	for _, fragment := range required {
		if !strings.Contains(script, fragment) {
			t.Fatalf("build.bat is missing go-winres discovery fragment %q", fragment)
		}
	}
	if count := strings.Count(script, `"%GO_WINRES%" simply`); count != 9 {
		t.Fatalf("expected all 9 resource builds to use resolved go-winres, got %d", count)
	}
	for _, fragment := range []string{
		`--file-description "Yime Layout Designer"`,
		`--original-filename "yime-layout-designer.exe"`,
		`--out cmd\yime-layout-designer\rsrc_layout_designer`,
		`if exist cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso del cmd\yime-layout-designer\rsrc_layout_designer_windows_amd64.syso`,
	} {
		if !strings.Contains(script, fragment) {
			t.Fatalf("layout designer VERSIONINFO build guard is missing %q", fragment)
		}
	}
	if strings.Contains(script, "\ngo-winres simply") || strings.Contains(script, "\r\ngo-winres simply") {
		t.Fatal("resource generation must not rely on a bare go-winres command")
	}
}

func TestBuildScriptPropagatesSanitizedChildFailure(t *testing.T) {
	buildScript := readBuildScript(t, filepath.Join("..", "build.bat"))
	wrapperScript := readBuildScript(t, filepath.Join("..", "tools", "invoke-build-environment.ps1"))

	buildRequired := []string{
		`invoke-build-environment.ps1" -BuildScript "%~f0"`,
		`if errorlevel 1 exit /b 1`,
		`exit /b 0`,
	}
	for _, fragment := range buildRequired {
		if !strings.Contains(buildScript, fragment) {
			t.Fatalf("build.bat is missing sanitized wrapper propagation %q", fragment)
		}
	}

	wrapperRequired := []string{
		`& $BuildScript --sanitized`,
		`exit $LASTEXITCODE`,
	}
	for _, fragment := range wrapperRequired {
		if !strings.Contains(wrapperScript, fragment) {
			t.Fatalf("invoke-build-environment.ps1 is missing child exit-code propagation %q", fragment)
		}
	}

	if strings.Contains(wrapperScript, `& $BuildScript --sanitized"`) {
		t.Fatal("sanitized wrapper must not discard the child script's exit code")
	}
}
