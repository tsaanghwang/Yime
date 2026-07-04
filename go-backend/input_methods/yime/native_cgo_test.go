//go:build windows

package yime

import "testing"

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
