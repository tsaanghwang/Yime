//go:build windows

package main

import (
	"strings"
	"syscall"
	"unsafe"
)

const (
	idDlgPhrase = 301
	idDlgOK     = 1
	idDlgCancel = 2

	swShowNormal = 1
)

type openFilename struct {
	StructSize      uint32
	Owner           syscall.Handle
	Instance        syscall.Handle
	Filter          *uint16
	CustomFilter    *uint16
	MaxCustomFilter uint32
	FilterIndex     uint32
	File            *uint16
	MaxFile         uint32
	FileTitle       *uint16
	MaxFileTitle    uint32
	InitialDir      *uint16
	Title           *uint16
	Flags           uint32
	FileOffset      uint16
	FileExtension   uint16
	DefExt          *uint16
	CustData        uintptr
	Hook            uintptr
	TemplateName    *uint16
	PvReserved      uintptr
	DwReserved      uint32
	FlagsEx         uint32
}

var (
	procDestroyWindow = moduser32.NewProc("DestroyWindow")
	procEnableWindow  = moduser32.NewProc("EnableWindow")
	procShowWindow    = moduser32.NewProc("ShowWindow")
	procGetDlgItem    = moduser32.NewProc("GetDlgItem")
)

func findDlgItem(parent syscall.Handle, id int) syscall.Handle {
	hwnd, _, _ := procGetDlgItem.Call(uintptr(parent), uintptr(id))
	return syscall.Handle(hwnd)
}

func showPhraseDialog(owner syscall.Handle, initial, title, okText string) (string, bool) {
	phrase := ""
	accepted := showModalForm(owner, title, 420, 180, func(hwnd syscall.Handle) {
		createStatic(hwnd, "要屏蔽的词条", rect{16, 18, 380, 36}, 0)
		edit := createEdit(hwnd, rect{16, 40, 388, 66}, idDlgPhrase)
		setWindowText(edit, initial)
		createButton(hwnd, okText, rect{220, 96, 298, 124}, idDlgOK)
		createButton(hwnd, "取消", rect{308, 96, 386, 124}, idDlgCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		if id != idDlgOK {
			return false
		}
		phrase = strings.TrimSpace(getWindowText(findDlgItem(hwnd, idDlgPhrase)))
		if phrase == "" {
			showMessageBox("请输入要屏蔽的词条。", 0x10)
			return false
		}
		return true
	})
	return phrase, accepted
}

func showOpenFileDialog(owner syscall.Handle, initialDir, filter string) (string, bool) {
	buf := make([]uint16, 260)
	instance, _, _ := procGetModuleHandleW.Call(0)
	dirPtr, _ := syscall.UTF16PtrFromString(initialDir)
	filterPtr, _ := syscall.UTF16PtrFromString(filter)
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Instance:   syscall.Handle(instance),
		Filter:     filterPtr,
		File:       &buf[0],
		MaxFile:    uint32(len(buf)),
		InitialDir: dirPtr,
		Title:      utf16Ptr("导入屏蔽词"),
		Flags:      0x00080000 | 0x00001000 | 0x00000800,
	}
	ret, _, _ := procGetOpenFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ret == 0 {
		return "", false
	}
	return syscall.UTF16ToString(buf), true
}

func showSaveFileDialog(owner syscall.Handle, defaultName, filter string) (string, bool) {
	buf := utf16FromString(defaultName)
	if len(buf) < 260 {
		padded := make([]uint16, 260)
		copy(padded, buf)
		buf = padded
	}
	filterPtr, _ := syscall.UTF16PtrFromString(filter)
	instance, _, _ := procGetModuleHandleW.Call(0)
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Instance:   syscall.Handle(instance),
		Filter:     filterPtr,
		File:       &buf[0],
		MaxFile:    uint32(len(buf)),
		Title:      utf16Ptr("导出屏蔽词"),
		Flags:      0x00080000 | 0x00000002 | 0x00001000,
	}
	ret, _, _ := procGetSaveFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ret == 0 {
		return "", false
	}
	return syscall.UTF16ToString(buf), true
}

func showModalForm(owner syscall.Handle, title string, width, height int32, build func(hwnd syscall.Handle), onCommand func(hwnd syscall.Handle, id int) bool) bool {
	accepted := false
	modalClosed := false
	className, _ := syscall.UTF16PtrFromString("YimeBlocklistModal")
	instance, _, _ := procGetModuleHandleW.Call(0)
	modalProc := syscall.NewCallback(func(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
		switch msg {
		case 0x0111:
			id := int(wParam & 0xffff)
			if id == idDlgCancel {
				procDestroyWindow.Call(uintptr(hwnd))
				return 0
			}
			if onCommand(hwnd, id) {
				accepted = true
				procDestroyWindow.Call(uintptr(hwnd))
			}
			return 0
		case 0x0002:
			modalClosed = true
			return 0
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
		return ret
	})
	wndClass := wndclassex{
		Size:      uint32(unsafe.Sizeof(wndclassex{})),
		WndProc:   modalProc,
		Instance:  syscall.Handle(instance),
		ClassName: className,
	}
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wndClass)))

	titlePtr, _ := syscall.UTF16PtrFromString(title)
	winW, winH := windowSizeForClient(width, height)
	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(wsExControlparent|wsExAppwindow),
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(titlePtr)),
		uintptr(wsOverlappedwindow&^0x00040000),
		0, 0, uintptr(winW), uintptr(winH),
		uintptr(owner), 0, instance, 0,
	)
	dlg := syscall.Handle(hwnd)
	build(dlg)
	procEnableWindow.Call(uintptr(owner), 0)
	procShowWindow.Call(uintptr(dlg), swShowNormal)

	var message winMsg
	for !modalClosed {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		if uintptr(message.Hwnd) == uintptr(dlg) || isChildOf(dlg, message.Hwnd) {
			procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
		}
	}
	procEnableWindow.Call(uintptr(owner), 1)
	return accepted
}

func isChildOf(parent, child syscall.Handle) bool {
	procGetParent := moduser32.NewProc("GetParent")
	current := child
	for current != 0 {
		if current == parent {
			return true
		}
		next, _, _ := procGetParent.Call(uintptr(current))
		current = syscall.Handle(next)
	}
	return false
}

func utf16Ptr(value string) *uint16 {
	ptr, _ := syscall.UTF16PtrFromString(value)
	return ptr
}

func utf16FromString(value string) []uint16 {
	data, _ := syscall.UTF16FromString(value)
	return data
}
