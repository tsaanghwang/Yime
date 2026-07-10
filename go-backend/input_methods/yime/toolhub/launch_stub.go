//go:build !windows

package toolhub

import "fmt"

func shellExecute(filePath, parameters string, showCmd uintptr) error {
	return fmt.Errorf("tool hub launch is only supported on Windows")
}
