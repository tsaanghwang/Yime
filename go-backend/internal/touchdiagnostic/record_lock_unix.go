//go:build darwin || dragonfly || freebsd || linux || netbsd || openbsd

package touchdiagnostic

import (
	"fmt"
	"os"
	"syscall"
)

// A persistent inode and a nonblocking kernel lock avoid stale lock ownership
// after a crash. Never unlink the file while any process could hold its lock.
func lockRecordPath(path string, mode recordLockMode) (*os.File, error) {
	flags := syscall.O_RDWR | syscall.O_CLOEXEC | syscall.O_NOFOLLOW
	if mode == recordLockCreate {
		flags |= syscall.O_CREAT
	} else if mode == recordLockCreateNew {
		flags |= syscall.O_CREAT | syscall.O_EXCL
	}
	fd, err := syscall.Open(path, flags, 0600)
	if err != nil {
		return nil, err
	}
	file := os.NewFile(uintptr(fd), path)
	info, err := file.Stat()
	if err != nil {
		file.Close()
		return nil, err
	}
	if !info.Mode().IsRegular() {
		file.Close()
		return nil, syscall.EACCES
	}
	if err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		file.Close()
		if err == syscall.EWOULDBLOCK || err == syscall.EAGAIN {
			return nil, fmt.Errorf("%w: %w", ErrStorageBusy, err)
		}
		return nil, err
	}
	return file, nil
}
