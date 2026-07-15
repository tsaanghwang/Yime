//go:build windows

package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userblocklist"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wmAppCommand = 0x0400 + 1
	wmAppRefresh = 0x0400 + 2
	enChange     = 0x0300 // EN_CHANGE

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000

	idSearchEdit     = 101
	idSearchReset    = 102
	idEntryList      = 103
	idSelectionLabel = 104
	idSummaryLabel   = 105
	idStatusLabel    = 106
	idBtnAdd         = 201
	idBtnDelete      = 202
	idBtnImport      = 203
	idBtnExport      = 204
	idBtnOpenFolder  = 205
	idBtnUndo        = 206

	wsChild             = 0x40000000
	wsVisible           = 0x10000000
	wsBorder            = 0x00800000
	wsVscroll           = 0x00200000
	wsTabstop           = 0x00010000
	entryListStyle      = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | 0x0001 | 0x0008
	lvmFirst            = 0x1000
	lvmDeleteallitems   = lvmFirst + 9
	lvmGetnextitem      = lvmFirst + 12
	lvmSetcolumnwidth   = lvmFirst + 30
	lvmSetitemstate     = lvmFirst + 43
	lvmSetextendedstyle = lvmFirst + 54
	lvmInsertitemw      = lvmFirst + 77
	lvmInsertcolumnw    = lvmFirst + 97
	lvifText            = 0x0001
	lvcfText            = 0x0004
	lvcfWidth           = 0x0002
	lvniSelected        = 0x0002
	lvisSelected        = 0x0002
	lvsExGridlines      = 0x00000001
	lvsExFullrowselect  = 0x00000020
	lvsExDoublebuffer   = 0x00010000
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
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")
	procGetOpenFileNameW     = modcomdlg32.NewProc("GetOpenFileNameW")
	procGetSaveFileNameW     = modcomdlg32.NewProc("GetSaveFileNameW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procMoveWindow           = moduser32.NewProc("MoveWindow")
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

type point struct{ X, Y int32 }
type minMaxInfo struct{ Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize point }

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

const blocklistColumnTitle = "屏蔽词"

type blocklistLayout struct {
	clientW, clientH                                                    int32
	toolbar                                                             []rect
	info, searchLabel, searchEdit, searchReset, list, selection, status rect
}

type appState struct {
	userDir         string
	sourcePath      string
	visibleEntries  []userblocklist.Entry
	lastUndoEntries []userblocklist.Entry
	lastUndoLabel   string
	mainHWND        syscall.Handle
	toolbarHWNDs    []syscall.Handle
	infoHWND        syscall.Handle
	searchLabelHWND syscall.Handle
	searchHWND      syscall.Handle
	searchResetHWND syscall.Handle
	listHWND        syscall.Handle
	selectionHWND   syscall.Handle
	statusHWND      syscall.Handle
	clientW         int32
	clientH         int32
}

func toolbarItems() []struct {
	text string
	id   int
} {
	return []struct {
		text string
		id   int
	}{{"添加", idBtnAdd}, {"删除", idBtnDelete}, {"撤销", idBtnUndo}, {"导入", idBtnImport}, {"导出", idBtnExport}, {"目录", idBtnOpenFolder}}
}

func buildLayout(clientW, clientH int32) blocklistLayout {
	const margin, gap = int32(8), int32(6)
	l := blocklistLayout{clientW: clientW, clientH: clientH}
	items := toolbarItems()
	buttonW := (clientW - margin*2 - gap*int32(len(items)-1)) / int32(len(items))
	if buttonW > 96 {
		buttonW = 96
	}
	total := buttonW*int32(len(items)) + gap*int32(len(items)-1)
	x := (clientW - total) / 2
	for range items {
		l.toolbar = append(l.toolbar, rect{x, 8, x + buttonW, 36})
		x += buttonW + gap
	}
	l.info = rect{margin, 44, clientW - margin, 64}
	l.searchLabel = rect{margin, 76, margin + 40, 96}
	l.searchReset = rect{clientW - margin - 64, 72, clientW - margin, 98}
	l.searchEdit = rect{l.searchLabel.Right + 4, 72, l.searchReset.Left - gap, 98}
	listBottom := clientH - 80
	l.list = rect{margin, 106, clientW - margin, listBottom}
	l.selection = rect{margin, listBottom + 8, clientW - margin, listBottom + 32}
	l.status = rect{margin, listBottom + 40, clientW - margin, listBottom + 64}
	return l
}

func main() {
	userDir := flag.String("UserDir", "", "Yime user data directory")
	flag.Parse()
	if strings.TrimSpace(*userDir) == "" {
		showMessageBox("缺少 UserDir 参数。", 0x10)
		os.Exit(1)
	}
	state := &appState{
		userDir:    strings.TrimSpace(*userDir),
		sourcePath: userblocklist.SourcePath(strings.TrimSpace(*userDir)),
	}
	if err := runApp(state); err != nil {
		showMessageBox(err.Error(), 0x10)
		os.Exit(1)
	}
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow("YimeUserBlocklistManager") {
		return nil
	}

	state.clientW = 680
	state.clientH = 480

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeUserBlocklistManager")
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

	title, _ := syscall.UTF16PtrFromString("用户屏蔽词表")
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
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)

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

func (state *appState) createControls() {
	l := buildLayout(state.clientW, state.clientH)
	for index, spec := range toolbarItems() {
		state.toolbarHWNDs = append(state.toolbarHWNDs, createButton(state.mainHWND, spec.text, l.toolbar[index], spec.id))
	}
	state.infoHWND = createStatic(state.mainHWND, "添加到本表的词条不会出现在输入候选中；所有改动保存后立即生效。", l.info, 0)
	state.searchLabelHWND = createStatic(state.mainHWND, "搜索", l.searchLabel, 0)
	state.searchHWND = createEdit(state.mainHWND, l.searchEdit, idSearchEdit)
	state.searchResetHWND = createButton(state.mainHWND, "清空", l.searchReset, idSearchReset)
	state.listHWND = createControl("SysListView32", "", entryListStyle, l.list, state.mainHWND, idEntryList)
	state.configureListView()
	state.selectionHWND = createStatic(state.mainHWND, "请在表格中选择要删除的词条。", l.selection, idSelectionLabel)
	state.statusHWND = createStatic(state.mainHWND, "就绪。", l.status, idStatusLabel)
	state.layoutControls(state.clientW, state.clientH)
	state.refreshList()
}

func (state *appState) configureListView() {
	extended := uintptr(lvsExGridlines | lvsExFullrowselect | lvsExDoublebuffer)
	procSendMessageW.Call(uintptr(state.listHWND), lvmSetextendedstyle, extended, extended)
	text, _ := syscall.UTF16PtrFromString(blocklistColumnTitle)
	column := listViewColumn{Mask: lvcfText | lvcfWidth, Width: state.clientW - 38, Text: text}
	procSendMessageW.Call(uintptr(state.listHWND), lvmInsertcolumnw, 0, uintptr(unsafe.Pointer(&column)))
}

func moveControl(hwnd syscall.Handle, box rect) {
	if hwnd != 0 {
		procMoveWindow.Call(uintptr(hwnd), uintptr(box.Left), uintptr(box.Top), uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top), 1)
	}
}

func (state *appState) layoutControls(clientW, clientH int32) {
	if clientW <= 0 || clientH <= 0 {
		return
	}
	state.clientW, state.clientH = clientW, clientH
	l := buildLayout(clientW, clientH)
	for index, hwnd := range state.toolbarHWNDs {
		moveControl(hwnd, l.toolbar[index])
	}
	moveControl(state.infoHWND, l.info)
	moveControl(state.searchLabelHWND, l.searchLabel)
	moveControl(state.searchHWND, l.searchEdit)
	moveControl(state.searchResetHWND, l.searchReset)
	moveControl(state.listHWND, l.list)
	moveControl(state.selectionHWND, l.selection)
	moveControl(state.statusHWND, l.status)
	procSendMessageW.Call(uintptr(state.listHWND), lvmSetcolumnwidth, 0, uintptr(l.list.Right-l.list.Left-22))
}

func (state *appState) toolbarButton(id int) syscall.Handle {
	for index, item := range toolbarItems() {
		if item.id == id && index < len(state.toolbarHWNDs) {
			return state.toolbarHWNDs[index]
		}
	}
	return 0
}

func (state *appState) updateToolbarState() {
	selected := len(state.selectedPhrases())
	procEnableWindow.Call(uintptr(state.toolbarButton(idBtnDelete)), boolToUintptr(selected > 0))
	procEnableWindow.Call(uintptr(state.toolbarButton(idBtnUndo)), boolToUintptr(state.lastUndoEntries != nil))
	setWindowText(state.toolbarButton(idBtnUndo), undoButtonText(state.lastUndoLabel))
}

func undoButtonText(label string) string {
	if strings.TrimSpace(label) == "" {
		return "撤销"
	}
	return "撤销" + label
}

func boolToUintptr(value bool) uintptr {
	if value {
		return 1
	}
	return 0
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0005:
		state.layoutControls(int32(lParam&0xffff), int32((lParam>>16)&0xffff))
		return 0
	case 0x0024:
		if lParam != 0 {
			w, h := windowSizeForClient(680, 480)
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
		state.handleCommand(wParam, lParam)
		return 0
	case wmAppRefresh:
		state.refreshList()
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

func (state *appState) handleCommand(wParam, lParam uintptr) {
	commandID := int(wParam & 0xffff)
	notifyCode := int((wParam >> 16) & 0xffff)
	switch commandID {
	case idBtnAdd:
		if notifyCode == 0 {
			state.addEntry()
		}
	case idBtnDelete:
		if notifyCode == 0 {
			state.deleteSelected()
		}
	case idBtnUndo:
		if notifyCode == 0 {
			state.undoLastChange()
		}
	case idBtnImport:
		if notifyCode == 0 {
			state.importEntries()
		}
	case idBtnExport:
		if notifyCode == 0 {
			state.exportEntries()
		}
	case idBtnOpenFolder:
		if notifyCode == 0 {
			_ = exec.Command("explorer.exe", filepath.Dir(state.sourcePath)).Start()
		}
	case idSearchReset:
		if notifyCode == 0 {
			setWindowText(state.searchHWND, "")
			state.refreshList()
		}
	case idSearchEdit:
		if notifyCode == enChange {
			procPostMessageW.Call(uintptr(state.mainHWND), wmAppRefresh, 0, 0)
		}
	}
}

func (state *appState) handleNotify(lParam uintptr) {
	if lParam == 0 {
		return
	}
	header := win32ui.ReadMessageStruct[notifyHeader](lParam)
	if int(header.IDFrom) == idEntryList && header.Code == -101 {
		state.updateSelectionSummary()
	}
}

func windowSizeForClient(clientW, clientH int32) (winW, winH int32) {
	r := rect{Left: 0, Top: 0, Right: clientW, Bottom: clientH}
	ret, _, _ := procAdjustWindowRectEx.Call(uintptr(unsafe.Pointer(&r)), uintptr(wsOverlappedwindow), 0, 0)
	if ret == 0 {
		return clientW + 16, clientH + 39
	}
	return r.Right - r.Left, r.Bottom - r.Top
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

func createControl(className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(classPtr)),
		uintptr(unsafe.Pointer(textPtr)),
		uintptr(style),
		uintptr(box.Left), uintptr(box.Top),
		uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top),
		uintptr(parent), uintptr(id), 0, 0,
	)
	control := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(control)
	return control
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

func showMessageBox(message string, flags uintptr) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("用户屏蔽词表")
	procMessageBoxW.Call(uintptr(statelessOwner()), uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), flags)
}

func showConfirmMessage(owner syscall.Handle, message string) bool {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("用户屏蔽词表")
	result, _, _ := procMessageBoxW.Call(uintptr(owner), uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x24)
	return result == 6
}

func statelessOwner() syscall.Handle {
	return 0
}

func readLinesFromFile(path string) ([]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	lines := []string{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	return lines, scanner.Err()
}
