//go:build windows

package yime

import (
	"os"
	"path/filepath"
)

func (ime *IME) diagnosticsToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "diagnostics-tool.exe")
}

func (ime *IME) startDiagnosticsToolHelper() error {
	toolPath := ime.diagnosticsToolPath()
	if toolPath == "" {
		return os.ErrNotExist
	}
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	helpDir := ime.helpDir()
	if userDir == "" || sharedDir == "" || helpDir == "" {
		return os.ErrNotExist
	}
	return startDetachedExecutable(
		toolPath,
		"-UserDir", userDir,
		"-SharedDir", sharedDir,
		"-HelpDir", helpDir,
		"-LogDir", filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"),
	)
}
