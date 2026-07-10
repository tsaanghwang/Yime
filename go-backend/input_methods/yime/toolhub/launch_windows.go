//go:build windows

package toolhub

import (
	"syscall"
	"unsafe"
)

const shellExecuteOpenVerb = "open"

const (
	swHide       uintptr = 0
	swShowNormal uintptr = 1
)

func shellExecute(filePath, parameters string, showCmd uintptr) error {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	shellExecuteW := shell32.NewProc("ShellExecuteW")
	verbPtr, err := syscall.UTF16PtrFromString(shellExecuteOpenVerb)
	if err != nil {
		return err
	}
	filePtr, err := syscall.UTF16PtrFromString(filePath)
	if err != nil {
		return err
	}
	var parametersPtr *uint16
	if parameters != "" {
		parametersPtr, err = syscall.UTF16PtrFromString(parameters)
		if err != nil {
			return err
		}
	}
	result, _, callErr := shellExecuteW.Call(
		0,
		uintptr(unsafe.Pointer(verbPtr)),
		uintptr(unsafe.Pointer(filePtr)),
		uintptr(unsafe.Pointer(parametersPtr)),
		0,
		showCmd,
	)
	if result <= 32 {
		if callErr != syscall.Errno(0) {
			return callErr
		}
		return syscall.Errno(result)
	}
	return nil
}
