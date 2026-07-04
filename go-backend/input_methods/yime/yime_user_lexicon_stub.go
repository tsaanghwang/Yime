//go:build !windows

package yime

func (ime *IME) startUserLexiconAddHelper(mode string) error {
	return nil
}

func (ime *IME) startUserLexiconManagerHelper(mode string) error {
	return nil
}
