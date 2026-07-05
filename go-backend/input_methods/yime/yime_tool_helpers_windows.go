//go:build windows

package yime

import (
	"os"
	"path/filepath"
)

func (ime *IME) ensureStandaloneToolScript(filename, content string) (string, error) {
	userDir := ime.userDir()
	if userDir == "" {
		return "", os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	scriptPath := filepath.Join(userDir, filename)
	scriptContent := append([]byte{0xEF, 0xBB, 0xBF}, []byte(content)...)
	if err := os.WriteFile(scriptPath, scriptContent, 0o644); err != nil {
		return "", err
	}
	return scriptPath, nil
}
