//go:build windows

package touchdiagnostic

import (
	"errors"
	"syscall"
)

func win32FromError(err error) *uint32 {
	var code syscall.Errno
	if errors.As(err, &code) && code != 0 && uint64(code) <= uint64(^uint32(0)) {
		value := uint32(code)
		return &value
	}
	return nil
}
