package symlinkfixture

import (
	"os"
	"syscall"
	"testing"
)

func TestUnavailableClassification(t *testing.T) {
	for _, c := range []struct {
		name, platform string
		err            error
		want           bool
	}{
		{"privilege", "windows", &os.LinkError{Op: "symlink", Err: syscall.Errno(1314)}, true},
		{"access-denied", "windows", syscall.Errno(5), false},
		{"missing-parent", "windows", os.ErrNotExist, false},
		{"collision", "windows", os.ErrExist, false},
		{"unsupported", "windows", syscall.Errno(50), false},
		{"other-os", "linux", syscall.Errno(1314), false},
		{"success", "windows", nil, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			if Unavailable(c.platform, c.err) != c.want {
				t.Fatal("incorrect SKIP classification")
			}
		})
	}
}
