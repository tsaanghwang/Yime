//go:build !windows

package yimecore

import "os"

func replaceFileAtomically(source, destination string) error {
	return os.Rename(source, destination)
}
