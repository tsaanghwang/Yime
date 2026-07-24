//go:build windows

package yime

import (
	"runtime"
	"testing"
	"unsafe"
)

func TestRimeAPIFunctionAtValidatesDataSize(t *testing.T) {
	api := rimeAPIC{
		DataSize: int32(unsafe.Sizeof(rimeAPIC{}) - unsafe.Sizeof(int32(0))),
	}
	api.Functions[rimeAPISetCaretPosIndex] = 0x12345678
	address := uintptr(unsafe.Pointer(&api))

	if got := rimeAPIFunctionAt(address, rimeAPISetCaretPosIndex); got != 0x12345678 {
		t.Fatalf("expected function pointer, got %#x", got)
	}
	api.DataSize = int32(unsafe.Offsetof(api.Functions) - unsafe.Sizeof(api.DataSize))
	if got := rimeAPIFunctionAt(address, rimeAPISetCaretPosIndex); got != 0 {
		t.Fatalf("truncated API table must be rejected, got %#x", got)
	}
	runtime.KeepAlive(&api)
}

func TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex(t *testing.T) {
	if got := rimeAPIFunctionAt(0, rimeAPIGetInputIndex); got != 0 {
		t.Fatalf("nil API address must be rejected, got %#x", got)
	}
	api := rimeAPIC{DataSize: -1}
	address := uintptr(unsafe.Pointer(&api))
	if got := rimeAPIFunctionAt(address, rimeAPIGetInputIndex); got != 0 {
		t.Fatalf("negative API size must be rejected, got %#x", got)
	}
	if got := rimeAPIFunctionAt(address, rimeAPIFunctionCount); got != 0 {
		t.Fatalf("out-of-range function index must be rejected, got %#x", got)
	}
	runtime.KeepAlive(&api)
}

func TestCStringAtCopiesBoundedExternalMemory(t *testing.T) {
	source := []byte{'b', 'j', 'j', 'j', 0, 'x'}
	address := uintptr(unsafe.Pointer(&source[0]))
	if got, ok := cStringAt(address, len(source)); !ok || got != "bjjj" {
		t.Fatalf("unexpected copied string %q ok=%v", got, ok)
	}
	if got, ok := cStringAt(address, 3); ok || got != "" {
		t.Fatalf("unterminated bounded string must be rejected, got %q ok=%v", got, ok)
	}
	runtime.KeepAlive(source)
}
