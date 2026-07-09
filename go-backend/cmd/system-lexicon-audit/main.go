//go:build windows

package main

import (
	"flag"
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
	"github.com/EasyIME/pime-go/input_methods/yime/systemlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	wmAppLoadDone  = 0x0400 + 1
	wmAppRefresh   = 0x0400 + 2
	wmAppCommand   = 0x0400 + 3
	wmAppShowError = 0x0400 + 4
	enChange       = 0x0300

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000

	idSearchEdit     = 101
	idRuleCombo      = 102
	idModeCombo      = 103
	idRefreshButton  = 104
	idResultList     = 105
	idDetailView     = 106
	idExportButton   = 107
	idStatusLabel    = 108

	cbsDropdownlist = 0x0003
	lbResetcontent  = 0x0184
	lbAddstring     = 0x0180
	lbGetcursel     = 0x0188
	lbSethorizontalextent = 0x0194
	cbAddstring     = 0x0143
	cbSetcursel     = 0x014E
	cbGetcursel     = 0x0147
	cbSelchange     = 1
	lbnSelchange    = 1

	wsChild       = 0x40000000
	wsVisible     = 0x10000000
	wsBorder      = 0x00800000
	wsVscroll     = 0x00200000
	wsTabstop     = 0x00010000
	lbsNotify     = 0x0001
	lbsHasstrings = 0x0040
	listBoxStyle  = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | lbsNotify | lbsHasstrings

	esMultiline   = 0x0004
	esReadonly    = 0x0800
	esAutoVscroll = 0x0040
	detailViewStyle = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | esMultiline | esReadonly | esAutoVscroll
)

var (
	moduser32   = syscall.NewLazyDLL("user32.dll")
	modkernel32 = syscall.NewLazyDLL("kernel32.dll")
	modcomctl32 = syscall.NewLazyDLL("comctl32.dll")

	procCreateWindowExW      = moduser32.NewProc("CreateWindowExW")
	procDefWindowProcW       = moduser32.NewProc("DefWindowProcW")
	procDispatchMessageW     = moduser32.NewProc("DispatchMessageW")
	procGetMessageW          = moduser32.NewProc("GetMessageW")
	procTranslateMessageW    = moduser32.NewProc("TranslateMessage")
	procPostQuitMessage      = moduser32.NewProc("PostQuitMessage")
	procRegisterClassExW     = moduser32.NewProc("RegisterClassExW")
	procSendMessageW         = moduser32.NewProc("SendMessageW")
	procSetWindowTextW       = moduser32.NewProc("SetWindowTextW")
	procGetWindowTextLengthW = moduser32.NewProc("GetWindowTextLengthW")
	procGetWindowTextW       = moduser32.NewProc("GetWindowTextW")
	procGetSystemMetrics     = moduser32.NewProc("GetSystemMetrics")
	procMessageBoxW          = moduser32.NewProc("MessageBoxW")
	procPostMessageW         = moduser32.NewProc("PostMessageW")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procLoadIconW            = moduser32.NewProc("LoadIconW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")
	procSetFocus             = moduser32.NewProc("SetFocus")

	wndProcCallback uintptr
)

type wndclassex struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   syscall.Handle
	Icon       syscall.Handle
	Cursor     syscall.Handle
	Background syscall.Handle
	MenuName   *uint16
	ClassName  *uint16
	IconSm     syscall.Handle
}

type winMsg struct {
	Hwnd    syscall.Handle
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      struct{ X, Y int32 }
}

type rect struct {
	Left, Top, Right, Bottom int32
}

type initCommonControlsEx struct {
	Size uint32
	ICC  uint32
}

type modeOption struct {
	Label string
	Value reverselookup.Mode
}

type uiLayout struct {
	clientW, clientH int32
	searchLabel      rect
	searchEdit       rect
	ruleLabel        rect
	ruleCombo        rect
	modeLabel        rect
	modeCombo        rect
	refreshButton    rect
	exportButton     rect
	resultList       rect
	detailView       rect
	statusLabel      rect
}

type appState struct {
	sharedDir          string
	userDir            string
	mode               reverselookup.Mode
	dictPath           string
	loading            bool
	suppressListNotify bool
	loadErr            error
	allFindings        []systemlexicon.Finding
	visibleFindings    []systemlexicon.Finding
	summary            systemlexicon.Summary
	mu                 sync.Mutex
	layout             uiLayout
	mainHWND           syscall.Handle
	searchHWND         syscall.Handle
	ruleHWND           syscall.Handle
	modeHWND           syscall.Handle
	resultHWND         syscall.Handle
	detailHWND         syscall.Handle
	statusHWND         syscall.Handle
	modeOptions        []modeOption
	ruleOptions        []systemlexicon.RuleID
}

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	mode := flag.String("Mode", "variable", "Yime schema mode: variable, full, shorthand")
	flag.Parse()

	if strings.TrimSpace(*sharedDir) == "" {
		showWin32Error("缺少 SharedDir 参数。")
		os.Exit(1)
	}

	state := &appState{
		sharedDir: strings.TrimSpace(*sharedDir),
		userDir:   strings.TrimSpace(*userDir),
		mode:      reverselookup.Mode(strings.TrimSpace(*mode)),
		modeOptions: []modeOption{
			{Label: "变长", Value: reverselookup.ModeVariable},
			{Label: "等长", Value: reverselookup.ModeFull},
			{Label: "省键", Value: reverselookup.ModeShorthand},
		},
		ruleOptions: systemlexicon.RuleOptions(),
	}
	if err := runWin32App(state); err != nil {
		showWin32Error(err.Error())
		os.Exit(1)
	}
}

func buildUILayout() uiLayout {
	const (
		margin       = int32(12)
		gap          = int32(8)
		rowGap       = int32(6)
		rowH         = int32(26)
		clientW      = int32(720)
		searchLabelW = int32(36)
		ruleLabelW   = int32(36)
		modeLabelW   = int32(36)
		ruleComboW   = int32(132)
		modeComboW   = int32(92)
		refreshBtnW  = int32(64)
		exportBtnW   = int32(88)
		listH        = int32(300)
		detailH      = int32(72)
		statusH      = int32(44)
	)

	row1Y := int32(10)
	row2Y := row1Y + rowH + rowGap

	layout := uiLayout{clientW: clientW}

	layout.searchLabel = rect{margin, row1Y + 4, margin + searchLabelW, row1Y + 4 + 18}
	searchEditLeft := margin + searchLabelW + gap
	searchEditRight := clientW - margin - refreshBtnW - gap
	layout.searchEdit = rect{searchEditLeft, row1Y, searchEditRight, row1Y + rowH}
	layout.refreshButton = rect{searchEditRight + gap, row1Y, clientW - margin, row1Y + rowH}

	x := margin
	layout.ruleLabel = rect{x, row2Y + 4, x + ruleLabelW, row2Y + 4 + 18}
	x += ruleLabelW + gap
	layout.ruleCombo = rect{x, row2Y, x + ruleComboW, row2Y + 120}
	x += ruleComboW + gap
	layout.modeLabel = rect{x, row2Y + 4, x + modeLabelW, row2Y + 4 + 18}
	x += modeLabelW + gap
	layout.modeCombo = rect{x, row2Y, x + modeComboW, row2Y + 120}
	x += modeComboW + gap
	layout.exportButton = rect{x, row2Y, x + exportBtnW, row2Y + rowH}

	listY := row2Y + rowH + gap
	layout.resultList = rect{margin, listY, clientW - margin, listY + listH}

	detailY := layout.resultList.Bottom + gap
	layout.detailView = rect{margin, detailY, clientW - margin, detailY + detailH}

	statusY := layout.detailView.Bottom + gap
	layout.statusLabel = rect{margin, statusY, clientW - margin, statusY + statusH}

	layout.clientH = layout.statusLabel.Bottom + margin
	return layout
}

func windowSizeForClient(clientW, clientH int32) (winW, winH int32) {
	r := rect{Left: 0, Top: 0, Right: clientW, Bottom: clientH}
	ret, _, _ := procAdjustWindowRectEx.Call(
		uintptr(unsafe.Pointer(&r)),
		uintptr(wsOverlappedwindow),
		0,
		0,
	)
	if ret == 0 {
		return clientW + 16, clientH + 39
	}
	return r.Right - r.Left, r.Bottom - r.Top
}

func runWin32App(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow("YimeSystemLexiconAudit") {
		return nil
	}

	state.layout = buildUILayout()

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeSystemLexiconAudit")
	cursor, _, _ := procLoadCursorW.Call(0, uintptr(32512))
	icon, _, _ := procLoadIconW.Call(instance, uintptr(32512))

	wndProcCallback = syscall.NewCallback(func(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
		return state.wndProc(hwnd, msg, wParam, lParam)
	})

	wndClass := wndclassex{
		Style:      win32ui.ClassRedraw,
		Size:       uint32(unsafe.Sizeof(wndclassex{})),
		WndProc:    wndProcCallback,
		Instance:   syscall.Handle(instance),
		Icon:       syscall.Handle(icon),
		IconSm:     syscall.Handle(icon),
		Cursor:     syscall.Handle(cursor),
		Background: win32ui.ColorWindowBackground,
		ClassName:  className,
	}
	if ret, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wndClass))); ret == 0 {
		return fmt.Errorf("RegisterClassEx failed")
	}

	title, _ := syscall.UTF16PtrFromString("Yime 系统词库审查")
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	winW, winH := windowSizeForClient(state.layout.clientW, state.layout.clientH)
	x := (int32(screenWidth) - winW) / 2
	y := (int32(screenHeight) - winH) / 2

	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(wsExControlparent|wsExAppwindow),
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		uintptr(wsOverlappedwindow),
		uintptr(x), uintptr(y), uintptr(winW), uintptr(winH),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowEx failed")
	}
	state.mainHWND = syscall.Handle(hwnd)
	state.createChildControls()
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
	state.startLoadAudit()

	var message winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) createChildControls() {
	l := state.layout
	createControl("STATIC", "搜索", 0x50000000, l.searchLabel, state.mainHWND, 0)
	state.searchHWND = createControl("EDIT", "", 0x50210000, l.searchEdit, state.mainHWND, idSearchEdit)
	createControl("BUTTON", "刷新", 0x50010000, l.refreshButton, state.mainHWND, idRefreshButton)

	createControl("STATIC", "规则", 0x50000000, l.ruleLabel, state.mainHWND, 0)
	state.ruleHWND = createControl("COMBOBOX", "", 0x50200000|cbsDropdownlist, l.ruleCombo, state.mainHWND, idRuleCombo)
	for _, rule := range state.ruleOptions {
		label, _ := syscall.UTF16PtrFromString(systemlexicon.RuleLabel(rule))
		procSendMessageW.Call(uintptr(state.ruleHWND), cbAddstring, 0, uintptr(unsafe.Pointer(label)))
	}
	procSendMessageW.Call(uintptr(state.ruleHWND), cbSetcursel, 0, 0)

	createControl("STATIC", "方案", 0x50000000, l.modeLabel, state.mainHWND, 0)
	state.modeHWND = createControl("COMBOBOX", "", 0x50200000|cbsDropdownlist, l.modeCombo, state.mainHWND, idModeCombo)
	selectedIndex := 0
	for index, option := range state.modeOptions {
		label, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.modeHWND), cbAddstring, 0, uintptr(unsafe.Pointer(label)))
		if option.Value == state.mode {
			selectedIndex = index
		}
	}
	procSendMessageW.Call(uintptr(state.modeHWND), cbSetcursel, uintptr(selectedIndex), 0)

	createControl("BUTTON", "导出报告", 0x50010000, l.exportButton, state.mainHWND, idExportButton)
	state.resultHWND = createControl("LISTBOX", "", listBoxStyle, l.resultList, state.mainHWND, idResultList)
	state.detailHWND = createControl("EDIT", "审查结果将显示在此。本工具只读，不会修改系统词库。", detailViewStyle, l.detailView, state.mainHWND, idDetailView)
	state.statusHWND = createControl("STATIC", "正在加载系统词库...", 0x50000000, l.statusLabel, state.mainHWND, idStatusLabel)
}

func createControl(className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	width := box.Right - box.Left
	height := box.Bottom - box.Top
	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(classPtr)),
		uintptr(unsafe.Pointer(textPtr)),
		uintptr(style),
		uintptr(box.Left), uintptr(box.Top), uintptr(width), uintptr(height),
		uintptr(parent), uintptr(id), 0, 0,
	)
	return syscall.Handle(hwnd)
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111:
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case wmAppCommand:
		state.handleWMCommand(wParam, lParam)
		return 0
	case wmAppLoadDone:
		state.onLoadDone()
		return 0
	case wmAppRefresh:
		state.refreshVisibleList()
		return 0
	case wmAppShowError:
		showWin32Error(state.readQueuedError(lParam))
		return 0
	case win32ui.WmDeferredPresent:
		win32ui.PresentMainWindow(state.mainHWND)
		return 0
	case 0x0006:
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0002:
		if hwnd == state.mainHWND {
			procPostQuitMessage.Call(0)
		}
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func showWin32Error(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 系统词库审查")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
