//go:build windows

package win32ui

import (
	"syscall"
	"time"
	"unsafe"
)

const (
	// ColorWindowBackground is the standard dialog background brush.
	ColorWindowBackground = syscall.Handle(6) // COLOR_WINDOW + 1
	// ClassRedraw asks Windows to repaint the whole client area on resize.
	ClassRedraw = 0x0001 | 0x0002 // CS_VREDRAW | CS_HREDRAW

	// WmDeferredPresent asks a tool window to foreground itself after launch.
	WmDeferredPresent = 0x0400 + 88

	swHide       = 0
	swRestore    = 9
	swShow       = 5
	swShowNormal = 1
	swShowMinimized = 2

	rdwInvalidate  = 0x0001
	rdwErase       = 0x0004
	rdwAllChildren = 0x0080
	rdwUpdateNow   = 0x0100

	swpShowWindow = 0x0040
	swpNomove     = 0x0002
	swpNosize     = 0x0001
)

var (
	modUser32                    = syscall.NewLazyDLL("user32.dll")
	modKernel32                  = syscall.NewLazyDLL("kernel32.dll")
	procRedrawWindow             = modUser32.NewProc("RedrawWindow")
	procShowWindow               = modUser32.NewProc("ShowWindow")
	procUpdateWindow             = modUser32.NewProc("UpdateWindow")
	procSetForegroundWindow      = modUser32.NewProc("SetForegroundWindow")
	procBringWindowToTop         = modUser32.NewProc("BringWindowToTop")
	procIsIconic                 = modUser32.NewProc("IsIconic")
	procFindWindowW              = modUser32.NewProc("FindWindowW")
	procAllowSetForeground       = modUser32.NewProc("AllowSetForegroundWindow")
	procGetForegroundWindow      = modUser32.NewProc("GetForegroundWindow")
	procGetWindowThreadProcessId = modUser32.NewProc("GetWindowThreadProcessId")
	procGetCurrentThreadId       = modKernel32.NewProc("GetCurrentThreadId")
	procAttachThreadInput        = modUser32.NewProc("AttachThreadInput")
	procSetWindowPos             = modUser32.NewProc("SetWindowPos")
	procGetWindowPlacement       = modUser32.NewProc("GetWindowPlacement")
	procSetWindowPlacement       = modUser32.NewProc("SetWindowPlacement")
	procPostMessageW             = modUser32.NewProc("PostMessageW")
)

type windowPlacement struct {
	Length           uint32
	Flags            uint32
	ShowCmd          uint32
	MinPosition      struct{ X, Y int32 }
	MaxPosition      struct{ X, Y int32 }
	NormalPosition   struct{ Left, Top, Right, Bottom int32 }
	Device           struct{ Left, Top, Right, Bottom int32 }
}

// AllowNextForegroundWindow lets the next launched process take foreground (ASFW_ANY).
func AllowNextForegroundWindow() {
	procAllowSetForeground.Call(^uintptr(0))
}

// ActivateExistingWindow foregrounds an already-running tool window with the given class name.
// It returns true when a matching window was found and activated.
func ActivateExistingWindow(className string) bool {
	classPtr, err := syscall.UTF16PtrFromString(className)
	if err != nil {
		return false
	}
	hwnd, _, _ := procFindWindowW.Call(uintptr(unsafe.Pointer(classPtr)), 0)
	if hwnd == 0 {
		return false
	}
	PresentMainWindow(syscall.Handle(hwnd))
	return true
}

// PresentMainWindowAfterLaunch shows a newly launched tool and schedules follow-up foreground attempts.
func PresentMainWindowAfterLaunch(hwnd syscall.Handle) {
	PresentMainWindow(hwnd)
	RequestDeferredPresent(hwnd)
}

// RequestDeferredPresent schedules follow-up foreground attempts after detached launch.
func RequestDeferredPresent(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	h := uintptr(hwnd)
	post := func() {
		procPostMessageW.Call(h, uintptr(WmDeferredPresent), 0, 0)
	}
	time.AfterFunc(80*time.Millisecond, post)
	time.AfterFunc(320*time.Millisecond, post)
}

// IsDeferredPresentMessage reports the custom deferred-present message.
func IsDeferredPresentMessage(message uint32) bool {
	return message == WmDeferredPresent
}

// RedrawChildrenNow forces an immediate paint of the window and all child controls.
func RedrawChildrenNow(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	flags := uintptr(rdwInvalidate | rdwErase | rdwAllChildren | rdwUpdateNow)
	procRedrawWindow.Call(uintptr(hwnd), 0, 0, flags)
}

// PresentMainWindow restores, shows, and foregrounds a tool window after controls are created.
func PresentMainWindow(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	h := uintptr(hwnd)

	var placement windowPlacement
	placement.Length = uint32(unsafe.Sizeof(placement))
	if ret, _, _ := procGetWindowPlacement.Call(h, uintptr(unsafe.Pointer(&placement))); ret != 0 {
		if placement.ShowCmd == swShowMinimized || placement.ShowCmd == swHide {
			placement.ShowCmd = swShowNormal
			procSetWindowPlacement.Call(h, uintptr(unsafe.Pointer(&placement)))
		}
	}

	if iconic, _, _ := procIsIconic.Call(h); iconic != 0 {
		procShowWindow.Call(h, swRestore)
	}

	RedrawChildrenNow(hwnd)
	procShowWindow.Call(h, swShowNormal)
	procShowWindow.Call(h, swShow)
	procSetWindowPos.Call(h, 0, 0, 0, 0, 0, uintptr(swpNomove|swpNosize|swpShowWindow))
	forceForegroundWindow(h)
	RedrawChildrenNow(hwnd)
	procUpdateWindow.Call(h)
}

func forceForegroundWindow(hwnd uintptr) {
	fgWnd, _, _ := procGetForegroundWindow.Call()
	if fgWnd == 0 {
		procSetForegroundWindow.Call(hwnd)
		procBringWindowToTop.Call(hwnd)
		return
	}

	var fgPID uint32
	fgTID, _, _ := procGetWindowThreadProcessId.Call(fgWnd, uintptr(unsafe.Pointer(&fgPID)))
	curTID, _, _ := procGetCurrentThreadId.Call()
	if fgTID != 0 && fgTID != curTID {
		procAttachThreadInput.Call(curTID, fgTID, 1)
		procSetForegroundWindow.Call(hwnd)
		procBringWindowToTop.Call(hwnd)
		procAttachThreadInput.Call(curTID, fgTID, 0)
		return
	}
	procSetForegroundWindow.Call(hwnd)
	procBringWindowToTop.Call(hwnd)
}

// IsActivateMessage reports whether WM_ACTIVATE is activating this window.
func IsActivateMessage(wParam uintptr) bool {
	return int32(wParam&0xFFFF) != 0
}
