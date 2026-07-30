//go:build windows

package toolbarstate

import (
	"syscall"
	"unsafe"
)

var (
	replaceKernel32 = syscall.NewLazyDLL("kernel32.dll")
	moveFileExW     = replaceKernel32.NewProc("MoveFileExW")
)

func replaceFile(tempPath, path string) error {
	source, err := syscall.UTF16PtrFromString(tempPath)
	if err != nil {
		return err
	}
	destination, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	const moveFileReplaceExisting = 0x1
	const moveFileWriteThrough = 0x8
	ret, _, callErr := moveFileExW.Call(
		uintptr(unsafe.Pointer(source)),
		uintptr(unsafe.Pointer(destination)),
		moveFileReplaceExisting|moveFileWriteThrough,
	)
	if ret == 0 {
		return callErr
	}
	return nil
}
