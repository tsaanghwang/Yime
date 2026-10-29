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
	if a.o.TouchUI {
		action, area := a.touchControlAt(x, y)
		if touchNavigation(action) {
			return action, area
		}
		return "", rect{}
	}
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
	palette := a.palette()
	for _, b := range navigationButtons {
		label, color := b.label, palette.panel
		if b.action == "select" && a.navSelecting {
			label, color = "选区：开", palette.active
		}
		if !a.preview.navigationEnabled() {
			color = palette.disabled
		}
		r := a.navigationRect(b)
		fill(dc, r, color)
		text(dc, label, r, 0x25)
	}
}
