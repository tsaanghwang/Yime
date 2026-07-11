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
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/runtimechange"
	"github.com/EasyIME/pime-go/input_methods/yime/settings"
	"github.com/EasyIME/pime-go/input_methods/yime/toolhub"
	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

const (
	wmAppCommand   = 0x0400 + 1
	wmAppApplyDone = 0x0400 + 2

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000

	swRestore    = 9
	swShowNormal = 1

	idSchemaCombo   = 101
	idPageSizeCombo = 102
	idReverseCombo  = 103
	idLayoutCombo   = 104
	idSummaryLabel  = 105
	idStatusLabel   = 106
	idBtnApply      = 201
	idBtnApplyBuild = 202
	idBtnOpenUser   = 203
	idBtnOpenHelp   = 204
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
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
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
	Hwnd           syscall.Handle
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             struct{ X, Y int32 }
}

type rect struct{ Left, Top, Right, Bottom int32 }

type initCommonControlsEx struct{ Size, ICC uint32 }

type appState struct {
	userDir, sharedDir, helpDir string

	mainHWND, schemaHWND, pageHWND, reverseHWND, layoutHWND, summaryHWND, statusHWND syscall.Handle
	schemaOptions                                                                    []settings.SchemaOption

	applyMu                 sync.Mutex
	applyRunning            bool
	applyErr                error
	applyCompletedWithBuild bool
}

type applyRequest struct {
	schemaID    string
	pageSize    int
	reverseMode string
	layout      string
	runBuild    bool
}

var applySettings = settings.Apply
var notifyRuntimeChange = runtimechange.Notify

func main() {
	userDir := flag.String("UserDir", "", "Yime user data directory")
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	helpDir := flag.String("HelpDir", "", "Yime help directory")
	_ = flag.String("LogDir", "", "PIME log directory")
	flag.Parse()
	if strings.TrimSpace(*userDir) == "" || strings.TrimSpace(*sharedDir) == "" {
		showError("缺少 UserDir 或 SharedDir 参数。")
		os.Exit(1)
	}
	state := &appState{
		userDir:       strings.TrimSpace(*userDir),
		sharedDir:     strings.TrimSpace(*sharedDir),
		helpDir:       strings.TrimSpace(*helpDir),
		schemaOptions: settings.AvailableSchemaOptions(strings.TrimSpace(*sharedDir)),
	}
	if err := runApp(state); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow("YimeSettingsTool") {
		return nil
	}

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))
	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeSettingsTool")
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
	title, _ := syscall.UTF16PtrFromString("Yime 设置")
	winW, winH := windowSizeForClient(820, 680)
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
	state.refreshView()
	state.presentMainWindowAfterLaunch()
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
	createStatic(state.mainHWND, "Yime 设置面板", rect{16, 16, 760, 42}, 0)
	createStatic(state.mainHWND, "此面板把设置相关工作从输入法回调路径中拆出。它会写入 Yime 已使用的同一套运行时文件。", rect{16, 48, 770, 92}, 0)
	createStatic(state.mainHWND, "输入方案", rect{36, 138, 156, 158}, 0)
	state.schemaHWND = createCombo(state.mainHWND, rect{160, 134, 340, 260}, idSchemaCombo)
	for _, option := range state.schemaOptions {
		if !option.Enabled {
			continue
		}
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.schemaHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "候选项数", rect{36, 188, 156, 208}, 0)
	state.pageHWND = createCombo(state.mainHWND, rect{160, 184, 340, 310}, idPageSizeCombo)
	for size := 5; size <= 9; size++ {
		text, _ := syscall.UTF16PtrFromString(fmt.Sprintf("%d", size))
		procSendMessageW.Call(uintptr(state.pageHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "显示编码", rect{36, 238, 156, 258}, 0)
	state.reverseHWND = createCombo(state.mainHWND, rect{160, 234, 340, 360}, idReverseCombo)
	for _, option := range settings.ReverseLookupOptions() {
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.reverseHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "候选排列", rect{36, 288, 156, 308}, 0)
	state.layoutHWND = createCombo(state.mainHWND, rect{160, 284, 340, 410}, idLayoutCombo)
	for _, option := range settings.CandidateLayoutOptions() {
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.layoutHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	state.summaryHWND = createStatic(state.mainHWND, "", rect{16, 360, 770, 400}, idSummaryLabel)
	createButton(state.mainHWND, "应用", rect{16, 430, 120, 458}, idBtnApply)
	createButton(state.mainHWND, "应用并重建", rect{132, 430, 260, 458}, idBtnApplyBuild)
	createButton(state.mainHWND, "打开用户目录", rect{276, 430, 404, 458}, idBtnOpenUser)
	if state.helpDir != "" {
		createButton(state.mainHWND, "设置说明", rect{420, 430, 548, 458}, idBtnOpenHelp)
	}
	state.statusHWND = createStatic(state.mainHWND, "就绪。", rect{16, 470, 770, 510}, idStatusLabel)
}

func (state *appState) refreshView() {
	snapshot := settings.LoadSnapshot(state.userDir, state.sharedDir)
	setComboBySchema(state.schemaHWND, state.schemaOptions, snapshot.SchemaID)
	setComboByText(state.pageHWND, fmt.Sprintf("%d", settings.NormalizePageSizeValue(snapshot.PageSize)))
	setComboByValue(state.reverseHWND, settings.ReverseLookupOptions(), snapshot.ReverseLookupMode)
	setComboByValue(state.layoutHWND, settings.CandidateLayoutOptions(), snapshot.CandidateLayout)
	setWindowText(state.summaryHWND, settings.SummaryText(snapshot))
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111:
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case wmAppCommand:
		state.handleCommand(wParam)
		return 0
	case wmAppApplyDone:
		state.finishApply()
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
	case 0x0010: // WM_CLOSE
		if state.isApplyRunning() {
			setWindowText(state.statusHWND, "正在应用设置，请等待完成后再关闭。")
			return 0
		}
		procPostQuitMessage.Call(0)
		return 0
	case 0x0002: // WM_DESTROY
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func (state *appState) handleCommand(wParam uintptr) {
	switch int(wParam & 0xffff) {
	case idBtnApply:
		state.startApply(false)
	case idBtnApplyBuild:
		state.startApply(true)
	case idBtnOpenUser:
		_, _ = toolhub.Invoke(toolhub.Entry{ActionType: toolhub.ActionOpenPath, TargetPath: state.userDir})
	case idBtnOpenHelp:
		if state.helpDir != "" {
			_, _ = toolhub.Invoke(toolhub.Entry{ActionType: toolhub.ActionOpenPath, TargetPath: filepath.Join(state.helpDir, "settings-and-data.html")})
		}
	}
}

func (state *appState) startApply(runBuild bool) {
	state.applyMu.Lock()
	if state.applyRunning {
		state.applyMu.Unlock()
		return
	}
	state.applyRunning = true
	state.applyMu.Unlock()

	request := applyRequest{
		schemaID:    selectedSchemaID(state.schemaHWND, state.schemaOptions),
		pageSize:    settings.NormalizePageSizeValue(atoiDefault(selectedComboText(state.pageHWND), 5)),
		reverseMode: selectedComboValue(state.reverseHWND, settings.ReverseLookupOptions()),
		layout:      selectedComboValue(state.layoutHWND, settings.CandidateLayoutOptions()),
		runBuild:    runBuild,
	}
	setWindowText(state.statusHWND, "正在应用设置，请稍候……")
	go func() {
		err := executeApply(state.userDir, state.sharedDir, request)
		state.applyMu.Lock()
		state.applyErr = err
		state.applyCompletedWithBuild = runBuild
		state.applyMu.Unlock()
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppApplyDone, 0, 0)
	}()
}

func (state *appState) isApplyRunning() bool {
	state.applyMu.Lock()
	defer state.applyMu.Unlock()
	return state.applyRunning
}

func executeApply(userDir, sharedDir string, request applyRequest) error {
	if err := applySettings(userDir, sharedDir, request.schemaID, request.pageSize, request.reverseMode, request.layout, request.runBuild); err != nil {
		return err
	}
	_, err := notifyRuntimeChange(userDir, runtimechange.ScopeSettings, request.runBuild)
	return err
}

func (state *appState) finishApply() {
	state.applyMu.Lock()
	err := state.applyErr
	runBuild := state.applyCompletedWithBuild
	state.applyErr = nil
	state.applyRunning = false
	state.applyMu.Unlock()
	if err != nil {
		showError(err.Error())
		setWindowText(state.statusHWND, "应用失败。")
		return
	}
	state.refreshView()
	if runBuild {
		setWindowText(state.statusHWND, "已写入设置并执行构建；活动输入会话将在下一次操作前刷新。")
	} else {
		setWindowText(state.statusHWND, "已写入设置；显示设置将在活动输入会话的下一次操作前同步。")
	}
}

func (state *appState) presentMainWindow() {
	win32ui.PresentMainWindow(state.mainHWND)
}

func (state *appState) presentMainWindowAfterLaunch() {
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)
}

func selectedSchemaID(hwnd syscall.Handle, options []settings.SchemaOption) string {
	index, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x0147, 0, 0)
	pos := 0
	for _, option := range options {
		if !option.Enabled {
			continue
		}
		if int(index) == pos {
			return option.ID
		}
		pos++
	}
	return settings.SchemaVariable
}

func selectedComboValue(hwnd syscall.Handle, options []settings.ComboOption) string {
	index, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x0147, 0, 0)
	if int(index) >= 0 && int(index) < len(options) {
		return options[index].Value
	}
	return ""
}

func setComboBySchema(hwnd syscall.Handle, options []settings.SchemaOption, schemaID string) {
	pos := 0
	for _, option := range options {
		if !option.Enabled {
			continue
		}
		if option.ID == schemaID {
			procSendMessageW.Call(uintptr(hwnd), 0x014E, uintptr(pos), 0)
			return
		}
		pos++
	}
	procSendMessageW.Call(uintptr(hwnd), 0x014E, 0, 0)
}

func setComboByValue(hwnd syscall.Handle, options []settings.ComboOption, value string) {
	for i, option := range options {
		if option.Value == value {
			procSendMessageW.Call(uintptr(hwnd), 0x014E, uintptr(i), 0)
			return
		}
	}
	procSendMessageW.Call(uintptr(hwnd), 0x014E, 0, 0)
}

func setComboByText(hwnd syscall.Handle, text string) {
	length, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x0146, 0, 0)
	for i := 0; i < int(length); i++ {
		buf := make([]uint16, 256)
		procSendMessageW.Call(uintptr(hwnd), 0x0149, uintptr(i), uintptr(unsafe.Pointer(&buf[0])))
		if syscall.UTF16ToString(buf) == text {
			procSendMessageW.Call(uintptr(hwnd), 0x014E, uintptr(i), 0)
			return
		}
	}
	procSendMessageW.Call(uintptr(hwnd), 0x014E, 0, 0)
}

func selectedComboText(hwnd syscall.Handle) string {
	index, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x0147, 0, 0)
	if int32(index) < 0 {
		return ""
	}
	buf := make([]uint16, 256)
	procSendMessageW.Call(uintptr(hwnd), 0x0148, index, uintptr(unsafe.Pointer(&buf[0])))
	return syscall.UTF16ToString(buf)
}

func createStatic(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("STATIC", text, 0x50000000, box, parent, id)
}
func createButton(parent syscall.Handle, text string, box rect, id int) syscall.Handle {
	return createControl("BUTTON", text, 0x50010000, box, parent, id)
}
func createCombo(parent syscall.Handle, box rect, id int) syscall.Handle {
	return createControl("COMBOBOX", "", 0x50200203, box, parent, id)
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
	title, _ := syscall.UTF16PtrFromString("Yime 设置")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
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
func atoiDefault(value string, fallback int) int {
	var n int
	if _, err := fmt.Sscanf(strings.TrimSpace(value), "%d", &n); err != nil {
		return fallback
	}
	return n
}
