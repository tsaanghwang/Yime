//go:build !windows

package yime

func (ime *IME) startDiagnosticsToolHelper() error {
	return nil
}

func (ime *IME) diagnosticsToolPath() string {
	return ""
}
