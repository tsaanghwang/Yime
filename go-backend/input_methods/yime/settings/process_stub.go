//go:build !windows

package settings

import "os/exec"

func configureBuildCommand(_ *exec.Cmd) {}
