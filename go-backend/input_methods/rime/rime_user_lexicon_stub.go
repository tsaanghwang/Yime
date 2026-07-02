//go:build !windows

package rime

type userLexiconEntry struct {
	Phrase string
	Pinyin string
}

func (ime *IME) promptUserLexiconEntry() (userLexiconEntry, bool, error) {
	return userLexiconEntry{}, false, nil
}
