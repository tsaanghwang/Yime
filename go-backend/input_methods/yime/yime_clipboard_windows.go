//go:build windows

package yime

import (
	"syscall"
	"unsafe"
)

func win32CopyToClipboard(text string) error {
	user32 := syscall.NewLazyDLL("user32.dll")
	openClipboard := user32.NewProc("OpenClipboard")
	closeClipboard := user32.NewProc("CloseClipboard")
	emptyClipboard := user32.NewProc("EmptyClipboard")
	setClipboardData := user32.NewProc("SetClipboardData")

	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	globalAlloc := kernel32.NewProc("GlobalAlloc")
	globalLock := kernel32.NewProc("GlobalLock")
	globalUnlock := kernel32.NewProc("GlobalUnlock")

	utf16, err := syscall.UTF16FromString(text)
	if err != nil {
		return err
	}
	size := len(utf16) * 2

	const gmemMoveable = 0x0002
	hMem, _, _ := globalAlloc.Call(gmemMoveable, uintptr(size))
	if hMem == 0 {
		return syscall.GetLastError()
	}

	ptr, _, _ := globalLock.Call(hMem)
	if ptr == 0 {
		return syscall.GetLastError()
	}
	copy(unsafe.Slice((*uint16)(unsafe.Pointer(ptr)), len(utf16)), utf16)
	globalUnlock.Call(hMem)

	ret, _, _ := openClipboard.Call(0)
	if ret == 0 {
		return syscall.GetLastError()
	}
	defer closeClipboard.Call()

	emptyClipboard.Call()

	r, _, _ := setClipboardData.Call(13, hMem) // CF_UNICODETEXT = 13
	if r == 0 {
		return syscall.GetLastError()
	}
	return nil
}
