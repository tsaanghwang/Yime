//go:build windows

package speechruntime

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"unsafe"
)

func productPlainPath(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for current := abs; ; current = filepath.Dir(current) {
		pointer, err := syscall.UTF16PtrFromString(current)
		if err != nil {
			return err
		}
		attributes, err := syscall.GetFileAttributes(pointer)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		if err == nil && attributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return errors.New("indirect product speech path forbidden")
		}
		if filepath.Dir(current) == current {
			return nil
		}
	}
}

var settingsMoveFileExW = syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")

func replaceSettingsAtomically(source, destination string) error {
	src, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	dst, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	result, _, callErr := settingsMoveFileExW.Call(uintptr(unsafe.Pointer(src)), uintptr(unsafe.Pointer(dst)), uintptr(0x1|0x8))
	if result == 0 {
		return fmt.Errorf("atomic speech settings replacement failed: %w", callErr)
	}
	return nil
}
