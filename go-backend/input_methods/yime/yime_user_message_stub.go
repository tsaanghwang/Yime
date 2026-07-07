//go:build !windows

package yime

import "log"

func (ime *IME) showUserLexiconMessage(title, message, icon string) {
	ime.showUserMessage(title, message, icon)
}

func (ime *IME) showUserMessage(title, message, icon string) {
	if message == "" {
		return
	}
	log.Printf("%s: %s", title, message)
}
