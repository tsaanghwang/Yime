//go:build windows

package win32ui

import (
	"fmt"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

// StartDetachedGUIExecutable launches a GUI tool with an explicit SW_SHOWNORMAL startup.
func StartDetachedGUIExecutable(exePath string, args ...string) error {
	AllowNextForegroundWindow()

	exePath = strings.TrimSpace(exePath)
	if exePath == "" {
		return fmt.Errorf("executable path is empty")
	}

	var cmdLine string
	if len(args) == 0 {
		cmdLine = quoteWindowsArgument(exePath)
	} else {
		quoted := make([]string, 0, len(args)+1)
		quoted = append(quoted, quoteWindowsArgument(exePath))
		for _, arg := range args {
			quoted = append(quoted, quoteWindowsArgument(arg))
		}
		cmdLine = strings.Join(quoted, " ")
	}

	cmdLineUTF16, err := syscall.UTF16FromString(cmdLine)
	if err != nil {
		return err
	}
	cmdLineBuf := make([]uint16, len(cmdLineUTF16))
	copy(cmdLineBuf, cmdLineUTF16)

	si := &syscall.StartupInfo{}
	si.Cb = uint32(unsafe.Sizeof(*si))
	si.Flags = syscall.STARTF_USESHOWWINDOW
	si.ShowWindow = syscall.SW_SHOWNORMAL

	pi := &syscall.ProcessInformation{}
	exeDir, _ := syscall.UTF16PtrFromString(filepath.Dir(exePath))

	if err := syscall.CreateProcess(
		nil,
		&cmdLineBuf[0],
		nil,
		nil,
		false,
		0,
		nil,
		exeDir,
		si,
		pi,
	); err != nil {
		return err
	}

	_ = syscall.CloseHandle(pi.Thread)
	_ = syscall.CloseHandle(pi.Process)
	return nil
}

func quoteWindowsArgument(value string) string {
	if value == "" {
		return `""`
	}
	if strings.ContainsAny(value, " \t\"") {
		return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
	}
	return value
}
