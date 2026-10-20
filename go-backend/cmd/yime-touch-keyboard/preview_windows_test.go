//go:build windows && (amd64 || arm64)

package main

import (
	"math"
	"path/filepath"
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
