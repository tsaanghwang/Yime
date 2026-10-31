//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"math"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func candidateFontFixture(t *testing.T) (*ui, uintptr) {
	t.Helper()
	a := touchUIFixture(t)
	height := int32(-22)
	font, _, _ := G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	if font == 0 || dc == 0 {
		t.Fatal("create candidate fixture font/DC")
	}
	a.font = font
	old, _, _ := G("SelectObject").Call(dc, font)
	t.Cleanup(func() {
		G("SelectObject").Call(dc, old)
		G("DeleteDC").Call(dc)
		for _, f := range []uintptr{font, a.keyFont, a.glyphFont, a.candidateFont, a.touchFont} {
			if f != 0 {
				G("DeleteObject").Call(f)
			}
		}
	})
	return a, dc
}

func TestTouchCandidateFontFitsWithoutChangingCandidateIdentity(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	a, dc := candidateFontFixture(t)
	previewAction(t, a.preview, "input", "a", "")
	before, _ := json.Marshal(a.preview.snapshot)
	press := a.preview.candidate(0)
	for _, ppm := range []float64{3, 4.4, 8.2, 3840 / 597.73 * 100 / 58} {
		a.ppm = ppm
		box := a.candidateRect(0)
		for level, scale := range []float64{.8, .9, 1} {
			want := -int32(math.Round(tk.UnitMM * ppm * .20 * scale))
			a.touchFontLevel = level
			if err := a.updateTouchFonts(); err != nil {
				t.Fatal(err)
			}
			var lf struct {
				height int32
				rest   [88]byte // LOGFONTW
			}
			if n, _, _ := G("GetObjectW").Call(a.candidateFont, unsafe.Sizeof(lf), uintptr(unsafe.Pointer(&lf))); n != unsafe.Sizeof(lf) || lf.height != want {
				t.Fatalf("candidate font level %d: got height %d, size %d", level, lf.height, n)
			}
			for _, label := range []string{"9  ‘", "9  ’", "9  “", "9  ”", "9  '\"", "1  你", "1  &"} {
				if f := a.touchCandidateFont(dc, label, box); f != a.candidateFont {
					t.Errorf("short candidate not enlarged at %.1f/%d: %q", ppm, level, label)
				}
			}
			if a.candidateRect(0) != box || a.preview.candidate(0) != press {
				t.Fatal("font update changed hit region or candidate identity")
			}
		}
		// The taller row now fits the existing two-line symbol descriptions
		// at regular key size, instead of always shrinking them on 4K screens.
		for _, label := range []string{"1  …\nU+2026", "2  ⋯⋯\nU+22EF", "9  ‘（暂停）"} {
			if a.touchCandidateFont(dc, label, box) != a.candidateFont {
				t.Errorf("regular candidate unnecessarily shrunk: %q", label)
			}
		}
		if a.touchCandidateFont(dc, "1  averylongunbrokenwordthatexceedsthecandidatecolumn", box) != a.touchFont {
			t.Fatal("oversize candidate did not use the calibrated fallback")
		}
	}
	after, _ := json.Marshal(a.preview.snapshot)
	if string(before) != string(after) {
		t.Fatal("font updates changed composition/candidates")
	}
	if err := a.preview.selectCandidate(press); err != nil || string(a.preview.editor.text) != "中文𠀀" {
		t.Fatal("candidate no longer selects the original text", err, a.preview.editor.text)
	}
}

// Exercise the actual candidate draw path on a memory bitmap: enlargement
// must add visible glyph pixels, preserve the complete quotes and restore the
// status/pager font. This is rendering evidence, not physical readability.
func TestTouchCandidateDrawEnlargesQuotesWithoutClipping(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	a, dc := candidateFontFixture(t)
	a.ppm = 3840 / 597.73 * 100 / 58
	if err := a.updateTouchFonts(); err != nil {
		t.Fatal(err)
	}
	G("SelectObject").Call(dc, a.touchFont)
	const width, height = 420, 260
	bitmap, _, _ := G("CreateCompatibleBitmap").Call(dc, width, height)
	if bitmap == 0 {
		t.Fatal("create bitmap")
	}
	oldBitmap, _, _ := G("SelectObject").Call(dc, bitmap)
	t.Cleanup(func() { G("SelectObject").Call(dc, oldBitmap); G("DeleteObject").Call(bitmap) })
	G("SetTextColor").Call(dc, 0)
	G("SetBkMode").Call(dc, 1)
	actual := a.candidateRect(0)
	box := rect{20, 10, 20 + actual.R - actual.L, 10 + actual.B - actual.T}
	ink := func(checkBounds bool) int {
		count := 0
		for y := int32(0); y < height; y++ {
			for x := int32(0); x < width; x++ {
				v, _, _ := G("GetPixel").Call(dc, uintptr(x), uintptr(y))
				if v != 0xffffff {
					count++
					if checkBounds && !inside(box, x, y) {
						t.Fatalf("candidate ink outside its hit rectangle at %d,%d", x, y)
					}
				}
			}
		}
		return count
	}
	for _, label := range []string{"9  ‘", "9  ’", "9  “", "9  ”", "9  '\"", "1  &"} {
		fill(dc, rect{0, 0, width, height}, 0xffffff)
		text(dc, label, box, 0x11)
		small := ink(false)
		fill(dc, rect{0, 0, width, height}, 0xffffff)
		a.drawTouchCandidate(dc, label, box)
		large := ink(true)
		current, _, _ := G("GetCurrentObject").Call(dc, 6) // OBJ_FONT
		if current != a.touchFont || large <= small {
			t.Fatalf("candidate %q did not enlarge or restore font: %d -> %d", label, small, large)
		}
		fill(dc, rect{0, 0, width, height}, 0xffffff)
		G("SelectObject").Call(dc, a.candidateFont)
		text(dc, label, rect{box.L, box.T, box.R, height}, 0x11)
		complete := ink(false)
		G("SelectObject").Call(dc, a.touchFont)
		if large != complete {
			t.Fatalf("candidate %q clipped: %d vs complete %d", label, large, complete)
		}
	}
}
