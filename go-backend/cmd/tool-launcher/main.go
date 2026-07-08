//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var version = "dev"

func main() {
	if len(os.Args) < 3 {
		exitWithError("usage: tool-launcher.exe powershell-script <script-path> [args...]")
	}

	switch os.Args[1] {
	case "powershell-script":
		scriptPath := os.Args[2]
		args := append([]string{
			"-NoProfile",
			"-STA",
			"-WindowStyle",
			"Hidden",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			scriptPath,
		}, os.Args[3:]...)
		if err := shellExecute(windowsPowerShellPath(), joinWindowsProcessArguments(args)); err != nil {
			exitWithError(err.Error())
		}
	default:
		exitWithError("unknown command: " + os.Args[1])
	}
}

func exitWithError(message string) {
	cmd := exec.Command(
		windowsPowerShellPath(),
		"-NoProfile",
		"-STA",
		"-WindowStyle",
		"Hidden",
		"-ExecutionPolicy",
		"Bypass",
		"-Command",
		"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show("+powerShellSingleQuoted(message)+", 'Yime Tool Launcher', 'OK', 'Error') | Out-Null",
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	_ = cmd.Start()
	os.Exit(1)
}

func windowsPowerShellPath() string {
	systemRoot := os.Getenv("SystemRoot")
	if systemRoot != "" {
		candidate := filepath.Join(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return "powershell.exe"
}

func shellExecute(filePath, parameters string) error {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	shellExecuteW := shell32.NewProc("ShellExecuteW")
	verbPtr, err := syscall.UTF16PtrFromString("open")
	if err != nil {
		return err
	}
	filePtr, err := syscall.UTF16PtrFromString(filePath)
	if err != nil {
		return err
	}
	var parametersPtr *uint16
	if parameters != "" {
		parametersPtr, err = syscall.UTF16PtrFromString(parameters)
		if err != nil {
			return err
		}
	}
	result, _, callErr := shellExecuteW.Call(
		0,
		uintptr(unsafe.Pointer(verbPtr)),
		uintptr(unsafe.Pointer(filePtr)),
		uintptr(unsafe.Pointer(parametersPtr)),
		0,
		1,
	)
	if result <= 32 {
		if callErr != syscall.Errno(0) {
			return callErr
		}
		return fmt.Errorf("ShellExecuteW failed with code %d", result)
	}
	return nil
}

func joinWindowsProcessArguments(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, quoteWindowsProcessArgument(arg))
	}
	return strings.Join(quoted, " ")
}

func quoteWindowsProcessArgument(value string) string {
	if value == "" {
		return `""`
	}
	return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
}

func powerShellSingleQuoted(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
