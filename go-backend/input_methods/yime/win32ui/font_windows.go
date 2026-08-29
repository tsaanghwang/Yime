//go:build windows

package win32ui

import (
	"sync"
	"syscall"
	"unsafe"
)

const (
	defaultGUIFont       = 17
	wmSetfont            = 0x0030
	DefaultGUIFontFamily = "Microsoft YaHei UI"
)

var (
	modGDI32            = syscall.NewLazyDLL("gdi32.dll")
	procCreateFontW     = modGDI32.NewProc("CreateFontW")
	procGetTextExtentW  = modGDI32.NewProc("GetTextExtentPoint32W")
	procGetStockObject  = modGDI32.NewProc("GetStockObject")
	procSelectObject    = modGDI32.NewProc("SelectObject")
	procGetTextDC       = modUser32.NewProc("GetDC")
	procReleaseTextDC   = modUser32.NewProc("ReleaseDC")
	procSendMessageFont = modUser32.NewProc("SendMessageW")
	sharedGUIFontOnce   sync.Once
	sharedGUIFont       uintptr
	sharedIconFontOnce  sync.Once
	sharedIconFont      uintptr
)

type textExtent struct {
	Width  int32
	Height int32
}

func sharedDefaultGUIFont() uintptr {
	sharedGUIFontOnce.Do(func() {
		family, _ := syscall.UTF16PtrFromString(DefaultGUIFontFamily)
		height := int32(-12)
		sharedGUIFont, _, _ = procCreateFontW.Call(
			uintptr(height), 0, 0, 0, 400, 0, 0, 0,
			1, 0, 0, 5, 0, uintptr(unsafe.Pointer(family)),
		)
		if sharedGUIFont == 0 {
			sharedGUIFont, _, _ = procGetStockObject.Call(defaultGUIFont)
		}
	})
	return sharedGUIFont
}

// ApplyDefaultGUIFont gives a raw Win32 child control the same normal-weight
// GUI font family used by all Yime desktop tools instead of the legacy system font.
// The process-lifetime shared font must not be deleted by child controls.
func ApplyDefaultGUIFont(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	font := sharedDefaultGUIFont()
	if font == 0 {
		return
	}
	procSendMessageFont.Call(uintptr(hwnd), wmSetfont, font, 1)
}

// MeasureDefaultGUITextWidth returns the rendered pixel width of text in the
// same font used by Yime's native controls. The fallback keeps layout usable
// if a display DC is temporarily unavailable.
func MeasureDefaultGUITextWidth(text string) int32 {
	data, err := syscall.UTF16FromString(text)
	if err != nil || len(data) <= 1 {
		return int32(len([]rune(text))) * 14
	}
	dc, _, _ := procGetTextDC.Call(0)
	if dc == 0 {
		return int32(len([]rune(text))) * 14
	}
	defer procReleaseTextDC.Call(0, dc)

	font := sharedDefaultGUIFont()
	oldFont := uintptr(0)
	if font != 0 {
		oldFont, _, _ = procSelectObject.Call(dc, font)
		if oldFont != 0 {
			defer procSelectObject.Call(dc, oldFont)
		}
	}

	size := textExtent{}
	ret, _, _ := procGetTextExtentW.Call(
		dc,
		uintptr(unsafe.Pointer(&data[0])),
		uintptr(len(data)-1),
		uintptr(unsafe.Pointer(&size)),
	)
	if ret == 0 || size.Width <= 0 {
		return int32(len([]rune(text))) * 14
	}
	return size.Width
}

// ApplyFluentIconFont renders toolbar glyphs from the icon font shipped with
// supported Windows versions. The font is shared for the process lifetime.
func ApplyFluentIconFont(hwnd syscall.Handle) {
	if hwnd == 0 {
		return
	}
	sharedIconFontOnce.Do(func() {
		family, _ := syscall.UTF16PtrFromString("Segoe Fluent Icons")
		height := int32(-16)
		sharedIconFont, _, _ = procCreateFontW.Call(
			uintptr(height), 0, 0, 0, 400, 0, 0, 0,
			1, 0, 0, 5, 0, uintptr(unsafe.Pointer(family)),
		)
	})
	if sharedIconFont != 0 {
		procSendMessageFont.Call(uintptr(hwnd), wmSetfont, sharedIconFont, 1)
	}
}
