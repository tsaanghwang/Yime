//go:build windows && (amd64 || arm64)

package main

import "testing"

func TestTouchEllipsisChoicesUseCurrentPointerStampInEnglish(t *testing.T) {
	a := touchUIFixture(t)
	previewAction(t, a.preview, "toggle-language", "", "")
	for i := 0; i < 3; i++ {
		previewAction(t, a.preview, "symbol", "·", "")
	}
	r := a.candidateRect(1)
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(80, x, y)
	previewAction(t, a.preview, "symbol", "·", "")
	a.up(80, x, y)
	if string(a.preview.editor.text) != "" || a.preview.snapshot.PendingMiddleDots != 4 {
		t.Fatal("stale pointer committed")
	}
	// Backspace to exactly three taps, then a fresh candidate click.
	previewAction(t, a.preview, "backspace", "", "")
	a.down(81, x, y)
	a.up(81, x, y)
	a.up(81, x, y)
	if string(a.preview.editor.text) != "⋯" || a.preview.snapshot.PendingMiddleDots != 0 {
		t.Fatal(a.preview.snapshot, a.preview.editor)
	}
	for i := 0; i < 6; i++ {
		previewAction(t, a.preview, "symbol", "·", "")
	}
	r = a.candidateRect(0)
	x, y = (r.L+r.R)/2, (r.T+r.B)/2
	a.down(82, x, y)
	a.up(82, x, y)
	if string(a.preview.editor.text) != "⋯……" || a.preview.snapshot.SymbolChoice {
		t.Fatal(a.preview.snapshot, a.preview.editor)
	}
}
