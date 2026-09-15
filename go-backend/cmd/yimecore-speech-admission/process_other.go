//go:build !windows

package main

import "os/exec"

func hideChild(command *exec.Cmd) {}
