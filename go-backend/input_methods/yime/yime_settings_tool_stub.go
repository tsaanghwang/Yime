//go:build !windows

package yime

func (ime *IME) ensureSettingsToolScript() (string, error) {
	return "", nil
}
