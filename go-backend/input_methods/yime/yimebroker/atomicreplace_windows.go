//go:build windows

package yimebroker

import (
	"fmt"
	"syscall"
	"unsafe"
)

var journalMoveFileExW = syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")

func replaceJournalAtomically(source, destination string) error {
	sourceUTF16, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	destinationUTF16, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	result, _, callErr := journalMoveFileExW.Call(uintptr(unsafe.Pointer(sourceUTF16)), uintptr(unsafe.Pointer(destinationUTF16)), uintptr(0x1|0x8))
	if result == 0 {
		return fmt.Errorf("MoveFileExW journal replacement failed: %w", callErr)
	}
	return nil
}
