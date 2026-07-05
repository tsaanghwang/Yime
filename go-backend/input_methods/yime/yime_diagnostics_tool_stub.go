//go:build !windows

package yime

func (ime *IME) ensureDiagnosticsToolScript() (string, error) {
	return "", nil
}
