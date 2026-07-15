//go:build !windows

package yime

func (ime *IME) startSettingsToolHelper() error {
	return nil
}

func (ime *IME) settingsToolPath() string {
	return ""
}
