//go:build !windows && !darwin && !dragonfly && !freebsd && !linux && !netbsd && !openbsd

package touchdiagnostic

import (
	"errors"
	"os"
)

func lockRecordPath(string, recordLockMode) (*os.File, error) {
	return nil, errors.New("diagnostic directory locking is unsupported")
}
