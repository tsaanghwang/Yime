//go:build windows && (amd64 || arm64)

package main

import (
	"errors"
	"fmt"
	"reflect"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func navigationPoint(t *testing.T, a *ui, key string) (int32, int32) {
	t.Helper()
	for _, b := range navigationButtons {
		if b.action == key {
			r := a.navigationRect(b)
			return (r.L + r.R) / 2, (r.T + r.B) / 2
		}
	}
	t.Fatal("unknown auxiliary button", key)
	return 0, 0
}

func TestNavigationCancellationDuringHostMessagePumps(t *testing.T) {
	for _, message := range []uint32{0x001F, 0x0215} { // WM_CANCELMODE, unexpected WM_CAPTURECHANGED
		for _, key := range []string{"Home", "select"} {
			t.Run(fmt.Sprintf("%x/up/%s", message, key), func(t *testing.T) {
				runtime.LockOSThread()
				defer runtime.UnlockOSThread()
				a, h, calls := navigationHostFixture(t)
				a.navSelecting = true
				x, y := navigationPoint(t, a, key)
				a.down(1, x, y)
				if ok, _, _ := U("PostMessageW").Call(h, uintptr(message), 0, 0); ok == 0 {
					t.Fatal("queue cancellation")
				}
				a.up(1, x, y)
				assertNavigationCancelled(t, a, calls(), "up", message, key)
			})
		}
		t.Run(fmt.Sprintf("%x/host-sink/Home", message), func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			a, h, calls := navigationHostFixture(t)
			a.navSelecting = true
			x, y := navigationPoint(t, a, "Home")
			a.down(1, x, y)
			queueOnCurrent := true
			a.host.current = func() hostTarget {
				if queueOnCurrent {
					queueOnCurrent = false
					if ok, _, _ := U("PostMessageW").Call(h, uintptr(message), 0, 0); ok == 0 {
						t.Error("queue cancellation during host sink")
					}
				}
				return hostTarget{1, 2, 3, 4}
			}
			a.up(1, x, y)
			assertNavigationCancelled(t, a, calls(), "host sink", message, "Home")
		})
	}
}

func navigationHostFixture(t *testing.T) (*ui, uintptr, func() int) {
	t.Helper()
	a := previewUI(t)
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create message-pump fixture")
	}
	t.Cleanup(func() { U("DestroyWindow").Call(h) })
	index := int32(-4) // GWLP_WNDPROC
	oldProc, _, _ := U("SetWindowLongPtrW").Call(h, uintptr(index), callback)
	if oldProc == 0 {
		t.Fatal("subclass fixture")
	}
	previous := active
	t.Cleanup(func() {
		U("SetWindowLongPtrW").Call(h, uintptr(index), oldProc)
		active = previous
	})
	a.h, active = h, a
	current := hostTarget{1, 2, 3, 4}
	calls := 0
	a.host = &deliveryGate{current: func() hostTarget { return current }, send: func(hostTarget, tk.Output) error {
		calls++
		return nil
	}}
	if err := a.host.bind(current); err != nil {
		t.Fatal(err)
	}
	return a, h, func() int { return calls }
}

func assertNavigationCancelled(t *testing.T, a *ui, sends int, stage string, message uint32, key string) {
	t.Helper()
	if sends != 0 || a.navSelecting || len(a.previewTouches) != 0 {
		t.Fatalf("stage=%s message=%x key=%s: cancelled action survived (sends=%d selection=%v)", stage, message, key, sends, a.navSelecting)
	}
}

func tapNavigation(t *testing.T, a *ui, key string) {
	t.Helper()
	x, y := navigationPoint(t, a, key)
	a.down(80, x, y)
	a.up(80, x, y)
}

func TestNavigationSequentialSelectionAndReplacement(t *testing.T) {
	a := previewUI(t)
	before := a.s.Board
	a.preview.editor.insert("a𠀀bc")
	tapNavigation(t, a, "ArrowLeft")
	if a.preview.editor.cursor != 3 {
		t.Fatal("left must move one code point")
	}
	tapNavigation(t, a, "ArrowRight")
	if a.preview.editor.cursor != 4 {
		t.Fatal("right")
	}
	tapNavigation(t, a, "Home")
	tapNavigation(t, a, "select")
	tapNavigation(t, a, "ArrowRight")
	tapNavigation(t, a, "ArrowRight")
	if l, r := a.preview.editor.bounds(); l != 0 || r != 2 {
		t.Fatal("single-contact selection", l, r)
	}
	tapNavigation(t, a, "ArrowLeft")
	if l, r := a.preview.editor.bounds(); l != 0 || r != 1 {
		t.Fatal("selection shrink", l, r)
	}
	tapNavigation(t, a, "End")
	if l, r := a.preview.editor.bounds(); l != 0 || r != 4 {
		t.Fatal("select End", l, r)
	}
	tapNavigation(t, a, "Home")
	if a.preview.editor.cursor != 0 || a.preview.editor.anchor != 0 {
		t.Fatal("select Home")
	}
	tapNavigation(t, a, "End")
	tapNavigation(t, a, "select") // Turning off the latch does not destroy the selection.
	if l, r := a.preview.editor.bounds(); l != 0 || r != 4 {
		t.Fatal("toggle mutated text selection")
	}
	tapNavigation(t, a, "ArrowLeft")
	if a.preview.editor.cursor != 0 || a.preview.editor.anchor != 0 {
		t.Fatal("plain left must collapse selection")
	}
	tapNavigation(t, a, "select")
	tapNavigation(t, a, "End")
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "backspace" })
	a.down(1, x, y)
	a.up(1, x, y)
	if len(a.preview.editor.text) != 0 || a.navSelecting {
		t.Fatal("selection deletion or latch leaked")
	}
	previewAction(t, a.preview, "toggle-language", "", "")
	a.s.Original = a.preview.original()
	a.preview.editor.insert("abc")
	tapNavigation(t, a, "Home")
	tapNavigation(t, a, "select")
	tapNavigation(t, a, "End")
	x, y = previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "x" })
	a.down(1, x, y)
	a.up(1, x, y)
	if string(a.preview.editor.text) != "x" || a.navSelecting || a.s.Held("Shift") {
		t.Fatal("replacement did not consume selection or inherited Shift")
	}
	if !reflect.DeepEqual(before, a.s.Board) || a.top != 300 || len(a.s.Board.Keys) != 100 || a.s.Board.Bounds.Width != 18 {
		t.Fatal("auxiliary controls changed board geometry, identity or colors")
	}
}

func TestNavigationNativeTouchAndPenCompatibleMouseRouting(t *testing.T) {
	a := previewUI(t)
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create hidden routing fixture")
	}
	defer U("DestroyWindow").Call(h)
	a.h = h
	previous := active
	active = a
	defer func() { active = previous }()
	a.preview.editor.insert("abc")
	// Inject WM_TOUCH records through the same reader/coordinate path as fingers.
	for _, key := range []string{"Home", "select", "ArrowRight"} {
		x, y := navigationPoint(t, a, key)
		p := point{x, y}
		U("ClientToScreen").Call(h, uintptr(unsafe.Pointer(&p)))
		for _, flags := range []uint32{2, 4} {
			a.touchReader = func(uintptr, uintptr) ([]touch, error) {
				return []touch{{ID: 55, X: p.X * 100, Y: p.Y * 100, Flags: flags}}, nil
			}
			windowProc(h, wmTouch, 1, 99)
		}
	}
	if l, r := a.preview.editor.bounds(); l != 0 || r != 1 || !a.navSelecting {
		t.Fatal("native touch navigation", l, r)
	}
	// Pen-promoted mouse uses this route. These are simulated messages, not pen evidence.
	x, y := navigationPoint(t, a, "End")
	lparam := uintptr(uint32(x) | uint32(y)<<16)
	windowProc(h, 0x0201, 0, lparam)
	windowProc(h, 0x0202, 0, lparam)
	if l, r := a.preview.editor.bounds(); l != 0 || r != 3 || !a.navSelecting {
		t.Fatal("mouse/pen-compatible selection", l, r)
	}
	windowProc(h, 0x0215, 0, 0) // unexpected capture loss
	if a.navSelecting {
		t.Fatal("capture loss retained selection latch")
	}
}

func TestNavigationContactCancellationAndModifiers(t *testing.T) {
	for _, key := range []string{"ArrowLeft", "ArrowRight", "Home", "End", "select"} {
		t.Run(key, func(t *testing.T) {
			a := previewUI(t)
			a.preview.editor.insert("abcd")
			x, y := navigationPoint(t, a, key)
			a.s.Shift, a.s.Ctrl, a.s.Alt = true, true, true
			a.down(1, x, y)
			if a.s.Held("Shift") || a.s.Held("Ctrl") || a.s.Held("Alt") {
				t.Fatal("virtual modifiers leaked into auxiliary action")
			}
			if a.preview.editor.cursor != 4 || a.navSelecting {
				t.Fatal("DOWN executed action")
			}
			a.move(1, x, 291)
			a.move(1, x, y)
			a.up(1, x, y)
			if a.preview.editor.cursor != 4 || a.navSelecting {
				t.Fatal("out/back executed action")
			}
			a.down(1, x, y)
			a.cancel()
			a.up(1, x, y)
			if a.preview.editor.cursor != 4 || a.navSelecting {
				t.Fatal("cancel executed action")
			}
			a.down(1, x, y)
			a.up(1, x, y)
			cursor, selecting := a.preview.editor.cursor, a.navSelecting
			a.up(1, x, y)
			if a.preview.editor.cursor != cursor || a.navSelecting != selecting {
				t.Fatal("duplicate UP executed action")
			}
		})
	}
}

func TestNavigationRejectsCompositionStaleStateAndOverlap(t *testing.T) {
	a := previewUI(t)
	a.preview.editor.insert("abcd")
	for _, english := range []bool{false, true} {
		previewAction(t, a.preview, "input", "a", "")
		if english {
			previewAction(t, a.preview, "toggle-language", "", "")
		}
		for _, key := range []string{"ArrowLeft", "Home", "End", "select"} {
			tapNavigation(t, a, key)
			if a.preview.editor.cursor != 4 || a.navSelecting || a.preview.snapshot.State.RawInput != "a" {
				t.Fatal("navigation changed active/paused composition")
			}
			if err := a.preview.navigate("Home", false, a.preview.stamp()); err == nil {
				t.Fatal("controller allowed composition navigation")
			}
		}
		previewAction(t, a.preview, "clear", "", "")
	}
	x, y := navigationPoint(t, a, "Home")
	a.down(1, x, y)
	previewAction(t, a.preview, "clear", "", "") // advance revision without writing text
	a.up(1, x, y)
	if a.preview.editor.cursor != 4 {
		t.Fatal("stale navigation executed")
	}
	// A subsequent key contact cancels the pending navigation and vice versa.
	kx, ky := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(1, x, y)
	a.down(2, kx, ky)
	a.up(2, kx, ky)
	a.up(1, x, y)
	if string(a.preview.editor.text) != "abcda" || a.preview.editor.cursor != 5 {
		t.Fatal("overlap edited wrong position")
	}
	a.down(2, kx, ky)
	tapNavigation(t, a, "Home")
	a.up(2, kx, ky)
	if string(a.preview.editor.text) != "abcda" || a.preview.editor.cursor != 0 {
		t.Fatal("late character followed navigation")
	}
	tapNavigation(t, a, "select")
	a.down(2, kx, ky)
	a.up(2, kx, ky)
	if a.navSelecting || string(a.preview.editor.text) != "aabcda" {
		t.Fatal("selection latch affected character")
	}
}

func TestNavigationHostDeliveryUsesExistingGate(t *testing.T) {
	a := previewUI(t)
	current := hostTarget{1, 2, 3, 4}
	var outputs []tk.Output
	a.host = &deliveryGate{current: func() hostTarget { return current }, send: func(_ hostTarget, o tk.Output) error { outputs = append(outputs, o); return nil }}
	if err := a.host.bind(current); err != nil {
		t.Fatal(err)
	}
	for _, extend := range []bool{false, true} {
		if extend {
			tapNavigation(t, a, "select")
		}
		for _, key := range []string{"ArrowLeft", "ArrowRight", "Home", "End"} {
			tapNavigation(t, a, key)
			if got := outputs[len(outputs)-1]; got.Key != key || got.Shift != extend || got.Ctrl || got.Alt || got.Text != "" {
				t.Fatal("incorrect navigation event", got)
			}
		}
	}
	if len(outputs) != 8 || len(a.host.seen) != 8 {
		t.Fatal("toggle sent OS input or missing unique event identity")
	}
	x, y := navigationPoint(t, a, "Home")
	a.down(1, x, y)
	a.loseHostFocus("test away and back")
	a.up(1, x, y)
	if len(outputs) != 8 || a.navSelecting {
		t.Fatal("old focus navigation survived")
	}
	tapNavigation(t, a, "End")
	if len(outputs) != 8 {
		t.Fatal("unbound navigation sent")
	}
}

func TestNavigationHostFailedSendStopsWithoutReplay(t *testing.T) {
	a := previewUI(t)
	current := hostTarget{1, 2, 3, 4}
	calls := 0
	a.host = &deliveryGate{current: func() hostTarget { return current }, send: func(_ hostTarget, o tk.Output) error {
		calls++
		if o.Key != "Home" || !o.Shift {
			t.Fatal("wrong selected navigation")
		}
		return errors.New("injected partial or unknown send")
	}}
	if err := a.host.bind(current); err != nil {
		t.Fatal(err)
	}
	tapNavigation(t, a, "select")
	tapNavigation(t, a, "Home")
	tapNavigation(t, a, "Home")
	if calls != 1 || !a.preview.fault || !a.host.blocked || a.navSelecting {
		t.Fatal("failed navigation replayed or retained latch")
	}
}

func TestNavigationHitRegionsStayOutsideBoardAndOutput(t *testing.T) {
	a := previewUI(t)
	for _, ppm := range []float64{2.5, 3, 4.28, 5} {
		a.ppm = ppm
		last := int32(14)
		for _, b := range navigationButtons {
			r := a.navigationRect(b)
			if r.L <= last || r.R > a.previewWidth()-10 || r.T < 240 || r.B >= int32(a.top) {
				t.Fatal("overlap or clipped control", r)
			}
			last = r.R
			if key, _ := a.navigationAt((r.L+r.R)/2, (r.T+r.B)/2); key != b.action {
				t.Fatal("paint/hit mismatch")
			}
			if key, _ := a.navigationAt(r.R, r.B); key != "" {
				t.Fatal("outside painted control is active")
			}
		}
	}
}
