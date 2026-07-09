//go:build windows

package toolhub

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const shellExecuteOpenVerb = "open"

const (
	swHide       uintptr = 0
	swShowNormal uintptr = 1
)

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

func shellExecute(filePath, parameters string, showCmd uintptr) error {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	shellExecuteW := shell32.NewProc("ShellExecuteW")
	verbPtr, err := syscall.UTF16PtrFromString(shellExecuteOpenVerb)
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
		showCmd,
	)
	if result <= 32 {
		if callErr != syscall.Errno(0) {
			return callErr
		}
		return syscall.Errno(result)
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
