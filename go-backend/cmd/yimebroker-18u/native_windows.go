//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"runtime"
	"syscall"
	"unsafe"
)

func requireNativeX64() error {
	p := syscall.NewLazyDLL("kernel32.dll").NewProc("IsWow64Process2")
	if e := p.Find(); e != nil {
		return fmt.Errorf("native architecture query unavailable")
	}
	process, e := syscall.GetCurrentProcess()
	if e != nil {
		return e
	}
	var machine, native uint16
	ok, _, _ := p.Call(uintptr(process), uintptr(unsafe.Pointer(&machine)), uintptr(unsafe.Pointer(&native)))
	expected := uint16(0x8664)
	if runtime.GOARCH == "arm64" {
		expected = 0xaa64
	}
	if ok == 0 || machine != 0 || native != expected {
		return fmt.Errorf("dedicated broker requires matching native Windows architecture, not emulation")
	}
	return nil
}
