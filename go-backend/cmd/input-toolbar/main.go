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
	windowTitle = "音元"

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
	wmClose   = 0x0010
	wmDestroy = 0x0002
	wmNull    = 0x0000

	idLanguage = 100
	idShape    = 101
	idPunct    = 102
	idScript   = 103
	idUnicode  = 104
	idSettings = 105
	idTrainer  = 106
	timerID    = 1

	idMenuOrientation = 200
	idMenuCandidate   = 201
	idMenuSystem      = 202
	idMenuHide        = 203
	idMenuButtonBase  = 300

	toolbarMargin       = int32(8)
	toolbarButtonGap    = int32(6)
	toolbarButtonHeight = int32(32)

	mfString    = 0x0000
	mfChecked   = 0x0008
	mfPopup     = 0x0010
	mfSeparator = 0x0800

	tpmRightButton = 0x0002
	tpmReturnCmd   = 0x0100
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	createWindowExW     = user32.NewProc("CreateWindowExW")
	defWindowProcW      = user32.NewProc("DefWindowProcW")
	dispatchMessageW    = user32.NewProc("DispatchMessageW")
	getMessageW         = user32.NewProc("GetMessageW")
	translateMessageW   = user32.NewProc("TranslateMessage")
	postQuitMessage     = user32.NewProc("PostQuitMessage")
	registerClassExW    = user32.NewProc("RegisterClassExW")
	loadCursorW         = user32.NewProc("LoadCursorW")
	showWindow          = user32.NewProc("ShowWindow")
	isWindowVisible     = user32.NewProc("IsWindowVisible")
	updateWindow        = user32.NewProc("UpdateWindow")
	moveWindow          = user32.NewProc("MoveWindow")
	getWindowRect       = user32.NewProc("GetWindowRect")
	setWindowPos        = user32.NewProc("SetWindowPos")
	setTimer            = user32.NewProc("SetTimer")
	killTimer           = user32.NewProc("KillTimer")
	setWindowTextW      = user32.NewProc("SetWindowTextW")
	messageBoxW         = user32.NewProc("MessageBoxW")
	getSystemMetrics    = user32.NewProc("GetSystemMetrics")
	adjustWindowRectEx  = user32.NewProc("AdjustWindowRectEx")
	createPopupMenu     = user32.NewProc("CreatePopupMenu")
	appendMenuW         = user32.NewProc("AppendMenuW")
	trackPopupMenu      = user32.NewProc("TrackPopupMenu")
	destroyMenu         = user32.NewProc("DestroyMenu")
	getCursorPos        = user32.NewProc("GetCursorPos")
	setForegroundWindow = user32.NewProc("SetForegroundWindow")
	postMessageW        = user32.NewProc("PostMessageW")
	getModuleHandleW    = kernel32.NewProc("GetModuleHandleW")

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

type rect struct {
	Left, Top, Right, Bottom int32
}

type toolbarButton struct {
	id           int
	key          string
	text         string
	width        int32
	customizable bool
}

type buttonPlacement struct {
	id      int
	x       int32
	y       int32
	width   int32
	height  int32
	visible bool
}

type toolbarLayout struct {
	clientWidth  int32
	clientHeight int32
	placements   []buttonPlacement
}

type point struct {
	X, Y int32
}

type app struct {
	statePath    string
	settingsTool string
	trainerTool  string
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
	trainerTool := flag.String("TrainerTool", "", "Path to yime-trainer.exe")
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
		trainerTool:  *trainerTool,
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
	a.state = loadToolbarState(a.statePath)
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

	title, _ := syscall.UTF16PtrFromString(windowTitle)
	windowStyle := uintptr(toolbarWindowStyle())
	windowExStyle := uintptr(wsExToolWindow | wsExTopmost)
	layout := calculateToolbarLayout(a.state)
	width, height := windowSizeForClient(layout.clientWidth, layout.clientHeight)
	screenW, _, _ := getSystemMetrics.Call(0)
	screenH, _, _ := getSystemMetrics.Call(1)
	x, y := defaultToolbarPosition(int32(screenW), int32(screenH), width, height)
	hwnd, _, _ := createWindowExW.Call(
		windowExStyle,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		windowStyle,
		uintptr(x), uintptr(y), uintptr(width), uintptr(height),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return errors.New("无法创建输入法工具栏窗口")
	}
	a.hwnd = syscall.Handle(hwnd)
	a.createButtons()
	a.updateLabels()
	a.applyLayout()
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

func loadToolbarState(path string) toolbarstate.State {
	state, err := toolbarstate.Update(path, "toolbar", func(state *toolbarstate.State) bool {
		if state.OrientationSet {
			return false
		}
		state.Vertical = true
		state.OrientationSet = true
		return true
	})
	if err == nil {
		return state
	}
	return toolbarstate.State{
		Version:        toolbarstate.FormatVersion,
		Vertical:       true,
		OrientationSet: true,
	}
}

func toolbarWindowStyle() uintptr {
	// Deliberately omit WS_SYSMENU: the toolbar is hidden through its settings
	// menu, so the title bar must not expose a focus-red close button.
	return wsPopup | wsCaption
}

func defaultToolbarPosition(screenWidth, screenHeight, width, height int32) (int32, int32) {
	const rightInset = int32(32)
	x := screenWidth - width - rightInset
	y := (screenHeight - height) / 2
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	return x, y
}

func fitToolbarPosition(x, y, screenWidth, screenHeight, width, height int32) (int32, int32) {
	const edgeInset = int32(32)
	if x+width > screenWidth-edgeInset {
		x = screenWidth - width - edgeInset
	}
	if y+height > screenHeight {
		y = screenHeight - height
	}
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	return x, y
}

func (a *app) createButtons() {
	for _, item := range toolbarButtons() {
		a.buttons[item.id] = createButton(
			a.hwnd, item.id, item.text,
			0, 0, item.width, toolbarButtonHeight,
		)
	}
}

func toolbarButtons() []toolbarButton {
	return []toolbarButton{
		{idLanguage, "language", "中文", 54, true},
		{idShape, "shape", "半宽", 54, true},
		{idPunct, "punctuation", "中标", 54, true},
		{idScript, "script", "简体", 54, true},
		{idUnicode, "unicode", "字符", 64, true},
		{idTrainer, "trainer", "练习", 64, true},
		{idSettings, "settings", "设置", 64, false},
	}
}

func calculateToolbarLayout(state toolbarstate.State) toolbarLayout {
	hidden := make(map[string]bool, len(state.HiddenButtons))
	for _, key := range state.HiddenButtons {
		hidden[key] = true
	}
	definitions := toolbarButtons()
	visible := make([]toolbarButton, 0, len(definitions))
	for _, button := range definitions {
		if !button.customizable || !hidden[button.key] {
			visible = append(visible, button)
		}
	}
	layout := toolbarLayout{placements: make([]buttonPlacement, 0, len(definitions))}
	if state.Vertical {
		maxWidth := int32(0)
		for _, button := range visible {
			if button.width > maxWidth {
				maxWidth = button.width
			}
		}
		layout.clientWidth = toolbarMargin*2 + maxWidth
		layout.clientHeight = toolbarMargin*2 +
			int32(len(visible))*toolbarButtonHeight +
			int32(len(visible)-1)*toolbarButtonGap
		y := toolbarMargin
		for _, button := range definitions {
			isVisible := !button.customizable || !hidden[button.key]
			placement := buttonPlacement{id: button.id, visible: isVisible}
			if isVisible {
				placement.x = toolbarMargin
				placement.y = y
				placement.width = maxWidth
				placement.height = toolbarButtonHeight
				y += toolbarButtonHeight + toolbarButtonGap
			}
			layout.placements = append(layout.placements, placement)
		}
		return layout
	}

	totalWidth := int32(0)
	for index, button := range visible {
		totalWidth += button.width
		if index > 0 {
			totalWidth += toolbarButtonGap
		}
	}
	layout.clientWidth = toolbarMargin*2 + totalWidth
	layout.clientHeight = toolbarMargin*2 + toolbarButtonHeight
	x := toolbarMargin
	for _, button := range definitions {
		isVisible := !button.customizable || !hidden[button.key]
		placement := buttonPlacement{id: button.id, visible: isVisible}
		if isVisible {
			placement.x = x
			placement.y = toolbarMargin
			placement.width = button.width
			placement.height = toolbarButtonHeight
			x += button.width + toolbarButtonGap
		}
		layout.placements = append(layout.placements, placement)
	}
	return layout
}

func (a *app) applyLayout() {
	layout := calculateToolbarLayout(a.state)
	for _, placement := range layout.placements {
		button := a.buttons[placement.id]
		if placement.visible {
			showWindow.Call(uintptr(button), 5)
			moveWindow.Call(
				uintptr(button),
				uintptr(placement.x), uintptr(placement.y),
				uintptr(placement.width), uintptr(placement.height),
				1,
			)
		} else {
			showWindow.Call(uintptr(button), 0)
		}
	}
	width, height := windowSizeForClient(layout.clientWidth, layout.clientHeight)
	const swpNoZOrder = 0x0004
	const swpNoActivate = 0x0010
	position := rect{}
	getWindowRect.Call(uintptr(a.hwnd), uintptr(unsafe.Pointer(&position)))
	screenW, _, _ := getSystemMetrics.Call(0)
	screenH, _, _ := getSystemMetrics.Call(1)
	x, y := fitToolbarPosition(
		position.Left, position.Top,
		int32(screenW), int32(screenH), width, height,
	)
	setWindowPos.Call(
		uintptr(a.hwnd), 0, uintptr(x), uintptr(y), uintptr(width), uintptr(height),
		swpNoZOrder|swpNoActivate,
	)
}

func windowSizeForClient(clientWidth, clientHeight int32) (int32, int32) {
	box := rect{Right: clientWidth, Bottom: clientHeight}
	ret, _, _ := adjustWindowRectEx.Call(
		uintptr(unsafe.Pointer(&box)),
		toolbarWindowStyle(),
		0,
		uintptr(wsExToolWindow|wsExTopmost),
	)
	if ret == 0 {
		// Conservative fallback: never let a non-client title bar consume the
		// button row if Windows cannot calculate the frame for some reason.
		return clientWidth + 16, clientHeight + 48
	}
	return box.Right - box.Left, box.Bottom - box.Top
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
	case wmClose:
		// The title-bar X is the toolbar's "hide" action. Keep this small
		// process and its state alive so the language-bar menu can show it
		// again without touching PIME or the candidate window.
		showWindow.Call(uintptr(hwnd), 0)
		return 0
	case wmCommand:
		if int((wParam>>16)&0xffff) == 0 {
			a.handleCommand(int(wParam & 0xffff))
		}
		return 0
	case wmTimer:
		if wParam == timerID {
			visible, _, _ := isWindowVisible.Call(uintptr(hwnd))
			if visible != 0 {
				a.refresh()
			}
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
	case idTrainer:
		a.openTrainer()
	case idSettings:
		a.showSettingsMenu()
	}
}

func (a *app) showSettingsMenu() {
	menu, _, _ := createPopupMenu.Call()
	customize, _, _ := createPopupMenu.Call()
	if menu == 0 || customize == 0 {
		if menu != 0 {
			destroyMenu.Call(menu)
		}
		if customize != 0 {
			destroyMenu.Call(customize)
		}
		showError("无法创建工具栏设置菜单。")
		return
	}
	defer destroyMenu.Call(menu)

	for index, button := range toolbarButtons() {
		if !button.customizable {
			continue
		}
		flags := uintptr(mfString)
		if !a.buttonHidden(button.key) {
			flags |= mfChecked
		}
		appendPopupMenuItem(customize, flags, uintptr(idMenuButtonBase+index), buttonMenuName(button.key))
	}
	appendPopupMenuItem(menu, mfPopup, customize, "定制")
	appendPopupMenuItem(menu, mfString, idMenuOrientation, orientationMenuLabel(a.state))
	appendPopupMenuItem(menu, mfString, idMenuHide, "隐藏")
	appendPopupMenuItem(menu, mfSeparator, 0, "")
	appendPopupMenuItem(menu, mfString, idMenuCandidate, "候选")
	appendPopupMenuItem(menu, mfString, idMenuSystem, "系统")

	var cursor point
	getCursorPos.Call(uintptr(unsafe.Pointer(&cursor)))
	setForegroundWindow.Call(uintptr(a.hwnd))
	command, _, _ := trackPopupMenu.Call(
		menu,
		tpmRightButton|tpmReturnCmd,
		uintptr(cursor.X), uintptr(cursor.Y),
		0,
		uintptr(a.hwnd),
		0,
	)
	postMessageW.Call(uintptr(a.hwnd), wmNull, 0, 0)
	a.handleSettingsMenuCommand(int(command))
}

func orientationMenuLabel(state toolbarstate.State) string {
	if state.Vertical {
		return "垂直"
	}
	return "水平"
}

func appendPopupMenuItem(menu uintptr, flags uintptr, id uintptr, text string) {
	var label *uint16
	if text != "" {
		label, _ = syscall.UTF16PtrFromString(text)
	}
	appendMenuW.Call(
		menu,
		flags,
		id,
		uintptr(unsafe.Pointer(label)),
	)
}

func buttonMenuName(key string) string {
	switch key {
	case "language":
		return "中文/英文"
	case "shape":
		return "半宽/全宽"
	case "punctuation":
		return "中标/英标"
	case "script":
		return "简体/繁体"
	case "unicode":
		return "字符"
	case "trainer":
		return "练习"
	default:
		return key
	}
}

func (a *app) handleSettingsMenuCommand(command int) {
	switch command {
	case 0:
		return
	case idMenuOrientation:
		a.updateState(func(state *toolbarstate.State) {
			state.Vertical = !state.Vertical
			state.OrientationSet = true
		})
	case idMenuHide:
		showWindow.Call(uintptr(a.hwnd), 0)
	case idMenuCandidate:
		a.openCandidateSettings()
	case idMenuSystem:
		if err := exec.Command("explorer.exe", "ms-settings:regionlanguage").Start(); err != nil {
			showError("无法打开 Windows 输入法设置：" + err.Error())
		}
	default:
		index := command - idMenuButtonBase
		buttons := toolbarButtons()
		if index < 0 || index >= len(buttons) || !buttons[index].customizable {
			return
		}
		key := buttons[index].key
		a.updateState(func(state *toolbarstate.State) {
			state.HiddenButtons = toggleHiddenButton(state.HiddenButtons, key)
		})
	}
}

func (a *app) openTrainer() {
	if a.trainerTool == "" {
		showError("没有找到指法练习工具。")
		return
	}
	if err := exec.Command(
		a.trainerTool,
		"-SharedDir", a.sharedDir,
		"-UserDir", a.userDir,
		"-Mode", trainerModeFromSchema(a.state.SchemaID),
	).Start(); err != nil {
		showError("无法打开指法练习：" + err.Error())
	}
}

func trainerModeFromSchema(schemaID string) string {
	switch schemaID {
	case "yime_full":
		return "full"
	case "yime_shorthand":
		return "shorthand"
	default:
		return "variable"
	}
}

func (a *app) openCandidateSettings() {
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

func (a *app) buttonHidden(key string) bool {
	for _, hidden := range a.state.HiddenButtons {
		if hidden == key {
			return true
		}
	}
	return false
}

func toggleHiddenButton(hidden []string, key string) []string {
	next := make([]string, 0, len(hidden)+1)
	found := false
	for _, existing := range hidden {
		if existing == key {
			found = true
			continue
		}
		next = append(next, existing)
	}
	if !found {
		next = append(next, key)
	}
	return next
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
	a.applyLayout()
}

func (a *app) refresh() {
	state, err := toolbarstate.Read(a.statePath)
	if err != nil || state.Revision <= a.state.Revision {
		return
	}
	a.state = state
	a.updateLabels()
	a.applyLayout()
}

func (a *app) updateLabels() {
	setButtonText(a.buttons[idLanguage], choose(a.state.ASCII, "英文", "中文"))
	setButtonText(a.buttons[idShape], choose(a.state.FullShape, "全宽", "半宽"))
	setButtonText(a.buttons[idPunct], choose(a.state.ASCIIPunctuation, "英标", "中标"))
	setButtonText(a.buttons[idScript], choose(a.state.Traditionalization, "繁体", "简体"))
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
	showMessage(message, windowTitle, 0x40)
}

func showError(message string) {
	showMessage(message, windowTitle, 0x10)
}

func showMessage(message, title string, flags uintptr) {
	text, _ := syscall.UTF16PtrFromString(message)
	caption, _ := syscall.UTF16PtrFromString(title)
	messageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(caption)), flags)
}
