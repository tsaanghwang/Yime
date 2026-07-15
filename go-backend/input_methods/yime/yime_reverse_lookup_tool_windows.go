//go:build windows

package yime

import (
	"os"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func (ime *IME) reverseLookupToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "reverse-lookup.exe")
}

func (ime *IME) openReverseLookupTool() error {
	toolPath := ime.reverseLookupToolPath()
	if toolPath == "" {
		return os.ErrNotExist
	}
	return startDetachedExecutable(
		toolPath,
		"-SharedDir", ime.sharedDir(),
		"-UserDir", ime.userDir(),
		"-Mode", ime.currentYimeMode(),
	)
}

func (ime *IME) warmReverseLookupCache() {
	sharedDir := ime.sharedDir()
	userDir := ime.userDir()
	if sharedDir == "" || userDir == "" {
		return
	}
	reverselookup.WarmCache(sharedDir, userDir, reverselookup.Mode(ime.currentYimeMode()))
}
