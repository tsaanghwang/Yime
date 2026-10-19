//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/binary"
	"testing"
	"unsafe"
)

func TestWin32StructSizes(t *testing.T) {
	if unsafe.Sizeof(input{}) != 40 || unsafe.Sizeof(touch{}) != 48 || unsafe.Sizeof(guiInfo{}) != 72 || unsafe.Sizeof(message{}) != 48 {
		t.Fatal("Windows ABI size mismatch")
	}
}
func TestPartialSendReleasesOnlyInsertedKeysWithoutRepeatingText(t *testing.T) {
	events := []input{keyInput(17, 0, 0), keyInput(18, 0, 0), keyInput(65, 0, 0), keyInput(65, 0, 2), keyInput(18, 0, 2), keyInput(17, 0, 2)}
	for n := 0; n <= len(events); n++ {
		r := cleanupPrefix(events, n)
		want := []int{0, 1, 2, 3, 2, 1, 0}[n]
		if len(r) != want {
			t.Fatalf("prefix %d got %d", n, len(r))
		}
		for _, e := range r {
			if binary.LittleEndian.Uint32(e.Data[4:8])&2 == 0 {
				t.Fatal("replayed key-down")
			}
		}
	}
	r := cleanupPrefix([]input{keyInput(0, 'a', 4), keyInput(0, 'a', 6)}, 1)
	if len(r) != 1 || binary.LittleEndian.Uint32(r[0].Data[4:8]) != 6 {
		t.Fatal("unfinished Unicode packet not released")
	}
}
