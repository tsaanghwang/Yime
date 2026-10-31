//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"math"
	"path/filepath"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// A top-down 32-bit DIB lets the tests inspect actual GDI output without a
// window, screen capture, or thousands of GetPixel calls.
type keycapDIB struct {
	dc            uintptr
	width, height int32
	pixels        []uint32
}

func newKeycapDIB(t *testing.T, width, height int32) *keycapDIB {
	t.Helper()
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	if dc == 0 {
		t.Fatal("create keycap memory DC")
	}
	var info struct {
		size                   uint32
		width, height          int32
		planes, bitCount       uint16
		compression, sizeImage uint32
		xPelsPerMeter          int32
		yPelsPerMeter          int32
		colorsUsed, important  uint32
	}
	info.size, info.width, info.height = uint32(unsafe.Sizeof(info)), width, -height
	info.planes, info.bitCount = 1, 32
	var bits unsafe.Pointer
	bitmap, _, _ := G("CreateDIBSection").Call(dc, uintptr(unsafe.Pointer(&info)), 0, uintptr(unsafe.Pointer(&bits)), 0, 0)
	if bitmap == 0 || bits == nil {
		G("DeleteDC").Call(dc)
		t.Fatal("create keycap DIB")
	}
	old, _, _ := G("SelectObject").Call(dc, bitmap)
	t.Cleanup(func() {
		G("SelectObject").Call(dc, old)
		G("DeleteObject").Call(bitmap)
		G("DeleteDC").Call(dc)
	})
	return &keycapDIB{dc: dc, width: width, height: height, pixels: unsafe.Slice((*uint32)(bits), int(width*height))}
}

func (d *keycapDIB) clear() {
	fill(d.dc, rect{0, 0, d.width, d.height}, 0xffffff)
}

// DIB pixels are RGB integers, while the drawing helpers take COLORREF BGR.
func (d *keycapDIB) colorAt(x, y int32) uintptr {
	G("GdiFlush").Call()
	v := d.pixels[y*d.width+x]
	return uintptr(v&0xff)<<16 | uintptr(v&0xff00) | uintptr(v>>16&0xff)
}

type keycapInk struct {
	bounds rect
	count  int
}

func (d *keycapDIB) ink() keycapInk {
	G("GdiFlush").Call()
	result := keycapInk{bounds: rect{d.width, d.height, 0, 0}}
	for y := int32(0); y < d.height; y++ {
		for x := int32(0); x < d.width; x++ {
			if d.pixels[y*d.width+x]&0xffffff == 0xffffff {
				continue
			}
			result.count++
			result.bounds.L = min(result.bounds.L, x)
			result.bounds.T = min(result.bounds.T, y)
			result.bounds.R = max(result.bounds.R, x+1)
			result.bounds.B = max(result.bounds.B, y+1)
		}
	}
	return result
}

func keycapContains(outer, inner rect) bool {
	return inner.L >= outer.L && inner.T >= outer.T && inner.R <= outer.R && inner.B <= outer.B
}

func TestTouchKeycapPreservesBoardAndEdgeHitTargets(t *testing.T) {
	a := touchUIFixture(t)
	before, _ := json.Marshal(a.s.Board)
	raised, shaped, controls := 0, 0, 0
	for i, k := range a.s.Board.Keys {
		if !touchRaisedKey(k) {
			if k.Action.Type == "touch-ui" {
				controls++
			} else {
				shaped++
				if len(k.Rectangles) != 2 || (k.Action.Key != "Tab" && k.Action.Type != "backspace") {
					t.Fatalf("unexpected unraised body key: %s", k.ID)
				}
			}
			continue
		}
		raised++
		q := k.Rectangles[0]
		for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
			unit := tk.UnitMM * ppm
			bounds := rect{20, 20, 20 + int32(q.Width*unit), 20 + int32(q.Height*unit)}
			up := touchKeycapLayout(bounds, unit, false)
			down := touchKeycapLayout(bounds, unit, true)
			if !keycapContains(bounds, up.base) || !keycapContains(up.base, up.face) || !keycapContains(up.face, up.legend) || !keycapContains(down.base, down.face) || !keycapContains(down.face, down.legend) {
				t.Fatalf("keycap escapes physical key %s at %.2f ppm", k.ID, ppm)
			}
			if up.base != down.base || down.face.T <= up.face.T || down.face.B-up.face.B != down.face.T-up.face.T || up.legend.R-up.legend.L != down.legend.R-down.legend.L {
				t.Fatalf("press changes cap size instead of depressing it: %s", k.ID)
			}
		}
		// These points fall in the new visual margin, but remain legitimate
		// touches in the original physical key, including after a redraw.
		for _, p := range [][2]float64{{q.X + .001, q.Y + q.Height/2}, {q.X + q.Width - .001, q.Y + q.Height/2}, {q.X + q.Width/2, q.Y + .001}, {q.X + q.Width/2, q.Y + q.Height - .001}} {
			if got := a.s.Hit(k.X+p[0], k.Y+p[1]); got != i {
				t.Fatalf("visual inset lost edge hit for %s: %d", k.ID, got)
			}
		}
	}
	after, _ := json.Marshal(a.s.Board)
	if raised != 82 || shaped != 2 || controls != 18 || string(before) != string(after) {
		t.Fatalf("visual treatment changed inventory or geometry: %d rectangular, %d shaped, %d controls", raised, shaped, controls)
	}
}

func TestTouchKeycapDrawHasGapBevelAndPressedDepth(t *testing.T) {
	for _, theme := range []string{"original", "dark"} {
		t.Run(theme, func(t *testing.T) {
			runtime.LockOSThread()
			t.Cleanup(runtime.UnlockOSThread)
			d := newKeycapDIB(t, 300, 240)
			a := &ui{o: options{Theme: theme}}
			c := a.palette().keyColor("#d8e8bc", false)
			bounds := rect{30, 30, 230, 190}
			for _, pressed := range []bool{false, true} {
				cap := touchKeycapLayout(bounds, 200, pressed)
				d.clear()
				drawTouchKeycap(d.dc, cap, c, pressed)
				if d.colorAt(bounds.L, bounds.T) != 0xffffff || d.colorAt(cap.base.L-1, cap.base.T) != 0xffffff || d.colorAt(cap.base.R, cap.base.B-1) != 0xffffff {
					t.Fatal("keycap paints over the visual gap")
				}
				midX, midY := (cap.face.L+cap.face.R)/2, (cap.face.T+cap.face.B)/2
				if d.colorAt(midX, midY) != c {
					t.Fatal("bevel changes the established face color")
				}
				lit := d.colorAt(midX, cap.face.T)
				shade := d.colorAt(midX, cap.face.B-1)
				if lit == c || shade == c || lit == shade || (!pressed && lit <= shade) || (pressed && lit >= shade) {
					t.Fatalf("missing or reversed key depth: pressed=%v, upper=%x lower=%x", pressed, lit, shade)
				}
				if !pressed && d.colorAt(midX, cap.base.B-1) == c {
					t.Fatal("unpressed key has no lower side wall")
				}
			}
		})
	}
}

func TestTouchKeycapLegendsKeepCompleteGlyphsAndSeparation(t *testing.T) {
	for _, ppm := range []float64{3, 3840.0 / 597.73 * 100 / 58} {
		for level := 0; level < 3; level++ {
			t.Run(fmt.Sprintf("ppm%.2f/font%d", ppm, level), func(t *testing.T) {
				runtime.LockOSThread()
				t.Cleanup(runtime.UnlockOSThread)
				a := touchUIFixture(t)
				d := newKeycapDIB(t, 384, 300)
				root, err := filepath.Abs("../../..")
				if err != nil {
					t.Fatal(err)
				}
				glyphs, err := loadPreviewGlyphs(root)
				if err != nil {
					t.Fatal(err)
				}
				fontPath := filepath.Join(root, "go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf")
				if n, _, _ := G("AddFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0); n == 0 {
					t.Fatal("load private keycap font")
				}
				t.Cleanup(func() { G("RemoveFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0) })
				height := int32(-18)
				a.font, _, _ = G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
				if a.font == 0 {
					t.Fatal("create keycap base font")
				}
				a.ppm, a.touchFontLevel = ppm, level
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				old, _, _ := G("SelectObject").Call(d.dc, a.keyFont)
				t.Cleanup(func() {
					G("SelectObject").Call(d.dc, old)
					for _, f := range []uintptr{a.font, a.keyFont, a.glyphFont, a.candidateFont, a.touchFont} {
						G("DeleteObject").Call(f)
					}
				})
				G("SetTextColor").Call(d.dc, 0)
				G("SetBkMode").Call(d.dc, 1)
				unit := tk.UnitMM * ppm
				nonemptyGlyphs, nonemptyIDs := 0, 0
				for _, original := range []bool{true, false} {
					a.s.Original = original
					for _, showGlyphs := range []bool{false, true} {
						for _, k := range a.s.Board.Keys {
							if !touchRaisedKey(k) || (k.Action.Type != "input" && k.Action.Type != "symbol") {
								continue
							}
							view := a.s.View(k)
							if view.Disabled {
								continue
							}
							q := k.Rectangles[0]
							bounds := rect{20, 20, 20 + int32(q.Width*unit), 20 + int32(q.Height*unit)}
							for _, pressed := range []bool{false, true} {
								cap := touchKeycapLayout(bounds, unit, pressed)
								var occupied []rect
								for pos, raw := range view.Labels {
									s := label(raw)
									if s == "" {
										continue
									}
									font := a.keyFont
									glyph, hasGlyph := glyphs[s]
									if hasGlyph && showGlyphs {
										s, font = glyph, a.glyphFont
									}
									G("SelectObject").Call(d.dc, font)
									d.clear()
									// Include negative side bearings in the complete reference.
									// A nominal text rectangle would clip the left edge of j.
									text(d.dc, s, rect{10, 10, d.width - 10, d.height - 10}, 0x120)
									complete := d.ink()
									d.clear()
									drawTouchKeyLegend(d.dc, s, cap.legend, pos)
									actual := d.ink()
									// Some existing private-font slots have no ink.
									// Preserve that reference rather than judging
									// an empty rectangle as a clipped or spilling glyph.
									if complete.count == 0 {
										if actual.count != 0 {
											t.Fatalf("empty reference %s legend %q gained ink", k.ID, raw)
										}
										continue
									}
									if actual.count == 0 || actual.count != complete.count || actual.bounds.R-actual.bounds.L != complete.bounds.R-complete.bounds.L || actual.bounds.B-actual.bounds.T != complete.bounds.B-complete.bounds.T {
										t.Fatalf("clipped %s legend %q position %d CN=%v glyphs=%v pressed=%v: actual=%+v complete=%+v", k.ID, raw, pos, original, showGlyphs, pressed, actual, complete)
									}
									if hasGlyph {
										if showGlyphs {
											nonemptyGlyphs++
										} else {
											nonemptyIDs++
										}
									}
									if !keycapContains(cap.legend, actual.bounds) {
										t.Fatalf("%s legend %q crosses inset bounds: %+v, cap=%+v", k.ID, raw, actual.bounds, cap.legend)
									}
									for _, previous := range occupied {
										if actual.bounds.L < previous.R && previous.L < actual.bounds.R && actual.bounds.T < previous.B && previous.T < actual.bounds.B {
											t.Fatalf("%s legend %q overlaps another corner CN=%v glyphs=%v pressed=%v", k.ID, raw, original, showGlyphs, pressed)
										}
									}
									occupied = append(occupied, actual.bounds)
									if pos%3 == 0 && actual.bounds.L <= bounds.L+int32(math.Round(.05*unit)) {
										t.Fatalf("%s left legend lost the enlarged side margin", k.ID)
									}
									if pos%3 == 2 && actual.bounds.R >= bounds.R-int32(math.Round(.05*unit)) {
										t.Fatalf("%s right legend lost the enlarged side margin", k.ID)
									}
								}
							}
						}
					}
				}
				if nonemptyGlyphs == 0 || nonemptyIDs == 0 {
					t.Fatalf("legend coverage produced no visible glyphs/IDs: glyphs=%d IDs=%d", nonemptyGlyphs, nonemptyIDs)
				}
			})
		}
	}
}

func TestTouchKeycapDoesNotChangeClassicRendering(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	d := newKeycapDIB(t, 300, 300)
	k := tk.Key{ID: "classic", X: 0, Y: 2, Width: 1, Height: 1, Color: "#d8e8bc", Rectangles: []tk.Rect{{Width: 1, Height: 1}}, Action: tk.Action{Type: "input", ASCII: "a"}}
	if !touchRaisedKey(k) {
		t.Fatal("fixture would not exercise the touch-only guard")
	}
	b := tk.Board{Keys: []tk.Key{k}}
	a := &ui{s: tk.NewState(b), ppm: 3, border: 20, top: 110}
	a.s.Original = true
	a.draw(d.dc, rect{0, 0, 300, 300})
	left, top := int32(a.border), int32(float64(a.top)+k.Y*tk.UnitMM*a.ppm)
	if d.colorAt(left+2, top+2) != color(k.Color) {
		t.Fatal("classic key incorrectly acquired the touch visual inset")
	}
}
