//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"math"
	"reflect"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func touchUIFixture(t *testing.T) *ui {
	a := previewUI(t)
	b, err := touchScreenBoard(a.s.Board)
	if err != nil {
		t.Fatal(err)
	}
	a.o.TouchUI = true
	a.top = a.touchHeaderLayout().height
	a.touchFontLevel = 2
	a.s = tk.NewState(b)
	a.s.Semantic = true
	a.s.Original = a.preview.original()
	return a
}
func tapTouchControl(t *testing.T, a *ui, action string) {
	t.Helper()
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "touch-ui" && v.Action.Key == action })
	a.down(51, x, y)
	a.up(51, x, y)
}
func tapTouchSetting(t *testing.T, a *ui, action string) {
	t.Helper()
	for i, name := range touchSettings {
		if name == action {
			r := a.touchSettingRect(i)
			a.down(52, (r.L+r.R)/2, (r.T+r.B)/2)
			a.up(52, (r.L+r.R)/2, (r.T+r.B)/2)
			return
		}
	}
	t.Fatal("missing setting", action)
}
func TestTouchSurfaceRetainsCanonicalInputAndHasNoOverlaps(t *testing.T) {
	a := previewUI(t)
	source := a.s.Board
	before, _ := json.Marshal(source)
	b, err := touchScreenBoard(source)
	if err != nil {
		t.Fatal(err)
	}
	after, _ := json.Marshal(source)
	if string(before) != string(after) {
		t.Fatal("canonical board mutated")
	}
	if len(b.Keys) != 102 || b.Bounds.Width != 18 || math.Abs(b.Bounds.Height-5.7) > 1e-6 {
		t.Fatal("unexpected touch geometry", b.Bounds, len(b.Keys))
	}
	byID := map[string]tk.Key{}
	for _, k := range source.Keys {
		byID[k.ID] = k
	}
	inputs := 0
	for i, k := range b.Keys {
		if k.Action.Type == "unsupported" && len(k.Action.Label) > 1 && k.Action.Label[0] == 'F' {
			t.Fatal("F key retained", k.ID)
		}
		if k.Action.Type != "touch-ui" {
			old := byID[k.ID]
			inputs++
			if !reflect.DeepEqual(k.Action, old.Action) || !reflect.DeepEqual(k.ShiftAction, old.ShiftAction) || !reflect.DeepEqual(k.English, old.English) || !reflect.DeepEqual(k.Labels, old.Labels) || k.X != old.X || k.Width != old.Width {
				t.Fatal("input mapping/width changed", k.ID)
			}
		}
		for _, r := range k.Rectangles {
			for _, other := range b.Keys[:i] {
				for _, q := range other.Rectangles {
					if k.X+r.X < other.X+q.X+q.Width-1e-8 && k.X+r.X+r.Width > other.X+q.X+1e-8 && k.Y+r.Y < other.Y+q.Y+q.Height-1e-8 && k.Y+r.Y+r.Height > other.Y+q.Y+1e-8 {
						t.Fatal("overlap", k.ID, other.ID)
					}
				}
			}
		}
	}
	if inputs != 84 {
		t.Fatal("input area inventory changed", inputs)
	}
}
func TestTouchSettingsPreserveRawAndBlockTypingThroughSheet(t *testing.T) {
	a := touchUIFixture(t)
	previewAction(t, a.preview, "input", "a", "")
	tapTouchControl(t, a, "settings")
	if !a.touchSettingsOpen || a.preview.snapshot.State.RawInput != "a" {
		t.Fatal("opening settings lost composition")
	}
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "confirm" && v.Action.Key == "Space" })
	a.down(2, x, y)
	a.up(2, x, y)
	if a.preview.snapshot.State.RawInput != "a" || len(a.preview.editor.text) != 0 {
		t.Fatal("typed through settings sheet")
	}
	tapTouchSetting(t, a, "full")
	if a.preview.mode != "full" || a.preview.snapshot.State.RawInput != "" || !a.touchSettingsOpen {
		t.Fatal("mode setting lost cancellation or sheet")
	}
	tapTouchSetting(t, a, "layout")
	if !a.preview.original() || a.preview.englishView {
		t.Fatal("English preference rewrote CN view")
	}
	tapTouchControl(t, a, "settings")
	if a.touchSettingsOpen {
		t.Fatal("cannot return to keyboard")
	}
}
func TestTouchEditingAndPausedCompositionGuard(t *testing.T) {
	a := touchUIFixture(t)
	a.preview.editor.insert("a𠀀b")
	tapTouchControl(t, a, "SelectAll")
	tapTouchControl(t, a, "Delete")
	if len(a.preview.editor.text) != 0 {
		t.Fatal("large editing controls did not delete selection")
	}
	a.preview.editor.insert("keep")
	previewAction(t, a.preview, "input", "a", "")
	tapTouchControl(t, a, "Delete")
	tapTouchControl(t, a, "language")
	tapTouchControl(t, a, "SelectAll")
	if string(a.preview.editor.text) != "keep" || a.preview.snapshot.State.RawInput != "a" || a.preview.editor.anchor != a.preview.editor.cursor {
		t.Fatal("editing changed active/paused composition")
	}
	tapTouchControl(t, a, "cancel")
	if a.preview.snapshot.State.RawInput != "" || string(a.preview.editor.text) != "keep" {
		t.Fatal("cancel changed confirmed text")
	}
}
func TestTouchLocalSettingsWorkWithoutHostBinding(t *testing.T) {
	a := touchUIFixture(t)
	sends := 0
	a.host = &deliveryGate{current: func() hostTarget { return hostTarget{} }, send: func(hostTarget, tk.Output) error { sends++; return nil }}
	a.preview.emit = func(string, tk.Output) error { t.Fatal("configuration emitted host input"); return nil }
	tapTouchControl(t, a, "settings")
	tapTouchSetting(t, a, "literal")
	tapTouchControl(t, a, "language")
	if !a.preview.literalEntries || a.preview.snapshot.Modes.Input != "english" || sends != 0 || a.host.target.Window != 0 {
		t.Fatal("configuration requires/binds host or sends input")
	}
	tapTouchControl(t, a, "Delete")
	if sends != 0 || len(a.previewTouches) != 0 {
		t.Fatal("unbound editor sent input")
	}
}
func TestTouchControlsRejectMoveOutDuplicateAndOldToolbar(t *testing.T) {
	a := touchUIFixture(t)
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "touch-ui" && v.Action.Key == "settings" })
	a.down(1, x, y)
	a.move(1, -1, y)
	a.move(1, x, y)
	a.up(1, x, y)
	if a.touchSettingsOpen {
		t.Fatal("moved-out settings activated")
	}
	a.down(2, x, y)
	a.up(2, x, y)
	a.up(2, x, y)
	if !a.touchSettingsOpen {
		t.Fatal("duplicate UP toggled twice")
	}
	a.touchSettingsOpen = false
	a.down(3, 390, 40)
	if a.previewTouches[3] != nil {
		t.Fatal("old toolbar still receives touch hits")
	}
}
func TestTouchSettingsFitTheScreenViewAtDifferentScales(t *testing.T) {
	for _, ppm := range []float64{3, 4.82, 8.2} {
		a := touchUIFixture(t)
		a.ppm = ppm
		bottom := int32(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*ppm)) + int32(a.top+a.border)
		for i := range touchSettings {
			r := a.touchSettingRect(i)
			if r.L < 0 || r.R > a.previewWidth() || r.B > bottom {
				t.Fatal("settings extend outside window", ppm, i, r, bottom)
			}
		}
	}
}

func TestTouchHeaderCalibrationRejectionKeepsPreviousGeometry(t *testing.T) {
	a := touchUIFixture(t)
	// Deliberately outside any desktop work area: resize must reject before
	// moving a window or committing a new board origin.
	a.ppm = 1e6
	beforePPM, beforeTop := a.ppm, a.top
	beforeCandidate := a.candidateRect(0)
	if err := a.applyTouchImmediate("larger"); err == nil {
		t.Fatal("oversized calibration was accepted")
	}
	if math.Abs(a.ppm-beforePPM) > 1e-6 || a.top != beforeTop || a.candidateRect(0) != beforeCandidate {
		t.Fatal("failed calibration retained changed geometry")
	}
}
