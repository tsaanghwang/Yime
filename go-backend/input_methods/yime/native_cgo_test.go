//go:build windows

package yime

import "testing"

func TestUTF8ByteOffsetToRuneIndex(t *testing.T) {
	const text = "a你😀b"
	tests := []struct {
		offset int
		want   int
	}{
		{0, 0},
		{1, 1},
		{4, 2},
		{8, 3},
		{9, 4},
		{999, 4},
	}
	for _, test := range tests {
		if got := utf8ByteOffsetToRuneIndex(text, test.offset); got != test.want {
			t.Fatalf("offset %d: got %d, want %d", test.offset, got, test.want)
		}
	}
}

func TestNativeBackendKeepsRimeOwnedCandidatePaging(t *testing.T) {
	backend := newNativeBackend()
	pager, ok := backend.(backendCandidatePager)
	if !ok {
		t.Fatalf("native backend must expose candidate paging ownership")
	}
	if !pager.UsesBackendCandidatePaging() {
		t.Fatal("native Rime backend must keep Rime-owned paging; do not move it to Go-side paging")
	}
}
