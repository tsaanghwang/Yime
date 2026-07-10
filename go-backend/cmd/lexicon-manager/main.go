//go:build windows

package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	wmAppCommand   = 0x0400 + 1
	wmAppLoadDone  = 0x0400 + 2
	wmAppRefresh   = 0x0400 + 3
	wmAppShowError = 0x0400 + 4

	enChange = 0x0300 // EN_CHANGE

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000

	swRestore    = 9
	swShowNormal = 1

	idSearchEdit     = 101
	idSearchReset    = 102
	idSortFieldCombo = 103
	idSortDirection  = 104
	idEntryList      = 105
	idSelectionLabel = 106
	idSummaryLabel   = 107
	idStatusLabel    = 108
	idBtnAdd         = 201
	idBtnEdit        = 202
	idBtnDelete      = 203
	idBtnSetWeight   = 204
	idBtnUndo        = 205
	idBtnApply       = 206
	idBtnImport      = 207
	idBtnExport      = 208
	idBtnOpenFolder  = 209

	wsChild               = 0x40000000
	wsVisible             = 0x10000000
	wsBorder              = 0x00800000
	wsVscroll             = 0x00200000
	wsTabstop             = 0x00010000
	lbsNotify             = 0x0001
	lbsHasstrings         = 0x0040
	lbsMultiplesel        = 0x0008
	lbsExtendedsel        = 0x0800
	entryListStyle        = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | lbsNotify | lbsHasstrings | lbsMultiplesel | lbsExtendedsel
	lbResetcontent        = 0x0184
	lbAddstring           = 0x0180
	lbSetsel              = 0x0185
	lbGetselcount         = 0x0190
	lbGetselitems         = 0x0191
	lbSethorizontalextent = 0x0194
	lbnSelchange          = 1
	lbnDblclk             = 2
)

var (
	moduser32   = syscall.NewLazyDLL("user32.dll")
	modkernel32 = syscall.NewLazyDLL("kernel32.dll")
	modcomctl32 = syscall.NewLazyDLL("comctl32.dll")
	modcomdlg32 = syscall.NewLazyDLL("comdlg32.dll")

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
	procSetForegroundWindow  = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop     = moduser32.NewProc("BringWindowToTop")
	procIsIconic             = moduser32.NewProc("IsIconic")
	procLoadIconW            = moduser32.NewProc("LoadIconW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")
	procGetOpenFileNameW     = modcomdlg32.NewProc("GetOpenFileNameW")
	procGetSaveFileNameW     = modcomdlg32.NewProc("GetSaveFileNameW")
	procFindWindowW          = moduser32.NewProc("FindWindowW")

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
	searchHWND        syscall.Handle
	sortFieldHWND     syscall.Handle
	sortDirectionHWND syscall.Handle
	listHWND          syscall.Handle
	selectionHWND     syscall.Handle
	summaryHWND       syscall.Handle
	statusHWND        syscall.Handle
	clientW           int32
	clientH           int32
	addOnLoad         bool
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
	state.clientH = 520

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeLexiconManager")
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
		contentW     = contentRight - contentLeft
		gap          = int32(6)
		toolbarY     = int32(8)
		toolbarH     = int32(28)
		rowY         = int32(68)
		rowH         = int32(26)
	)

	toolbar := []struct {
		text string
		id   int
	}{
		{"添加", idBtnAdd},
		{"编辑", idBtnEdit},
		{"删除", idBtnDelete},
		{"权重", idBtnSetWeight},
		{"撤销", idBtnUndo},
		{"应用", idBtnApply},
		{"导入", idBtnImport},
		{"导出", idBtnExport},
		{"目录", idBtnOpenFolder},
	}
	btnW := (contentW - gap*int32(len(toolbar)-1)) / int32(len(toolbar))
	x := contentLeft
	for i, spec := range toolbar {
		w := btnW
		if i == len(toolbar)-1 {
			w = contentRight - x
		}
		createButton(state.mainHWND, spec.text, rect{x, toolbarY, x + w, toolbarY + toolbarH}, spec.id)
		x += w + gap
	}

	modeText := fmt.Sprintf("编码方案：%s", state.mode)
	createStatic(state.mainHWND, modeText, rect{contentLeft, 44, contentRight, 64}, 0)

	const labelW, resetW, comboW, dirW = int32(48), int32(64), int32(88), int32(64)
	labelRight := contentLeft + labelW
	searchLeft := labelRight + gap
	resetRight := contentRight - comboW - gap - dirW - gap
	resetLeft := resetRight - resetW
	searchRight := resetLeft - gap
	comboLeft := resetRight + gap
	comboRight := comboLeft + comboW
	dirLeft := comboRight + gap

	createStatic(state.mainHWND, "搜索", rect{contentLeft, rowY + 4, labelRight, rowY + 24}, 0)
	state.searchHWND = createEdit(state.mainHWND, rect{searchLeft, rowY, searchRight, rowY + rowH}, idSearchEdit)
	createButton(state.mainHWND, "清空", rect{resetLeft, rowY, resetRight, rowY + rowH}, idSearchReset)

	state.sortFieldHWND = createCombo(state.mainHWND, rect{comboLeft, rowY, comboRight, rowY + 132}, idSortFieldCombo)
	for _, label := range []string{"词条", "拼音", "权重"} {
		text, _ := syscall.UTF16PtrFromString(label)
		procSendMessageW.Call(uintptr(state.sortFieldHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	procSendMessageW.Call(uintptr(state.sortFieldHWND), 0x014E, 0, 0)

	state.sortDirectionHWND = createButton(state.mainHWND, "升序", rect{dirLeft, rowY, contentRight, rowY + rowH}, idSortDirection)

	state.listHWND = createControl("LISTBOX", "", entryListStyle, rect{contentLeft, 100, contentRight, 380}, state.mainHWND, idEntryList)
	state.selectionHWND = createStatic(state.mainHWND, "未选中词条", rect{contentLeft, 388, contentRight, 408}, idSelectionLabel)
	state.summaryHWND = createStatic(state.mainHWND, "", rect{contentLeft, 412, contentRight, 452}, idSummaryLabel)
	state.statusHWND = createStatic(state.mainHWND, "就绪。", rect{contentLeft, 456, contentRight, 476}, idStatusLabel)

	state.refreshList()
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111:
		state.handleCommand(wParam, lParam)
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
	case win32ui.WmDeferredPresent:
		win32ui.PresentMainWindow(state.mainHWND)
		return 0
	case 0x0006:
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0010:
		if state.dirty {
			result := showMessageBoxResult("源词库有未应用改动，确定要关闭吗？", 0x23)
			if result == 2 {
				return 0
			}
		}
		procPostQuitMessage.Call(0)
		return 0
	case 0x0018:
		if wParam != 0 && lParam == 0 {
			state.presentMainWindow()
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
	if id == idSearchEdit && notify == enChange {
		state.refreshList()
		return
	}
	if notify == 1 && id == idSortFieldCombo {
		state.refreshList()
		return
	}
	if id == idEntryList && notify == lbnSelchange {
		state.updateSelectionSummary()
		return
	}
	if id == idEntryList && notify == lbnDblclk {
		state.editSelected()
		return
	}
	switch id {
	case idBtnAdd, idBtnEdit, idBtnDelete, idBtnSetWeight, idBtnUndo, idBtnApply, idBtnImport, idBtnExport, idBtnOpenFolder, idSearchReset, idSortDirection:
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
	case idBtnSetWeight:
		state.setSelectedWeights()
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

func (state *appState) onCodeMapLoaded() {
	if state.codeMapErr != nil {
		setWindowText(state.statusHWND, "编码表加载失败："+state.codeMapErr.Error())
		return
	}
	if _, err := userlexicon.HydrateSourceIfEmpty(state.userDir, state.mode, state.codeMap); err != nil {
		setWindowText(state.statusHWND, "同步用户词库失败："+err.Error())
	}
	state.refreshList()
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
}

func (state *appState) presentMainWindowAfterLaunch() {
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
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

func createButton(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("BUTTON", text, 0x50010000, box, parent, id)
}

func createEdit(parent syscall.Handle, box rect, id int) syscall.Handle {
	return createControl("EDIT", "", 0x50210080, box, parent, id)
}

func createCombo(parent syscall.Handle, box rect, id int) syscall.Handle {
	return createControl("COMBOBOX", "", 0x50200203, box, parent, id)
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
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("词库管理")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), flags)
}

func showMessageBoxResult(message string, flags uintptr) int {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("词库管理")
	result, _, _ := procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), flags)
	return int(result)
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
