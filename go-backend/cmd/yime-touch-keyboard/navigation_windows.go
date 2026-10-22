//go:build windows && (amd64 || arm64)

package main

// Auxiliary controls occupy the right of the existing output strip. They do
// not enter Board.Keys, change key identities, or move/scale the 18u board.
var navigationButtons = []toolButton{
	{0, 70, "ArrowLeft", "← 左"}, {75, 145, "ArrowRight", "右 →"},
	{150, 230, "Home", "Home"}, {235, 315, "End", "End"},
	{320, 430, "select", "选区：关"},
}

func (a *ui) navigationRect(b toolButton) rect {
	x := a.previewWidth() - 440
	return rect{x + b.l, 240, x + b.r, 290}
}

func (a *ui) navigationAt(x, y int32) (string, rect) {
	for _, b := range navigationButtons {
		r := a.navigationRect(b)
		if inside(r, x, y) {
			return b.action, r
		}
	}
	return "", rect{}
}

func (a *ui) navigationPending() bool {
	for _, g := range a.previewTouches {
		if g.navigation != "" {
			return true
		}
	}
	return false
}

func (a *ui) drawNavigation(dc uintptr) {
	for _, b := range navigationButtons {
		label, color := b.label, uintptr(0xE5EBE2)
		if b.action == "select" && a.navSelecting {
			label, color = "选区：开", 0xB3DDC5
		}
		if !a.preview.navigationEnabled() {
			color = 0xDDDDDD
		}
		r := a.navigationRect(b)
		fill(dc, r, color)
		text(dc, label, r, 0x25)
	}
}
