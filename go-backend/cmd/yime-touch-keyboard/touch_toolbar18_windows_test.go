//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"math"
	"reflect"
	"runtime"
	"sort"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func touchToolbarKeyRect(t *testing.T, a *ui, id string) rect {
	t.Helper()
	for _, k := range a.s.Board.Keys {
		if k.ID == id {
			return a.keyPixelRect(k)
		}
	}
	t.Fatal("missing toolbar key", id)
	return rect{}
}

func TestTouchToolbar18UniformKeysKeepExistingIdentities(t *testing.T) {
	a := touchUIFixture(t)
	var row []tk.Key
	for _, k := range a.s.Board.Keys {
		if k.Y == 0 {
			row = append(row, k)
		}
	}
	sort.Slice(row, func(i, j int) bool { return row[i].X < row[j].X })
	if len(row) != 18 || len(a.s.Board.Keys) != 102 || a.s.Board.Bounds.Width != 18 || math.Abs(a.s.Board.Bounds.Height-5.7) > 1e-6 {
		t.Fatal("unexpected control/body inventory", len(row), len(a.s.Board.Keys), a.s.Board.Bounds)
	}
	want := map[string]string{
		"TU-SETTINGS": "settings", "TU-HELP": "help", "TU-BIND": "reset",
		"R01K02": "cancel", "R01K03": "language", "TU-LEFT": "ArrowLeft", "TU-RIGHT": "ArrowRight",
		"TU-HOME": "Home", "TU-END": "End", "TU-SELECT": "select", "TU-ALL": "SelectAll",
		"TU-DELETE": "Delete", "TU-MINIMIZE": "minimize", "R01K17": "close",
		"TU-BACKSPACE": "Backspace", "TU-SPARE-1": "reserved", "TU-SPARE-2": "reserved", "TU-SPARE-3": "reserved",
	}
	for i, k := range row {
		if k.X != float64(i) || k.Width != 1 || k.Height != touchBodyHeightScale || k.Action.Type != "touch-ui" || want[k.ID] != k.Action.Key {
			t.Fatal("toolbar key is not the expected equal-sized control", i, k)
		}
		if len(k.Rectangles) != 1 || k.Rectangles[0] != (tk.Rect{Width: 1, Height: touchBodyHeightScale}) {
			t.Fatal("toolbar hit geometry differs from its visual key", k.ID, k.Rectangles)
		}
		delete(want, k.ID)
	}
	if len(want) != 0 {
		t.Fatal("lost/duplicated existing or new control identities", want)
	}
}

func TestTouchToolbarSpareKeysAreInertInAllInputContexts(t *testing.T) {
	for _, context := range []string{"CN-empty", "CN-composition", "EN-paused", "unbound-host"} {
		t.Run(context, func(t *testing.T) {
			a := touchUIFixture(t)
			a.preview.editor.insert("a𠀀bc")
			a.preview.editor.anchor, a.preview.editor.cursor = 1, 3
			if context == "CN-composition" || context == "EN-paused" {
				previewAction(t, a.preview, "input", "a", "")
			}
			if context == "EN-paused" {
				previewAction(t, a.preview, "toggle-language", "", "")
				a.s.Original = a.preview.original()
			}
			if context == "unbound-host" {
				a.host = &deliveryGate{current: func() hostTarget { return hostTarget{} }, send: func(hostTarget, tk.Output) error {
					t.Fatal("spare key emitted host input")
					return nil
				}}
			}
			a.navSelecting = true
			a.s.Shift, a.s.Ctrl, a.s.Alt = true, true, true
			beforeState := localKeyState(a.s)
			beforeSnapshot, _ := json.Marshal(a.preview.snapshot)
			sequence, accepted := a.preview.sequence, a.acceptedInputSerial
			clicks := countKeyClicks(a, true)
			for i := 1; i <= 3; i++ {
				r := touchToolbarKeyRect(t, a, fmt.Sprintf("TU-SPARE-%d", i))
				x, y := (r.L+r.R)/2, (r.T+r.B)/2
				action, area, blocked := a.touchUIActionAt(x, y)
				if action != "" || !blocked || area != r {
					t.Fatal("reserved control is not blocked before dispatch", action, area, blocked)
				}
				a.down(uint32(i), x, y)
				a.up(uint32(i), x, y)
				a.up(uint32(i), x, y)
			}
			afterSnapshot, _ := json.Marshal(a.preview.snapshot)
			if string(beforeSnapshot) != string(afterSnapshot) || a.preview.sequence != sequence || a.preview.fault || a.acceptedInputSerial != accepted || *clicks != 0 {
				t.Fatal("spare key dispatched, changed candidates/fault state or sounded")
			}
			if !a.navSelecting || a.preview.editor.anchor != 1 || a.preview.editor.cursor != 3 || string(a.preview.editor.text) != "a𠀀bc" || !reflect.DeepEqual(beforeState, localKeyState(a.s)) || len(a.previewTouches) != 0 {
				t.Fatal("spare key changed selection, modifiers, text or touch state")
			}
		})
	}
}

func TestTouchToolbarBackspaceEditsCompleteRunesAndSelection(t *testing.T) {
	a := touchUIFixture(t)
	a.preview.editor.insert("a𠀀b")
	a.preview.editor.cursor, a.preview.editor.anchor = 2, 2
	tapTouchControl(t, a, "Backspace")
	if string(a.preview.editor.text) != "ab" || a.preview.editor.cursor != 1 || a.preview.editor.anchor != 1 {
		t.Fatal("toolbar backspace did not remove exactly one Unicode rune", a.preview.editor)
	}
	a.preview.editor = previewEditor{}
	a.preview.editor.insert("a𠀀bc")
	a.preview.editor.cursor, a.preview.editor.anchor = 3, 1
	a.navSelecting = true
	tapTouchControl(t, a, "Backspace")
	if string(a.preview.editor.text) != "ac" || a.preview.editor.cursor != 1 || a.preview.editor.anchor != 1 {
		t.Fatal("toolbar backspace did not consume the selection", a.preview.editor)
	}
}

func TestTouchToolbarBackspaceRejectsCompositionAndOldGestures(t *testing.T) {
	for _, paused := range []bool{false, true} {
		t.Run(fmt.Sprintf("paused_%v", paused), func(t *testing.T) {
			a := touchUIFixture(t)
			a.preview.editor.insert("keep")
			previewAction(t, a.preview, "input", "a", "")
			if paused {
				previewAction(t, a.preview, "toggle-language", "", "")
			}
			before, _ := json.Marshal(a.preview.snapshot)
			clicks := countKeyClicks(a, true)
			tapTouchControl(t, a, "Backspace")
			after, _ := json.Marshal(a.preview.snapshot)
			if string(before) != string(after) || string(a.preview.editor.text) != "keep" || *clicks != 0 {
				t.Fatal("toolbar backspace edited active/paused composition or confirmed text")
			}
		})
	}
	a := touchUIFixture(t)
	a.preview.editor.insert("abcd")
	r := touchToolbarKeyRect(t, a, "TU-BACKSPACE")
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	clicks := countKeyClicks(a, true)
	a.down(1, x, y)
	previewAction(t, a.preview, "clear", "", "") // New revision makes the pending edit stale.
	a.up(1, x, y)
	a.down(2, x, y)
	a.move(2, r.R, y)
	a.move(2, x, y)
	a.up(2, x, y)
	if string(a.preview.editor.text) != "abcd" || *clicks != 0 {
		t.Fatal("stale or moved-out backspace executed")
	}
	a.down(3, x, y)
	a.up(3, x, y)
	a.up(3, x, y)
	if string(a.preview.editor.text) != "abc" || *clicks != 1 {
		t.Fatal("fresh backspace did not execute exactly once")
	}
}

func TestTouchToolbarBackspaceUsesBoundHostWithoutStickyModifiers(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	current := hostTarget{1, 2, 3, 4}
	var outputs []tk.Output
	makeHost := func(a *ui) {
		a.host = &deliveryGate{current: func() hostTarget { return current }, send: func(_ hostTarget, o tk.Output) error {
			outputs = append(outputs, o)
			return nil
		}}
	}
	unbound := touchUIFixture(t)
	makeHost(unbound)
	tapTouchControl(t, unbound, "Backspace")
	if len(outputs) != 0 {
		t.Fatal("unbound toolbar backspace sent input")
	}
	a := touchUIFixture(t)
	makeHost(a)
	if err := a.host.bind(current); err != nil {
		t.Fatal(err)
	}
	a.s.Shift, a.s.Ctrl, a.s.Alt = true, true, true
	a.navSelecting = true
	r := touchToolbarKeyRect(t, a, "TU-BACKSPACE")
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(1, x, y)
	if a.s.Held("Shift") || a.s.Held("Ctrl") || a.s.Held("Alt") {
		t.Fatal("toolbar backspace retained virtual modifiers")
	}
	a.up(1, x, y)
	a.up(1, x, y)
	if len(outputs) != 1 || outputs[0].Key != "Backspace" || outputs[0].Shift || outputs[0].Ctrl || outputs[0].Alt || outputs[0].Text != "" || len(a.host.seen) != 1 {
		t.Fatal("host backspace was not one plain gated edit", outputs)
	}
	a.down(2, x, y)
	a.loseHostFocus("fixture focus loss")
	a.up(2, x, y)
	if len(outputs) != 1 {
		t.Fatal("old-focus toolbar backspace reached the host")
	}
}
