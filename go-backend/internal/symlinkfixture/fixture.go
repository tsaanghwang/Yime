// Package symlinkfixture is test-only support; never called by product code.
package symlinkfixture

import (
	"errors"
	"os"
	"runtime"
	"syscall"
	"testing"
)

// Unavailable deliberately excludes access denied, missing parents, collisions,
// and unsupported filesystems. Those are broken prerequisites, not evidence SKIPs.
func Unavailable(platform string, err error) bool {
	return platform == "windows" && errors.Is(err, syscall.Errno(1314))
}

func Create(t *testing.T, target, link string) {
	t.Helper()
	if _, err := os.Lstat(target); err != nil {
		t.Fatal("fixture target: ", err)
	}
	if err := os.Symlink(target, link); err != nil {
		if Unavailable(runtime.GOOS, err) && os.Getenv("YIME_REQUIRE_SYMLINK_FIXTURE") != "1" {
			t.Skipf("SYMLINK_FIXTURE_UNAVAILABLE windows_error=1314 rejection_exercised=false: %v", err)
		}
		t.Fatalf("SYMLINK_FIXTURE_SETUP_FAILED rejection_exercised=false: %v", err)
	}
	info, err := os.Lstat(link)
	if err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("fixture is not a symbolic link: %v", err)
	}
	got, err := os.Readlink(link)
	if err != nil || got != target {
		t.Fatalf("fixture target mismatch: %q %v", got, err)
	}
	t.Log("SYMLINK_FIXTURE_READY")
}

func Rejected(t *testing.T, err error, want string) {
	t.Helper()
	if err == nil || err.Error() != want {
		t.Fatalf("expected precise symlink rejection %q, got %v", want, err)
	}
	t.Logf("SYMLINK_REJECTION_EXERCISED diagnostic=%s", want)
}

func PackageDiagnostic() string {
	if runtime.GOOS == "windows" {
		return "reparse points forbidden in candidate package paths"
	}
	return "indirect trial paths are forbidden"
}
