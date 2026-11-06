//go:build !windows || (!amd64 && !arm64)

package main

import "fmt"

func requireNativeArchitecture() error {
	return fmt.Errorf("dedicated broker requires native Windows x64 or ARM64")
}
