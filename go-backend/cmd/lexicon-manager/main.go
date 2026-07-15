//go:build windows

package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wmAppCommand   = 0x0400 + 1
	wmAppLoadDone  = 0x0400 + 2
	wmAppRefresh   = 0x0400 + 3
	wmAppShowError = 0x0400 + 4
	wmAppApplyDone = 0x0400 + 5

	enChange = 0x0300 // EN_CHANGE

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsExClientedge     = 0x00000200
	wsOverlappedwindow = 0x00CF0000

	swRestore    = 9
	swShowNormal = 1

	idSearchEdit     = 101
	idSearchReset    = 102
	idSortFieldCombo = 103
	idSortDirection  = 104
	idEntryList      = 105
	idSelectionLabel = 106
	idStatusLabel    = 108
	idApplyProgress  = 109
	idBtnAdd         = 201
	idBtnEdit        = 202
	idBtnDelete      = 203
	idBtnUndo        = 205
	idBtnApply       = 206
	idBtnImport      = 207
	idBtnExport      = 208
	idBtnOpenFolder  = 209

	wsChild               = 0x40000000
	wsVisible             = 0x10000000
	wsBorder              = 0x00800000
	wsVscroll             = 0x00200000
	wsHscroll             = 0x00100000
	wsTabstop             = 0x00010000
	lbsNotify             = 0x0001
	lbsHasstrings         = 0x0040
	lbsMultiplesel        = 0x0008
	lbsExtendedsel        = 0x0800
	entryListStyle        = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | lbsNotify | lbsHasstrings | lbsMultiplesel | lbsExtendedsel
	lexiconListViewStyle  = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | 0x0001 | 0x0008 // LVS_REPORT | LVS_SHOWSELALWAYS
	lbResetcontent        = 0x0184
	lbAddstring           = 0x0180
	lbSetsel              = 0x0185
	lbGetselcount         = 0x0190
	lbGetselitems         = 0x0191
	lbSethorizontalextent = 0x0194
	lbnSelchange          = 1
	lbnDblclk             = 2
	lvmFirst              = 0x1000
	lvmDeleteallitems     = lvmFirst + 9
	lvmGetnextitem        = lvmFirst + 12
	lvmSetcolumnwidth     = lvmFirst + 30
	lvmSetitemstate       = lvmFirst + 43
	lvmSetextendedstyle   = lvmFirst + 54
	lvmInsertitemw        = lvmFirst + 77
	lvmSetitemtextw       = lvmFirst + 116
	lvmInsertcolumnw      = lvmFirst + 97
	lvifText              = 0x0001
	lvcfText              = 0x0004
	lvcfWidth             = 0x0002
	lvniSelected          = 0x0002
	lvisSelected          = 0x0002
	lvsExGridlines        = 0x00000001
	lvsExFullrowselect    = 0x00000020
	lvsExDoublebuffer     = 0x00010000
	pbsMarquee            = 0x0008
	pbmSetMarquee         = 0x040A
	esMultiline           = 0x0004
	esAutoVscroll         = 0x0040
	esAutoHscroll         = 0x0080
	esReadonly            = 0x0800
)

var (
	moduser32   = syscall.NewLazyDLL("user32.dll")
	modkernel32 = syscall.NewLazyDLL("kernel32.dll")
	modcomctl32 = syscall.NewLazyDLL("comctl32.dll")
	modcomdlg32 = syscall.NewLazyDLL("comdlg32.dll")
	modgdi32    = syscall.NewLazyDLL("gdi32.dll")

	procCreateWindowExW       = moduser32.NewProc("CreateWindowExW")
	procDefWindowProcW        = moduser32.NewProc("DefWindowProcW")
	procDispatchMessageW      = moduser32.NewProc("DispatchMessageW")
	procGetMessageW           = moduser32.NewProc("GetMessageW")
	procTranslateMessageW     = moduser32.NewProc("TranslateMessage")
	procIsDialogMessageW      = moduser32.NewProc("IsDialogMessageW")
	procPostQuitMessage       = moduser32.NewProc("PostQuitMessage")
	procRegisterClassExW      = moduser32.NewProc("RegisterClassExW")
	procSendMessageW          = moduser32.NewProc("SendMessageW")
	procSetWindowTextW        = moduser32.NewProc("SetWindowTextW")
	procGetWindowTextLengthW  = moduser32.NewProc("GetWindowTextLengthW")
	procGetWindowTextW        = moduser32.NewProc("GetWindowTextW")
	procGetSystemMetrics      = moduser32.NewProc("GetSystemMetrics")
	procGetDC                 = moduser32.NewProc("GetDC")
	procReleaseDC             = moduser32.NewProc("ReleaseDC")
	procGetActiveWindow       = moduser32.NewProc("GetActiveWindow")
	procPostMessageW          = moduser32.NewProc("PostMessageW")
	procGetFocus              = moduser32.NewProc("GetFocus")
	procSetFocus              = moduser32.NewProc("SetFocus")
	procShowWindow            = moduser32.NewProc("ShowWindow")
	procUpdateWindow          = moduser32.NewProc("UpdateWindow")
	procSetForegroundWindow   = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop      = moduser32.NewProc("BringWindowToTop")
	procIsIconic              = moduser32.NewProc("IsIconic")
	procLoadCursorW           = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx    = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW      = modkernel32.NewProc("GetModuleHandleW")
	procInitCommonControlsEx  = modcomctl32.NewProc("InitCommonControlsEx")
	procGetOpenFileNameW      = modcomdlg32.NewProc("GetOpenFileNameW")
	procGetSaveFileNameW      = modcomdlg32.NewProc("GetSaveFileNameW")
	procGetTextExtentPoint32W = modgdi32.NewProc("GetTextExtentPoint32W")
	procFindWindowW           = moduser32.NewProc("FindWindowW")
	procMoveWindow            = moduser32.NewProc("MoveWindow")

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

type textSize struct {
	Width  int32
	Height int32
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

type lexiconInfoLayout struct {
	list, selection, status rect
}

type lexiconToolbarItem struct {
	text string
	id   int
}

type lexiconColumnSpec struct {
	title string
	width int32
}

type appState struct {
	sharedDir         string
	userDir           string
	mode              reverselookup.Mode
	sourcePath        string
	rimeLexiconPath   string
	codeMap           map[string]reverselookup.CodeRecord
	codeMapLoaded     bool
	codeMapErr        error
	systemLexicon     map[string]struct{}
	systemLexiconErr  error
	systemLexiconOnce bool
	dirty             bool
	sortField         userlexicon.SortField
	sortDescending    bool
	lastUndoEntries   []userlexicon.Entry
	lastUndoLabel     string
	operationHistory  []string
	visibleEntries    []userlexicon.Entry
	mainHWND          syscall.Handle
	toolbarHWNDs      []syscall.Handle
	modeHWND          syscall.Handle
	searchLabelHWND   syscall.Handle
	searchHWND        syscall.Handle
	searchResetHWND   syscall.Handle
	sortFieldHWND     syscall.Handle
	sortDirectionHWND syscall.Handle
	listHWND          syscall.Handle
	selectionHWND     syscall.Handle
	statusHWND        syscall.Handle
	progressHWND      syscall.Handle
	clientW           int32
	clientH           int32
	addOnLoad         bool
	applyMu           sync.Mutex
	applyRunning      bool
	applyErr          error
}

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	mode := flag.String("Mode", "variable", "Yime schema mode: variable, full, shorthand")
	addMode := flag.Bool("Add", false, "Open the add-phrase dialog immediately after launch")
	flag.Parse()
	if strings.TrimSpace(*sharedDir) == "" || strings.TrimSpace(*userDir) == "" {
		showMessageBox("缺少 SharedDir 或 UserDir 参数。", 0x10)
		os.Exit(1)
	}
	state := &appState{
		sharedDir:       strings.TrimSpace(*sharedDir),
		userDir:         strings.TrimSpace(*userDir),
		mode:            reverselookup.Mode(strings.TrimSpace(*mode)),
		sourcePath:      filepath.Join(strings.TrimSpace(*userDir), userlexicon.SourceFileName),
		rimeLexiconPath: userlexicon.RimeLexiconPath(strings.TrimSpace(*userDir), strings.TrimSpace(*mode)),
		addOnLoad:       *addMode,
	}
	if err := runApp(state); err != nil {
		showMessageBox(err.Error(), 0x10)
		os.Exit(1)
	}
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if hwnd := findExistingWindow("YimeLexiconManager"); hwnd != 0 {
		win32ui.PresentMainWindow(hwnd)
		if state.addOnLoad {
			procPostMessageW.Call(uintptr(hwnd), wmAppCommand, uintptr(idBtnAdd), 0)
		}
		return nil
	}

	state.clientW = 780
	state.clientH = 440

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeLexiconManager")
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

	title, _ := syscall.UTF16PtrFromString("词库管理")
	winW, winH := windowSizeForClient(state.clientW, state.clientH)
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
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
	state.createControls()
	state.presentMainWindowAfterLaunch()
	go func() {
		codeMap, err := reverselookup.LoadSharedCodeMap(state.sharedDir)
		time.Sleep(10 * time.Millisecond)
		state.codeMap = codeMap
		state.codeMapErr = err
		state.codeMapLoaded = true
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppLoadDone, 0, 0)
		if state.addOnLoad {
			time.Sleep(50 * time.Millisecond)
			procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, uintptr(idBtnAdd), 0)
		}
	}()

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

func (state *appState) createControls() {
	const (
		margin       = int32(8)
		contentLeft  = margin
		contentRight = int32(772)
		gap          = int32(6)
		toolbarY     = int32(8)
		toolbarH     = int32(28)
		rowY         = int32(68)
		rowH         = int32(26)
	)

	toolbar := lexiconToolbarItems()
	buttonRects := toolbarButtonRects(contentLeft, contentRight, len(toolbar))
	state.toolbarHWNDs = make([]syscall.Handle, 0, len(toolbar))
	for i, spec := range toolbar {
		box := buttonRects[i]
		box.Top, box.Bottom = toolbarY, toolbarY+toolbarH
		state.toolbarHWNDs = append(state.toolbarHWNDs, createButton(state.mainHWND, spec.text, box, spec.id))
	}

	modeText := fmt.Sprintf("编码方案：%s", modeDisplayName(state.mode))
	state.modeHWND = createStatic(state.mainHWND, modeText, rect{contentLeft, 44, contentRight, 64}, 0)

	const labelW, resetW, comboW, dirW = int32(48), int32(64), int32(88), int32(64)
	labelRight := contentLeft + labelW
	searchLeft := labelRight + gap
	resetRight := contentRight - comboW - gap - dirW - gap
	resetLeft := resetRight - resetW
	searchRight := resetLeft - gap
	comboLeft := resetRight + gap
	comboRight := comboLeft + comboW
	dirLeft := comboRight + gap

	state.searchLabelHWND = createStatic(state.mainHWND, "搜索", rect{contentLeft, rowY + 4, labelRight, rowY + 24}, 0)
	state.searchHWND = createEdit(state.mainHWND, rect{searchLeft, rowY, searchRight, rowY + rowH}, idSearchEdit)
	state.searchResetHWND = createButton(state.mainHWND, "清空", rect{resetLeft, rowY, resetRight, rowY + rowH}, idSearchReset)

	state.sortFieldHWND = createCombo(state.mainHWND, rect{comboLeft, rowY, comboRight, rowY + 132}, idSortFieldCombo)
	for _, label := range []string{"词条", "拼音", "权重"} {
		text, _ := syscall.UTF16PtrFromString(label)
		procSendMessageW.Call(uintptr(state.sortFieldHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	procSendMessageW.Call(uintptr(state.sortFieldHWND), 0x014E, 0, 0)

	state.sortDirectionHWND = createButton(state.mainHWND, "升序", rect{dirLeft, rowY, contentRight, rowY + rowH}, idSortDirection)

	info := buildLexiconInfoLayout(contentLeft, contentRight, state.clientH)
	state.listHWND = createControl("SysListView32", "", lexiconListViewStyle, info.list, state.mainHWND, idEntryList)
	state.configureLexiconColumns()
	state.selectionHWND = createStatic(state.mainHWND, "请在搜索框中输入想要编辑的词条。", info.selection, idSelectionLabel)
	state.statusHWND = createStatic(state.mainHWND, "就绪。", info.status, idStatusLabel)
	state.progressHWND = createControl("msctls_progress32", "", wsChild|pbsMarquee, info.status, state.mainHWND, idApplyProgress)

	state.layoutControls(state.clientW, state.clientH)
	state.refreshList()
	state.updateToolbarState()
}

func lexiconToolbarItems() []lexiconToolbarItem {
	return []lexiconToolbarItem{
		{"编辑", idBtnEdit},
		{"添加", idBtnAdd},
		{"删除", idBtnDelete},
		{"撤销", idBtnUndo},
		{"应用", idBtnApply},
		{"导入", idBtnImport},
		{"导出", idBtnExport},
		{"文档", idBtnOpenFolder},
	}
}

func toolbarButtonRects(left, right int32, count int) []rect {
	if count <= 0 {
		return nil
	}
	const gap, maxButtonWidth = int32(6), int32(96)
	available := right - left
	buttonWidth := (available - gap*int32(count-1)) / int32(count)
	if buttonWidth > maxButtonWidth {
		buttonWidth = maxButtonWidth
	}
	totalWidth := buttonWidth*int32(count) + gap*int32(count-1)
	x := left + (available-totalWidth)/2
	result := make([]rect, count)
	for index := range result {
		result[index] = rect{Left: x, Right: x + buttonWidth}
		x += buttonWidth + gap
	}
	return result
}

func (state *appState) toolbarButton(id int) syscall.Handle {
	for index, item := range lexiconToolbarItems() {
		if item.id == id && index < len(state.toolbarHWNDs) {
			return state.toolbarHWNDs[index]
		}
	}
	return 0
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

func (state *appState) updateToolbarState() {
	busy := state.isApplyRunning()
	selectedCount := len(state.selectedPhrases())
	for _, item := range lexiconToolbarItems() {
		enabled := !busy
		switch item.id {
		case idBtnEdit:
			enabled = !busy && state.codeMapLoaded && state.codeMapErr == nil && selectedCount == 1
		case idBtnDelete:
			enabled = !busy && selectedCount > 0
		case idBtnAdd, idBtnImport:
			enabled = !busy && state.codeMapLoaded && state.codeMapErr == nil
		case idBtnUndo:
			enabled = !busy && state.lastUndoEntries != nil
		case idBtnApply:
			enabled = !busy && state.dirty && state.codeMapLoaded && state.codeMapErr == nil
		case idBtnOpenFolder:
			enabled = true
		}
		setControlEnabled(state.toolbarButton(item.id), enabled)
	}
	applyText := "应用"
	if busy {
		applyText = "应用中…"
	}
	setWindowText(state.toolbarButton(idBtnApply), applyText)
	setWindowText(state.toolbarButton(idBtnUndo), undoButtonText(state.lastUndoLabel))
	if busy {
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 1, 30)
		procShowWindow.Call(uintptr(state.progressHWND), 5)
	} else {
		procSendMessageW.Call(uintptr(state.progressHWND), pbmSetMarquee, 0, 0)
		procShowWindow.Call(uintptr(state.progressHWND), 0)
	}
	state.layoutControls(state.clientW, state.clientH)
}

func undoButtonText(label string) string {
	switch {
	case strings.Contains(label, "导入"):
		return "撤销导入"
	case strings.Contains(label, "删除"):
		return "撤销删除"
	case strings.Contains(label, "编辑"):
		return "撤销编辑"
	case strings.Contains(label, "添加"), strings.Contains(label, "更新"):
		return "撤销添加"
	case strings.TrimSpace(label) != "":
		return "撤销操作"
	default:
		return "撤销"
	}
}

func lexiconColumns() []lexiconColumnSpec {
	return []lexiconColumnSpec{
		{title: "词条", width: 180},
		{title: "数字标调拼音", width: 450},
		{title: "权重", width: 110},
	}
}

func (state *appState) configureLexiconColumns() {
	extendedStyle := uintptr(lvsExGridlines | lvsExFullrowselect | lvsExDoublebuffer)
	procSendMessageW.Call(uintptr(state.listHWND), lvmSetextendedstyle, extendedStyle, extendedStyle)
	for index, spec := range lexiconColumns() {
		text, _ := syscall.UTF16PtrFromString(spec.title)
		column := listViewColumn{
			Mask:    lvcfText | lvcfWidth,
			Width:   spec.width,
			Text:    text,
			TextMax: int32(len([]rune(spec.title))),
		}
		procSendMessageW.Call(uintptr(state.listHWND), lvmInsertcolumnw, uintptr(index), uintptr(unsafe.Pointer(&column)))
	}
}

func lexiconColumnWidths(listWidth int32) []int32 {
	const phraseWidth, weightWidth, borderAndScrollbar = int32(180), int32(110), int32(22)
	pinyinWidth := listWidth - phraseWidth - weightWidth - borderAndScrollbar
	if pinyinWidth < 240 {
		pinyinWidth = 240
	}
	return []int32{phraseWidth, pinyinWidth, weightWidth}
}

func (state *appState) resizeLexiconColumns(listWidth int32) {
	for index, width := range lexiconColumnWidths(listWidth) {
		procSendMessageW.Call(uintptr(state.listHWND), lvmSetcolumnwidth, uintptr(index), uintptr(width))
	}
}

func buildLexiconInfoLayout(left, right, clientHeight int32) lexiconInfoLayout {
	listBottom := clientHeight - 80
	return lexiconInfoLayout{
		list:      rect{left, 100, right, listBottom},
		selection: rect{left, listBottom + 8, right, listBottom + 32},
		status:    rect{left, listBottom + 40, right, listBottom + 64},
	}
}

func moveControl(hwnd syscall.Handle, box rect) {
	if hwnd == 0 {
		return
	}
	procMoveWindow.Call(uintptr(hwnd), uintptr(box.Left), uintptr(box.Top), uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top), 1)
}

func statusProgressLayout(status rect, busy bool) (text rect, progress rect) {
	text = status
	if !busy {
		return text, rect{}
	}
	const gap, progressWidth = int32(8), int32(180)
	progress = rect{Left: status.Right - progressWidth, Top: status.Top, Right: status.Right, Bottom: status.Bottom}
	text.Right = progress.Left - gap
	return text, progress
}

func (state *appState) layoutControls(clientWidth, clientHeight int32) {
	if clientWidth <= 0 || clientHeight <= 0 {
		return
	}
	state.clientW, state.clientH = clientWidth, clientHeight
	const margin, gap, toolbarY, toolbarH = int32(8), int32(6), int32(8), int32(28)
	contentLeft, contentRight := margin, clientWidth-margin
	if len(state.toolbarHWNDs) > 0 {
		buttonRects := toolbarButtonRects(contentLeft, contentRight, len(state.toolbarHWNDs))
		for index, hwnd := range state.toolbarHWNDs {
			box := buttonRects[index]
			box.Top, box.Bottom = toolbarY, toolbarY+toolbarH
			moveControl(hwnd, box)
		}
	}
	moveControl(state.modeHWND, rect{contentLeft, 44, contentRight, 64})

	const rowY, rowH = int32(68), int32(26)
	const labelW, resetW, comboW, dirW = int32(48), int32(64), int32(88), int32(64)
	labelRight := contentLeft + labelW
	searchLeft := labelRight + gap
	resetRight := contentRight - comboW - gap - dirW - gap
	resetLeft := resetRight - resetW
	searchRight := resetLeft - gap
	comboLeft := resetRight + gap
	comboRight := comboLeft + comboW
	dirLeft := comboRight + gap
	moveControl(state.searchLabelHWND, rect{contentLeft, rowY + 4, labelRight, rowY + 24})
	moveControl(state.searchHWND, rect{searchLeft, rowY, searchRight, rowY + rowH})
	moveControl(state.searchResetHWND, rect{resetLeft, rowY, resetRight, rowY + rowH})
	moveControl(state.sortFieldHWND, rect{comboLeft, rowY, comboRight, rowY + 132})
	moveControl(state.sortDirectionHWND, rect{dirLeft, rowY, contentRight, rowY + rowH})

	info := buildLexiconInfoLayout(contentLeft, contentRight, clientHeight)
	moveControl(state.listHWND, info.list)
	moveControl(state.selectionHWND, info.selection)
	statusBox, progressBox := statusProgressLayout(info.status, state.isApplyRunning())
	moveControl(state.statusHWND, statusBox)
	if progressBox.Right > progressBox.Left {
		moveControl(state.progressHWND, progressBox)
	}
	state.resizeLexiconColumns(info.list.Right - info.list.Left)
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
			width, height := windowSizeForClient(780, 440)
			info := win32ui.ReadMessageStruct[minMaxInfo](lParam)
			info.MinTrackSize = point{X: width, Y: height}
			win32ui.WriteMessageStruct(lParam, &info)
		}
		return 0
	case 0x0111:
		state.handleCommand(wParam, lParam)
		return 0
	case 0x004E: // WM_NOTIFY
		state.handleNotify(lParam)
		return 0
	case wmAppCommand:
		state.handleCommand(wParam, lParam)
		return 0
	case wmAppLoadDone:
		state.onCodeMapLoaded()
		return 0
	case wmAppRefresh:
		state.refreshList()
		return 0
	case wmAppShowError:
		showMessageBox(state.readQueuedError(lParam), 0x10)
		return 0
	case wmAppApplyDone:
		state.finishApplyLexicon()
		return 0
	case 0x0006:
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0010:
		if state.isApplyRunning() {
			setWindowText(state.statusHWND, "正在应用用户词库，请等待完成后再关闭。")
			return 0
		}
		if state.dirty {
			if !showConfirmDialog(state.mainHWND, "退出词库管理", "源词库有未应用改动，确认要关闭吗？") {
				return 0
			}
		}
		procPostQuitMessage.Call(0)
		return 0
	case 0x0002:
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

var queuedError string

func (state *appState) readQueuedError(_ uintptr) string {
	msg := queuedError
	queuedError = ""
	return msg
}

func findExistingWindow(className string) syscall.Handle {
	classPtr, err := syscall.UTF16PtrFromString(className)
	if err != nil {
		return 0
	}
	hwnd, _, _ := procFindWindowW.Call(uintptr(unsafe.Pointer(classPtr)), 0)
	return syscall.Handle(hwnd)
}

func (state *appState) handleCommand(wParam, _ uintptr) {
	id := int(wParam & 0xffff)
	notify := int((wParam >> 16) & 0xffff)
	if state.isApplyRunning() && id != idBtnOpenFolder {
		return
	}
	if id == idSearchEdit && notify == enChange {
		state.refreshList()
		return
	}
	if notify == 1 && id == idSortFieldCombo {
		state.refreshList()
		return
	}
	switch id {
	case idBtnAdd, idBtnEdit, idBtnDelete, idBtnUndo, idBtnApply, idBtnImport, idBtnExport, idBtnOpenFolder, idSearchReset, idSortDirection:
		if notify != 0 {
			return
		}
	}
	switch id {
	case idBtnAdd:
		state.addEntry()
	case idBtnEdit:
		state.editSelected()
	case idBtnDelete:
		state.deleteSelected()
	case idBtnUndo:
		state.undoLastChange()
	case idBtnApply:
		state.applyLexicon()
	case idBtnImport:
		state.importLexicon()
	case idBtnExport:
		state.exportLexicon()
	case idBtnOpenFolder:
		state.openUserFolder()
	case idSearchReset:
		setWindowText(state.searchHWND, "")
		state.refreshList()
	case idSortDirection:
		state.sortDescending = !state.sortDescending
		if state.sortDescending {
			setWindowText(state.sortDirectionHWND, "降序")
		} else {
			setWindowText(state.sortDirectionHWND, "升序")
		}
		state.refreshList()
	}
}

func (state *appState) handleNotify(lParam uintptr) {
	if lParam == 0 {
		return
	}
	header := win32ui.ReadMessageStruct[notifyHeader](lParam)
	if int(header.IDFrom) != idEntryList {
		return
	}
	switch header.Code {
	case -101: // LVN_ITEMCHANGED
		state.updateSelectionSummary()
	case -3: // NM_DBLCLK
		state.editSelected()
	}
}

func modeDisplayName(mode reverselookup.Mode) string {
	switch mode {
	case reverselookup.ModeVariable:
		return "变长模式"
	case reverselookup.ModeFull:
		return "等长模式"
	case reverselookup.ModeShorthand:
		return "省键模式"
	default:
		return string(mode)
	}
}

func (state *appState) onCodeMapLoaded() {
	if state.codeMapErr != nil {
		message := "编码表加载失败：" + state.codeMapErr.Error()
		setWindowText(state.statusHWND, message)
		state.updateToolbarState()
		showNoticeDialog(state.mainHWND, "词库管理初始化失败", message)
		return
	}
	_, syncErr := userlexicon.HydrateSourceIfEmpty(state.userDir, state.mode, state.codeMap)
	state.refreshList()
	if syncErr != nil {
		message := "同步用户词库失败：" + syncErr.Error()
		setWindowText(state.statusHWND, message)
		showNoticeDialog(state.mainHWND, "词库同步失败", message)
	}
}

func (state *appState) requireCodeMap() error {
	if !state.codeMapLoaded {
		return fmt.Errorf("编码表仍在加载，请稍后再试。")
	}
	if state.codeMapErr != nil {
		return state.codeMapErr
	}
	return nil
}

func (state *appState) presentMainWindow() {
	win32ui.PresentMainWindow(state.mainHWND)
	state.focusSearchIfNeeded()
}

func (state *appState) presentMainWindowAfterLaunch() {
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
	state.focusSearchIfNeeded()
}

func (state *appState) focusSearchIfNeeded() {
	if state.searchHWND == 0 {
		return
	}
	focused, _, _ := procGetFocus.Call()
	if focused != 0 && focused != uintptr(state.mainHWND) && isChildOf(state.mainHWND, syscall.Handle(focused)) {
		return
	}
	procSetFocus.Call(uintptr(state.searchHWND))
	procSendMessageW.Call(uintptr(state.searchHWND), 0x00B1, 0, 0) // EM_SETSEL: caret at start.
}

func (state *appState) ensureRestored() {
	hwnd := uintptr(state.mainHWND)
	iconic, _, _ := procIsIconic.Call(hwnd)
	if iconic != 0 {
		procShowWindow.Call(hwnd, swRestore)
	}
}

func createStatic(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("STATIC", text, 0x50000000, box, parent, id)
}

func createAutoStatic(parent syscall.Handle, text string, left, top, height int32, id int) syscall.Handle {
	width := measureTextWidth(parent, text) + 4
	return createStatic(parent, text, rect{left, top, left + width, top + height}, id)
}

func measureTextWidth(parent syscall.Handle, text string) int32 {
	data, err := syscall.UTF16FromString(text)
	if err != nil || len(data) <= 1 {
		return int32(len([]rune(text))) * 16
	}
	dc, _, _ := procGetDC.Call(uintptr(parent))
	if dc == 0 {
		return int32(len([]rune(text))) * 16
	}
	defer procReleaseDC.Call(uintptr(parent), dc)

	size := textSize{}
	ret, _, _ := procGetTextExtentPoint32W.Call(
		dc,
		uintptr(unsafe.Pointer(&data[0])),
		uintptr(len(data)-1),
		uintptr(unsafe.Pointer(&size)),
	)
	if ret == 0 || size.Width <= 0 {
		return int32(len([]rune(text))) * 16
	}
	return size.Width
}

func createButton(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("BUTTON", text, 0x50010000, box, parent, id)
}

func createEdit(parent syscall.Handle, box rect, id int) syscall.Handle {
	return createControlEx(wsExClientedge, "EDIT", "", 0x50210080, box, parent, id)
}

func createReadOnlyScrollEdit(parent syscall.Handle, box rect, id int) syscall.Handle {
	style := int32(wsChild | wsVisible | wsBorder | wsVscroll | wsHscroll | wsTabstop | esMultiline | esAutoVscroll | esAutoHscroll | esReadonly)
	return createControlEx(wsExClientedge, "EDIT", "", style, box, parent, id)
}

func createCombo(parent syscall.Handle, box rect, id int) syscall.Handle {
	return createControl("COMBOBOX", "", 0x50200203, box, parent, id)
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

func showMessageBox(message string, flags uintptr) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	owner, _, _ := procGetActiveWindow.Call()
	showNoticeDialog(syscall.Handle(owner), noticeTitleForFlags(flags), message)
}

func noticeTitleForFlags(flags uintptr) string {
	switch flags & 0xF0 {
	case 0x10:
		return "操作失败"
	case 0x30:
		return "提示"
	case 0x40:
		return "操作完成"
	default:
		return "词库管理"
	}
}

func setWindowText(hwnd syscall.Handle, text string) {
	ptr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(ptr)))
}

func getWindowText(hwnd syscall.Handle) string {
	length, _, _ := procGetWindowTextLengthW.Call(uintptr(hwnd))
	if length == 0 {
		return ""
	}
	buf := make([]uint16, length+1)
	procGetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&buf[0])), length+1)
	return syscall.UTF16ToString(buf)
}
