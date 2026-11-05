package main

import (
	"strings"
	"unicode"
)

// Keep a remote failure readable on one status line without losing stage codes
// or HRESULTs. The diagnostic never grants a lease or consumes a commit.
func diagnosticDetail(s string) string {
	const limit = 512
	var b strings.Builder
	n := 0
	for _, r := range s {
		if n == limit {
			b.WriteRune('…')
			break
		}
		if unicode.IsControl(r) || unicode.Is(unicode.Cf, r) || unicode.IsSpace(r) {
			r = ' '
		}
		b.WriteRune(r)
		n++
	}
	if detail := strings.TrimSpace(b.String()); detail != "" {
		return detail
	}
	return "未提供具体错误"
}
