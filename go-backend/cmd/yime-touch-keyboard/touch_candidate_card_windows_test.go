//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestTouchCandidateCardTextIsCompleteAndCentered(t *testing.T) {
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
				d := newKeycapDIB(t, 640, 500)
				old, _, _ := G("SelectObject").Call(d.dc, a.touchFont)
				t.Cleanup(func() { G("SelectObject").Call(d.dc, old) })
				G("SetBkMode").Call(d.dc, 1)
				G("SetTextColor").Call(d.dc, 0)
				original := a.candidateRect(0)
				bounds := rect{40, 40, 40 + original.R - original.L, 40 + original.B - original.T}
				for _, pressed := range []bool{false, true} {
					cap := touchKeycapLayout(bounds, tk.UnitMM*ppm, pressed)
					box := touchCandidateTextBox(cap)
					if !keycapContains(cap.face, box) || box.L <= cap.face.L+cap.bevel || box.T <= cap.face.T+cap.bevel || box.R >= cap.face.R-cap.bevel || box.B >= cap.face.B-cap.bevel {
						t.Fatal("candidate text reaches the bevel", cap, box)
					}
					for _, label := range []string{"1  你", "9  ‘", "9  ’", "9  “", "9  ”", "9  '\"", "1  &", "1  …\nU+2026", "2  ⋯⋯\nU+22EF", "9  ‘（暂停）", "1  较长候选内容需要换行"} {
						font := a.touchCandidateFont(d.dc, label, box)
						G("SelectObject").Call(d.dc, font)
						alignment := touchCandidateAlignmentBox(box)
						measured := alignment
						height, _, _ := U("DrawTextW").Call(d.dc, ptr(str(label)), ^uintptr(0), uintptr(unsafe.Pointer(&measured)), 0x411|drawTextNoPrefix)
						if height == 0 || int32(height) > box.B-box.T {
							t.Fatalf("representative candidate %q cannot fit its complete block: height=%d box=%+v", label, height, box)
						}
						// Reference uses the alignment width, retaining the content box's
						// side-bearing allowance, with enough height for every line.
						d.clear()
						text(d.dc, label, rect{alignment.L, 10, alignment.R, d.height - 10}, 0x111)
						complete := d.ink()
						G("SelectObject").Call(d.dc, a.touchFont)
						d.clear()
						a.drawTouchCandidate(d.dc, label, box)
						actual := d.ink()
						current, _, _ := G("GetCurrentObject").Call(d.dc, 6)
						if current != a.touchFont {
							t.Fatal("candidate draw leaked its selected font")
						}
						if complete.count == 0 || actual.count != complete.count || actual.bounds.R-actual.bounds.L != complete.bounds.R-complete.bounds.L || actual.bounds.B-actual.bounds.T != complete.bounds.B-complete.bounds.T || !keycapContains(box, actual.bounds) {
							t.Fatalf("candidate %q clipped, pressed=%v: actual=%+v complete=%+v", label, pressed, actual, complete)
						}
						wantTop := box.T + (box.B-box.T-int32(height))/2 + complete.bounds.T - 10
						// Compare against DT_CENTER's complete reference, not the ink
						// midpoint: full-width parentheses have asymmetric blank bearings.
						if delta := actual.bounds.T - wantTop; delta < -1 || delta > 1 || actual.bounds.L != complete.bounds.L || actual.bounds.R != complete.bounds.R {
							t.Fatalf("candidate block %q is not centered as a whole: ink=%+v expected top=%d", label, actual.bounds, wantTop)
						}
					}
					long := "1  averylongunbrokenwordthatexceedsthecandidatecolumn"
					if a.touchCandidateFont(d.dc, long, box) != a.touchFont {
						t.Fatal("oversize candidate lost its existing fallback font")
					}
					d.clear()
					a.drawTouchCandidate(d.dc, long, box)
					if ink := d.ink(); ink.count == 0 || !keycapContains(box, ink.bounds) {
						t.Fatal("oversize fallback escaped the content clip", ink)
					}
				}
				if a.candidateRect(0) != original {
					t.Fatal("text rendering changed the candidate hit rectangle")
				}
			})
		}
	}
}

func TestTouchCandidateCardsRenderOnlyCurrentValidPresses(t *testing.T) {
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
				d := newKeycapDIB(t, a.previewWidth(), int32(a.top)+1)
				surface := rect{0, 0, d.width, d.height}
				palette, unit := a.palette(), tk.UnitMM*ppm
				previewAction(t, a.preview, "input", "p", "")
				before, _ := json.Marshal(a.preview.snapshot)
				var boxes []rect
				var identities []candidatePress
				for i := range a.preview.snapshot.State.Candidates {
					boxes = append(boxes, a.candidateRect(i))
					identities = append(identities, a.preview.candidate(i))
				}
				draw := func(index int, face uintptr, pressed bool) {
					t.Helper()
					a.draw(d.dc, surface)
					controlCapPixels(t, d, a.candidateRect(index), unit, face, palette.background, pressed)
				}
				for i := range boxes {
					draw(i, palette.candidate, false)
				}
				for i := range boxes {
					if a.candidateRect(i) != boxes[i] || a.preview.candidate(i) != identities[i] {
						t.Fatal("raised card changed candidate identity or hit geometry")
					}
				}
				after, _ := json.Marshal(a.preview.snapshot)
				if string(before) != string(after) {
					t.Fatal("drawing changed candidate state")
				}
				box := boxes[0]
				for _, xy := range [][2]int32{{box.L, (box.T + box.B) / 2}, {box.R - 1, (box.T + box.B) / 2}, {(box.L + box.R) / 2, box.T}, {(box.L + box.R) / 2, box.B - 1}} {
					a.down(71, xy[0], xy[1])
					g := a.previewTouches[71]
					if g == nil || g.action != "candidate" || g.area != box || g.candidate != identities[0] || !a.touchCandidatePressed(0, box) {
						t.Fatal("visual card margin lost its original candidate target")
					}
					draw(0, palette.pressed, true)
					a.cancel()
				}
				x, y := box.L+1, box.B-1
				a.down(72, x, y)
				valid := *a.previewTouches[72]
				for _, invalid := range []struct {
					name string
					edit func(*previewGesture)
				}{
					{"left", func(g *previewGesture) { g.left = true }},
					{"action", func(g *previewGesture) { g.action = "next" }},
					{"area", func(g *previewGesture) { g.area.R++ }},
					{"identity", func(g *previewGesture) { g.candidate.id = identities[1].id }},
					{"candidate revision", func(g *previewGesture) { g.candidate.stamp.revision++ }},
					{"gesture revision", func(g *previewGesture) { g.stamp.revision++ }},
					{"cancel generation", func(g *previewGesture) { g.cancelGeneration++ }},
				} {
					g := valid
					invalid.edit(&g)
					a.previewTouches[72] = &g
					if a.touchCandidatePressed(0, box) {
						t.Fatal("invalid contact still depresses a candidate:", invalid.name)
					}
					draw(0, palette.candidate, false)
				}
				a.previewTouches[72] = &valid
				a.move(72, box.R, y)
				a.move(72, x, y)
				draw(0, palette.candidate, false)
				a.up(72, x, y)
				a.down(73, x, y)
				a.cancel()
				draw(0, palette.candidate, false)
				a.up(73, x, y)
				if len(a.preview.editor.text) != 0 {
					t.Fatal("cancelled or moved-out candidate committed")
				}
				a.down(74, x, y)
				if err := a.preview.page(1); err != nil {
					t.Fatal(err)
				}
				draw(0, palette.candidate, false)
				a.up(74, x, y)
				if len(a.preview.editor.text) != 0 || a.preview.snapshot.State.PageNumber != 1 {
					t.Fatal("old-page card selected a new candidate")
				}
				a.down(75, x, y)
				previewAction(t, a.preview, "toggle-language", "", "")
				draw(0, palette.disabled, false)
				if a.touchCandidatePressed(0, box) {
					t.Fatal("paused candidate remained pressed")
				}
				// The actual card path must retain legible text even for disabled cards.
				G("SetTextColor").Call(d.dc, palette.mutedText)
				a.drawTouchCandidateItem(d.dc, 0)
				if got, _, _ := G("GetTextColor").Call(d.dc); got != palette.text {
					t.Fatal("candidate card uses muted rather than the clear text color")
				}
				a.up(75, x, y)
				a.down(76, x, y)
				a.up(76, x, y)
				if len(a.preview.editor.text) != 0 || len(a.previewTouches) != 0 {
					t.Fatal("disabled candidate accepted a contact")
				}
				previewAction(t, a.preview, "toggle-language", "", "")
				want := a.preview.snapshot.State.Candidates[0].Text
				sequence := a.preview.sequence
				a.down(77, x, y)
				draw(0, palette.pressed, true)
				a.up(77, x, y)
				a.up(77, x, y)
				if string(a.preview.editor.text) != want || a.preview.sequence != sequence+1 {
					t.Fatal("fresh edge contact did not commit its original candidate exactly once")
				}
			})
		}
	}
}

func TestTouchCandidateCardsLeaveClassicPreviewFlat(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	a := previewUI(t)
	headerFontFixture(t, a)
	d := newKeycapDIB(t, a.previewWidth(), 300)
	previewAction(t, a.preview, "input", "a", "")
	before := a.preview.candidate(0)
	box := a.candidateRect(0)
	w := (a.previewWidth() - 20) / 9
	if a.o.TouchUI || box != (rect{10, 184, 10 + w - 3, 234}) {
		t.Fatal("fixture no longer exercises the original classic target")
	}
	a.draw(d.dc, rect{0, 0, d.width, d.height})
	cap := touchKeycapLayout(box, tk.UnitMM*a.ppm, false)
	for _, xy := range [][2]int32{{box.L, box.T}, {cap.base.L - 1, cap.base.T}, {box.R - 1, box.B - 1}} {
		if d.colorAt(xy[0], xy[1]) != a.palette().candidate {
			t.Fatal("classic candidate gained the touch card's inset or bevel")
		}
	}
	if a.candidateRect(0) != box || a.preview.candidate(0) != before {
		t.Fatal("classic candidate geometry or identity changed")
	}
}
