//go:build windows

package main

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
)

const (
	idDlgPhrase = 301
	idDlgPinyin = 302
	idDlgWeight = 303
	idDlgOK     = 1
	idDlgCancel = 2

	idWeightValue = 401
	idWeightOK    = 1
	idWeightCancel = 2

	idImportList = 501
	idImportOK   = 1
	idImportCancel = 2
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
	PvReserved0     uintptr
	PvReserved1     uintptr
	FlagsEx         uint32
}

func showEntryDialog(owner syscall.Handle, initial userlexicon.Entry, title, okText string) (userlexicon.Entry, bool) {
	result := userlexicon.Entry{}
	accepted := showModalForm(owner, title, 460, 302, func(hwnd syscall.Handle) {
		createStatic(hwnd, "词条汉字", rect{16, 18, 400, 36}, 0)
		phrase := createEdit(hwnd, rect{16, 40, 430, 66}, idDlgPhrase)
		createStatic(hwnd, "数字标调拼音，例如 zhong1 guo2", rect{16, 76, 410, 94}, 0)
		pinyin := createEdit(hwnd, rect{16, 98, 430, 124}, idDlgPinyin)
		createStatic(hwnd, "权重", rect{16, 134, 410, 152}, 0)
		weight := createEdit(hwnd, rect{16, 156, 430, 182}, idDlgWeight)
		setWindowText(phrase, initial.Phrase)
		setWindowText(pinyin, initial.Pinyin)
		setWindowText(weight, initial.Weight)
		createButton(hwnd, okText, rect{260, 216, 338, 244}, idDlgOK)
		createButton(hwnd, "取消", rect{348, 216, 426, 244}, idDlgCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		if id != idDlgOK {
			return false
		}
		entry := userlexicon.Entry{
			Phrase: strings.TrimSpace(getWindowText(findDlgItem(hwnd, idDlgPhrase))),
			Pinyin: strings.TrimSpace(getWindowText(findDlgItem(hwnd, idDlgPinyin))),
			Weight: strings.TrimSpace(getWindowText(findDlgItem(hwnd, idDlgWeight))),
		}
		if entry.Weight == "" {
			entry.Weight = userlexicon.DefaultEntryWeight
		}
		if err := userlexicon.AssertEntryFields(entry); err != nil {
			showMessageBox(err.Error(), 0x10)
			return false
		}
		result = entry
		return true
	})
	return result, accepted
}

func showWeightDialog(owner syscall.Handle, initial string) (string, bool) {
	value := ""
	accepted := showModalForm(owner, "设置词条权重", 380, 180, func(hwnd syscall.Handle) {
		createStatic(hwnd, "权重", rect{16, 18, 320, 36}, 0)
		edit := createEdit(hwnd, rect{16, 42, 346, 68}, idWeightValue)
		setWindowText(edit, initial)
		createButton(hwnd, "确定", rect{180, 88, 258, 116}, idWeightOK)
		createButton(hwnd, "取消", rect{268, 88, 346, 116}, idWeightCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		if id != idWeightOK {
			return false
		}
		value = strings.TrimSpace(getWindowText(findDlgItem(hwnd, idWeightValue)))
		if value == "" {
			showMessageBox("请输入权重。", 0x10)
			return false
		}
		return true
	})
	return value, accepted
}

func showImportPreviewDialog(owner syscall.Handle, preview userlexicon.ImportPreview) (map[string]bool, bool) {
	selected := map[string]bool{}
	for _, conflict := range preview.Conflicts {
		selected[conflict.Phrase] = true
	}
	accepted := showModalForm(owner, "导入预览", 760, 470, func(hwnd syscall.Handle) {
		summary := fmt.Sprintf("新增：%d    覆盖：%d    相同：%d", preview.NewCount, preview.ReplaceCount, preview.SameCount)
		createStatic(hwnd, summary, rect{16, 16, 700, 54}, 0)
		list := createControl("LISTBOX", "", 0x50210121, rect{16, 78, 720, 340}, hwnd, idImportList)
		for _, conflict := range preview.Conflicts {
			line := fmt.Sprintf("%s | %s/%s -> %s/%s", conflict.Phrase, conflict.CurrentPinyin, conflict.CurrentWeight, conflict.ImportedPinyin, conflict.ImportedWeight)
			text, _ := syscall.UTF16PtrFromString(line)
			index, _, _ := procSendMessageW.Call(uintptr(list), 0x0180, 0, uintptr(unsafe.Pointer(text)))
			procSendMessageW.Call(uintptr(list), 0x0185, index, 1)
		}
		for _, entry := range preview.NewEntries {
			line := fmt.Sprintf("[新增] %s | %s | %s", entry.Phrase, entry.ImportedPinyin, entry.ImportedWeight)
			text, _ := syscall.UTF16PtrFromString(line)
			procSendMessageW.Call(uintptr(list), 0x0180, 0, uintptr(unsafe.Pointer(text)))
		}
		createButton(hwnd, "继续合并", rect{560, 390, 650, 418}, idImportOK)
		createButton(hwnd, "取消", rect{662, 390, 736, 418}, idImportCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		if id != idImportOK {
			return false
		}
		list := findDlgItem(hwnd, idImportList)
		count, _, _ := procSendMessageW.Call(uintptr(list), 0x0186, 0, 0)
		items := make([]int32, count)
		procSendMessageW.Call(uintptr(list), 0x0187, count, uintptr(unsafe.Pointer(&items[0])))
		selected = map[string]bool{}
		conflictCount := len(preview.Conflicts)
		for _, index := range items {
			if int(index) < conflictCount {
				selected[preview.Conflicts[index].Phrase] = true
			}
		}
		return true
	})
	return selected, accepted
}

var (
	procEndDialog    = moduser32.NewProc("EndDialog")
	procGetDlgItem   = moduser32.NewProc("GetDlgItem")
	procEnableWindow = moduser32.NewProc("EnableWindow")
)

func findDlgItem(parent syscall.Handle, id int) syscall.Handle {
	hwnd, _, _ := procGetDlgItem.Call(uintptr(parent), uintptr(id))
	return syscall.Handle(hwnd)
}

func showModalForm(owner syscall.Handle, title string, width, height int32, build func(hwnd syscall.Handle), onCommand func(hwnd syscall.Handle, id int) bool) bool {
	accepted := false
	modalClosed := false
	className, _ := syscall.UTF16PtrFromString("YimeLexiconModal")
	instance, _, _ := procGetModuleHandleW.Call(0)
	wndProcCallback := syscall.NewCallback(func(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
		switch msg {
		case 0x0111:
			id := int(wParam & 0xffff)
			if id == idDlgCancel || id == idWeightCancel || id == idImportCancel {
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
		WndProc:   wndProcCallback,
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
		uintptr(wsOverlappedwindow&^0x00040000), // no thick frame
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

var procDestroyWindow = moduser32.NewProc("DestroyWindow")

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

func pickOpenFile(owner syscall.Handle, title, filter string) (string, bool) {
	buf := make([]uint16, 260)
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Filter:     utf16Ptr(filter),
		File:       &buf[0],
		MaxFile:    uint32(len(buf)),
		Title:      utf16Ptr(title),
		Flags:      0x00080000 | 0x00001000 | 0x00000800,
	}
	ret, _, _ := procGetOpenFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ret == 0 {
		return "", false
	}
	return syscall.UTF16ToString(buf), true
}

func pickSaveFile(owner syscall.Handle, title, defaultName, filter string) (string, bool) {
	buf := utf16FromString(defaultName)
	if len(buf) < 260 {
		padded := make([]uint16, 260)
		copy(padded, buf)
		buf = padded
	}
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Filter:     utf16Ptr(filter),
		File:       &buf[0],
		MaxFile:    uint32(len(buf)),
		Title:      utf16Ptr(title),
		Flags:      0x00080000 | 0x00000002 | 0x00001000,
	}
	ret, _, _ := procGetSaveFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ret == 0 {
		return "", false
	}
	return syscall.UTF16ToString(buf), true
}

func utf16Ptr(value string) *uint16 {
	ptr, _ := syscall.UTF16PtrFromString(value)
	return ptr
}

func utf16FromString(value string) []uint16 {
	data, _ := syscall.UTF16FromString(value)
	return data
}
