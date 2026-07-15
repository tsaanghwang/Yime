//go:build windows

package yime

import "os"

func (ime *IME) blocklistManagerToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "blocklist-manager.exe")
}
