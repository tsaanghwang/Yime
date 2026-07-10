//go:build windows

package settings

import (
	"os/exec"
	"syscall"
)

const createNoWindow = 0x08000000

func configureBuildCommand(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: createNoWindow,
	}
}
