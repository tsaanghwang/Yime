//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

func showError(e error) {
	p, _ := syscall.UTF16PtrFromString(e.Error())
	title, _ := syscall.UTF16PtrFromString("Yime desktop keyboard")
	syscall.NewLazyDLL("user32.dll").NewProc("MessageBoxW").Call(0, uintptr(unsafe.Pointer(p)), uintptr(unsafe.Pointer(title)), 0x10)
}
