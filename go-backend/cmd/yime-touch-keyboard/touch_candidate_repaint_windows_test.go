//go:build windows && (amd64 || arm64)

package main

import (
	"runtime"
	"testing"
	"unsafe"
)

func TestTouchCandidateMouseMoveRepaintsCancelledPress(t *testing.T) {
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	a := touchUIFixture(t)
	a.top = a.touchHeaderLayout().height
	instance, _, _ := k32.NewProc("GetModuleHandleW").Call(0)
	c := wc{Proc: callback, Instance: instance, Name: str("YimeCandidateRepaintRegression")}
	c.Size = uint32(unsafe.Sizeof(c))
	if atom, _, err := U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&c))); atom == 0 {
		t.Fatal("register candidate repaint fixture", err)
	}
	t.Cleanup(func() { U("UnregisterClassW").Call(ptr(c.Name), instance) })
	// Use an owned, nonactivating test surface: Windows can discard the update
	// region of a hidden window before GetUpdateRect can observe invalidation.
	h, _, err := U("CreateWindowExW").Call(0x08000080, ptr(c.Name), ptr(str("Candidate repaint fixture")), 0x80000000, 0, 0, 400, 180, 0, 0, instance, 0)
	if h == 0 {
		t.Fatal("create candidate repaint fixture", err)
	}
	previous := active
	a.h, active = h, a
	t.Cleanup(func() {
		active, a.h = previous, 0 // Detach before destruction can post WM_QUIT.
		if ok, _, err := U("DestroyWindow").Call(h); ok == 0 {
			t.Error("destroy candidate repaint fixture on its owning thread", err)
		}
		var m message
		if quit, _, _ := U("PeekMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0x0012, 0x0012, 1); quit != 0 {
			t.Error("candidate repaint fixture teardown posted WM_QUIT")
		}
	})
	previewAction(t, a.preview, "input", "p", "")
	U("ShowWindow").Call(h, 4) // SW_SHOWNOACTIVATE; never bind or send to a user host.
	box := a.candidateRect(0)
	x, y := (box.L+box.R)/2, (box.T+box.B)/2
	a.down(0, x, y)
	if !a.touchCandidatePressed(0, box) {
		t.Fatal("fixture has no pressed candidate")
	}
	U("ValidateRect").Call(h, 0)
	mouseMove := func(x, y int32) {
		l := uintptr(uint32(uint16(x)) | uint32(uint16(y))<<16)
		windowProc(h, 0x0200, 1, l) // WM_MOUSEMOVE / MK_LBUTTON, same promoted-mouse path.
	}
	invalidated := func() bool {
		var update rect
		pending, _, _ := U("GetUpdateRect").Call(h, uintptr(unsafe.Pointer(&update)), 0)
		return pending != 0
	}
	mouseMove(x, y)
	if invalidated() || !a.touchCandidatePressed(0, box) {
		t.Fatal("moving within a candidate should retain its press without extra invalidation")
	}
	mouseMove(box.R, y)
	pressed, pending := a.touchCandidatePressed(0, box), invalidated()
	if pressed || !pending {
		t.Fatalf("leaving a candidate failed to repaint the cancelled press: pressed=%v pending=%v", pressed, pending)
	}
	U("ValidateRect").Call(h, 0)
	mouseMove(x, y)
	if invalidated() || a.touchCandidatePressed(0, box) {
		t.Fatal("returning to a cancelled candidate restored its pressed state")
	}
	a.up(0, x, y)
	if len(a.preview.editor.text) != 0 {
		t.Fatal("cancelled candidate committed on mouse release")
	}
}
