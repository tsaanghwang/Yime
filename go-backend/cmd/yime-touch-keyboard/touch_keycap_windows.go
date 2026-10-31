//go:build windows && (amd64 || arm64)

package main

import (
	"math"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// Only the rectangular body caps are inset. The board, its hit rectangles and
// the shared CN/EN key identities stay intact; L-shaped keys retain their union.
func touchRaisedKey(k tk.Key) bool {
	return k.Action.Type != "touch-ui" && k.Y >= touchBodyTopU && len(k.Rectangles) == 1
}

type touchKeycap struct {
	base, face, legend rect
	bevel              int32
}

func touchKeycapLayout(bounds rect, unit float64, pressed bool) touchKeycap {
	x := max(int32(2), int32(math.Round(.04*unit)))
	y := max(int32(2), int32(math.Round(.03*unit)))
	depth := max(int32(2), int32(math.Round(.025*unit)))
	base := rect{bounds.L + x, bounds.T + y, bounds.R - x, bounds.B - y}
	face := base
	face.B -= depth
	if pressed {
		face.T += depth
		face.B += depth
	}
	// Leave room around left/right legends in addition to drawKeyLegend's
	// measured-cell padding. This scales with one column, not a wide space key.
	inset := max(int32(2), int32(math.Round(.05*unit)))
	legend := rect{face.L + inset, face.T, face.R - inset, face.B}
	return touchKeycap{base: base, face: face, legend: legend,
		bevel: max(int32(1), int32(math.Round(.012*unit)))}
}

// COLORREF channels are blended independently so both existing palettes keep
// their key colors while gaining distinct lit and shaded edges.
func keycapBlend(c, target uintptr, percent int) uintptr {
	var result uintptr
	for shift := uint(0); shift < 24; shift += 8 {
		channel := (int(c>>shift&255)*(100-percent) + int(target>>shift&255)*percent) / 100
		result |= uintptr(channel) << shift
	}
	return result
}

func drawTouchKeycap(dc uintptr, cap touchKeycap, c uintptr, pressed bool) {
	fill(dc, cap.base, keycapBlend(c, 0, 55))
	fill(dc, cap.face, c)
	light, shade := keycapBlend(c, 0xffffff, 25), keycapBlend(c, 0, 28)
	if pressed {
		light, shade = shade, light
	}
	r, b := cap.face, cap.bevel
	fill(dc, rect{r.L, r.T, r.R, r.T + b}, light)
	fill(dc, rect{r.L, r.T + b, r.L + b, r.B}, light)
	fill(dc, rect{r.R - b, r.T + b, r.R, r.B}, shade)
	fill(dc, rect{r.L + b, r.B - b, r.R, r.B}, shade)
}

func drawTouchKeyLegend(dc uintptr, s string, bounds rect, position int) {
	// DrawText's alignment rectangle can clip glyph overhang (e.g. j or P).
	// Let bearings use the existing padding, but clip to the inset cap itself
	// so a long future label still cannot paint into its neighbor.
	saved, _, _ := G("SaveDC").Call(dc)
	if saved == 0 {
		drawKeyLegend(dc, s, bounds, position)
		return
	}
	defer G("RestoreDC").Call(dc, saved)
	if result, _, _ := G("IntersectClipRect").Call(dc, uintptr(bounds.L), uintptr(bounds.T), uintptr(bounds.R), uintptr(bounds.B)); result == 0 {
		drawKeyLegend(dc, s, bounds, position)
		return
	}
	drawKeyLegendFlags(dc, s, bounds, position, 0x100) // DT_NOCLIP; DC clip remains in force.
}
