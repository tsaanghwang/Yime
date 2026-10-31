//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"runtime"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func shapedKeycapTestParts(k tk.Key, unit float64) []rect {
	left, top := math.Inf(1), math.Inf(1)
	for _, q := range k.Rectangles {
		left, top = math.Min(left, q.X), math.Min(top, q.Y)
	}
	var parts []rect
	for _, q := range k.Rectangles {
		parts = append(parts, rect{20 + int32((q.X-left)*unit), 20 + int32((q.Y-top)*unit), 20 + int32((q.X-left+q.Width)*unit), 20 + int32((q.Y-top+q.Height)*unit)})
	}
	return parts
}

func inShapedKeycapParts(parts []rect, x, y int32) bool {
	for _, part := range parts {
		if inside(part, x, y) {
			return true
		}
	}
	return false
}

func TestTouchShapedKeycapKeepsPhysicalGeometryAndHits(t *testing.T) {
	a := touchUIFixture(t)
	before, _ := json.Marshal(a.s.Board)
	shaped := 0
	for i, k := range a.s.Board.Keys {
		if len(k.Rectangles) != 2 {
			continue
		}
		shaped++
		for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
			unit := tk.UnitMM * ppm
			parts := shapedKeycapTestParts(k, unit)
			originalParts := append([]rect(nil), parts...)
			up := touchShapedKeycapLayout(parts, unit, false)
			down := touchShapedKeycapLayout(parts, unit, true)
			if !reflect.DeepEqual(parts, originalParts) || !reflect.DeepEqual(up.base, down.base) {
				t.Fatal("L keycap layout changed source rectangles or physical footprint", k.ID)
			}
			if down.legend.T <= up.legend.T || down.legend.B-up.legend.B != down.legend.T-up.legend.T || down.legend.R-down.legend.L != up.legend.R-up.legend.L {
				t.Fatal("pressed L key should translate its face and label without resizing", k.ID)
			}
			for _, cap := range []touchShapedKeycap{up, down} {
				contained := false
				for _, face := range cap.face {
					contained = contained || keycapContains(face, cap.legend)
				}
				if !contained {
					t.Fatal("L label bounds cross the concave notch", k.ID)
				}
			}
		}
		for _, q := range k.Rectangles {
			for _, p := range [][2]float64{{q.X + .001, q.Y + q.Height/2}, {q.X + q.Width - .001, q.Y + q.Height/2}, {q.X + q.Width/2, q.Y + .001}, {q.X + q.Width/2, q.Y + q.Height - .001}} {
				if a.s.Hit(k.X+p[0], k.Y+p[1]) != i {
					t.Fatal("L visual inset changed a physical edge hit", k.ID)
				}
			}
		}
	}
	after, _ := json.Marshal(a.s.Board)
	if shaped != 2 || string(before) != string(after) {
		t.Fatal("L visual treatment changed board inventory or source geometry")
	}
}

func TestTouchShapedKeycapDrawsOneContinuousContour(t *testing.T) {
	for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
		for _, theme := range []string{"original", "dark"} {
			t.Run(fmt.Sprintf("ppm%.2f/%s", ppm, theme), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				a.o.Theme = theme
				d := newKeycapDIB(t, 440, 400)
				unit := tk.UnitMM * ppm
				for _, k := range a.s.Board.Keys {
					if len(k.Rectangles) != 2 {
						continue
					}
					parts := shapedKeycapTestParts(k, unit)
					c := a.palette().keyColor(k.Color, true)
					for _, pressed := range []bool{false, true} {
						cap := touchShapedKeycapLayout(parts, unit, pressed)
						d.clear()
						drawTouchShapedKeycap(d.dc, cap, c, pressed)
						G("GdiFlush").Call()
						ink, interior, light, shade, wall := 0, 0, 0, 0, 0
						for y := int32(0); y < d.height; y++ {
							for x := int32(0); x < d.width; x++ {
								pixel := d.pixels[y*d.width+x]
								color := uintptr(pixel&0xff)<<16 | uintptr(pixel&0xff00) | uintptr(pixel>>16&0xff)
								if color == 0xffffff {
									if inShapedKeycapParts(cap.base, x, y) {
										t.Fatalf("%s has an unpainted hole or seam at %d,%d", k.ID, x, y)
									}
									continue
								}
								ink++
								if !inShapedKeycapParts(parts, x, y) || !inShapedKeycapParts(cap.base, x, y) {
									t.Fatalf("%s paints into a gap or its notch at %d,%d", k.ID, x, y)
								}
								if color == keycapBlend(c, 0xffffff, 25) {
									light++
								}
								if color == keycapBlend(c, 0, 28) {
									shade++
								}
								if !inShapedKeycapParts(cap.face, x, y) {
									wall++
									if color != keycapBlend(c, 0, 55) {
										t.Fatal("L side wall does not match rectangular keys", k.ID)
									}
									continue
								}
								// Far from the union's perimeter, even the overlap and
								// old rectangle boundaries must be uninterrupted face.
								b := cap.bevel
								if inShapedKeycapParts(cap.face, x-b, y-b) && inShapedKeycapParts(cap.face, x+b, y-b) && inShapedKeycapParts(cap.face, x-b, y+b) && inShapedKeycapParts(cap.face, x+b, y+b) {
									interior++
									if color != c {
										t.Fatalf("%s has an internal seam at %d,%d pressed=%v", k.ID, x, y, pressed)
									}
								}
							}
						}
						if ink == 0 || interior == 0 || light == 0 || shade == 0 || (!pressed && wall == 0) {
							t.Fatalf("incomplete L rendering %s pressed=%v: ink=%d interior=%d light=%d shade=%d wall=%d", k.ID, pressed, ink, interior, light, shade, wall)
						}
					}
				}
			})
		}
	}
}

func TestTouchShapedKeycapLabelsFitInsideFoot(t *testing.T) {
	for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
		for level := 0; level < 3; level++ {
			t.Run(fmt.Sprintf("ppm%.2f/font%d", ppm, level), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				d := newKeycapDIB(t, 440, 400)
				height := int32(-18)
				a.font, _, _ = G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
				if a.font == 0 {
					t.Fatal("create shaped keycap font")
				}
				var old uintptr
				t.Cleanup(func() {
					if old != 0 {
						G("SelectObject").Call(d.dc, old)
					}
					for _, f := range []uintptr{a.font, a.keyFont, a.glyphFont, a.candidateFont, a.touchFont} {
						if f != 0 {
							G("DeleteObject").Call(f)
						}
					}
				})
				a.ppm, a.touchFontLevel = ppm, level
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				old, _, _ = G("SelectObject").Call(d.dc, a.keyFont)
				G("SetTextColor").Call(d.dc, 0)
				G("SetBkMode").Call(d.dc, 1)
				labels := 0
				for _, original := range []bool{true, false} {
					a.s.Original = original
					for _, k := range a.s.Board.Keys {
						if len(k.Rectangles) != 2 {
							continue
						}
						for _, pressed := range []bool{false, true} {
							cap := touchShapedKeycapLayout(shapedKeycapTestParts(k, tk.UnitMM*ppm), tk.UnitMM*ppm, pressed)
							for pos, raw := range a.s.View(k).Labels {
								s := label(raw)
								if s == "" {
									continue
								}
								d.clear()
								text(d.dc, s, rect{10, 10, d.width - 10, d.height - 10}, 0x120)
								complete := d.ink()
								d.clear()
								drawTouchKeyLegend(d.dc, s, cap.legend, pos)
								actual := d.ink()
								if actual.count == 0 || actual.count != complete.count || actual.bounds.R-actual.bounds.L != complete.bounds.R-complete.bounds.L || actual.bounds.B-actual.bounds.T != complete.bounds.B-complete.bounds.T || !keycapContains(cap.legend, actual.bounds) {
									t.Fatalf("%s label %q clipped or crossed its foot: actual=%+v complete=%+v", k.ID, s, actual, complete)
								}
								labels++
							}
						}
					}
				}
				if labels != 8 {
					t.Fatalf("did not exercise both L labels in CN/EN and pressed/up states: %d", labels)
				}
			})
		}
	}
}
