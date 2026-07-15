//go:build windows

package win32ui

import (
	"testing"
	"unsafe"
)

type messageMemoryFixture struct {
	ID    uintptr
	Code  int32
	Value int32
}

func TestMessageStructRoundTrip(t *testing.T) {
	source := messageMemoryFixture{ID: 42, Code: -101, Value: 7}
	read := ReadMessageStruct[messageMemoryFixture](uintptr(unsafe.Pointer(&source)))
	if read != source {
		t.Fatalf("message structure read mismatch: got %#v want %#v", read, source)
	}

	replacement := messageMemoryFixture{ID: 84, Code: -3, Value: 9}
	WriteMessageStruct(uintptr(unsafe.Pointer(&source)), &replacement)
	if source != replacement {
		t.Fatalf("message structure write mismatch: got %#v want %#v", source, replacement)
	}
}
