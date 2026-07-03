//go:build !windows

package rime

import "log"

func (ime *IME) showUserLexiconMessage(title, message, icon string) {
	if message == "" {
		return
	}
	log.Printf("%s: %s", title, message)
}
