//go:build windows

package main

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	idDlgPhrase       = 301
	idDlgPinyin       = 302
	idDlgWeight       = 303
	idDlgOK           = 1
	idDlgCancel       = 2
	idWeightValue     = 401
	idWeightStep      = 402
	idWeightMinus     = 403
	idWeightPlus      = 404
	idWeightOK        = 1
	idWeightCancel    = 2
	idImportList      = 501
	idImportOK        = 1
	idImportCancel    = 2
	idChoicePrimary   = 601
	idChoiceSecondary = 602
)

type entryDialogResult int

type dialogChoice struct {
	ID    int
	Label string
}

const (
	entryDialogCanceled entryDialogResult = iota
	entryDialogSavedAndContinue
)

func centeredButtonRects(left, right, top, height, gap int32, widths []int32) []rect {
	if len(widths) == 0 {
		return nil
	}
	totalWidth := gap * int32(len(widths)-1)
	for _, width := range widths {
		totalWidth += width
	}
	x := left + (right-left-totalWidth)/2
	result := make([]rect, len(widths))
	for index, width := range widths {
		result[index] = rect{x, top, x + width, top + height}
		x += width + gap
	}
	return result
}

func weightAdjustmentRects(left, right, top, height, buttonWidth, gap int32) (minus, step, plus rect) {
	minus = rect{left, top, left + buttonWidth, top + height}
	plus = rect{right - buttonWidth, top, right, top + height}
	step = rect{minus.Right + gap, top, plus.Left - gap, top + height - 2}
	return minus, step, plus
}

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
		const contentLeft, contentRight = int32(16), int32(504)
		createAutoStatic(hwnd, "词条汉字", contentLeft, 18, 18, 0)
		phrase := createEdit(hwnd, rect{contentLeft, 40, contentRight, 66}, idDlgPhrase)
		createAutoStatic(hwnd, "数字标调拼音，例如 zhong1 guo2", contentLeft, 76, 18, 0)
		pinyin := createEdit(hwnd, rect{contentLeft, 98, contentRight, 124}, idDlgPinyin)
		createAutoStatic(hwnd, "权重", contentLeft, 134, 18, 0)
		weight := createEdit(hwnd, rect{contentLeft, 156, contentRight, 182}, idDlgWeight)
		setWindowText(phrase, initial.Phrase)
		setWindowText(pinyin, initial.Pinyin)
		setWindowText(weight, initial.Weight)
		buttons := centeredButtonRects(contentLeft, contentRight, 216, 28, 10, []int32{88, 88})
		createButton(hwnd, okText, buttons[0], idDlgOK)
		createButton(hwnd, "退出", buttons[1], idDlgCancel)
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

func adjustWeightValue(currentValue, stepValue string, direction int) (string, error) {
	currentValue = strings.TrimSpace(currentValue)
	if currentValue == "" {
		currentValue = "0"
	}
	current, err := strconv.Atoi(currentValue)
	if err != nil {
		return "", fmt.Errorf("当前权重必须是整数")
	}

	stepValue = strings.TrimSpace(stepValue)
	if stepValue == "" {
		stepValue = "1"
	}
	step, err := strconv.Atoi(stepValue)
	if err != nil || step < 0 {
		return "", fmt.Errorf("增减数值必须是非负整数")
	}
	if direction != -1 && direction != 1 {
		return "", fmt.Errorf("无效的权重调整方向")
	}

	maxInt := int(^uint(0) >> 1)
	minInt := -maxInt - 1
	if direction > 0 && current > maxInt-step {
		return "", fmt.Errorf("权重超出整数范围")
	}
	if direction < 0 && current < minInt+step {
		return "", fmt.Errorf("权重超出整数范围")
	}
	return strconv.Itoa(current + direction*step), nil
}

func showWeightDialog(owner syscall.Handle, initial string) (string, bool) {
	value := ""
	accepted := showModalForm(owner, "设置词条权重", 380, 220, func(hwnd syscall.Handle) {
		const contentLeft, contentRight = int32(16), int32(364)
		createAutoStatic(hwnd, "权重", contentLeft, 18, 18, 0)
		edit := createEdit(hwnd, rect{contentLeft, 42, contentRight, 68}, idWeightValue)
		setWindowText(edit, initial)
		createAutoStatic(hwnd, "每次增减", contentLeft, 82, 18, 0)
		const adjustButtonW, controlGap = int32(74), int32(10)
		minusRect, stepRect, plusRect := weightAdjustmentRects(contentLeft, contentRight, 106, 28, adjustButtonW, controlGap)
		createButton(hwnd, "减", minusRect, idWeightMinus)
		stepEdit := createEdit(hwnd, stepRect, idWeightStep)
		setWindowText(stepEdit, "1")
		createButton(hwnd, "加", plusRect, idWeightPlus)
		buttons := centeredButtonRects(contentLeft, contentRight, 154, 28, 10, []int32{78, 78})
		createButton(hwnd, "确认", buttons[0], idWeightOK)
		createButton(hwnd, "取消", buttons[1], idWeightCancel)
	}, func(hwnd syscall.Handle, id int) bool {
		switch id {
		case idWeightMinus, idWeightPlus:
			weightHWND := findDlgItem(hwnd, idWeightValue)
			stepHWND := findDlgItem(hwnd, idWeightStep)
			stepValue := strings.TrimSpace(getWindowText(stepHWND))
			if stepValue == "" {
				stepValue = "1"
				setWindowText(stepHWND, stepValue)
			}
			direction := 1
			if id == idWeightMinus {
				direction = -1
			}
			adjusted, err := adjustWeightValue(getWindowText(weightHWND), stepValue, direction)
			if err != nil {
				showMessageBox(err.Error(), 0x10)
				return false
			}
			setWindowText(weightHWND, adjusted)
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
		const contentLeft, contentRight = int32(16), int32(744)
		summary := fmt.Sprintf("新增：%d    覆盖：%d    相同：%d", preview.NewCount, preview.ReplaceCount, preview.SameCount)
		createAutoStatic(hwnd, summary, contentLeft, 16, 22, 0)
		list := createControl("LISTBOX", "", entryListStyle, rect{contentLeft, 54, contentRight, 360}, hwnd, idImportList)
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
		buttons := centeredButtonRects(contentLeft, contentRight, 390, 28, 12, []int32{96, 88})
		createButton(hwnd, "继续合并", buttons[0], idImportOK)
		createButton(hwnd, "取消", buttons[1], idImportCancel)
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

func showChoiceDialog(owner syscall.Handle, title, message string, choices []dialogChoice) int {
	if len(choices) == 0 {
		return 0
	}
	const (
		clientW      = int32(460)
		contentLeft  = int32(16)
		contentRight = int32(444)
		buttonH      = int32(30)
		buttonGap    = int32(10)
	)
	lineCount := int32(strings.Count(message, "\n") + 1)
	messageH := lineCount * 20
	if messageH < 54 {
		messageH = 54
	}
	buttonsTop := int32(22) + messageH + 16
	clientH := buttonsTop + buttonH + 20

	result := 0
	showModalForm(owner, title, clientW, clientH, func(hwnd syscall.Handle) {
		createStatic(hwnd, message, rect{contentLeft, 18, contentRight, 18 + messageH}, 0)
		widths := make([]int32, len(choices))
		for index, choice := range choices {
			widths[index] = measureTextWidth(hwnd, choice.Label) + 32
			if widths[index] < 88 {
				widths[index] = 88
			}
		}
		buttons := centeredButtonRects(contentLeft, contentRight, buttonsTop, buttonH, buttonGap, widths)
		for index, choice := range choices {
			createButton(hwnd, choice.Label, buttons[index], choice.ID)
		}
	}, func(_ syscall.Handle, id int) bool {
		for _, choice := range choices {
			if id == choice.ID {
				result = id
				return true
			}
		}
		return false
	})
	return result
}

func showConfirmDialog(owner syscall.Handle, title, message string) bool {
	return showChoiceDialog(owner, title, message, []dialogChoice{
		{ID: idChoicePrimary, Label: "确认"},
		{ID: idDlgCancel, Label: "取消"},
	}) == idChoicePrimary
}

func showNoticeDialog(owner syscall.Handle, title, message string) {
	showChoiceDialog(owner, title, message, []dialogChoice{
		{ID: idChoicePrimary, Label: "确认"},
	})
}

func showImportModeDialog(owner syscall.Handle, message string) int {
	return showChoiceDialog(owner, "选择导入方式", message, []dialogChoice{
		{ID: idChoicePrimary, Label: "完全替换"},
		{ID: idChoiceSecondary, Label: "合并导入"},
		{ID: idDlgCancel, Label: "取消"},
	})
}

var (
	procEndDialog        = moduser32.NewProc("EndDialog")
	procGetDlgItem       = moduser32.NewProc("GetDlgItem")
	procEnableWindow     = moduser32.NewProc("EnableWindow")
	procGetWindowRect    = moduser32.NewProc("GetWindowRect")
	procUnregisterClassW = moduser32.NewProc("UnregisterClassW")
	procDestroyWindow    = moduser32.NewProc("DestroyWindow")
)

var modalContexts sync.Map

type modalFormContext struct {
	accepted    *bool
	modalClosed *bool
	onCommand   func(hwnd syscall.Handle, id int) bool
}

func modalWndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	value, ok := modalContexts.Load(hwnd)
	if !ok {
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
		return ret
	}
	ctx := value.(*modalFormContext)
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
		modalContexts.Delete(hwnd)
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
	modalContexts.Store(dlg, &ctx)
	defer modalContexts.Delete(dlg)
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
