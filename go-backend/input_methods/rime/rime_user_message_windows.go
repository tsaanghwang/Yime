//go:build windows

package rime

import (
	"os/exec"
	"strings"
)

func (ime *IME) showUserLexiconMessage(title, message, icon string) {
	if title == "" {
		title = "用户词库"
	}
	if message == "" {
		return
	}
	if icon != "Error" && icon != "Warning" && icon != "Information" {
		icon = "Information"
	}
	script := "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show(" + powerShellSingleQuoted(message) + ", " + powerShellSingleQuoted(title) + ", 'OK', '" + icon + "') | Out-Null"
	cmd := exec.Command("powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", script)
	_ = cmd.Start()
}

func powerShellSingleQuoted(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
