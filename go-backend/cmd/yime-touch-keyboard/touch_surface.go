package main

import (
	"fmt"
	"math"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

const touchSurfaceVersion = "touch-screen-v1"
const touchBodyHeightScale = 0.8
const touchControlHeightU = 0.75
const touchBodyTopU = 0.85

type touchControl struct {
	id, action, label string
	width             float64
}

// This opt-in screen view leaves the canonical board/encoding files untouched.
// Horizontal 18u geometry is retained; vertical parameters are explicit trial
// values, not a change to the ruler calibration or the frozen 17u profiles.
var touchControls = []touchControl{
	{"TU-SETTINGS", "settings", "设置", 1.25}, {"TU-HELP", "help", "帮助", 1},
	{"TU-BIND", "reset", "绑定", 1.5}, {"R01K02", "cancel", "取消", 1.5},
	{"R01K03", "language", "CN", 1.25}, {"TU-LEFT", "ArrowLeft", "←", 1}, {"TU-RIGHT", "ArrowRight", "→", 1},
	{"TU-HOME", "Home", "Home", 1.25}, {"TU-END", "End", "End", 1.25},
	{"TU-SELECT", "select", "选区：关", 1.5}, {"TU-ALL", "SelectAll", "全选", 1.5},
	{"TU-DELETE", "Delete", "Delete", 1.5}, {"TU-MINIMIZE", "minimize", "最小化", 1},
	{"R01K17", "close", "退出", 1.5},
}

func touchScreenBoard(source tk.Board) (tk.Board, error) {
	if len(source.Keys) != 100 || math.Abs(source.Bounds.Width-18) > 1e-6 || math.Abs(source.Bounds.Height-7.25) > 1e-6 {
		return tk.Board{}, fmt.Errorf("--touch-ui requires the original 18u/100-key main-only view")
	}
	b := source
	b.Keys = nil
	removed := 0
	for _, original := range source.Keys {
		if original.Zone != "main" {
			return tk.Board{}, fmt.Errorf("--touch-ui does not include side numeric zones")
		}
		if original.Y < 1.25 {
			removed++
			continue
		}
		k := original
		k.Y = touchBodyTopU + (original.Y-1.25)*touchBodyHeightScale
		k.Height *= touchBodyHeightScale
		k.Rectangles = append([]tk.Rect(nil), original.Rectangles...)
		for i := range k.Rectangles {
			k.Rectangles[i].Y *= touchBodyHeightScale
			k.Rectangles[i].Height *= touchBodyHeightScale
		}
		b.Keys = append(b.Keys, k)
	}
	if removed != 16 || len(b.Keys) != 84 {
		return tk.Board{}, fmt.Errorf("unexpected top-row inventory for touch surface")
	}
	x := 0.0
	for _, c := range touchControls {
		labels := make([]string, 12)
		labels[4] = c.label
		a := tk.Action{Type: "touch-ui", Key: c.action}
		k := tk.Key{ID: c.id, X: x, Y: 0, Width: c.width, Height: touchControlHeightU, Rectangles: []tk.Rect{{Width: c.width, Height: touchControlHeightU}}, Zone: "main", Color: "#cbacac", Labels: labels, Action: a, English: tk.View{Labels: labels, Action: a}}
		b.Keys = append(b.Keys, k)
		x += c.width
	}
	if math.Abs(x-18) > 1e-6 {
		return tk.Board{}, fmt.Errorf("touch control row must span 18u")
	}
	b.Bounds.Height = touchBodyTopU + 6*touchBodyHeightScale
	return b, nil
}

func touchNavigation(action string) bool {
	switch action {
	case "ArrowLeft", "ArrowRight", "Home", "End", "select", "SelectAll", "Delete":
		return true
	}
	return false
}

func touchLocalConfiguration(action string) bool {
	switch action {
	case "settings", "help", "help-previous", "help-next", "minimize", "close", "cancel", "language", "variable", "full", "shorthand", "literal", "glyphs", "layout", "theme", "font", "ruler", "smaller", "larger", "sound":
		return true
	}
	return false
}
