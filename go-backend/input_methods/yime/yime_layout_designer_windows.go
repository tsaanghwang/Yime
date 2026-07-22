//go:build windows

package yime

import "os"

func (ime *IME) layoutDesignerToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "yime-layout-designer.exe")
}
