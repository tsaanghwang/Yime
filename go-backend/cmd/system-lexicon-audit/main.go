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

	idSearchEdit    = 101
	idRuleCombo     = 102
	idModeCombo     = 103
	idRefreshButton = 104
	idResultList    = 105
	idDetailView    = 106
	idExportButton  = 107
	idStatusLabel   = 108
	idBusyProgress  = 109

	cbsDropdownlist = 0x0003
	cbAddstring     = 0x0143
	cbSetcursel     = 0x014E
	cbGetcursel     = 0x0147
	cbSelchange     = 1

	wsChild             = 0x40000000
	wsVisible           = 0x10000000
	wsBorder            = 0x00800000
	wsVscroll           = 0x00200000
	wsTabstop           = 0x00010000
	listViewStyle       = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | 0x0001 | 0x0004 | 0x0008
	lvmFirst            = 0x1000
	lvmDeleteallitems   = lvmFirst + 9
	lvmGetnextitem      = lvmFirst + 12
	lvmSetcolumnwidth   = lvmFirst + 30
	lvmSetitemstate     = lvmFirst + 43
	lvmSetextendedstyle = lvmFirst + 54
	lvmInsertitemw      = lvmFirst + 77
	lvmInsertcolumnw    = lvmFirst + 97
	lvmSetitemtextw     = lvmFirst + 116
	lvifText            = 0x0001
	lvcfText            = 0x0004
	lvcfWidth           = 0x0002
	lvniSelected        = 0x0002
	lvisFocused         = 0x0001
	lvisSelected        = 0x0002
	lvsExGridlines      = 0x00000001
	lvsExFullrowselect  = 0x00000020
	lvsExDoublebuffer   = 0x00010000
	pbsMarquee          = 0x0008
	pbmSetMarquee       = 0x040A

	esMultiline     = 0x0004
	esReadonly      = 0x0800
	esAutoVscroll   = 0x0040
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
	procIsDialogMessageW     = moduser32.NewProc("IsDialogMessageW")
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
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")
	procSetFocus             = moduser32.NewProc("SetFocus")
	procEnableWindow         = moduser32.NewProc("EnableWindow")
	procMoveWindow           = moduser32.NewProc("MoveWindow")
	procShowWindow           = moduser32.NewProc("ShowWindow")

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

type point struct{ X, Y int32 }
type minMaxInfo struct {
	Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize point
}

type initCommonControlsEx struct {
	Size uint32
	ICC  uint32
}

type listViewColumn struct {
	Mask                                                               uint32
	Format, Width                                                      int32
	Text                                                               *uint16
	TextMax, SubItem, Image, Order, MinWidth, DefaultWidth, IdealWidth int32
}
type listViewItem struct {
	Mask             uint32
	Item, SubItem    int32
	State, StateMask uint32
	Text             *uint16
	TextMax, Image   int32
	Param            uintptr
	Indent, GroupID  int32
	Columns          uint32
	Column           *uint32
	Group            int32
}
type notifyHeader struct {
	WindowFrom syscall.Handle
	IDFrom     uintptr
	Code       int32
}
type auditColumnSpec struct {
	title string
	width int32
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
	searchLabelHWND    syscall.Handle
	searchHWND         syscall.Handle
	refreshHWND        syscall.Handle
	ruleLabelHWND      syscall.Handle
	ruleHWND           syscall.Handle
	modeLabelHWND      syscall.Handle
	modeHWND           syscall.Handle
	exportHWND         syscall.Handle
	resultHWND         syscall.Handle
	detailHWND         syscall.Handle
	statusHWND         syscall.Handle
	progressHWND       syscall.Handle
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
	return buildUILayoutForSize(820, 600)
}

func buildUILayoutForSize(clientW, clientH int32) uiLayout {
	const margin, gap, rowH = int32(12), int32(8), int32(26)
	l := uiLayout{clientW: clientW, clientH: clientH}
	right := clientW - margin
	l.searchLabel = rect{margin, 14, margin + 40, 32}
	l.refreshButton = rect{right - 88, 10, right, 36}
	l.searchEdit = rect{l.searchLabel.Right + gap, 10, l.refreshButton.Left - gap, 36}

	const ruleLabelW, ruleComboW, modeLabelW, modeComboW, exportW = int32(40), int32(180), int32(40), int32(100), int32(96)
	groupW := ruleLabelW + gap + ruleComboW + gap + modeLabelW + gap + modeComboW + gap + exportW
	x := margin + (right-margin-groupW)/2
	l.ruleLabel = rect{x, 46, x + ruleLabelW, 64}
	x = l.ruleLabel.Right + gap
	l.ruleCombo = rect{x, 42, x + ruleComboW, 162}
	x = l.ruleCombo.Right + gap
	l.modeLabel = rect{x, 46, x + modeLabelW, 64}
	x = l.modeLabel.Right + gap
	l.modeCombo = rect{x, 42, x + modeComboW, 162}
	x = l.modeCombo.Right + gap
	l.exportButton = rect{x, 42, x + exportW, 42 + rowH}

	l.statusLabel = rect{margin, clientH - margin - 28, right, clientH - margin}
	l.detailView = rect{margin, l.statusLabel.Top - gap - 112, right, l.statusLabel.Top - gap}
	l.resultList = rect{margin, 76, right, l.detailView.Top - gap}
	return l
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
	icon := win32ui.LoadYimeIcon(instance)

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
		handled, _, _ := procIsDialogMessageW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(&message)))
		if handled == 0 {
			procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
			procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
		}
	}
	return nil
}

func (state *appState) createChildControls() {
	l := state.layout
	state.searchLabelHWND = createControl("STATIC", "搜索", 0x50000000, l.searchLabel, state.mainHWND, 0)
	state.searchHWND = createControl("EDIT", "", 0x50210000, l.searchEdit, state.mainHWND, idSearchEdit)
	state.refreshHWND = createControl("BUTTON", "重新扫描", 0x50010000, l.refreshButton, state.mainHWND, idRefreshButton)

	state.ruleLabelHWND = createControl("STATIC", "规则", 0x50000000, l.ruleLabel, state.mainHWND, 0)
	state.ruleHWND = createControl("COMBOBOX", "", 0x50200000|cbsDropdownlist, l.ruleCombo, state.mainHWND, idRuleCombo)
	for _, rule := range state.ruleOptions {
		label, _ := syscall.UTF16PtrFromString(systemlexicon.RuleLabel(rule))
		procSendMessageW.Call(uintptr(state.ruleHWND), cbAddstring, 0, uintptr(unsafe.Pointer(label)))
	}
	procSendMessageW.Call(uintptr(state.ruleHWND), cbSetcursel, 0, 0)

	state.modeLabelHWND = createControl("STATIC", "方案", 0x50000000, l.modeLabel, state.mainHWND, 0)
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

	state.exportHWND = createControl("BUTTON", "导出报告", 0x50010000, l.exportButton, state.mainHWND, idExportButton)
	state.resultHWND = createControl("SysListView32", "", listViewStyle, l.resultList, state.mainHWND, idResultList)
	state.configureAuditColumns()
	state.detailHWND = createControl("EDIT", "审查结果将显示在此。本工具只读，不会修改系统词库。", detailViewStyle, l.detailView, state.mainHWND, idDetailView)
	state.statusHWND = createControl("STATIC", "正在加载系统词库...", 0x50000000, l.statusLabel, state.mainHWND, idStatusLabel)
	state.progressHWND = createControl("msctls_progress32", "", wsChild|pbsMarquee, l.statusLabel, state.mainHWND, idBusyProgress)
	state.layoutControls(l.clientW, l.clientH)
	state.updateControlState()
	procSetFocus.Call(uintptr(state.searchHWND))
}

func auditColumns() []auditColumnSpec {
	return []auditColumnSpec{{"规则", 160}, {"词条", 180}, {"编码", 300}, {"权重", 100}}
}

func (state *appState) configureAuditColumns() {
	extended := uintptr(lvsExGridlines | lvsExFullrowselect | lvsExDoublebuffer)
	procSendMessageW.Call(uintptr(state.resultHWND), lvmSetextendedstyle, extended, extended)
	for index, spec := range auditColumns() {
		text, _ := syscall.UTF16PtrFromString(spec.title)
		column := listViewColumn{Mask: lvcfText | lvcfWidth, Width: spec.width, Text: text}
		procSendMessageW.Call(uintptr(state.resultHWND), lvmInsertcolumnw, uintptr(index), uintptr(unsafe.Pointer(&column)))
	}
}

func auditColumnWidths(listWidth int32) []int32 {
	const rule, phrase, weight, chrome = int32(160), int32(180), int32(100), int32(22)
	code := listWidth - rule - phrase - weight - chrome
	if code < 220 {
		code = 220
	}
	return []int32{rule, phrase, code, weight}
}

func moveControl(hwnd syscall.Handle, box rect) {
	if hwnd == 0 {
		return
	}
	procMoveWindow.Call(uintptr(hwnd), uintptr(box.Left), uintptr(box.Top), uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top), 1)
}

func statusProgressLayout(status rect, busy bool) (rect, rect) {
	if !busy {
		return status, rect{}
	}
	progress := rect{status.Right - 180, status.Top, status.Right, status.Bottom}
	status.Right = progress.Left - 8
	return status, progress
}

func (state *appState) layoutControls(clientW, clientH int32) {
	if clientW <= 0 || clientH <= 0 {
		return
	}
	state.layout = buildUILayoutForSize(clientW, clientH)
	l := state.layout
	moveControl(state.searchLabelHWND, l.searchLabel)
	moveControl(state.searchHWND, l.searchEdit)
	moveControl(state.refreshHWND, l.refreshButton)
	moveControl(state.ruleLabelHWND, l.ruleLabel)
	moveControl(state.ruleHWND, l.ruleCombo)
	moveControl(state.modeLabelHWND, l.modeLabel)
	moveControl(state.modeHWND, l.modeCombo)
	moveControl(state.exportHWND, l.exportButton)
	moveControl(state.resultHWND, l.resultList)
	moveControl(state.detailHWND, l.detailView)
	status, progress := statusProgressLayout(l.statusLabel, state.isLoading())
	moveControl(state.statusHWND, status)
	if progress.Right > progress.Left {
		moveControl(state.progressHWND, progress)
	}
	for index, width := range auditColumnWidths(l.resultList.Right - l.resultList.Left) {
		procSendMessageW.Call(uintptr(state.resultHWND), lvmSetcolumnwidth, uintptr(index), uintptr(width))
	}
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
	control := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(control)
	return control
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0005:
		state.layoutControls(int32(lParam&0xffff), int32((lParam>>16)&0xffff))
		return 0
	case 0x0024:
		if lParam != 0 {
			w, h := windowSizeForClient(820, 600)
			info := win32ui.ReadMessageStruct[minMaxInfo](lParam)
			info.MinTrackSize = point{w, h}
			win32ui.WriteMessageStruct(lParam, &info)
		}
		return 0
	case 0x0111:
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case 0x004E:
		state.handleNotify(lParam)
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

func showWin32Info(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 系统词库审查")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x40)
}
