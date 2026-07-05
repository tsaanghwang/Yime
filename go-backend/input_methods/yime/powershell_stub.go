//go:build !windows

package yime

import "os/exec"

func newUIPowerShellCommand(args ...string) *exec.Cmd {
	return exec.Command("powershell", args...)
}

func startDetachedUIPowerShell(args ...string) error {
	return newUIPowerShellCommand(args...).Start()
}
