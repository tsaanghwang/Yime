//go:build windows

package main

import (
	"errors"
	"flag"
	"os"
	"os/exec"
	"runtime"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	windowClass = "YimeInputToolbar"

	wsExToolWindow = 0x00000080
	wsExTopmost    = 0x00000008
	wsCaption      = 0x00C00000
	wsSysMenu      = 0x00080000
	wsPopup        = 0x80000000
	wsChild        = 0x40000000
	wsVisible      = 0x10000000
	wsTabStop      = 0x00010000
	bsPushButton   = 0x00000000

	wmCommand = 0x0111
	wmTimer   = 0x0113
	wmDestroy = 0x0002

	idLanguage = 100
	idShape    = 101
	idPunct    = 102
	idScript   = 103
	idUnicode  = 104
	idSettings = 105
	timerID    = 1
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	createWindowExW   = user32.NewProc("CreateWindowExW")
	defWindowProcW    = user32.NewProc("DefWindowProcW")
	dispatchMessageW  = user32.NewProc("DispatchMessageW")
	getMessageW       = user32.NewProc("GetMessageW")
	translateMessageW = user32.NewProc("TranslateMessage")
	postQuitMessage   = user32.NewProc("PostQuitMessage")
	registerClassExW  = user32.NewProc("RegisterClassExW")
	loadCursorW       = user32.NewProc("LoadCursorW")
	showWindow        = user32.NewProc("ShowWindow")
	updateWindow      = user32.NewProc("UpdateWindow")
	setTimer          = user32.NewProc("SetTimer")
	killTimer         = user32.NewProc("KillTimer")
	setWindowTextW    = user32.NewProc("SetWindowTextW")
	messageBoxW       = user32.NewProc("MessageBoxW")
	getSystemMetrics  = user32.NewProc("GetSystemMetrics")
	getModuleHandleW  = kernel32.NewProc("GetModuleHandleW")

	windowProc uintptr
)

type wndClassEx struct {
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

type app struct {
	statePath    string
	settingsTool string
	userDir      string
	sharedDir    string
	helpDir      string
	logDir       string
	hwnd         syscall.Handle
	buttons      map[int]syscall.Handle
	state        toolbarstate.State
}

func main() {
	statePath := flag.String("StatePath", "", "Path to yime_input_toolbar_state.json")
	settingsTool := flag.String("SettingsTool", "", "Path to settings-tool.exe")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	sharedDir := flag.String("SharedDir", "", "Yime shared data directory")
	helpDir := flag.String("HelpDir", "", "Yime help directory")
	logDir := flag.String("LogDir", "", "PIME log directory")
	flag.Parse()
	if *statePath == "" {
		showError("缺少 StatePath 参数。")
		os.Exit(1)
	}
	instance := &app{
		statePath:    *statePath,
		settingsTool: *settingsTool,
		userDir:      *userDir,
		sharedDir:    *sharedDir,
		helpDir:      *helpDir,
		logDir:       *logDir,
		buttons:      map[int]syscall.Handle{},
	}
	if err := instance.run(); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func (a *app) run() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow(windowClass) {
		return nil
	}
	instance, _, _ := getModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString(windowClass)
	cursor, _, _ := loadCursorW.Call(0, uintptr(32512))
	icon := win32ui.LoadYimeIcon(instance)
	windowProc = syscall.NewCallback(a.wndProc)
	class := wndClassEx{
		Size:       uint32(unsafe.Sizeof(wndClassEx{})),
		Style:      win32ui.ClassRedraw,
		WndProc:    windowProc,
		Instance:   syscall.Handle(instance),
		Icon:       syscall.Handle(icon),
		IconSm:     syscall.Handle(icon),
		Cursor:     syscall.Handle(cursor),
		Background: win32ui.ColorWindowBackground,
		ClassName:  className,
	}
	if ret, _, _ := registerClassExW.Call(uintptr(unsafe.Pointer(&class))); ret == 0 {
		return errors.New("无法注册输入法工具栏窗口")
	}

	title, _ := syscall.UTF16PtrFromString("Yime 输入法工具栏")
	const width, height = int32(394), int32(72)
	screenW, _, _ := getSystemMetrics.Call(0)
	x := int32(screenW) - width - 24
	if x < 0 {
		x = 0
	}
	hwnd, _, _ := createWindowExW.Call(
		wsExToolWindow|wsExTopmost,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		wsPopup|wsCaption|wsSysMenu,
		uintptr(x), 48, uintptr(width), uintptr(height),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return errors.New("无法创建输入法工具栏窗口")
	}
	a.hwnd = syscall.Handle(hwnd)
	a.createButtons()
	a.refresh()
	setTimer.Call(hwnd, timerID, 200, 0)
	showWindow.Call(hwnd, 5)
	updateWindow.Call(hwnd)

	var message winMsg
	for {
		ret, _, _ := getMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		translateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		dispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (a *app) createButtons() {
	labels := []struct {
		id   int
		text string
		w    int32
	}{
		{idLanguage, "中", 44},
		{idShape, "半", 44},
		{idPunct, "中标", 54},
		{idScript, "简", 44},
		{idUnicode, "字符", 64},
		{idSettings, "设置", 64},
	}
	left := int32(8)
	for _, item := range labels {
		a.buttons[item.id] = createButton(a.hwnd, item.id, item.text, left, 8, item.w, 28)
		left += item.w + 6
	}
}

func createButton(parent syscall.Handle, id int, text string, x, y, width, height int32) syscall.Handle {
	className, _ := syscall.UTF16PtrFromString("BUTTON")
	label, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := createWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(label)),
		wsChild|wsVisible|wsTabStop|bsPushButton,
		uintptr(x), uintptr(y), uintptr(width), uintptr(height),
		uintptr(parent), uintptr(id), 0, 0,
	)
	button := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(button)
	return button
}

func (a *app) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case wmCommand:
		if int((wParam>>16)&0xffff) == 0 {
			a.handleCommand(int(wParam & 0xffff))
		}
		return 0
	case wmTimer:
		if wParam == timerID {
			a.refresh()
		}
		return 0
	case wmDestroy:
		killTimer.Call(uintptr(hwnd), timerID)
		postQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := defWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func (a *app) handleCommand(id int) {
	switch id {
	case idLanguage:
		a.updateState(func(state *toolbarstate.State) { state.ASCII = !state.ASCII })
	case idShape:
		a.updateState(func(state *toolbarstate.State) { state.FullShape = !state.FullShape })
	case idPunct:
		a.updateState(func(state *toolbarstate.State) { state.ASCIIPunctuation = !state.ASCIIPunctuation })
	case idScript:
		a.updateState(func(state *toolbarstate.State) {
			state.Traditionalization = !state.Traditionalization
		})
	case idUnicode:
		showInformation("Unicode 字符面板将在下一阶段作为独立窗口接通。")
	case idSettings:
		if a.settingsTool == "" {
			showError("没有找到设置工具。")
			return
		}
		if err := exec.Command(
			a.settingsTool,
			"-UserDir", a.userDir,
			"-SharedDir", a.sharedDir,
			"-HelpDir", a.helpDir,
			"-LogDir", a.logDir,
		).Start(); err != nil {
			showError("无法打开设置工具：" + err.Error())
		}
	}
}

func (a *app) updateState(change func(*toolbarstate.State)) {
	state, err := toolbarstate.Update(a.statePath, "toolbar", func(state *toolbarstate.State) bool {
		change(state)
		return true
	})
	if err != nil {
		showError("无法更新输入状态：" + err.Error())
		return
	}
	a.state = state
	a.updateLabels()
}

func (a *app) refresh() {
	state, err := toolbarstate.Read(a.statePath)
	if err != nil || state.Revision <= a.state.Revision {
		return
	}
	a.state = state
	a.updateLabels()
}

func (a *app) updateLabels() {
	setButtonText(a.buttons[idLanguage], choose(a.state.ASCII, "英", "中"))
	setButtonText(a.buttons[idShape], choose(a.state.FullShape, "全", "半"))
	setButtonText(a.buttons[idPunct], choose(a.state.ASCIIPunctuation, "英标", "中标"))
	setButtonText(a.buttons[idScript], choose(a.state.Traditionalization, "繁", "简"))
}

func choose(value bool, whenTrue, whenFalse string) string {
	if value {
		return whenTrue
	}
	return whenFalse
}

func setButtonText(hwnd syscall.Handle, text string) {
	if hwnd == 0 {
		return
	}
	value, _ := syscall.UTF16PtrFromString(text)
	setWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(value)))
}

func showInformation(message string) {
	showMessage(message, "Yime 输入法工具栏", 0x40)
}

func showError(message string) {
	showMessage(message, "Yime 输入法工具栏", 0x10)
}

func showMessage(message, title string, flags uintptr) {
	text, _ := syscall.UTF16PtrFromString(message)
	caption, _ := syscall.UTF16PtrFromString(title)
	messageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(caption)), flags)
}
