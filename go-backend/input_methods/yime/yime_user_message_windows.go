//go:build windows

package yime

import (
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
	cmd := newUIPowerShellCommand("-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", script)
	_ = cmd.Start()
}

func powerShellSingleQuoted(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
