//go:build windows

package win32ui

import (
	"syscall"
)

const (
	defaultGUIFont = 17
	wmSetfont      = 0x0030
)

var (
	modGDI32            = syscall.NewLazyDLL("gdi32.dll")
	procGetStockObject  = modGDI32.NewProc("GetStockObject")
	procSendMessageFont = modUser32.NewProc("SendMessageW")
)

// ApplyDefaultGUIFont gives a raw Win32 child control the same normal-weight
// GUI font family used by standard Windows UI instead of the legacy system font.
// The returned stock font is owned by Windows and must not be deleted.
func ApplyDefaultGUIFont(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	font, _, _ := procGetStockObject.Call(defaultGUIFont)
	if font == 0 {
		return
	}
	procSendMessageFont.Call(uintptr(hwnd), wmSetfont, font, 1)
}
