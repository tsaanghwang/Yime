//go:build !windows || (!amd64 && !arm64)

package main

import "fmt"

func requireNativeX64() error { return fmt.Errorf("dedicated broker requires native Windows x64") }
