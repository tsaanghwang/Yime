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
	idBtnApply      = 201
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

type settingsUILayout struct {
	clientW, clientH                            int32
	schemaLabel, schemaCombo                    rect
	pageLabel, pageCombo                        rect
	reverseLabel, reverseCombo                  rect
	layoutLabel, layoutCombo                    rect
	applyButton, openUserButton, openHelpButton rect
}

type appState struct {
	userDir, sharedDir, helpDir string

	mainHWND, schemaHWND, pageHWND, reverseHWND, layoutHWND syscall.Handle
	schemaOptions                                           []settings.SchemaOption
	layout                                                  settingsUILayout

	applyMu      sync.Mutex
	applyRunning bool
	applyErr     error
}

type applyRequest struct {
	schemaID    string
	pageSize    int
	reverseMode string
	layout      string
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
	state.layout = buildSettingsUILayout(state.helpDir != "")

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
	winW, winH := windowSizeForClient(state.layout.clientW, state.layout.clientH)
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
	// The window caption already identifies this as the Yime settings panel.
	// Developer note: this standalone panel keeps settings work out of the
	// input-method callback path and writes the same runtime files Yime consumes.
	l := state.layout
	createStatic(state.mainHWND, "输入方案", l.schemaLabel, 0)
	state.schemaHWND = createCombo(state.mainHWND, l.schemaCombo, idSchemaCombo)
	for _, option := range state.schemaOptions {
		if !option.Enabled {
			continue
		}
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.schemaHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "候选项数", l.pageLabel, 0)
	state.pageHWND = createCombo(state.mainHWND, l.pageCombo, idPageSizeCombo)
	for size := 5; size <= 9; size++ {
		text, _ := syscall.UTF16PtrFromString(fmt.Sprintf("%d", size))
		procSendMessageW.Call(uintptr(state.pageHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "显示编码", l.reverseLabel, 0)
	state.reverseHWND = createCombo(state.mainHWND, l.reverseCombo, idReverseCombo)
	for _, option := range settings.ReverseLookupOptions() {
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.reverseHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	createStatic(state.mainHWND, "候选排列", l.layoutLabel, 0)
	state.layoutHWND = createCombo(state.mainHWND, l.layoutCombo, idLayoutCombo)
	for _, option := range settings.CandidateLayoutOptions() {
		text, _ := syscall.UTF16PtrFromString(option.Label)
		procSendMessageW.Call(uintptr(state.layoutHWND), 0x0143, 0, uintptr(unsafe.Pointer(text)))
	}
	// The selected controls already show the current configuration; do not
	// duplicate it in a developer-oriented "current configuration" summary.
	createButton(state.mainHWND, "应用", l.applyButton, idBtnApply)
	createButton(state.mainHWND, "打开用户目录", l.openUserButton, idBtnOpenUser)
	if state.helpDir != "" {
		createButton(state.mainHWND, "设置说明", l.openHelpButton, idBtnOpenHelp)
	}
}

func buildSettingsUILayout(withHelp bool) settingsUILayout {
	const (
		margin     = int32(16)
		labelW     = int32(96)
		comboW     = int32(220)
		rowH       = int32(26)
		rowGap     = int32(12)
		controlGap = int32(8)
		buttonH    = int32(30)
		buttonGap  = int32(8)
	)
	l := settingsUILayout{}
	labelX := margin
	comboX := labelX + labelW + controlGap
	row := func(index int32) (rect, rect) {
		y := margin + index*(rowH+rowGap)
		return rect{labelX, y + 4, labelX + labelW, y + rowH}, rect{comboX, y, comboX + comboW, y + 126}
	}
	l.schemaLabel, l.schemaCombo = row(0)
	l.pageLabel, l.pageCombo = row(1)
	l.reverseLabel, l.reverseCombo = row(2)
	l.layoutLabel, l.layoutCombo = row(3)

	buttonY := margin + 4*(rowH+rowGap) + 8
	x := margin
	button := func(width int32) rect {
		result := rect{x, buttonY, x + width, buttonY + buttonH}
		x = result.Right + buttonGap
		return result
	}
	l.applyButton = button(84)
	l.openUserButton = button(116)
	if withHelp {
		l.openHelpButton = button(100)
	}
	contentRight := l.openUserButton.Right
	if withHelp {
		contentRight = l.openHelpButton.Right
	}
	if l.layoutCombo.Right > contentRight {
		contentRight = l.layoutCombo.Right
	}
	l.clientW = contentRight + margin
	l.clientH = l.applyButton.Bottom + margin
	return l
}

func (state *appState) refreshView() {
	snapshot := settings.LoadSnapshot(state.userDir, state.sharedDir)
	setComboBySchema(state.schemaHWND, state.schemaOptions, snapshot.SchemaID)
	setComboByText(state.pageHWND, fmt.Sprintf("%d", settings.NormalizePageSizeValue(snapshot.PageSize)))
	setComboByValue(state.reverseHWND, settings.ReverseLookupOptions(), snapshot.ReverseLookupMode)
	setComboByValue(state.layoutHWND, settings.CandidateLayoutOptions(), snapshot.CandidateLayout)
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
			showInfo("正在应用设置，请等待完成后再关闭。")
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
		state.startApply()
	case idBtnOpenUser:
		_, _ = toolhub.Invoke(toolhub.Entry{ActionType: toolhub.ActionOpenPath, TargetPath: state.userDir})
	case idBtnOpenHelp:
		if state.helpDir != "" {
			_, _ = toolhub.Invoke(toolhub.Entry{ActionType: toolhub.ActionOpenPath, TargetPath: filepath.Join(state.helpDir, "settings-and-data.html")})
		}
	}
}

func (state *appState) startApply() {
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
	}
	setWindowText(state.mainHWND, "Yime 设置（正在应用……）")
	go func() {
		err := executeApply(state.userDir, state.sharedDir, request)
		state.applyMu.Lock()
		state.applyErr = err
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
	if err := applySettings(userDir, sharedDir, request.schemaID, request.pageSize, request.reverseMode, request.layout, true); err != nil {
		return err
	}
	_, err := notifyRuntimeChange(userDir, runtimechange.ScopeSettings, true)
	return err
}

func (state *appState) finishApply() {
	state.applyMu.Lock()
	err := state.applyErr
	state.applyErr = nil
	state.applyRunning = false
	state.applyMu.Unlock()
	if err != nil {
		setWindowText(state.mainHWND, "Yime 设置")
		showError(err.Error())
		return
	}
	state.refreshView()
	setWindowText(state.mainHWND, "Yime 设置")
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
	control := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(control)
	return control
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
func showInfo(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 设置")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x40)
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
