//go:build windows

package yime

import "os"

func (ime *IME) trainerToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "yime-trainer.exe")
}
