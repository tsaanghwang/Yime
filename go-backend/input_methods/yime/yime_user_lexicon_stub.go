//go:build !windows

package yime

func (ime *IME) startUserLexiconAddHelper(mode string) error {
	return nil
}
