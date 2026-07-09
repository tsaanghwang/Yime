//go:build windows

package yime

import (
	"syscall"
	"unsafe"
)

func (ime *IME) showUserLexiconMessage(title, message, icon string) {
	ime.showUserMessage(title, message, icon)
}

func (ime *IME) showUserMessage(title, message, icon string) {
	if title == "" {
		title = "音元输入法"
	}
	if message == "" {
		return
	}
	msgBoxW(title, message, icon)
}

func msgBoxW(title, message, icon string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBoxW := user32.NewProc("MessageBoxW")

	var mbIcon uintptr
	switch icon {
	case "Error":
		mbIcon = 0x10
	case "Warning":
		mbIcon = 0x30
	case "Information":
		mbIcon = 0x40
	default:
		mbIcon = 0x40
	}

	titlePtr, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return
	}
	messagePtr, err := syscall.UTF16PtrFromString(message)
	if err != nil {
		return
	}

	messageBoxW.Call(0, uintptr(unsafe.Pointer(messagePtr)), uintptr(unsafe.Pointer(titlePtr)), mbIcon|0x00)
}
