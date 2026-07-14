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
	"time"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	wmAppLoadDone   = 0x0400 + 1
	wmAppSearchDone = 0x0400 + 2
	wmAppSearchRun  = 0x0400 + 3
	wmAppCommand    = 0x0400 + 4
	enChange        = 0x0300

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsExClientedge     = 0x00000200
	wsOverlappedwindow = 0x00CF0000

	swRestore    = 9
	swShowNormal = 1

	idSearchEdit    = 101
	idContainsCheck = 102
	idModeCombo     = 103
	idSearchButton  = 104
	idResultList    = 105
	idDetailView    = 106
	idStatusLabel   = 107
	idBusyProgress  = 108

	cbsDropdownlist = 0x0003
	cbAddstring     = 0x0143
	cbSetcursel     = 0x014E
	cbGetcursel     = 0x0147
	cbSelchange     = 1
	bmGetcheck      = 0x00F0
	bstChecked      = 1

	wsChild             = 0x40000000
	wsVisible           = 0x10000000
	wsBorder            = 0x00800000
	wsVscroll           = 0x00200000
	wsTabstop           = 0x00010000
	listViewStyle       = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | 0x0001 | 0x0004 | 0x0008 // report|single-select|show-selection
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
	procShowWindow           = moduser32.NewProc("ShowWindow")
	procUpdateWindow         = moduser32.NewProc("UpdateWindow")
	procGetFocus             = moduser32.NewProc("GetFocus")
	procGetParent            = moduser32.NewProc("GetParent")
	procSetFocus             = moduser32.NewProc("SetFocus")
	procSetForegroundWindow  = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop     = moduser32.NewProc("BringWindowToTop")
	procEnableWindow         = moduser32.NewProc("EnableWindow")
	procMoveWindow           = moduser32.NewProc("MoveWindow")
	procIsIconic             = moduser32.NewProc("IsIconic")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")

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

type point struct {
	X int32
	Y int32
}

type minMaxInfo struct {
	Reserved     point
	MaxSize      point
	MaxPosition  point
	MinTrackSize point
	MaxTrackSize point
}

type initCommonControlsEx struct {
	Size uint32
	ICC  uint32
}

type listViewColumn struct {
	Mask         uint32
	Format       int32
	Width        int32
	Text         *uint16
	TextMax      int32
	SubItem      int32
	Image        int32
	Order        int32
	MinWidth     int32
	DefaultWidth int32
	IdealWidth   int32
}

type listViewItem struct {
	Mask      uint32
	Item      int32
	SubItem   int32
	State     uint32
	StateMask uint32
	Text      *uint16
	TextMax   int32
	Image     int32
	Param     uintptr
	Indent    int32
	GroupID   int32
	Columns   uint32
	Column    *uint32
	Group     int32
}

type notifyHeader struct {
	WindowFrom syscall.Handle
	IDFrom     uintptr
	Code       int32
}

type resultColumnSpec struct {
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
	containsCheck    rect
	modeLabel        rect
	modeCombo        rect
	searchButton     rect
	resultList       rect
	detailView       rect
	statusLabel      rect
}

type appState struct {
	sharedDir          string
	userDir            string
	mode               reverselookup.Mode
	index              *reverselookup.Index
	loading            bool
	searching          bool
	suppressListNotify bool
	loadErr            error
	results            []reverselookup.Result
	searchTimer        *time.Timer
	mu                 sync.Mutex
	layout             uiLayout
	mainHWND           syscall.Handle
	searchLabelHWND    syscall.Handle
	searchHWND         syscall.Handle
	containsHWND       syscall.Handle
	modeLabelHWND      syscall.Handle
	modeHWND           syscall.Handle
	searchButtonHWND   syscall.Handle
	resultHWND         syscall.Handle
	detailHWND         syscall.Handle
	statusHWND         syscall.Handle
	progressHWND       syscall.Handle
	modeOptions        []modeOption
}

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	mode := flag.String("Mode", "variable", "Yime schema mode: variable, full, shorthand")
	flag.Parse()

	if strings.TrimSpace(*sharedDir) == "" || strings.TrimSpace(*userDir) == "" {
		showWin32Error("缺少 SharedDir 或 UserDir 参数。")
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
	}
	if err := runWin32App(state); err != nil {
		showWin32Error(err.Error())
		os.Exit(1)
	}
}

func buildUILayout() uiLayout {
	return buildUILayoutForSize(820, 560)
}

func buildUILayoutForSize(clientW, clientH int32) uiLayout {
	const margin, gap, rowY, rowH = int32(12), int32(8), int32(10), int32(26)
	const searchLabelW, searchBtnW, containsW, modeLabelW, modeComboW = int32(48), int32(64), int32(104), int32(40), int32(100)
	contentRight := clientW - margin
	layout := uiLayout{clientW: clientW, clientH: clientH}
	layout.searchLabel = rect{margin, rowY + 4, margin + searchLabelW, rowY + 22}
	layout.searchButton = rect{contentRight - searchBtnW, rowY, contentRight, rowY + rowH}
	layout.modeCombo = rect{layout.searchButton.Left - gap - modeComboW, rowY, layout.searchButton.Left - gap, rowY + 120}
	layout.modeLabel = rect{layout.modeCombo.Left - gap - modeLabelW, rowY + 4, layout.modeCombo.Left - gap, rowY + 22}
	layout.containsCheck = rect{layout.modeLabel.Left - gap - containsW, rowY + 2, layout.modeLabel.Left - gap, rowY + 24}
	layout.searchEdit = rect{layout.searchLabel.Right + gap, rowY, layout.containsCheck.Left - gap, rowY + rowH}

	listTop := rowY + rowH + gap
	statusBottom := clientH - margin
	layout.statusLabel = rect{margin, statusBottom - 28, contentRight, statusBottom}
	layout.detailView = rect{margin, layout.statusLabel.Top - gap - 140, contentRight, layout.statusLabel.Top - gap}
	layout.resultList = rect{margin, listTop, contentRight, layout.detailView.Top - gap}
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

	if win32ui.ActivateExistingWindow("YimeReverseLookupTool") {
		return nil
	}

	state.layout = buildUILayout()

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeReverseLookupTool")
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

	title, _ := syscall.UTF16PtrFromString("Yime 反查编码")
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
		uintptr(x),
		uintptr(y),
		uintptr(winW),
		uintptr(winH),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowEx failed")
	}
	state.mainHWND = syscall.Handle(hwnd)
	state.createChildControls()
	state.presentMainWindowAfterLaunch()

	state.startLoadIndex()

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
	state.searchLabelHWND = createControl("STATIC", "输入", 0x50000000, l.searchLabel, state.mainHWND, 0)
	state.searchHWND = createControlEx(wsExClientedge, "EDIT", "", 0x50210080, l.searchEdit, state.mainHWND, idSearchEdit)
	state.containsHWND = createControl("BUTTON", "包含匹配", 0x50010003, l.containsCheck, state.mainHWND, idContainsCheck)
	state.modeLabelHWND = createControl("STATIC", "方案", 0x50000000, l.modeLabel, state.mainHWND, 0)
	state.modeHWND = createControl("COMBOBOX", "", 0x50200000|cbsDropdownlist, l.modeCombo, state.mainHWND, idModeCombo)
	for _, option := range state.modeOptions {
		label, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.modeHWND), cbAddstring, 0, uintptr(unsafe.Pointer(label)))
	}
	selectedIndex := 0
	for index, option := range state.modeOptions {
		if option.Value == state.mode {
			selectedIndex = index
			break
		}
	}
	procSendMessageW.Call(uintptr(state.modeHWND), cbSetcursel, uintptr(selectedIndex), 0)
	state.searchButtonHWND = createControl("BUTTON", "查询", 0x50010001, l.searchButton, state.mainHWND, idSearchButton)
	state.resultHWND = createControl("SysListView32", "", listViewStyle, l.resultList, state.mainHWND, idResultList)
	state.configureResultColumns()
	state.detailHWND = createControl("EDIT", "选中词条后在此显示拼音与各方案编码。", detailViewStyle, l.detailView, state.mainHWND, idDetailView)
	state.statusHWND = createControl("STATIC", "输入字词后点击【查询】，可查看标准拼音、数字标调与音元编码。", 0x50000000, l.statusLabel, state.mainHWND, idStatusLabel)
	state.progressHWND = createControl("msctls_progress32", "", wsChild|pbsMarquee, l.statusLabel, state.mainHWND, idBusyProgress)
	state.layoutControls(l.clientW, l.clientH)
	state.updateControlState()
}

func resultColumns() []resultColumnSpec {
	return []resultColumnSpec{
		{title: "词条", width: 100},
		{title: "来源", width: 80},
		{title: "标准拼音", width: 200},
		{title: "当前编码", width: 120},
		{title: "等长", width: 90},
		{title: "变长", width: 90},
		{title: "省键", width: 90},
	}
}

func (state *appState) configureResultColumns() {
	extendedStyle := uintptr(lvsExGridlines | lvsExFullrowselect | lvsExDoublebuffer)
	procSendMessageW.Call(uintptr(state.resultHWND), lvmSetextendedstyle, extendedStyle, extendedStyle)
	for index, spec := range resultColumns() {
		text, _ := syscall.UTF16PtrFromString(spec.title)
		column := listViewColumn{Mask: lvcfText | lvcfWidth, Width: spec.width, Text: text, TextMax: int32(len([]rune(spec.title)))}
		procSendMessageW.Call(uintptr(state.resultHWND), lvmInsertcolumnw, uintptr(index), uintptr(unsafe.Pointer(&column)))
	}
}

func resultColumnWidths(listWidth int32) []int32 {
	const phrase, source, active, full, variable, shorthand, chrome = int32(100), int32(80), int32(120), int32(90), int32(90), int32(90), int32(22)
	pinyin := listWidth - phrase - source - active - full - variable - shorthand - chrome
	if pinyin < 180 {
		pinyin = 180
	}
	return []int32{phrase, source, pinyin, active, full, variable, shorthand}
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
	const gap, progressWidth = int32(8), int32(180)
	progress := rect{status.Right - progressWidth, status.Top, status.Right, status.Bottom}
	status.Right = progress.Left - gap
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
	moveControl(state.containsHWND, l.containsCheck)
	moveControl(state.modeLabelHWND, l.modeLabel)
	moveControl(state.modeHWND, l.modeCombo)
	moveControl(state.searchButtonHWND, l.searchButton)
	moveControl(state.resultHWND, l.resultList)
	moveControl(state.detailHWND, l.detailView)
	busy := state.isBusy()
	status, progress := statusProgressLayout(l.statusLabel, busy)
	moveControl(state.statusHWND, status)
	if progress.Right > progress.Left {
		moveControl(state.progressHWND, progress)
	}
	for index, width := range resultColumnWidths(l.resultList.Right - l.resultList.Left) {
		procSendMessageW.Call(uintptr(state.resultHWND), lvmSetcolumnwidth, uintptr(index), uintptr(width))
	}
}

func createControl(className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	return createControlEx(0, className, text, style, box, parent, id)
}

func createControlEx(exStyle int32, className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	width := box.Right - box.Left
	height := box.Bottom - box.Top
	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(exStyle),
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
	if shouldPresentForWindowMessage(message) {
		state.presentMainWindow()
		return 0
	}
	switch message {
	case 0x0005: // WM_SIZE
		state.layoutControls(int32(lParam&0xffff), int32((lParam>>16)&0xffff))
		return 0
	case 0x0024: // WM_GETMINMAXINFO
		if lParam != 0 {
			width, height := windowSizeForClient(820, 560)
			info := win32ui.ReadMessageStruct[minMaxInfo](lParam)
			info.MinTrackSize = point{X: width, Y: height}
			win32ui.WriteMessageStruct(lParam, &info)
		}
		return 0
	case 0x0111: // WM_COMMAND
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case 0x004E: // WM_NOTIFY
		state.handleNotify(lParam)
		return 0
	case wmAppCommand:
		state.handleWMCommand(wParam, lParam)
		return 0
	case wmAppLoadDone:
		state.onLoadDone()
		return 0
	case wmAppSearchRun:
		state.runSearchAsync()
		return 0
	case wmAppSearchDone:
		state.onSearchDone()
		return 0
	case 0x0006: // WM_ACTIVATE
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0002: // WM_DESTROY
		if hwnd == state.mainHWND {
			procPostQuitMessage.Call(0)
		}
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func shouldPresentForWindowMessage(message uint32) bool {
	return win32ui.IsDeferredPresentMessage(message)
}

func (state *appState) presentMainWindow() {
	if uintptr(state.mainHWND) == 0 {
		return
	}
	win32ui.PresentMainWindow(state.mainHWND)
	state.focusSearchIfNeeded()
}

func (state *appState) presentMainWindowAfterLaunch() {
	if uintptr(state.mainHWND) == 0 {
		return
	}
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
	state.focusSearchIfNeeded()
}

func (state *appState) focusSearchIfNeeded() {
	if state.searchHWND == 0 {
		return
	}
	focused, _, _ := procGetFocus.Call()
	if focused != 0 && focused != uintptr(state.mainHWND) && isChildWindow(state.mainHWND, syscall.Handle(focused)) {
		return
	}
	procSetFocus.Call(uintptr(state.searchHWND))
	procSendMessageW.Call(uintptr(state.searchHWND), 0x00B1, 0, 0) // EM_SETSEL: caret at start.
}

func isChildWindow(parent, child syscall.Handle) bool {
	for current := child; current != 0; {
		if current == parent {
			return true
		}
		next, _, _ := procGetParent.Call(uintptr(current))
		current = syscall.Handle(next)
	}
	return false
}

func (state *appState) ensureMainWindowRestored() {
	hwnd := uintptr(state.mainHWND)
	if hwnd == 0 {
		return
	}
	iconic, _, _ := procIsIconic.Call(hwnd)
	if iconic != 0 {
		procShowWindow.Call(hwnd, swRestore)
	}
	procShowWindow.Call(hwnd, swShowNormal)
}

func (state *appState) handleWMCommand(wParam, lParam uintptr) {
	commandID := int(wParam & 0xffff)
	notifyCode := int((wParam >> 16) & 0xffff)
	switch commandID {
	case idSearchButton:
		if notifyCode == 0 {
			state.requestSearch()
		}
	case idSearchEdit:
		if notifyCode == enChange {
			state.updateControlState()
			state.scheduleSearch()
		}
	case idContainsCheck:
		if notifyCode == 0 {
			state.scheduleSearch()
		}
	case idModeCombo:
		if notifyCode == cbSelchange {
			state.onModeChanged()
		}
	}
}

func (state *appState) handleNotify(lParam uintptr) {
	if lParam == 0 || state.suppressListNotify {
		return
	}
	header := win32ui.ReadMessageStruct[notifyHeader](lParam)
	if int(header.IDFrom) == idResultList && header.Code == -101 { // LVN_ITEMCHANGED
		state.updateDetail(-1)
	}
}

func (state *appState) onModeChanged() {
	if state.isBusy() {
		return
	}
	index, _, _ := procSendMessageW.Call(uintptr(state.modeHWND), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(state.modeOptions) {
		return
	}
	newMode := state.modeOptions[index].Value
	if newMode == state.mode {
		return
	}
	state.mode = newMode

	state.mu.Lock()
	currentIndex := state.index
	state.mu.Unlock()

	if currentIndex != nil && currentIndex.SchemaID == reverselookup.SchemaIDFromMode(newMode) {
		currentIndex.SetMode(newMode)
		state.requestSearch()
		return
	}

	state.mu.Lock()
	state.index = nil
	state.mu.Unlock()
	state.startLoadIndex()
}

func (state *appState) startLoadIndex() {
	state.mu.Lock()
	if state.loading {
		state.mu.Unlock()
		return
	}
	state.loading = true
	state.mu.Unlock()
	state.setStatus("正在加载反查数据，请稍候...")
	state.updateControlState()

	sharedDir := state.sharedDir
	userDir := state.userDir
	mode := state.mode

	go func() {
		codeMap, codeMapErr := reverselookup.LoadSharedCodeMap(sharedDir)
		if codeMapErr == nil {
			_, _ = userlexicon.HydrateSourceIfEmpty(userDir, mode, codeMap)
		}
		index, err := reverselookup.Load(sharedDir, userDir, mode)
		state.mu.Lock()
		state.index = index
		state.loadErr = err
		state.loading = false
		state.mu.Unlock()
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppLoadDone, 0, 0)
	}()
}

func (state *appState) onLoadDone() {
	state.mu.Lock()
	err := state.loadErr
	index := state.index
	state.mu.Unlock()
	state.updateControlState()

	if err != nil {
		showWin32Error(err.Error())
		state.setStatus("加载失败：" + err.Error())
		return
	}
	dictCount := len(index.DictLookup)
	state.setStatus(fmt.Sprintf("数据已加载（系统词库 %d 条）。输入字词后点击【查询】。", dictCount))
	if strings.TrimSpace(state.readSearchText()) != "" {
		state.requestSearch()
	}
}

func (state *appState) scheduleSearch() {
	if state.searchTimer != nil {
		state.searchTimer.Stop()
	}
	state.searchTimer = time.AfterFunc(500*time.Millisecond, func() {
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppSearchRun, 0, 0)
	})
}

func (state *appState) requestSearch() {
	if state.searchTimer != nil {
		state.searchTimer.Stop()
		state.searchTimer = nil
	}
	procPostMessageW.Call(uintptr(state.mainHWND), wmAppSearchRun, 0, 0)
}

func (state *appState) runSearchAsync() {
	state.mu.Lock()
	if state.searching {
		state.mu.Unlock()
		return
	}
	index := state.index
	state.mu.Unlock()
	term := strings.TrimSpace(state.readSearchText())
	if term == "" {
		state.results = nil
		state.refreshResultList(nil)
		state.setDetail("选中词条后在此显示拼音与各方案编码。")
		state.setStatus("输入字词后点击【查询】，可查看标准拼音、数字标调与音元编码。")
		state.updateControlState()
		return
	}

	if index == nil {
		state.setStatus("数据尚未加载完成，请稍候...")
		return
	}

	state.mu.Lock()
	state.searching = true
	state.mu.Unlock()
	state.setStatus("正在查询...")
	state.updateControlState()
	contains := state.isContainsChecked()

	go func() {
		results := index.Search(term, contains)
		state.mu.Lock()
		state.results = results
		state.searching = false
		state.mu.Unlock()
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppSearchDone, 0, 0)
	}()
}

func (state *appState) onSearchDone() {
	state.mu.Lock()
	results := append([]reverselookup.Result(nil), state.results...)
	state.mu.Unlock()
	state.updateControlState()

	state.refreshResultList(results)
	if len(results) > 0 {
		selection := listViewItem{State: lvisSelected | lvisFocused, StateMask: lvisSelected | lvisFocused}
		procSendMessageW.Call(uintptr(state.resultHWND), lvmSetitemstate, 0, uintptr(unsafe.Pointer(&selection)))
		state.updateDetail(0)
	} else {
		state.setDetail("未找到匹配结果。")
	}

	switch {
	case len(results) == 0:
		state.setStatus("未找到匹配结果。可勾选【包含匹配】在用户词库和系统词库中模糊搜索。")
	case len(results) >= 200:
		state.setStatus(fmt.Sprintf("找到 %d+ 条结果（已截断）。请缩小搜索范围。", len(results)))
	default:
		state.setStatus(fmt.Sprintf("找到 %d 条结果。选中后可在下方详情区查看编码。", len(results)))
	}
}

func (state *appState) busyState() (loading, searching bool, indexReady bool) {
	state.mu.Lock()
	defer state.mu.Unlock()
	return state.loading, state.searching, state.index != nil
}

func (state *appState) isBusy() bool {
	loading, searching, _ := state.busyState()
	return loading || searching
}

func setControlEnabled(hwnd syscall.Handle, enabled bool) {
	if hwnd == 0 {
		return
	}
	value := uintptr(0)
	if enabled {
		value = 1
	}
	procEnableWindow.Call(uintptr(hwnd), value)
}

func (state *appState) updateControlState() {
	loading, searching, indexReady := state.busyState()
	busy := loading || searching
	setControlEnabled(state.modeHWND, !busy)
	setControlEnabled(state.containsHWND, !busy)
	setControlEnabled(state.searchButtonHWND, !busy && indexReady && strings.TrimSpace(state.readSearchText()) != "")
	buttonText := "查询"
	if loading {
		buttonText = "加载中…"
	} else if searching {
		buttonText = "查询中…"
	}
	setWindowText(state.searchButtonHWND, buttonText)
	if busy {
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 1, 30)
		procShowWindow.Call(uintptr(state.progressHWND), 5)
	} else {
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 0, 0)
		procShowWindow.Call(uintptr(state.progressHWND), 0)
	}
	state.layoutControls(state.layout.clientW, state.layout.clientH)
}

func (state *appState) refreshResultList(results []reverselookup.Result) {
	state.suppressListNotify = true
	defer func() { state.suppressListNotify = false }()

	procSendMessageW.Call(uintptr(state.resultHWND), lvmDeleteallitems, 0, 0)
	for index, result := range results {
		phrase, _ := syscall.UTF16PtrFromString(result.Phrase)
		item := listViewItem{Mask: lvifText, Item: int32(index), Text: phrase}
		inserted, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lvmInsertitemw, 0, uintptr(unsafe.Pointer(&item)))
		if int32(inserted) < 0 {
			continue
		}
		values := []string{result.Source, result.StandardPinyin, result.ActiveCode, result.FullCode, result.VariableCode, result.ShorthandCode}
		for subItem, value := range values {
			text, _ := syscall.UTF16PtrFromString(value)
			cell := listViewItem{Item: int32(index), SubItem: int32(subItem + 1), Text: text}
			procSendMessageW.Call(uintptr(state.resultHWND), lvmSetitemtextw, uintptr(index), uintptr(unsafe.Pointer(&cell)))
		}
	}
}

func (state *appState) updateDetail(selected int) {
	state.mu.Lock()
	results := state.results
	state.mu.Unlock()

	if selected < 0 {
		sel, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lvmGetnextitem, ^uintptr(0), lvniSelected)
		selected = int(int32(sel))
	}
	if selected < 0 || selected >= len(results) {
		state.setDetail("选中词条后在此显示拼音与各方案编码。")
		return
	}
	item := results[selected]
	detail := fmt.Sprintf(
		"词条：%s\r\n来源：%s\r\n数字标调：%s\r\n标准拼音：%s\r\n当前编码：%s\r\n等长：%s\r\n变长：%s\r\n省键：%s",
		item.Phrase, item.Source, item.NumericPinyin, item.StandardPinyin, item.ActiveCode, item.FullCode, item.VariableCode, item.ShorthandCode,
	)
	state.setDetail(detail)
}

func (state *appState) readSearchText() string {
	length, _, _ := procGetWindowTextLengthW.Call(uintptr(state.searchHWND))
	if length == 0 {
		return ""
	}
	buffer := make([]uint16, length+1)
	procGetWindowTextW.Call(uintptr(state.searchHWND), uintptr(unsafe.Pointer(&buffer[0])), length+1)
	return syscall.UTF16ToString(buffer)
}

func (state *appState) isContainsChecked() bool {
	ret, _, _ := procSendMessageW.Call(uintptr(state.containsHWND), bmGetcheck, 0, 0)
	return ret == bstChecked
}

func (state *appState) setStatus(text string) {
	setWindowText(state.statusHWND, text)
}

func setWindowText(hwnd syscall.Handle, text string) {
	textPtr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(textPtr)))
}

func (state *appState) setDetail(text string) {
	textPtr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(state.detailHWND), uintptr(unsafe.Pointer(textPtr)))
}

func showWin32Error(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("反查编码")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
