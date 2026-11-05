//go:build windows

package touchdiagnostic

import (
	"errors"
	"os"
	"syscall"
	"testing"
)

func TestDiagnosticPreservesOnlyTypedWin32(t *testing.T) {
	err := &os.PathError{Op: "private-operation", Path: "private-input-path", Err: syscall.Errno(5)}
	d := FromError(err, "transport-read", "read-failed")
	if d.Win32 == nil || *d.Win32 != 5 || d.Error() != "transport-read/read-failed win32=5" {
		t.Fatal("wrapped system error was not preserved safely")
	}
	for _, err := range []error{errors.New("ReadFile failed with Windows error 5 private-input"), syscall.Errno(0)} {
		if FromError(err, "transport-read", "read-failed").Win32 != nil {
			t.Fatal("unavailable or textual system error was invented")
		}
	}
}
