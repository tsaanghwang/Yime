//go:build !windows

package yime

func (ime *IME) lexiconManagerToolPath() string {
	return ""
}

func (ime *IME) toolHubPath() string {
	return ""
}

func (ime *IME) settingsToolPath() string {
	return ""
}

func (ime *IME) diagnosticsToolPath() string {
	return ""
}
