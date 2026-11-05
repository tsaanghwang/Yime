//go:build windows

package yime

import (
	"runtime"
	"testing"
	"unsafe"
)

// Keep a large frame live across recursion so the caller's stack must grow.
// The fixtures below export integer addresses, just like Rime's DLL memory.
//
//go:noinline
func growRimeMemoryTestStack(depth int) byte {
	var frame [4096]byte
	frame[depth] = byte(depth)
	if depth > 0 {
		frame[0] = growRimeMemoryTestStack(depth - 1)
	}
	result := frame[depth]
	runtime.KeepAlive(&frame)
	return result
}

func TestRimeAPIFunctionAtValidatesDataSize(t *testing.T) {
	api := rimeAPIC{
		DataSize: int32(unsafe.Sizeof(rimeAPIC{}) - unsafe.Sizeof(int32(0))),
	}
	api.Functions[rimeAPISetCaretPosIndex] = 0x12345678
	// Unlike DLL-owned memory, Go stack storage can move between calls.
	// KeepAlive alone does not keep an exported uintptr pointing at the object.
	var pin runtime.Pinner
	pin.Pin(&api)
	defer pin.Unpin()
	address := uintptr(unsafe.Pointer(&api))

	if got := rimeAPIFunctionAt(address, rimeAPISetCaretPosIndex); got != 0x12345678 {
		t.Fatalf("expected function pointer, got %#x", got)
	}
	growRimeMemoryTestStack(64)
	api.DataSize = int32(unsafe.Offsetof(api.Functions) - unsafe.Sizeof(api.DataSize))
	if got := rimeAPIFunctionAt(address, rimeAPISetCaretPosIndex); got != 0 {
		t.Fatalf("truncated API table must be rejected, got %#x", got)
	}
	api.DataSize = int32(unsafe.Sizeof(api) - unsafe.Sizeof(api.DataSize))
	api.Functions[rimeAPISetCaretPosIndex] = 0x87654321
	if got := rimeAPIFunctionAt(address, rimeAPISetCaretPosIndex); got != 0x87654321 {
		t.Fatalf("restored API table must expose the updated function pointer, got %#x", got)
	}
	runtime.KeepAlive(&api)
}

func TestRimeAPIFunctionAtRejectsInvalidAddressAndIndex(t *testing.T) {
	if got := rimeAPIFunctionAt(0, rimeAPIGetInputIndex); got != 0 {
		t.Fatalf("nil API address must be rejected, got %#x", got)
	}
	api := rimeAPIC{DataSize: -1}
	var pin runtime.Pinner
	pin.Pin(&api)
	defer pin.Unpin()
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
	var pin runtime.Pinner
	pin.Pin(&source[0])
	defer pin.Unpin()
	address := uintptr(unsafe.Pointer(&source[0]))
	if got, ok := cStringAt(address, len(source)); !ok || got != "bjjj" {
		t.Fatalf("unexpected copied string %q ok=%v", got, ok)
	}
	if got, ok := cStringAt(address, 3); ok || got != "" {
		t.Fatalf("unterminated bounded string must be rejected, got %q ok=%v", got, ok)
	}
	growRimeMemoryTestStack(64)
	source[0] = 'x'
	if got, ok := cStringAt(address, len(source)); !ok || got != "xjjj" {
		t.Fatalf("updated external string was not copied after stack growth: %q ok=%v", got, ok)
	}
	runtime.KeepAlive(source)
}
