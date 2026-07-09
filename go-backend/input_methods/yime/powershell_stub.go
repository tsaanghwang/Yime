//go:build !windows

package yime

import "os/exec"

func newUIPowerShellCommand(args ...string) *exec.Cmd {
	return exec.Command("powershell", args...)
}

func startDetachedExecutable(filePath string, args ...string) error {
	return exec.Command(filePath, args...).Start()
}
