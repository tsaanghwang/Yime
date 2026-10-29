//go:build windows && (amd64 || arm64)

package main

import (
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func penCompatibilityFixture(t *testing.T) (*ui, func()) {
	t.Helper()
	a := previewUI(t)
	previewAction(t, a.preview, "toggle-language", "", "")
	a.s.Original = a.preview.original()
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create pen compatibility fixture")
	}
	index := int32(-4)
	old, _, _ := U("SetWindowLongPtrW").Call(h, uintptr(index), callback)
	if old == 0 {
		U("DestroyWindow").Call(h)
		t.Fatal("subclass fixture")
	}
	previous := active
	a.h, active = h, a
	return a, func() {
		U("SetWindowLongPtrW").Call(h, uintptr(index), old)
		U("DestroyWindow").Call(h)
		active = previous
	}
}

func nativePenFrame(a *ui, id, flags uint32, x, y int32) {
	p := point{x, y}
	U("ClientToScreen").Call(a.h, uintptr(unsafe.Pointer(&p)))
	a.touchReader = func(uintptr, uintptr) ([]touch, error) {
		return []touch{{ID: id, Flags: flags, X: p.X * 100, Y: p.Y * 100}}, nil
	}
	windowProc(a.h, wmTouch, 1, 99)
}

func promotedPenMouse(a *ui, msg uint32, extra uintptr, x, y int32) {
	previous, _, _ := U("SetMessageExtraInfo").Call(extra)
	defer U("SetMessageExtraInfo").Call(previous)
	U("SendMessageW").Call(a.h, uintptr(msg), 0, uintptr(uint32(x)|uint32(y)<<16))
}

func TestNativePenTouchAndPromotedMouseCommitOnlyOnce(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, close := penCompatibilityFixture(t)
	defer close()
	sounds := countKeyClicks(a, true)
	sx, sy := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "shift" })
	ax, ay := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	// Replay the recorded order: WM_TOUCH with PEN|PRIMARY, followed by a
	// pen-tagged mouse DOWN and touch-tagged compatibility mouse UP.
	tap := func(id uint32, x, y int32) {
		nativePenFrame(a, id, 0x5a, x, y)
		promotedPenMouse(a, 0x0201, 0xff515702, x, y)
		capture, _, _ := U("GetCapture").Call()
		if len(a.previewTouches) != 1 || capture != 0 {
			t.Fatalf("duplicate pen path changed gesture/capture: pending=%d capture=%x", len(a.previewTouches), capture)
		}
		nativePenFrame(a, id, 0x54, x, y)
		promotedPenMouse(a, 0x0202, 0xff515782, x, y)
	}
	tap(11, sx, sy)
	if !a.s.Shift {
		t.Fatal("recorded pen sequence lost Shift")
	}
	tap(12, ax, ay)
	tap(13, ax, ay)
	if string(a.preview.editor.text) != "Aa" {
		t.Fatal("pen replay must commit exactly Aa", string(a.preview.editor.text))
	}
	if *sounds != 3 {
		t.Fatal("pen compatibility messages duplicated or lost key sounds", *sounds)
	}
}

func TestNativePenCancellationStillRejectsLateCompatibilityInput(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, close := penCompatibilityFixture(t)
	defer close()
	sounds := countKeyClicks(a, true)
	ax, ay := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	nativePenFrame(a, 21, 0x5a, ax, ay)
	windowProc(a.h, 0x0215, 0, 123) // Genuine unexpected capture loss remains a cancellation.
	promotedPenMouse(a, 0x0201, 0xff515702, ax, ay)
	nativePenFrame(a, 21, 0x54, ax, ay)
	promotedPenMouse(a, 0x0202, 0xff515782, ax, ay)
	if len(a.preview.editor.text) != 0 || len(a.previewTouches) != 0 || a.s.Held("Shift") {
		t.Fatal("late pen compatibility input revived a cancelled contact")
	}
	if *sounds != 0 {
		t.Fatal("cancelled pen contact sounded", *sounds)
	}
}

func TestPenMouseFallbackRemainsAvailableWithoutNativeContact(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, close := penCompatibilityFixture(t)
	defer close()
	sx, sy := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "shift" })
	ax, ay := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	tap := func(x, y int32) {
		promotedPenMouse(a, 0x0201, 0xff515702, x, y)
		promotedPenMouse(a, 0x0202, 0xff515702, x, y)
	}
	tap(sx, sy)
	tap(ax, ay)
	tap(ax, ay)
	if string(a.preview.editor.text) != "Aa" {
		t.Fatal("legacy-only pen route lost", string(a.preview.editor.text))
	}
}
