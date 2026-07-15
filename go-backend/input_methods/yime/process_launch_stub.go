//go:build !windows

package yime

import "os/exec"

func startDetachedExecutable(filePath string, args ...string) error {
	return exec.Command(filePath, args...).Start()
}
