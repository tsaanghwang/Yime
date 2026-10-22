//go:build windows && (amd64 || arm64)

package main

import (
	"math"
	"path/filepath"
	"strings"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func previewUI(t *testing.T) *ui {
	t.Helper()
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	b, err := load(options{Root: root, Zones: "none", Gutters: true})
	if err != nil {
		t.Fatal(err)
	}
	a := &ui{s: tk.NewState(b), preview: previewFixture(t), ppm: 3, top: 300, border: 10, previewTouches: map[uint32]*previewGesture{}}
	a.s.Semantic, a.s.Original = true, true
	return a
}
func TestPreviewNativePathHasNoTargetAndConsumesOnlyInsideUp(t *testing.T) {
	a := previewUI(t)
	previous := active
	active = a
	defer func() { active = previous }()
	if err := sendOutput(tk.Output{Text: "must-not-send"}); err == nil {
		t.Fatal("preview allowed OS input")
	}
	var x, y int32
	for _, k := range a.s.Board.Keys {
		if k.Action.Type == "input" && k.Action.ASCII == "a" {
			x = int32(math.Round(float64(a.border) + (k.X+.5)*tk.UnitMM*a.ppm))
			y = int32(math.Round(float64(a.top) + (k.Y+.5)*tk.UnitMM*a.ppm))
		}
	}
	if x == 0 {
		t.Fatal("fixture key not found")
	}
	a.down(1, x, y)
	a.up(1, x, y)
	if a.preview.snapshot.State.RawInput != "a" || len(a.owners) != 0 || a.lastTarget != (target{}) {
		t.Fatal("preview used host ownership")
	}
	r := a.candidateRect(0)
	cx, cy := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(2, cx, cy)
	a.move(2, r.R+1, cy)
	a.move(2, cx, cy)
	a.up(2, cx, cy)
	if len(a.preview.editor.text) != 0 {
		t.Fatal("drag out/back committed")
	}
	a.down(3, cx, cy)
	a.up(3, cx, cy)
	a.up(3, cx, cy)
	if string(a.preview.editor.text) != "中文𠀀" {
		t.Fatal("duplicate UP or selection lost")
	}
	previewAction(t, a.preview, "input", "p", "")
	a.down(4, cx, cy)
	if err := a.preview.page(1); err != nil {
		t.Fatal(err)
	}
	a.up(4, cx, cy)
	if string(a.preview.editor.text) != "中文𠀀" {
		t.Fatal("old candidate committed after paging")
	}
	a.down(5, cx, cy)
	a.cancel()
	a.up(5, cx, cy)
	if string(a.preview.editor.text) != "中文𠀀" {
		t.Fatal("cancelled contact committed")
	}
}
func TestPreviewGlyphSourceIsLabResolvedInventory(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	g, err := loadPreviewGlyphs(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(g) != 60 || len([]rune(g["M01"])) != 1 || []rune(g["M01"])[0] <= 0xffff {
		t.Fatal("supplementary PUA mapping lost")
	}
	if _, err := loadPreviewGlyphs(t.TempDir()); err == nil {
		t.Fatal("missing glyph data silently ignored")
	}
}

func previewKeyPoint(t *testing.T, a *ui, match func(tk.Key, tk.View) bool) (int32, int32) {
	t.Helper()
	for _, k := range a.s.Board.Keys {
		if match(k, a.s.View(k)) {
			r := k.Rectangles[0]
			return int32(math.Round(float64(a.border) + (k.X+r.X+r.Width/2)*tk.UnitMM*a.ppm)), int32(math.Round(float64(a.top) + (k.Y+r.Y+r.Height/2)*tk.UnitMM*a.ppm))
		}
	}
	t.Fatal("required key absent from 18u board")
	return 0, 0
}

func TestPreviewPausedCandidateHasNoPointerTarget(t *testing.T) {
	a := previewUI(t)
	previewAction(t, a.preview, "input", "a", "")
	a.down(1, 300, 130)
	a.up(1, 300, 130) // toolbar CN -> EN
	box := a.candidateRect(0)
	x, y := (box.L+box.R)/2, (box.T+box.B)/2
	a.down(2, x, y)
	if a.previewTouches[2] != nil || a.preview.candidatesEnabled() {
		t.Fatal("paused candidate remains enabled")
	}
	a.up(2, x, y)
	if a.preview.snapshot.State.RawInput != "a" || len(a.preview.editor.text) != 0 {
		t.Fatal("paused pointer submitted")
	}
}

func TestPreviewHeldZeroCannotCommitAfterPhysicalPageButton(t *testing.T) {
	a := previewUI(t)
	previewAction(t, a.preview, "input", "p", "")
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "0" })
	a.down(1, x, y)
	a.down(2, 730, 130)
	a.up(2, 730, 130) // next page
	if a.preview.snapshot.State.PageNumber != 1 {
		t.Fatal("fixture did not page")
	}
	a.up(1, x, y)
	if a.preview.snapshot.State.RawInput != "p" || len(a.preview.editor.text) != 0 {
		t.Fatal("held zero committed new page")
	}
}

func TestPreviewEnglishOverlappingPointerKeys(t *testing.T) {
	for _, name := range []string{"1", "Space", "Enter"} {
		t.Run(name, func(t *testing.T) {
			a := previewUI(t)
			a.down(9, 300, 130)
			a.up(9, 300, 130)
			x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.ASCII == name || v.Action.Key == name })
			ax, ay := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
			a.down(1, x, y)
			a.down(2, ax, ay)
			a.up(2, ax, ay)
			a.up(1, x, y)
			want := "a1"
			if name == "Space" {
				want = "a "
			}
			if name == "Enter" {
				want = "a\n"
			}
			if string(a.preview.editor.text) != want {
				t.Fatal("overlapping physical contact lost", string(a.preview.editor.text))
			}
		})
	}
}

func TestPreview18uAcceptanceCaseKeys(t *testing.T) {
	a := previewUI(t)
	a.down(9, 300, 130)
	a.up(9, 300, 130)
	tap := func(kind, value string) {
		x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool {
			return v.Action.Type == kind && (value == "" || v.Action.ASCII == value)
		})
		a.down(1, x, y)
		a.up(1, x, y)
	}
	// P07/P08 use the actual EN a/A key, not the original a/] carrier.
	x, y := previewKeyPoint(t, a, func(k tk.Key, v tk.View) bool {
		return k.ID == "R05K06" && v.Action.ASCII == "a" && v.ShiftAction.ASCII == "A"
	})
	a.down(1, x, y)
	a.up(1, x, y)
	tap("shift", "")
	a.down(1, x, y)
	a.up(1, x, y)
	if string(a.preview.editor.text) != "aA" {
		t.Fatal("P07 wrong view", string(a.preview.editor.text))
	}
	a.preview.editor = previewEditor{}
	for _, c := range []string{"a", "b", "c"} {
		tap("input", c)
	}
	tap("backspace", "")
	tap("shift", "")
	tap("input", "x")
	if string(a.preview.editor.text) != "abX" {
		t.Fatal("H02 main-area editing", string(a.preview.editor.text))
	}
	for i := 0; i < 3; i++ {
		tap("backspace", "")
	}
	if len(a.preview.editor.text) != 0 {
		t.Fatal("H02 backspace failed")
	}
	for _, k := range a.s.Board.Keys {
		for _, action := range []tk.Action{k.Action, k.ShiftAction, k.English.Action, k.English.ShiftAction} {
			if action.Key == "ArrowLeft" || action.Key == "Home" || action.Key == "End" {
				t.Fatal("navigation must remain auxiliary, not change the 18u key inventory", k.ID)
			}
		}
	}
}

func TestPreviewDisplayFitsMeasuredSingleLine(t *testing.T) {
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	if dc == 0 {
		t.Fatal("create measuring DC")
	}
	defer G("DeleteDC").Call(dc)
	e := previewEditor{}
	e.insert(strings.Repeat("你好𠀀\n\t", 100))
	e.anchor = 0
	for _, width := range []int32{100, 250, 800} {
		s := e.fittedDisplay(func(s string) bool { return previewTextWidth(dc, s) <= width })
		if strings.ContainsAny(s, "\n\r\t") || !strings.Contains(s, "│") || previewTextWidth(dc, s) > width {
			t.Fatal("caret clipped or wrapped", width, s)
		}
	}
}
