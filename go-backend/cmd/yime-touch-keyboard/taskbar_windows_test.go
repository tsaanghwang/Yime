//go:build windows && (amd64 || arm64)

package main

import (
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestTaskbarMinimizeRestoreAndCancellation(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	instance, _, _ := k32.NewProc("GetModuleHandleW").Call(0)
	c := wc{Proc: callback, Instance: instance, Name: str("YimeTaskbarRegression")}
	c.Size = uint32(unsafe.Sizeof(c))
	U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&c)))
	for _, route := range []string{"toolbar", "hotkey", "system-menu"} {
		t.Run(route, func(t *testing.T) {
			a := previewUI(t)
			h, _, err := U("CreateWindowExW").Call(keyboardWindowExStyle, ptr(c.Name), ptr(str("Disposable taskbar regression")), keyboardWindowStyle, 50, 50, 600, 350, 0, 0, instance, 0)
			if h == 0 {
				t.Fatal(err)
			}
			previous := active
			a.h, active = h, a
			defer func() { U("DestroyWindow").Call(h); active = previous }()
			U("ShowWindow").Call(h, 4)
			index := int32(-20) // GWL_EXSTYLE
			style, _, _ := U("GetWindowLongPtrW").Call(h, uintptr(index))
			if style&0x00040000 == 0 || style&0x80 != 0 || style&0x08000000 == 0 {
				t.Fatalf("missing taskbar/noactivate style or still a tool window: %x", style)
			}
			a.preview.editor.insert("confirmed")
			previewAction(t, a.preview, "input", "a", "")
			if a.preview.snapshot.State.RawInput == "" {
				t.Fatal("fixture has no composition")
			}
			if route == "hotkey" { // A paused composition must also be cancelled.
				previewAction(t, a.preview, "toggle-language", "", "")
			}
			a.s.Shift, a.navSelecting = true, true
			a.previewTouches = map[uint32]*previewGesture{99: {action: "candidate"}}
			switch route {
			case "toolbar":
				a.toolbar(300, 40)
			case "hotkey":
				windowProc(h, 0x0312, 0, 0)
			case "system-menu":
				U("SendMessageW").Call(h, 0x0112, 0xf020, 0)
			}
			iconic, _, _ := U("IsIconic").Call(h)
			visible, _, _ := U("IsWindowVisible").Call(h)
			if iconic == 0 || visible == 0 {
				t.Fatal("window disappeared instead of minimizing")
			}
			if a.preview.snapshot.State.RawInput != "" || a.s.Held("Shift") || a.navSelecting || len(a.previewTouches) != 0 || string(a.preview.editor.text) != "confirmed" {
				t.Fatal("minimize retained unconfirmed state or changed confirmed text")
			}
			if route == "hotkey" {
				windowProc(h, 0x0312, 0, 0)
			} else {
				U("SendMessageW").Call(h, 0x0112, 0xf120, 0) // Same restore command as the taskbar.
			}
			iconic, _, _ = U("IsIconic").Call(h)
			if iconic != 0 {
				t.Fatal("restore did not restore the same window")
			}
		})
	}
}

func TestMinimizeInvalidatesHostTicket(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, _, calls := navigationHostFixture(t)
	ticket := a.host.ticket()
	a.suspendForMinimize()
	if a.host.valid(ticket) || !a.preview.fault || calls() != 0 {
		t.Fatal("minimize kept the old target bound or sent input")
	}
	if err := a.host.deliver(ticket, "late-confirm", tk.Output{Text: "must-not-send"}); err == nil || calls() != 0 {
		t.Fatal("late commit survived minimization")
	}
}
