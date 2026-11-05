//go:build windows

package touchdiagnostic

import (
	"fmt"
	"os"
	"syscall"
)

// The file remains in place; exclusive sharing belongs to this kernel handle,
// so closing the handle or terminating the process releases the lock. Deleting
// the lock file would let another process create a second independent lock.
func lockRecordPath(path string, mode recordLockMode) (*os.File, error) {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	disposition := uint32(syscall.OPEN_EXISTING)
	if mode == recordLockCreate {
		disposition = syscall.OPEN_ALWAYS
	} else if mode == recordLockCreateNew {
		disposition = syscall.CREATE_NEW
	}
	handle, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, disposition, syscall.FILE_ATTRIBUTE_NORMAL|0x00200000, 0)
	if err != nil {
		if err == syscall.Errno(32) || err == syscall.Errno(33) {
			return nil, fmt.Errorf("%w: %w", ErrStorageBusy, err)
		}
		return nil, err
	}
	var info syscall.ByHandleFileInformation
	if err = syscall.GetFileInformationByHandle(handle, &info); err != nil {
		syscall.CloseHandle(handle)
		return nil, err
	}
	if info.FileAttributes&(syscall.FILE_ATTRIBUTE_REPARSE_POINT|syscall.FILE_ATTRIBUTE_DIRECTORY) != 0 {
		syscall.CloseHandle(handle)
		return nil, syscall.ERROR_ACCESS_DENIED
	}
	return os.NewFile(uintptr(handle), path), nil
}
