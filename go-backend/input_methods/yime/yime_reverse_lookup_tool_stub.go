//go:build !windows

package yime

func (ime *IME) ensureReverseLookupToolScript() (string, error) {
	return "", nil
}
