//go:build windows

package settings

import (
	"os/exec"
	"testing"
)

func TestConfigureBuildCommandSuppressesConsoleWindow(t *testing.T) {
	cmd := exec.Command("rime_deployer.exe")
	configureBuildCommand(cmd)

	if cmd.SysProcAttr == nil {
		t.Fatal("expected Windows process attributes")
	}
	if !cmd.SysProcAttr.HideWindow {
		t.Fatal("expected deployer window to be hidden")
	}
	if cmd.SysProcAttr.CreationFlags&createNoWindow == 0 {
		t.Fatal("expected CREATE_NO_WINDOW for deployer")
	}
}
