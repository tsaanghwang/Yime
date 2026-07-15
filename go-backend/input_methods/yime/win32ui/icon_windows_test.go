//go:build windows

package win32ui

import (
	"path/filepath"
	"testing"
)

func TestYimeIconPathUsesSharedInputProfileIcon(t *testing.T) {
	got := yimeIconPath(filepath.Join(`C:\Program Files (x86)\YIME\go-backend`, "tool-hub.exe"))
	want := filepath.Join(`C:\Program Files (x86)\YIME\go-backend`, "input_methods", "yime", "icon.ico")
	if got != want {
		t.Fatalf("yimeIconPath() = %q, want %q", got, want)
	}
}
