//go:build windows && amd64

package main

import (
	"fmt"
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
	if ok == 0 || machine != 0 || native != 0x8664 {
		return fmt.Errorf("dedicated broker requires native Windows x64, not emulation")
	}
	return nil
}
