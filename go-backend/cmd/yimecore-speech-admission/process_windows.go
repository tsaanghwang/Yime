//go:build windows

package main

import (
	"os/exec"
	"syscall"
)

func hideChild(command *exec.Cmd) { command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true} }
