//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"runtime"
	"syscall"
	"unsafe"
)

const privateFontFlags = 0x10 // FR_PRIVATE: only this process can use the font.

// Keep the UTF-16 allocation reachable until removal. Saving only its uintptr
// in a deferred Call leaves the allocation unowned during the UI message loop.
type privateFontResource struct {
	path *uint16
}

func loadPrivateFont(path string) (*privateFontResource, error) {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, fmt.Errorf("private font path: %w", err)
	}
	n, _, _ := G("AddFontResourceExW").Call(uintptr(unsafe.Pointer(name)), privateFontFlags, 0)
	runtime.KeepAlive(name)
	if n == 0 {
		return nil, fmt.Errorf("无法加载进程私有 YinYuan 字体")
	}
	return &privateFontResource{path: name}, nil
}

func (font *privateFontResource) Close() error {
	if font == nil || font.path == nil {
		return nil
	}
	name := font.path
	font.path = nil // This owner removes its one registration at most once.
	n, _, _ := G("RemoveFontResourceExW").Call(uintptr(unsafe.Pointer(name)), privateFontFlags, 0)
	runtime.KeepAlive(name)
	if n == 0 {
		return fmt.Errorf("无法移除进程私有 YinYuan 字体")
	}
	return nil
}
