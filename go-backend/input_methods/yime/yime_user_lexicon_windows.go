//go:build windows

package yime

import (
	"os"
)

func (ime *IME) startUserLexiconAddHelper(mode string) error {
	userDir := ime.userDir()
	sharedDir := ime.sharedDir()
	if userDir == "" || sharedDir == "" {
		return os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	exePath := ime.lexiconManagerToolPath()
	return startDetachedExecutable(exePath, "-SharedDir", sharedDir, "-UserDir", userDir, "-Mode", mode, "-Add")
}
