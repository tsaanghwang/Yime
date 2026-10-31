//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"runtime"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func controlCapPixels(t *testing.T, d *keycapDIB, bounds rect, unit float64, face, background uintptr, pressed bool) {
	t.Helper()
	cap := touchKeycapLayout(bounds, unit, pressed)
	light, shade := keycapBlend(face, 0xffffff, 25), keycapBlend(face, 0, 28)
	if pressed {
		light, shade = shade, light
	}
	mid := (cap.face.L + cap.face.R) / 2
	for _, sample := range []struct {
		x, y int32
		want uintptr
	}{
		{bounds.L, bounds.T, background},
		{cap.base.L - 1, cap.base.T, background},
		{mid, cap.face.T, light},
		{mid, cap.face.B - 1, shade},
		{cap.face.L + cap.bevel, cap.face.T + cap.bevel, face},
	} {
		if got := d.colorAt(sample.x, sample.y); got != sample.want {
			t.Fatalf("cap pixel (%d,%d), pressed=%v: got %#x want %#x", sample.x, sample.y, pressed, got, sample.want)
		}
	}
	if !pressed && d.colorAt(mid, cap.base.B-1) != keycapBlend(face, 0, 55) {
		t.Fatal("unpressed cap lost its lower side wall")
	}
}

func TestTouchControlsRenderRaisedCapsWithOriginalHits(t *testing.T) {
	for _, theme := range []string{"original", "dark"} {
		for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
			t.Run(fmt.Sprintf("%s/ppm%.2f", theme, ppm), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				a.ppm, a.o.Theme = ppm, theme
				a.top = a.touchHeaderLayout().height
				headerFontFixture(t, a)
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				unit := tk.UnitMM * ppm
				d := newKeycapDIB(t, a.previewWidth(), int32(float64(a.top)+unit)+10)
				surface := rect{0, 0, d.width, d.height}
				before, _ := json.Marshal(a.s.Board)
				a.draw(d.dc, surface)
				palette := a.palette()
				controls, spares := 0, 0
				for i, k := range a.s.Board.Keys {
					if k.Action.Type != "touch-ui" {
						continue
					}
					controls++
					if !touchRaisedKey(k) || k.Width != 1 || k.Height != touchBodyHeightScale || len(k.Rectangles) != 1 {
						t.Fatal("control cap changed its equal-sized physical target", k.ID)
					}
					bounds := a.keyPixelRect(k)
					face := palette.keyColor(k.Color, true)
					if k.Action.Key == "reserved" {
						spares++
						face = palette.disabled
					}
					controlCapPixels(t, d, bounds, unit, face, palette.background, false)
					// Every original edge remains actionable, including the visible gap.
					for _, xy := range [][2]float64{{k.X + .001, k.Y + k.Height/2}, {k.X + k.Width - .001, k.Y + k.Height/2}, {k.X + k.Width/2, k.Y + .001}, {k.X + k.Width/2, k.Y + k.Height - .001}} {
						if got := a.s.Hit(xy[0], xy[1]); got != i {
							t.Fatalf("control %s lost original edge hit: %d", k.ID, got)
						}
					}
					if k.Action.Key != "reserved" {
						// Draw a held gesture without executing settings, close or host actions.
						a.previewTouches[901] = &previewGesture{area: bounds, action: k.Action.Key}
						a.draw(d.dc, surface)
						controlCapPixels(t, d, bounds, unit, palette.pressed, palette.background, true)
						delete(a.previewTouches, 901)
						a.draw(d.dc, surface)
					}
				}
				after, _ := json.Marshal(a.s.Board)
				if controls != 18 || spares != 3 || string(before) != string(after) {
					t.Fatal("drawing changed the control inventory or board geometry")
				}

				// The three grey caps stay inert even with a selection and live candidates.
				a.preview.editor.insert("a𠀀bc")
				a.preview.editor.anchor, a.preview.editor.cursor = 1, 3
				a.navSelecting = true
				previewAction(t, a.preview, "input", "p", "")
				before, _ = json.Marshal(a.preview.snapshot)
				sequence := a.preview.sequence
				clicks := countKeyClicks(a, true)
				for n := 1; n <= 3; n++ {
					box := touchToolbarKeyRect(t, a, fmt.Sprintf("TU-SPARE-%d", n))
					x, y := box.L+1, box.B-1
					a.down(uint32(n), x, y)
					a.draw(d.dc, surface)
					controlCapPixels(t, d, box, unit, palette.disabled, palette.background, false)
					a.up(uint32(n), x, y)
					a.up(uint32(n), x, y)
				}
				after, _ = json.Marshal(a.preview.snapshot)
				if string(before) != string(after) || a.preview.sequence != sequence || *clicks != 0 || len(a.previewTouches) != 0 || !a.navSelecting || a.preview.editor.anchor != 1 || a.preview.editor.cursor != 3 || string(a.preview.editor.text) != "a𠀀bc" {
					t.Fatal("raised reserved cap dispatched input, sounded or changed selection/candidates")
				}
			})
		}
	}
}

func TestTouchControlLegendsRemainCompleteAtAllFontSizes(t *testing.T) {
	for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
		for level := 0; level < 3; level++ {
			t.Run(fmt.Sprintf("ppm%.2f/font%d", ppm, level), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				a.ppm, a.touchFontLevel = ppm, level
				headerFontFixture(t, a)
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				d := newKeycapDIB(t, 384, 300)
				old, _, _ := G("SelectObject").Call(d.dc, a.keyFont)
				t.Cleanup(func() { G("SelectObject").Call(d.dc, old) })
				G("SetTextColor").Call(d.dc, 0)
				G("SetBkMode").Call(d.dc, 1)
				labels := map[string]bool{"返回": true, "EN": true, "选区：开": true, "绑定": true}
				for _, k := range a.s.Board.Keys {
					if k.Action.Type != "touch-ui" {
						continue
					}
					for _, s := range a.touchLabels(k, a.s.View(k).Labels) {
						if s = label(s); s != "" {
							labels[s] = true
						}
					}
				}
				if !labels["选区：关"] {
					t.Fatal("missing four-character control caption coverage")
				}
				unit := tk.UnitMM * ppm
				bounds := rect{20, 20, 20 + int32(unit), 20 + int32(touchBodyHeightScale*unit)}
				for s := range labels {
					d.clear()
					text(d.dc, s, rect{10, 10, d.width - 10, d.height - 10}, 0x120)
					complete := d.ink()
					for _, pressed := range []bool{false, true} {
						cap := touchKeycapLayout(bounds, unit, pressed)
						d.clear()
						drawTouchKeyLegend(d.dc, s, cap.face, 4)
						actual := d.ink()
						if complete.count == 0 || actual.count != complete.count || actual.bounds.R-actual.bounds.L != complete.bounds.R-complete.bounds.L || actual.bounds.B-actual.bounds.T != complete.bounds.B-complete.bounds.T || !keycapContains(cap.face, actual.bounds) {
							t.Fatalf("control caption %q clipped, pressed=%v: actual=%+v complete=%+v", s, pressed, actual, complete)
						}
					}
				}
			})
		}
	}
}

func TestTouchRaisedPagersRenderStateAndKeepEdgeGestures(t *testing.T) {
	for _, theme := range []string{"original", "dark"} {
		for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
			t.Run(fmt.Sprintf("%s/ppm%.2f", theme, ppm), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				a.ppm, a.o.Theme = ppm, theme
				header := a.touchHeaderLayout()
				a.top = header.height
				headerFontFixture(t, a)
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				d := newKeycapDIB(t, a.previewWidth(), int32(a.top)+1)
				surface := rect{0, 0, d.width, d.height}
				unit, palette := tk.UnitMM*ppm, a.palette()
				previewAction(t, a.preview, "input", "p", "")
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.next, unit, palette.panel, palette.background, false)
				controlCapPixels(t, d, header.previous, unit, palette.panel, palette.background, false)
				// Save the enabled arrow's actual ink to distinguish the disabled foreground.
				G("GdiFlush").Call()
				normal := append([]uint32(nil), d.pixels...)
				a.previewTouches[99] = &previewGesture{area: header.previous, action: "previous"}
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.previous, unit, palette.panel, palette.background, false)
				delete(a.previewTouches, 99)

				candidate := a.candidateRect(0)
				cx, cy := (candidate.L+candidate.R)/2, (candidate.T+candidate.B)/2
				a.down(100, cx, cy)
				nx, ny := header.next.L+1, header.next.B-1
				a.down(101, nx, ny)
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.next, unit, palette.pressed, palette.background, true)
				if a.preview.snapshot.State.PageNumber != 0 {
					t.Fatal("pager committed on pointer down")
				}
				a.up(101, nx, ny)
				a.up(101, nx, ny)
				a.up(100, cx, cy)
				if a.preview.snapshot.State.PageNumber != 1 || a.preview.snapshot.State.HasNext || len(a.preview.editor.text) != 0 {
					t.Fatal("pager edge did not page once or allowed a stale candidate commit")
				}
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.next, unit, palette.panel, palette.background, false)
				changed := 0
				for y := header.next.T; y < header.next.B; y++ {
					for x := header.next.L; x < header.next.R; x++ {
						if d.pixels[y*d.width+x] != normal[y*d.width+x] {
							changed++
						}
					}
				}
				if changed == 0 {
					t.Fatal("disabled pager retained the enabled arrow foreground")
				}
				a.down(102, nx, ny)
				a.up(102, nx, ny)
				px, py := header.previous.R-1, header.previous.B-1
				a.down(103, px, py)
				a.move(103, header.previous.R, py)
				a.move(103, px, py)
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.previous, unit, palette.panel, palette.background, false)
				a.up(103, px, py)
				if a.preview.snapshot.State.PageNumber != 1 {
					t.Fatal("disabled pager or moved-out/back gesture changed the page")
				}
				a.down(104, px, py)
				a.draw(d.dc, surface)
				controlCapPixels(t, d, header.previous, unit, palette.pressed, palette.background, true)
				a.up(104, px, py)
				a.up(104, px, py)
				if a.preview.snapshot.State.PageNumber != 0 || a.preview.snapshot.State.RawInput != "p" || len(a.preview.editor.text) != 0 || len(a.previewTouches) != 0 || a.touchHeaderLayout() != header {
					t.Fatal("raised pagers changed hit geometry or existing gesture semantics")
				}
			})
		}
	}
}
