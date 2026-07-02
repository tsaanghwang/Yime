//go:build !windows

package rime

func (ime *IME) startUserLexiconAddHelper(mode string) error {
	return nil
}
