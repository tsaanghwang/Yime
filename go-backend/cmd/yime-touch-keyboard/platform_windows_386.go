//go:build windows && 386

package main

import "errors"

func run(options) error {
	return errors.New("desktop keyboard host targets Windows x64/ARM64; 32-bit target applications are a separate compatibility check")
}
