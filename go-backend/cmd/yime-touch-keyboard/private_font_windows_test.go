//go:build windows && (amd64 || arm64)

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

// A native invalid-pointer fault cannot be recovered by testing.T. Isolate this
// real GDI lifetime test in a child, with no window, TIP or frontend startup.
func TestPrivateFontResourceSurvivesGC(t *testing.T) {
	const childEnv = "YIME_PRIVATE_FONT_LIFETIME_CHILD"
	if os.Getenv(childEnv) != "1" {
		exe, err := os.Executable()
		if err != nil {
			t.Fatal(err)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, exe, "-test.run=^TestPrivateFontResourceSurvivesGC$", "-test.v")
		cmd.Env = append(os.Environ(), childEnv+"=1")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("private-font child: %v\n%s", err, out)
		}
		t.Logf("private-font child:\n%s", out)
		return
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	data, err := os.ReadFile("../../input_methods/yime/data/fonts/YinYuan-Regular.ttf")
	if err != nil {
		t.Fatal(err)
	}
	// A unique copy gives this test sole ownership of this path's registration.
	fontPath := filepath.Join(t.TempDir(), "YinYuan-字体-lifetime.ttf")
	if err := os.WriteFile(fontPath, data, 0600); err != nil {
		t.Fatal(err)
	}
	name, err := syscall.UTF16FromString(fontPath)
	if err != nil {
		t.Fatal(err)
	}
	// If removal fails, this independently live buffer still releases our
	// unique registration before TempDir cleanup. It does not retain the
	// separate UTF-16 allocation owned by loadPrivateFont.
	t.Cleanup(func() {
		G("RemoveFontResourceExW").Call(uintptr(unsafe.Pointer(&name[0])), privateFontFlags, 0)
		runtime.KeepAlive(name)
	})
	for cycle := 0; cycle < 3; cycle++ {
		font, err := loadPrivateFont(fontPath)
		if err != nil {
			t.Fatal(err)
		}
		// This is the same ownership arrangement as run's long-lived defer.
		func() {
			var churn [][]uint16
			defer func() {
				err := font.Close()
				runtime.KeepAlive(churn)
				if err != nil {
					t.Fatal(err)
				}
			}()
			runtime.GC()
			debug.FreeOSMemory()
			// Reuse the old buffer's allocation class if it was kept only as an
			// integer address. Keep the pressure alive through native removal.
			churn = make([][]uint16, 8192)
			for i := range churn {
				churn[i] = make([]uint16, len(name))
				for j := range churn[i] {
					churn[i][j] = 'x'
				}
			}
			runtime.GC()
		}()
		// Removing again by an independently live path must fail: Close must
		// actually have released the registration, not merely returned success.
		n, _, _ := G("RemoveFontResourceExW").Call(uintptr(unsafe.Pointer(&name[0])), privateFontFlags, 0)
		runtime.KeepAlive(name)
		if n != 0 {
			t.Fatal("Close left a private font registration behind")
		}
		if err := font.Close(); err != nil {
			t.Fatalf("second Close must be harmless: %v", err)
		}
		t.Logf("cycle %d: Add succeeded, deferred Remove survived GC, extra Remove returned zero", cycle+1)
	}
}

func TestPrivateFontResourceRejectsInvalidPaths(t *testing.T) {
	for _, path := range []string{filepath.Join(t.TempDir(), "missing.ttf"), "bad\x00path.ttf"} {
		font, err := loadPrivateFont(path)
		if err == nil || font != nil {
			if font != nil {
				_ = font.Close()
			}
			t.Fatalf("invalid path accepted: %q", path)
		}
	}
}
