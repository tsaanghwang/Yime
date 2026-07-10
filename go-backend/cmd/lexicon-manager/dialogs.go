//go:build windows

package main

import (
	"fmt"
	"strconv"
	"strings"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	idDlgPhrase    = 301
	idDlgPinyin    = 302
	idDlgWeight    = 303
	idDlgOK        = 1
	idDlgCancel    = 2
	idWeightValue  = 401
	idWeightStep   = 402
	idWeightMinus  = 403
	idWeightPlus   = 404
	idWeightOK     = 1
	idWeightCancel = 2
	idImportList   = 501
	idImportOK     = 1
	idImportCancel = 2
)

type entryDialogResult int

const (
	entryDialogCanceled entryDialogResult = iota
	entryDialogSavedAndContinue
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

func showEntryDialog(owner syscall.Handle, initial userlexicon.Entry, title, okText string) (userlexicon.Entry, entryDialogResult) {
	result := userlexicon.Entry{}
	dialogResult := entryDialogCanceled
	accepted := showModalForm(owner, title, 520, 302, func(hwnd syscall.Handle) {
		createStatic(hwnd, "词条汉字", rect{16, 18, 400, 36}, 0)
		phrase := createEdit(hwnd, rect{16, 40, 490, 66}, idDlgPhrase)
		createStatic(hwnd, "数字标调拼音，例如 zhong1 guo2", rect{16, 76, 490, 94}, 0)
		pinyin := createEdit(hwnd, rect{16, 98, 490, 124}, idDlgPinyin)
		createStatic(hwnd, "权重", rect{16, 134, 490, 152}, 0)
		weight := createEdit(hwnd, rect{16, 156, 490, 182}, idDlgWeight)
		setWindowText(phrase, initial.Phrase)
		setWindowText(pinyin, initial.Pinyin)
		setWindowText(weight, initial.Weight)
		createButton(hwnd, okText, rect{170, 216, 248, 244}, idDlgOK)
		createButton(hwnd, "退出", rect{258, 216, 336, 244}, idDlgCancel)
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
		dialogResult = entryDialogSavedAndContinue
		return true
	})
	if !accepted {
		return result, entryDialogCanceled
	}
	return result, dialogResult
}

func showWeightDialog(owner syscall.Handle, initial string) (string, bool) {
	value := ""
	accepted := showModalForm(owner, "设置词条权重", 380, 220, func(hwnd syscall.Handle) {
		createStatic(hwnd, "权重", rect{16, 18, 320, 36}, 0)
		edit := createEdit(hwnd, rect{16, 42, 346, 68}, idWeightValue)
		setWindowText(edit, initial)
		createStatic(hwnd, "每次增减", rect{16, 82, 320, 100}, 0)
		createButton(hwnd, "减", rect{16, 106, 82, 134}, idWeightMinus)
		stepEdit := createEdit(hwnd, rect{92, 106, 160, 132}, idWeightStep)
		setWindowText(stepEdit, "1")
		createButton(hwnd, "加", rect{170, 106, 236, 134}, idWeightPlus)
		createButton(hwnd, "确定", rect{180, 154, 258, 182}, idWeightOK)
		createButton(hwnd, "取消", rect{268, 154, 346, 182}, idWeightCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		switch id {
		case idWeightMinus, idWeightPlus:
			weightHWND := findDlgItem(hwnd, idWeightValue)
			stepHWND := findDlgItem(hwnd, idWeightStep)
			currentValue := strings.TrimSpace(getWindowText(weightHWND))
			if currentValue == "" {
				currentValue = "0"
			}
			current, err := strconv.Atoi(currentValue)
			if err != nil {
				showMessageBox("当前权重必须是整数。", 0x10)
				return false
			}
			stepValue := strings.TrimSpace(getWindowText(stepHWND))
			if stepValue == "" {
				stepValue = "1"
				setWindowText(stepHWND, stepValue)
			}
			step, err := strconv.Atoi(stepValue)
			if err != nil || step < 0 {
				showMessageBox("增减数值必须是非负整数。", 0x10)
				return false
			}
			if id == idWeightMinus {
				current -= step
			} else {
				current += step
			}
			setWindowText(weightHWND, strconv.Itoa(current))
			return false
		case idWeightOK:
			value = strings.TrimSpace(getWindowText(findDlgItem(hwnd, idWeightValue)))
			if value == "" {
				showMessageBox("请输入权重。", 0x10)
				return false
			}
			return true
		default:
			return false
		}
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
		list := createControl("LISTBOX", "", entryListStyle, rect{16, 78, 720, 340}, hwnd, idImportList)
		for _, conflict := range preview.Conflicts {
			line := fmt.Sprintf("%s | %s/%s -> %s/%s", conflict.Phrase, conflict.CurrentPinyin, conflict.CurrentWeight, conflict.ImportedPinyin, conflict.ImportedWeight)
			text, _ := syscall.UTF16PtrFromString(line)
			index, _, _ := procSendMessageW.Call(uintptr(list), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
			procSendMessageW.Call(uintptr(list), lbSetsel, index, 1)
		}
		for _, entry := range preview.NewEntries {
			line := fmt.Sprintf("[新增] %s | %s | %s", entry.Phrase, entry.ImportedPinyin, entry.ImportedWeight)
			text, _ := syscall.UTF16PtrFromString(line)
			procSendMessageW.Call(uintptr(list), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
		}
		createButton(hwnd, "继续合并", rect{560, 390, 650, 418}, idImportOK)
		createButton(hwnd, "取消", rect{662, 390, 736, 418}, idImportCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		if id != idImportOK {
			return false
		}
		list := findDlgItem(hwnd, idImportList)
		count, _, _ := procSendMessageW.Call(uintptr(list), lbGetselcount, 0, 0)
		items := []int32{}
		if count > 0 {
			items = make([]int32, count)
			procSendMessageW.Call(uintptr(list), lbGetselitems, count, uintptr(unsafe.Pointer(&items[0])))
		}
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
	procEndDialog         = moduser32.NewProc("EndDialog")
	procGetDlgItem        = moduser32.NewProc("GetDlgItem")
	procEnableWindow      = moduser32.NewProc("EnableWindow")
	procGetWindowRect     = moduser32.NewProc("GetWindowRect")
	procUnregisterClassW  = moduser32.NewProc("UnregisterClassW")
	procDestroyWindow     = moduser32.NewProc("DestroyWindow")
	procSetWindowLongPtrW = moduser32.NewProc("SetWindowLongPtrW")
	procGetWindowLongPtrW = moduser32.NewProc("GetWindowLongPtrW")

	gwlpUserdata = ^uintptr(20)
)

type modalFormContext struct {
	accepted    *bool
	modalClosed *bool
	onCommand   func(hwnd syscall.Handle, id int) bool
}

func modalWndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	ctxPtr, _, _ := procGetWindowLongPtrW.Call(uintptr(hwnd), gwlpUserdata)
	if ctxPtr == 0 {
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
		return ret
	}
	ctx := (*modalFormContext)(unsafe.Pointer(ctxPtr))
	switch msg {
	case 0x0111:
		id := int(wParam & 0xffff)
		notify := int((wParam >> 16) & 0xffff)
		if id == idDlgCancel || id == idWeightCancel || id == idImportCancel {
			procDestroyWindow.Call(uintptr(hwnd))
			return 0
		}
		if notify != 0 {
			return 0
		}
		if ctx.onCommand(hwnd, id) {
			*ctx.accepted = true
			procDestroyWindow.Call(uintptr(hwnd))
		}
		return 0
	case 0x0002:
		*ctx.modalClosed = true
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return ret
}

func centerDialogOnOwner(owner syscall.Handle, winW, winH int32) (x, y int32) {
	if owner != 0 {
		var ownerRect rect
		if ret, _, _ := procGetWindowRect.Call(uintptr(owner), uintptr(unsafe.Pointer(&ownerRect))); ret != 0 {
			ownerW := ownerRect.Right - ownerRect.Left
			ownerH := ownerRect.Bottom - ownerRect.Top
			return ownerRect.Left + (ownerW-winW)/2, ownerRect.Top + (ownerH-winH)/2
		}
	}
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	return (int32(screenWidth) - winW) / 2, (int32(screenHeight) - winH) / 2
}

func findDlgItem(parent syscall.Handle, id int) syscall.Handle {
	hwnd, _, _ := procGetDlgItem.Call(uintptr(parent), uintptr(id))
	return syscall.Handle(hwnd)
}

func showModalForm(owner syscall.Handle, title string, width, height int32, build func(hwnd syscall.Handle), onCommand func(hwnd syscall.Handle, id int) bool) bool {
	accepted := false
	modalClosed := false
	ctx := modalFormContext{
		accepted:    &accepted,
		modalClosed: &modalClosed,
		onCommand:   onCommand,
	}

	className, _ := syscall.UTF16PtrFromString("YimeLexiconModal")
	instance, _, _ := procGetModuleHandleW.Call(0)
	modalProc := syscall.NewCallback(modalWndProc)
	wndClass := wndclassex{
		Size:       uint32(unsafe.Sizeof(wndclassex{})),
		WndProc:    modalProc,
		Instance:   syscall.Handle(instance),
		ClassName:  className,
		Background: win32ui.ColorWindowBackground,
	}
	procUnregisterClassW.Call(instance, uintptr(unsafe.Pointer(className)))
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wndClass)))
	defer procUnregisterClassW.Call(instance, uintptr(unsafe.Pointer(className)))

	titlePtr, _ := syscall.UTF16PtrFromString(title)
	winW, winH := windowSizeForClient(width, height)
	x, y := centerDialogOnOwner(owner, winW, winH)
	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(wsExControlparent|wsExAppwindow),
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(titlePtr)),
		uintptr(wsOverlappedwindow&^0x00040000),
		uintptr(x), uintptr(y), uintptr(winW), uintptr(winH),
		uintptr(owner), 0, instance, 0,
	)
	dlg := syscall.Handle(hwnd)
	if dlg == 0 {
		return false
	}
	procSetWindowLongPtrW.Call(uintptr(dlg), gwlpUserdata, uintptr(unsafe.Pointer(&ctx)))
	build(dlg)
	if owner != 0 {
		procEnableWindow.Call(uintptr(owner), 0)
	}
	procShowWindow.Call(uintptr(dlg), swShowNormal)
	win32ui.PresentMainWindow(dlg)

	var message winMsg
	for !modalClosed {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		handled, _, _ := procIsDialogMessageW.Call(uintptr(dlg), uintptr(unsafe.Pointer(&message)))
		if handled == 0 {
			procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
		}
	}
	if owner != 0 {
		procEnableWindow.Call(uintptr(owner), 1)
		procSetForegroundWindow.Call(uintptr(owner))
		procBringWindowToTop.Call(uintptr(owner))
	}
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

func pickOpenFile(owner syscall.Handle, title, filter string) (string, bool) {
	buf := make([]uint16, 260)
	instance, _, _ := procGetModuleHandleW.Call(0)
	filterPtr, _ := syscall.UTF16PtrFromString(filter)
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Instance:   syscall.Handle(instance),
		Filter:     filterPtr,
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
	instance, _, _ := procGetModuleHandleW.Call(0)
	filterPtr, _ := syscall.UTF16PtrFromString(filter)
	ofn := openFilename{
		StructSize: uint32(unsafe.Sizeof(openFilename{})),
		Owner:      owner,
		Instance:   syscall.Handle(instance),
		Filter:     filterPtr,
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
