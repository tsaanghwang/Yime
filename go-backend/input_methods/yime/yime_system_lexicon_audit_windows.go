//go:build windows

package yime

import "os"

func (ime *IME) systemLexiconAuditToolPath() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepathJoinExecutableDir(exePath, "system-lexicon-audit.exe")
}
