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

	"github.com/EasyIME/pime-go/input_methods/yime/userblocklist"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
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

	wsChild        = 0x40000000
	wsVisible      = 0x10000000
	wsBorder       = 0x00800000
	wsVscroll      = 0x00200000
	wsTabstop      = 0x00010000
	lbsNotify      = 0x0001
	lbsHasstrings  = 0x0040
	lbsMultiplesel = 0x0008
	lbsExtendedsel = 0x0800
	entryListStyle = wsChild | wsVisible | wsBorder | wsVscroll | wsTabstop | lbsNotify | lbsHasstrings | lbsMultiplesel | lbsExtendedsel

	lbResetcontent        = 0x0184
	lbAddstring           = 0x0180
	lbSetsel              = 0x0185
	lbGetselcount         = 0x0190
	lbGetselitems         = 0x0191
	lbSethorizontalextent = 0x0194
	lbnSelchange          = 1
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
	userDir        string
	sourcePath     string
	visibleEntries []userblocklist.Entry
	mainHWND       syscall.Handle
	searchHWND     syscall.Handle
	listHWND       syscall.Handle
	selectionHWND  syscall.Handle
	summaryHWND    syscall.Handle
	statusHWND     syscall.Handle
	clientW        int32
	clientH        int32
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
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) createControls() {
	const margin = int32(8)
	toolbarY := int32(8)
	x := margin
	for _, spec := range []struct {
		text string
		id   int
	}{
		{"添加", idBtnAdd},
		{"删除", idBtnDelete},
		{"导入", idBtnImport},
		{"导出", idBtnExport},
		{"目录", idBtnOpenFolder},
	} {
		createButton(state.mainHWND, spec.text, rect{x, toolbarY, x + 72, toolbarY + 28}, spec.id)
		x += 76
	}

	createStatic(state.mainHWND, "添加到本表的词条将不会出现在输入候选中。保存后立即生效，无需重新部署。", rect{margin, 44, 664, 64}, 0)
	createStatic(state.mainHWND, "搜索", rect{margin, 72, margin + 36, 92}, 0)
	state.searchHWND = createEdit(state.mainHWND, rect{52, 68, 540, 94}, idSearchEdit)
	createButton(state.mainHWND, "清空", rect{548, 68, 604, 94}, idSearchReset)

	state.listHWND = createControl("LISTBOX", "", entryListStyle, rect{margin, 100, 664, 360}, state.mainHWND, idEntryList)
	state.selectionHWND = createStatic(state.mainHWND, "未选中词条", rect{margin, 368, 664, 388}, idSelectionLabel)
	state.summaryHWND = createStatic(state.mainHWND, "", rect{margin, 392, 664, 420}, idSummaryLabel)
	state.statusHWND = createStatic(state.mainHWND, "就绪。", rect{margin, 424, 664, 444}, idStatusLabel)

	state.refreshList()
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111:
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
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
	case idEntryList:
		if notifyCode == 1 {
			state.updateSelectionSummary()
		}
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
	return syscall.Handle(hwnd)
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
