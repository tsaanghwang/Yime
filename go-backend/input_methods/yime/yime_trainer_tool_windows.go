//go:build windows

package yime

import "os"

func (ime *IME) openTrainerTool() error {
	toolPath := ime.trainerToolPath()
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

func (ime *IME) trainerToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "yime-trainer.exe")
}
