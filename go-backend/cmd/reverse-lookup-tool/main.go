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

	wsExControlparent = 0x00010000
	wsExAppwindow     = 0x00040000
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

	cbsDropdownlist       = 0x0003
	lbResetcontent        = 0x0184
	lbAddstring           = 0x0180
	lbGetcursel           = 0x0188
	lbSetcursel           = 0x0186
	lbSethorizontalextent = 0x0194
	cbAddstring           = 0x0143
	cbSetcursel           = 0x014E
	cbGetcursel           = 0x0147
	cbSelchange           = 1
	lbnSelchange          = 1
	bmGetcheck            = 0x00F0
	bstChecked            = 1

	wsChild     = 0x40000000
	wsVisible   = 0x10000000
	wsBorder    = 0x00800000
	wsVscroll   = 0x00200000
	wsTabstop   = 0x00010000
	lbsNotify   = 0x0001
	lbsHasstrings = 0x0040
	listBoxStyle = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | lbsNotify | lbsHasstrings

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
	procShowWindow           = moduser32.NewProc("ShowWindow")
	procUpdateWindow         = moduser32.NewProc("UpdateWindow")
	procSetFocus             = moduser32.NewProc("SetFocus")
	procSetForegroundWindow  = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop     = moduser32.NewProc("BringWindowToTop")
	procIsIconic             = moduser32.NewProc("IsIconic")
	procLoadIconW            = moduser32.NewProc("LoadIconW")
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
	searchHWND         syscall.Handle
	containsHWND       syscall.Handle
	modeHWND           syscall.Handle
	resultHWND         syscall.Handle
	detailHWND         syscall.Handle
	statusHWND         syscall.Handle
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
	const (
		margin       = int32(12)
		gap          = int32(8)
		rowGap       = int32(6)
		rowH         = int32(26)
		clientW      = int32(680)
		searchLabelW = int32(60)
		searchBtnW   = int32(64)
		containsW    = int32(104)
		modeLabelW   = int32(40)
		modeComboW   = int32(100)
		listH        = int32(280)
		detailH      = int32(76)
		statusH      = int32(44)
	)

	row1Y := int32(10)
	row2Y := row1Y + rowH + rowGap

	layout := uiLayout{clientW: clientW}

	x := margin
	layout.searchLabel = rect{x, row1Y + 4, x + searchLabelW, row1Y + 4 + 18}
	searchEditLeft := margin + searchLabelW + gap
	searchBtnLeft := clientW - margin - searchBtnW
	layout.searchEdit = rect{searchEditLeft, row1Y, searchBtnLeft - gap, row1Y + rowH}
	layout.searchButton = rect{searchBtnLeft, row1Y, clientW - margin, row1Y + rowH}

	x = margin
	layout.containsCheck = rect{x, row2Y + 2, x + containsW, row2Y + 2 + 22}
	x += containsW + gap
	layout.modeLabel = rect{x, row2Y + 4, x + modeLabelW, row2Y + 4 + 18}
	x += modeLabelW + gap
	layout.modeCombo = rect{x, row2Y, x + modeComboW, row2Y + 120}

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

	if win32ui.ActivateExistingWindow("YimeReverseLookupTool") {
		return nil
	}

	state.layout = buildUILayout()

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeReverseLookupTool")
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
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) createChildControls() {
	l := state.layout
	createControl("STATIC", "查询词条", 0x50000000, l.searchLabel, state.mainHWND, 0)
	state.searchHWND = createControl("EDIT", "", 0x50210000, l.searchEdit, state.mainHWND, idSearchEdit)
	state.containsHWND = createControl("BUTTON", "包含匹配", 0x50010003, l.containsCheck, state.mainHWND, idContainsCheck)
	createControl("STATIC", "方案", 0x50000000, l.modeLabel, state.mainHWND, 0)
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
	createControl("BUTTON", "查询", 0x50010000, l.searchButton, state.mainHWND, idSearchButton)
	state.resultHWND = createControl("LISTBOX", "", listBoxStyle, l.resultList, state.mainHWND, idResultList)
	state.detailHWND = createControl("EDIT", "选中词条后在此显示拼音与各方案编码。", detailViewStyle, l.detailView, state.mainHWND, idDetailView)
	state.statusHWND = createControl("STATIC", "输入字词后点击【查询】，可查看标准拼音、数字标调与音元编码。", 0x50000000, l.statusLabel, state.mainHWND, idStatusLabel)
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
	case 0x0111: // WM_COMMAND
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
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
	case win32ui.WmDeferredPresent:
		win32ui.PresentMainWindow(state.mainHWND)
		return 0
	case 0x0006: // WM_ACTIVATE
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0018: // WM_SHOWWINDOW
		if wParam != 0 && lParam == 0 {
			state.presentMainWindow()
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

func (state *appState) presentMainWindow() {
	if uintptr(state.mainHWND) == 0 {
		return
	}
	win32ui.PresentMainWindow(state.mainHWND)
	procSetFocus.Call(uintptr(state.searchHWND))
}

func (state *appState) presentMainWindowAfterLaunch() {
	if uintptr(state.mainHWND) == 0 {
		return
	}
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
	procSetFocus.Call(uintptr(state.searchHWND))
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
	case idResultList:
		if state.suppressListNotify {
			return
		}
		switch notifyCode {
		case lbnSelchange:
			state.updateDetail(-1)
		}
	}
}

func (state *appState) onModeChanged() {
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
	if state.loading {
		return
	}
	state.loading = true
	state.setStatus("正在加载反查数据，请稍候...")

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
	procPostMessageW.Call(uintptr(state.mainHWND), wmAppSearchRun, 0, 0)
}

func (state *appState) runSearchAsync() {
	if state.searching {
		return
	}
	term := strings.TrimSpace(state.readSearchText())
	if term == "" {
		state.results = nil
		state.refreshResultList(nil)
		state.setDetail("选中词条后在此显示拼音与各方案编码。")
		state.setStatus("输入字词后点击【查询】，可查看标准拼音、数字标调与音元编码。")
		return
	}

	state.mu.Lock()
	index := state.index
	state.mu.Unlock()
	if index == nil {
		state.setStatus("数据尚未加载完成，请稍候...")
		return
	}

	state.searching = true
	state.setStatus("正在查询...")
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

	state.refreshResultList(results)
	if len(results) > 0 {
		procSendMessageW.Call(uintptr(state.resultHWND), lbSetcursel, 0, 0)
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

func (state *appState) refreshResultList(results []reverselookup.Result) {
	state.suppressListNotify = true
	defer func() { state.suppressListNotify = false }()

	procSendMessageW.Call(uintptr(state.resultHWND), lbResetcontent, 0, 0)
	maxExtent := int32(0)
	for _, item := range results {
		line := fmt.Sprintf("%s | %s | %s | %s", item.Phrase, item.Source, item.StandardPinyin, item.ActiveCode)
		text, _ := syscall.UTF16PtrFromString(line)
		procSendMessageW.Call(uintptr(state.resultHWND), lbAddstring, 0, uintptr(unsafe.Pointer(text)))
		if extent := int32(len(line) * 7); extent > maxExtent {
			maxExtent = extent
		}
	}
	if maxExtent < state.layout.resultList.Right-state.layout.resultList.Left {
		maxExtent = state.layout.resultList.Right - state.layout.resultList.Left
	}
	procSendMessageW.Call(uintptr(state.resultHWND), lbSethorizontalextent, uintptr(maxExtent), 0)
}

func (state *appState) updateDetail(selected int) {
	state.mu.Lock()
	results := state.results
	state.mu.Unlock()

	if selected < 0 {
		sel, _, _ := procSendMessageW.Call(uintptr(state.resultHWND), lbGetcursel, 0, 0)
		selected = int(sel)
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
	textPtr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(state.statusHWND), uintptr(unsafe.Pointer(textPtr)))
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
