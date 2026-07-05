//go:build !windows

package yime

func (ime *IME) ensureStandaloneToolScript(filename, content string) (string, error) {
	return "", nil
}
