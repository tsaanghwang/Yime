//go:build windows

package yime

import "os"

func (ime *IME) lexiconPromotionScanToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "lexicon-promotion-scan.exe")
}
