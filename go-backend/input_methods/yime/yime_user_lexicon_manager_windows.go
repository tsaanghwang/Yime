//go:build windows

package yime

import (
	"os"
)

func (ime *IME) startUserLexiconManagerHelper(mode string) error {
	toolPath := ime.lexiconManagerToolPath()
	if toolPath == "" {
		return os.ErrNotExist
	}
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	if userDir == "" || sharedDir == "" {
		return os.ErrNotExist
	}
	return startDetachedExecutable(
		toolPath,
		"-SharedDir", sharedDir,
		"-UserDir", userDir,
		"-Mode", mode,
	)
}

func (ime *IME) lexiconManagerToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "lexicon-manager.exe")
}
