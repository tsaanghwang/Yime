//go:build !windows || (!amd64 && !arm64)

package main

import "testing"

func TestUnsupportedNativeArchitecture(t *testing.T) {
	if err := requireNativeArchitecture(); err == nil {
		t.Fatal("unsupported native gate accepted")
	}
}
