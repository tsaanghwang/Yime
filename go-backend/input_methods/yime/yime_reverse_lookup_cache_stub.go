//go:build !windows

package yime

import "os"

func (ime *IME) warmReverseLookupCache() {}

func (ime *IME) reverseLookupToolPath() string {
	return ""
}

func (ime *IME) openReverseLookupTool() error {
	return os.ErrNotExist
}
