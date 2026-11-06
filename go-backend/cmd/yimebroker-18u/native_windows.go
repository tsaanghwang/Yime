//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"runtime"
	"syscall"
	"unsafe"
)

func requireNativeArchitecture() error {
	machine, native, e := queryNativeArchitecture()
	return validateNativeArchitecture(runtime.GOARCH, machine, native, e)
}

func queryNativeArchitecture() (uint16, uint16, error) {
	p := syscall.NewLazyDLL("kernel32.dll").NewProc("IsWow64Process2")
	if e := p.Find(); e != nil {
		return 0, 0, fmt.Errorf("native architecture query unavailable: %w", e)
	}
	process, e := syscall.GetCurrentProcess()
	if e != nil {
		return 0, 0, e
	}
	var machine, native uint16
	ok, _, callErr := p.Call(uintptr(process), uintptr(unsafe.Pointer(&machine)), uintptr(unsafe.Pointer(&native)))
	if ok == 0 {
		return 0, 0, fmt.Errorf("native architecture query failed: %w", callErr)
	}
	return machine, native, nil
}
