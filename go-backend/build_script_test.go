package main

import (
	"os"
	"strings"
	"testing"
)

func TestBuildScriptKeepsGoExecutableHashesStableAndSupportsSigning(t *testing.T) {
	data, err := os.ReadFile("build.bat")
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)

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
