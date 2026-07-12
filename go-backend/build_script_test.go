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
	if count := strings.Count(script, "go build %GO_REPRO_FLAGS%"); count != 8 {
		t.Fatalf("expected all 8 Go executables to use reproducible flags, got %d", count)
	}
}

func TestBuildScriptPropagatesSanitizedChildFailure(t *testing.T) {
	script := readBuildScript(t, filepath.Join("..", "build.bat"))

	required := []string{
		`& $script --sanitized; exit $LASTEXITCODE`,
		`if errorlevel 1 exit /b 1`,
		`exit /b 0`,
	}
	for _, fragment := range required {
		if !strings.Contains(script, fragment) {
			t.Fatalf("build.bat is missing sanitized child exit-code propagation %q", fragment)
		}
	}

	if strings.Contains(script, "& $script --sanitized\"") {
		t.Fatal("sanitized wrapper must explicitly exit with the child script's exit code")
	}
}
