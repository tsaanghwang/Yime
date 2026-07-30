//go:build !windows

package toolbarstate

import "os"

func replaceFile(tempPath, path string) error {
	return os.Rename(tempPath, path)
}
