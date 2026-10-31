//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"math"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func headerRectsOverlap(a, b rect) bool {
	return a.L < b.R && b.L < a.R && a.T < b.B && b.T < a.B
}

func TestTouchHeaderScalesWithoutChangingTheBody(t *testing.T) {
	for _, ppm := range []float64{3, 8.2, 11.077} {
		t.Run(fmt.Sprintf("ppm_%.3f", ppm), func(t *testing.T) {
			a := touchUIFixture(t)
			bodyBefore, err := json.Marshal(a.s.Board)
			if err != nil {
				t.Fatal(err)
			}
			a.ppm = ppm
			layout := a.touchHeaderLayout()
			a.top = layout.height
			width := a.previewWidth()
			areas := []rect{layout.status, layout.previous, layout.next, layout.candidates}
			for i, r := range areas {
				if r.L < 0 || r.T < 0 || r.R > width || r.B > int32(a.top) || r.L >= r.R || r.T >= r.B {
					t.Fatalf("header area %d outside the window/header: %+v", i, r)
				}
				for j := 0; j < i; j++ {
					if headerRectsOverlap(r, areas[j]) {
						t.Fatalf("header areas %d and %d overlap", i, j)
					}
				}
			}
			if layout.previous.R-layout.previous.L != layout.next.R-layout.next.L || layout.previous.T != layout.next.T || layout.previous.B != layout.next.B {
				t.Fatal("paging targets are not symmetric", layout)
			}
			// Match one ordinary calibrated key unit on every screen, rather
			// than a fixed-pixel minimum that changes the physical key size.
			unit := int32(math.Round(tk.UnitMM * ppm))
			if layout.previous.R-layout.previous.L != unit || layout.previous.B-layout.previous.T != unit {
				t.Fatal("paging target is not 1u square", layout, unit)
			}
			for i := 0; i < 9; i++ {
				r := a.candidateRect(i)
				if r.L < layout.candidates.L || r.R > layout.candidates.R || r.T != layout.candidates.T || r.B != layout.candidates.B || r.L >= r.R {
					t.Fatalf("candidate %d outside its row: %+v", i, r)
				}
				if i > 0 && r.L <= a.candidateRect(i-1).R {
					t.Fatalf("candidate %d has no separation from its neighbour", i)
				}
			}
			for _, k := range a.s.Board.Keys {
				if r := a.keyPixelRect(k); r.T < int32(a.top) {
					t.Fatalf("body key %s overlaps header: %+v", k.ID, r)
				}
			}
			bodyAfter, err := json.Marshal(a.s.Board)
			if err != nil || string(bodyBefore) != string(bodyAfter) {
				t.Fatal("header sizing changed the 18u body geometry", err)
			}
		})
	}
}

// Create a DC on the caller's locked OS thread. Fonts are released only after
// deselection and DC deletion; the caller registers thread unlock first.
func headerFontFixture(t *testing.T, a *ui) uintptr {
	t.Helper()
	height := int32(-15)
	font, _, _ := G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	var old uintptr
	t.Cleanup(func() {
		if dc != 0 {
			if old != 0 {
				G("SelectObject").Call(dc, old)
			}
			G("DeleteDC").Call(dc)
		}
		for _, f := range []uintptr{font, a.keyFont, a.glyphFont, a.touchFont, a.candidateFont} {
			if f != 0 {
				G("DeleteObject").Call(f)
			}
		}
	})
	if font == 0 || dc == 0 {
		t.Fatal("create header font/DC")
	}
	a.font = font
	old, _, _ = G("SelectObject").Call(dc, font)
	return dc
}

func TestTouchHeaderRegularFontKeepsEllipsisDescriptions(t *testing.T) {
	for _, ppm := range []float64{3, 8.2, 11.077} {
		t.Run(fmt.Sprintf("ppm_%.3f", ppm), func(t *testing.T) {
			runtime.LockOSThread()
			t.Cleanup(runtime.UnlockOSThread)
			a := touchUIFixture(t)
			a.ppm = ppm
			a.top = a.touchHeaderLayout().height
			dc := headerFontFixture(t, a)
			for i := 0; i < 6; i++ {
				previewAction(t, a.preview, "symbol", "·", "")
			}
			if !a.preview.snapshot.SymbolChoice || len(a.preview.snapshot.State.Candidates) != 2 {
				t.Fatal("ellipsis fixture did not produce both choices")
			}
			fontHeight := func(font uintptr) int32 {
				var lf struct {
					height int32
					rest   [88]byte
				}
				if n, _, _ := G("GetObjectW").Call(font, unsafe.Sizeof(lf), uintptr(unsafe.Pointer(&lf))); n != unsafe.Sizeof(lf) {
					t.Fatal("read font metrics")
				}
				return lf.height
			}
			for level := 0; level < 3; level++ {
				a.touchFontLevel = level
				if err := a.updateTouchFonts(); err != nil {
					t.Fatal(err)
				}
				if fontHeight(a.candidateFont) != fontHeight(a.keyFont) {
					t.Fatal("header candidates do not use the regular body font size")
				}
				if ppm == 11.077 && level == 2 && fontHeight(a.candidateFont) > -42 {
					t.Fatal("4K regular font remained at the old small candidate size")
				}
				for i := range a.preview.snapshot.State.Candidates {
					label, box := a.preview.candidateLabel(i), a.candidateRect(i)
					if a.touchCandidateFont(dc, label, box) != a.candidateFont {
						t.Fatalf("PR83 two-line choice fell back to small text at level %d: %q", level, label)
					}
				}
				old, _, _ := G("SelectObject").Call(dc, a.candidateFont)
				measured, box := a.touchHeaderLayout().status, a.touchHeaderLayout().status
				height, _, _ := U("DrawTextW").Call(dc, ptr(str("组合：ni  |  12你abc")), ^uintptr(0), uintptr(unsafe.Pointer(&measured)), 0x420|drawTextNoPrefix)
				G("SelectObject").Call(dc, old)
				if height == 0 || measured.B > box.B || measured.R > box.R {
					t.Fatal("regular input/preview text is clipped by the header line", measured, box)
				}
			}
		})
	}
}

func TestTouchHeaderPagerEdgesKeepGestureCancellation(t *testing.T) {
	for _, ppm := range []float64{3, 8.2, 11.077} {
		t.Run(fmt.Sprintf("ppm_%.3f", ppm), func(t *testing.T) {
			a := touchUIFixture(t)
			a.ppm = ppm
			layout := a.touchHeaderLayout()
			a.top = layout.height
			previewAction(t, a.preview, "input", "p", "")
			if !a.preview.snapshot.State.HasNext {
				t.Fatal("fixture has no next page")
			}
			candidate := a.candidateRect(0)
			cx, cy := (candidate.L+candidate.R)/2, (candidate.T+candidate.B)/2
			a.down(100, cx, cy) // Held candidate must become stale after paging.
			nx, ny := layout.next.L+1, layout.next.B-1
			a.down(101, nx, ny)
			a.up(101, nx, ny)
			a.up(101, nx, ny)
			if a.preview.snapshot.State.PageNumber != 1 {
				t.Fatal("new next-page edge did not page exactly once")
			}
			a.up(100, cx, cy)
			if len(a.preview.editor.text) != 0 || a.preview.snapshot.State.RawInput != "p" {
				t.Fatal("held candidate committed a different page")
			}
			px, py := layout.previous.R-1, layout.previous.B-1
			a.down(102, px, py)
			a.move(102, layout.previous.R, py)
			a.move(102, px, py)
			a.up(102, px, py)
			if a.preview.snapshot.State.PageNumber != 1 {
				t.Fatal("move-out/back activated previous page")
			}
			a.down(103, px, py)
			a.up(103, px, py)
			a.up(103, px, py)
			if a.preview.snapshot.State.PageNumber != 0 {
				t.Fatal("new previous-page edge did not page exactly once")
			}
			// The same area is blocked on the first page, not a character key.
			a.down(104, px, py)
			a.up(104, px, py)
			if a.preview.snapshot.State.PageNumber != 0 || a.preview.snapshot.State.RawInput != "p" || len(a.preview.editor.text) != 0 {
				t.Fatal("disabled pager changed input")
			}
		})
	}
}
