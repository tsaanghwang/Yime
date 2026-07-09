//go:build windows

package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/diagnostics"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	wmAppCommand  = 0x0400 + 1
	wmAppRefresh  = 0x0400 + 2

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000

	swRestore    = 9
	swShowNormal = 1

	cfUnicode   = 13
	gmemMoveable = 0x0002

	idStatusView      = 101
	idPresetCombo     = 102
	idIncludeEnv      = 103
	idIncludeActions  = 104
	idIncludeLogs     = 105
	idAnonymize       = 106
	idBtnRefresh      = 201
	idBtnCopy         = 202
	idBtnGuide        = 203
	idBtnLogs         = 204
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
	procSetForegroundWindow  = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop     = moduser32.NewProc("BringWindowToTop")
	procIsIconic             = moduser32.NewProc("IsIconic")
	procLoadIconW            = moduser32.NewProc("LoadIconW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")
	procOpenClipboard        = moduser32.NewProc("OpenClipboard")
	procCloseClipboard       = moduser32.NewProc("CloseClipboard")
	procEmptyClipboard       = moduser32.NewProc("EmptyClipboard")
	procSetClipboardData     = moduser32.NewProc("SetClipboardData")
	procGlobalAlloc          = modkernel32.NewProc("GlobalAlloc")
	procGlobalLock           = modkernel32.NewProc("GlobalLock")
	procGlobalUnlock         = modkernel32.NewProc("GlobalUnlock")

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

type rect struct{ Left, Top, Right, Bottom int32 }

type initCommonControlsEx struct{ Size, ICC uint32 }

type appState struct {
	ctx        diagnostics.Context
	mainHWND   syscall.Handle
	statusHWND syscall.Handle
	envHWND    syscall.Handle
	actionsHWND syscall.Handle
	logsHWND   syscall.Handle
	anonHWND   syscall.Handle
}

func main() {
	userDir := flag.String("UserDir", "", "Yime user data directory")
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	helpDir := flag.String("HelpDir", "", "Yime help directory")
	logDir := flag.String("LogDir", "", "PIME log directory")
	flag.Parse()
	if strings.TrimSpace(*userDir) == "" || strings.TrimSpace(*sharedDir) == "" {
		showError("缺少 UserDir 或 SharedDir 参数。")
		os.Exit(1)
	}
	state := &appState{ctx: diagnostics.Context{
		UserDir: strings.TrimSpace(*userDir),
		SharedDir: strings.TrimSpace(*sharedDir),
		HelpDir: strings.TrimSpace(*helpDir),
		LogDir: strings.TrimSpace(*logDir),
	}}
	if state.ctx.LogDir == "" {
		state.ctx.LogDir = strings.TrimSpace(os.Getenv("LOCALAPPDATA"))
		if state.ctx.LogDir != "" {
			state.ctx.LogDir = state.ctx.LogDir + `\PIME\Logs`
		}
	}
	if err := runApp(state); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow("YimeDiagnosticsTool") {
		return nil
	}

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))
	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeDiagnosticsTool")
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
	procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wndClass)))
	title, _ := syscall.UTF16PtrFromString("Yime 诊断")
	winW, winH := windowSizeForClient(900, 620)
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	x := (int32(screenWidth) - winW) / 2
	y := (int32(screenHeight) - winH) / 2
	hwnd, _, _ := procCreateWindowExW.Call(uintptr(wsExControlparent|wsExAppwindow), uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), uintptr(wsOverlappedwindow), uintptr(x), uintptr(y), uintptr(winW), uintptr(winH), 0, 0, instance, 0)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowEx failed")
	}
	state.mainHWND = syscall.Handle(hwnd)
	state.createControls()
	setWindowText(state.statusHWND, "正在收集诊断信息，请稍候…")
	state.presentMainWindow()
	procPostMessageW.Call(uintptr(state.mainHWND), wmAppRefresh, 0, 0)
	var message winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		if isDialog, _, _ := procIsDialogMessageW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(&message))); isDialog != 0 {
			continue
		}
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) createControls() {
	createStatic(state.mainHWND, "Yime 诊断面板", rect{16, 16, 860, 40}, 0)
	createStatic(state.mainHWND, "此面板检查路径、已安装二进制、运行进程、用户 Rime 文件和当前日志。", rect{16, 48, 860, 84}, 0)
	detailStyle := int32(0x50200000 | 0x10000000 | 0x00800000 | 0x00200000 | 0x00010000 | 0x0800 | 0x0004 | 0x0040)
	state.statusHWND = createControl("EDIT", "", detailStyle, rect{16, 96, 876, 468}, state.mainHWND, idStatusView)
	state.envHWND = createCheck(state.mainHWND, "包含环境摘要", rect{16, 480, 180, 504}, idIncludeEnv)
	state.actionsHWND = createCheck(state.mainHWND, "包含建议操作", rect{188, 480, 360, 504}, idIncludeActions)
	state.logsHWND = createCheck(state.mainHWND, "包含原始日志摘录", rect{372, 480, 560, 504}, idIncludeLogs)
	state.anonHWND = createCheck(state.mainHWND, "匿名化报告", rect{572, 480, 720, 504}, idAnonymize)
	procSendMessageW.Call(uintptr(state.envHWND), 0x00F1, 1, 0)
	procSendMessageW.Call(uintptr(state.actionsHWND), 0x00F1, 1, 0)
	procSendMessageW.Call(uintptr(state.logsHWND), 0x00F1, 1, 0)
	procSendMessageW.Call(uintptr(state.anonHWND), 0x00F1, 1, 0)
	createButton(state.mainHWND, "刷新", rect{16, 520, 100, 548}, idBtnRefresh)
	createButton(state.mainHWND, "复制结构化报告", rect{112, 520, 260, 548}, idBtnCopy)
	createButton(state.mainHWND, "诊断说明", rect{272, 520, 372, 548}, idBtnGuide)
	createButton(state.mainHWND, "日志目录", rect{384, 520, 484, 548}, idBtnLogs)
}

func (state *appState) refreshStatus() {
	setWindowText(state.statusHWND, diagnostics.BuildStatusReport(state.ctx))
}

func (state *appState) reportOptions() diagnostics.ReportOptions {
	opts := diagnostics.DefaultIssueReadyOptions()
	opts.IncludeEnvironmentSummary = isChecked(state.envHWND)
	opts.IncludeRecommendedActions = isChecked(state.actionsHWND)
	opts.IncludeRawLogExcerpt = isChecked(state.logsHWND)
	opts.Anonymize = isChecked(state.anonHWND)
	return opts
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111:
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case wmAppCommand:
		state.handleCommand(wParam)
		return 0
	case wmAppRefresh:
		state.refreshStatus()
		return 0
	case 0x0006: // WM_ACTIVATE
		if win32ui.IsActivateMessage(wParam) {
			win32ui.RedrawChildrenNow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0018: // WM_SHOWWINDOW
		if wParam != 0 && lParam == 0 {
			win32ui.PresentMainWindow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0010, 0x0002:
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func (state *appState) handleCommand(wParam uintptr) {
	switch int(wParam & 0xffff) {
	case idBtnRefresh:
		state.refreshStatus()
	case idBtnCopy:
		report := diagnostics.BuildStructuredReport(state.ctx, state.reportOptions())
		if err := setClipboardText(report); err != nil {
			showError(err.Error())
		}
	case idBtnGuide:
		if strings.TrimSpace(state.ctx.HelpDir) == "" {
			showError("缺少 HelpDir，无法打开诊断说明。")
			return
		}
		guidePath := filepath.Join(state.ctx.HelpDir, "diagnostics.html")
		if err := openPath(guidePath); err != nil {
			showError(err.Error())
		}
	case idBtnLogs:
		if strings.TrimSpace(state.ctx.LogDir) == "" {
			showError("缺少 LogDir，无法打开日志目录。")
			return
		}
		if err := openPath(state.ctx.LogDir); err != nil {
			showError(err.Error())
		}
	}
}

func (state *appState) presentMainWindow() {
	win32ui.PresentMainWindow(state.mainHWND)
}

func isChecked(hwnd syscall.Handle) bool {
	state, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x00F0, 0, 0)
	return state == 1
}

func setClipboardText(text string) error {
	ok, _, _ := procOpenClipboard.Call(0)
	if ok == 0 {
		return fmt.Errorf("无法打开剪贴板")
	}
	defer procCloseClipboard.Call()
	procEmptyClipboard.Call()
	utf16, err := syscall.UTF16FromString(text)
	if err != nil {
		return err
	}
	size := len(utf16) * 2
	mem, _, _ := procGlobalAlloc.Call(gmemMoveable, uintptr(size))
	if mem == 0 {
		return fmt.Errorf("无法分配剪贴板内存")
	}
	lock, _, _ := procGlobalLock.Call(mem)
	if lock == 0 {
		return fmt.Errorf("无法锁定剪贴板内存")
	}
	copy((*[1 << 20]uint16)(unsafe.Pointer(lock))[:len(utf16):len(utf16)], utf16)
	procGlobalUnlock.Call(mem)
	r, _, _ := procSetClipboardData.Call(cfUnicode, mem)
	if r == 0 {
		return fmt.Errorf("无法写入剪贴板")
	}
	return nil
}

func createStatic(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("STATIC", text, 0x50000000, box, parent, id)
}
func createButton(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("BUTTON", text, 0x50010000, box, parent, id)
}
func createCheck(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("BUTTON", text, 0x50010003, box, parent, id)
}
func createControl(className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(classPtr)), uintptr(unsafe.Pointer(textPtr)), uintptr(style), uintptr(box.Left), uintptr(box.Top), uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top), uintptr(parent), uintptr(id), 0, 0)
	return syscall.Handle(hwnd)
}
func windowSizeForClient(clientW, clientH int32) (int32, int32) {
	r := rect{0, 0, clientW, clientH}
	if ret, _, _ := procAdjustWindowRectEx.Call(uintptr(unsafe.Pointer(&r)), uintptr(wsOverlappedwindow), 0, 0); ret != 0 {
		return r.Right - r.Left, r.Bottom - r.Top
	}
	return clientW + 16, clientH + 39
}
func showError(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 诊断")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
func setWindowText(hwnd syscall.Handle, text string) {
	ptr, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(ptr)))
}

func openPath(path string) error {
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("路径为空")
	}
	if _, err := os.Stat(path); err != nil {
		return fmt.Errorf("找不到路径：%s", path)
	}
	return exec.Command("explorer.exe", path).Start()
}
