//go:build windows

package win32ui

import (
	"runtime"
	"syscall"
	"unsafe"
)

var procRtlMoveMemory = syscall.NewLazyDLL("kernel32.dll").NewProc("RtlMoveMemory")

// ReadMessageStruct copies a structure supplied by a synchronous Win32
// callback into Go-managed memory. The callback address is valid only while
// the window procedure is running and must not be retained.
func ReadMessageStruct[T any](address uintptr) T {
	var value T
	if address == 0 {
		return value
	}
	procRtlMoveMemory.Call(
		uintptr(unsafe.Pointer(&value)),
		address,
		unsafe.Sizeof(value),
	)
	runtime.KeepAlive(&value)
	return value
}

// WriteMessageStruct copies a Go structure back to memory supplied by a
// synchronous Win32 callback. It is used for writable messages such as
// WM_GETMINMAXINFO.
func WriteMessageStruct[T any](address uintptr, value *T) {
	if address == 0 || value == nil {
		return
	}
	procRtlMoveMemory.Call(
		address,
		uintptr(unsafe.Pointer(value)),
		unsafe.Sizeof(*value),
	)
	runtime.KeepAlive(value)
}
