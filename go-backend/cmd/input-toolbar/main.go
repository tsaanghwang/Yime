//go:build windows

package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	windowClass           = "YimeInputToolbar"
	experimentWindowClass = "YimeCoreInputToolbarWindow"
	previewWindowClass    = "YimePunctuationIconPreview"
	messageTitle          = "音元桌面浮动工具栏"
	experimentWindowTitle = "Yime 元版桌面浮动工具栏"
	previewWindowTitle    = "中英文工具栏图标预览（点击切换）"

	wsExToolWindow = 0x00000080
	wsExTopmost    = 0x00000008
	wsExLayered    = 0x00080000
	wsExNoActivate = 0x08000000
	wsCaption      = 0x00C00000
	wsSysMenu      = 0x00080000
	wsBorder       = 0x00800000
	wsDlgFrame     = 0x00400000
	wsPopup        = 0x80000000
	wsChild        = 0x40000000
	wsVisible      = 0x10000000
	wsTabStop      = 0x00010000
	bsPushButton   = 0x00000000
	ssCenter       = 0x00000001
	ssCenterImage  = 0x00000200
	ssNotify       = 0x00000100
	ttsAlwaysTip   = 0x00000001
	ttfIDIsHWND    = 0x00000001
	ttfSubclass    = 0x00000010

	wmCommand         = 0x0111
	wmTimer           = 0x0113
	wmClose           = 0x0010
	wmDestroy         = 0x0002
	wmPaint           = 0x000f
	wmMouseActivate   = 0x0021
	wmNull            = 0x0000
	wmLButtonDown     = 0x0201
	wmNcLButtonDown   = 0x00A1
	wmPrintClient     = 0x0318
	maNoActivate      = 3
	swShowNoActivate  = 4
	wmUser            = 0x0400
	wmDrawToolbarIcon = wmUser + 1
	htCaption         = 2
	ttmAddToolW       = wmUser + 50

	idHandle   = 99
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
	idMenuToolCenter  = 204
	idMenuDisplayIcon = 205
	idMenuDisplayText = 206
	idMenuTransparent = 207
	idMenuOpaque      = 208
	idMenuButtonBase  = 300

	toolbarMargin       = int32(7)
	toolbarButtonGap    = int32(4)
	toolbarButtonHeight = int32(34)
	toolbarHandleWidth  = int32(18)
	toolbarHandleHeight = int32(18)
	toolbarTextPadding  = int32(24)
	toolbarIconWidth    = int32(40)
	toolbarMinTextWidth = int32(48)

	mfString    = 0x0000
	mfChecked   = 0x0008
	mfPopup     = 0x0010
	mfSeparator = 0x0800

	tpmRightButton = 0x0002
	tpmReturnCmd   = 0x0100

	bmGetState = 0x00f2
	bstPushed  = 0x0004
	psSolid    = 0
	nullBrush  = 5
	nullPen    = 8

	colorWindow       = 5
	colorWindowText   = 8
	bkModeTransparent = 1
	dtCenter          = 0x00000001
	dtVCenter         = 0x00000004
	dtSingleLine      = 0x00000020
	dtNoClip          = 0x00000100
	dtNoPrefix        = 0x00000800
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	uxtheme  = syscall.NewLazyDLL("uxtheme.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	dwmapi   = syscall.NewLazyDLL("dwmapi.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")

	createWindowExW       = user32.NewProc("CreateWindowExW")
	defWindowProcW        = user32.NewProc("DefWindowProcW")
	dispatchMessageW      = user32.NewProc("DispatchMessageW")
	getMessageW           = user32.NewProc("GetMessageW")
	translateMessageW     = user32.NewProc("TranslateMessage")
	postQuitMessage       = user32.NewProc("PostQuitMessage")
	destroyWindow         = user32.NewProc("DestroyWindow")
	registerClassExW      = user32.NewProc("RegisterClassExW")
	loadCursorW           = user32.NewProc("LoadCursorW")
	showWindow            = user32.NewProc("ShowWindow")
	isWindowVisible       = user32.NewProc("IsWindowVisible")
	updateWindow          = user32.NewProc("UpdateWindow")
	moveWindow            = user32.NewProc("MoveWindow")
	getWindowRect         = user32.NewProc("GetWindowRect")
	setWindowPos          = user32.NewProc("SetWindowPos")
	setTimer              = user32.NewProc("SetTimer")
	killTimer             = user32.NewProc("KillTimer")
	setWindowTextW        = user32.NewProc("SetWindowTextW")
	messageBoxW           = user32.NewProc("MessageBoxW")
	drawTextW             = user32.NewProc("DrawTextW")
	getSystemMetrics      = user32.NewProc("GetSystemMetrics")
	getDpiForWindow       = user32.NewProc("GetDpiForWindow")
	getSysColor           = user32.NewProc("GetSysColor")
	getSysColorBrush      = user32.NewProc("GetSysColorBrush")
	getClientRect         = user32.NewProc("GetClientRect")
	getDC                 = user32.NewProc("GetDC")
	releaseDC             = user32.NewProc("ReleaseDC")
	adjustWindowRectEx    = user32.NewProc("AdjustWindowRectEx")
	fillRect              = user32.NewProc("FillRect")
	invalidateRect        = user32.NewProc("InvalidateRect")
	createPopupMenu       = user32.NewProc("CreatePopupMenu")
	appendMenuW           = user32.NewProc("AppendMenuW")
	trackPopupMenu        = user32.NewProc("TrackPopupMenu")
	destroyMenu           = user32.NewProc("DestroyMenu")
	getCursorPos          = user32.NewProc("GetCursorPos")
	setForegroundWindow   = user32.NewProc("SetForegroundWindow")
	postMessageW          = user32.NewProc("PostMessageW")
	getParent             = user32.NewProc("GetParent")
	setLayeredAttributes  = user32.NewProc("SetLayeredWindowAttributes")
	releaseCapture        = user32.NewProc("ReleaseCapture")
	sendMessageW          = user32.NewProc("SendMessageW")
	callWindowProcW       = user32.NewProc("CallWindowProcW")
	setWindowLongPtrW     = user32.NewProc("SetWindowLongPtrW")
	getModuleHandleW      = kernel32.NewProc("GetModuleHandleW")
	setWindowTheme        = uxtheme.NewProc("SetWindowTheme")
	createSolidBrush      = gdi32.NewProc("CreateSolidBrush")
	createFontW           = gdi32.NewProc("CreateFontW")
	createPen             = gdi32.NewProc("CreatePen")
	deleteObject          = gdi32.NewProc("DeleteObject")
	ellipse               = gdi32.NewProc("Ellipse")
	getStockObject        = gdi32.NewProc("GetStockObject")
	selectObject          = gdi32.NewProc("SelectObject")
	setBkMode             = gdi32.NewProc("SetBkMode")
	setTextColor          = gdi32.NewProc("SetTextColor")
	setTextAlign          = gdi32.NewProc("SetTextAlign")
	textOutW              = gdi32.NewProc("TextOutW")
	getGlyphOutlineW      = gdi32.NewProc("GetGlyphOutlineW")
	dwmSetWindowAttribute = dwmapi.NewProc("DwmSetWindowAttribute")
	initCommonControlsEx  = comctl32.NewProc("InitCommonControlsEx")

	windowProc            uintptr
	handleWindowProc      uintptr
	originalHandleProc    uintptr
	iconButtonWindowProc  uintptr
	originalButtonProc    uintptr
	scriptGlyphFonts      = map[int32]uintptr{}
	punctuationGlyphFonts = map[string]uintptr{}

	closeToolbarWindow = func(hwnd syscall.Handle) {
		destroyWindow.Call(uintptr(hwnd))
	}
	beginToolbarDrag = func(hwnd syscall.Handle) {
		parent, _, _ := getParent.Call(uintptr(hwnd))
		if parent == 0 {
			return
		}
		releaseCapture.Call()
		sendMessageW.Call(parent, wmNcLButtonDown, htCaption, 0)
	}
	measureToolbarTextWidth = win32ui.MeasureDefaultGUITextWidth
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

type shapeIconGeometry struct {
	Outer rect
	Light rect
	Dark  rect
}

type punctuationIconGeometry struct {
	Canvas       rect
	TopGlyph     string
	TopBounds    rect
	BottomGlyph  string
	BottomBounds rect
	FontHeight   int32
}

type languageIconGeometry struct {
	Canvas     rect
	Glyph      string
	FontHeight int32
}

type scriptIconGeometry struct {
	Canvas     rect
	Glyph      string
	FontHeight int32
}

type toolbarButton struct {
	id           int
	key          string
	text         string
	icon         string
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

type fixed struct {
	Fract uint16
	Value int16
}

type mat2 struct {
	M11 fixed
	M12 fixed
	M21 fixed
	M22 fixed
}

type glyphMetrics struct {
	BlackBoxX uint32
	BlackBoxY uint32
	Origin    point
	CellIncX  int16
	CellIncY  int16
}

type commonControlsConfig struct {
	Size    uint32
	Classes uint32
}

type toolInfo struct {
	Size     uint32
	Flags    uint32
	Hwnd     syscall.Handle
	ID       uintptr
	Box      rect
	Instance syscall.Handle
	Text     *uint16
	LParam   uintptr
	Reserved unsafe.Pointer
}

type app struct {
	statePath          string
	settingsTool       string
	trainerTool        string
	toolCenterTool     string
	userDir            string
	sharedDir          string
	helpDir            string
	logDir             string
	hwnd               syscall.Handle
	buttons            map[int]syscall.Handle
	tooltip            syscall.Handle
	tooltipText        map[int][]uint16
	state              toolbarstate.State
	experimental       bool
	previewPunctuation bool
}

func main() {
	statePath := flag.String("StatePath", "", "Path to yime_input_toolbar_state.json")
	settingsTool := flag.String("SettingsTool", "", "Path to settings-tool.exe")
	trainerTool := flag.String("TrainerTool", "", "Path to yime-trainer.exe")
	toolCenterTool := flag.String("ToolCenterTool", "", "Path to tool-hub.exe")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	sharedDir := flag.String("SharedDir", "", "Yime shared data directory")
	helpDir := flag.String("HelpDir", "", "Yime help directory")
	logDir := flag.String("LogDir", "", "PIME log directory")
	experimental := flag.Bool("Experimental", false, "Run the independent YimeCore trial toolbar")
	previewPunctuation := flag.Bool("PreviewPunctuation", false, "Preview the punctuation toolbar icons without installing PIME")
	flag.Parse()
	cleanupPreview := func() {}
	if *previewPunctuation {
		var err error
		*statePath, cleanupPreview, err = createPunctuationPreviewState()
		if err != nil {
			showError(err.Error())
			os.Exit(1)
		}
		defer cleanupPreview()
	}
	if *statePath == "" {
		showError("缺少 StatePath 参数。")
		os.Exit(1)
	}
	instance := &app{
		statePath:          *statePath,
		settingsTool:       *settingsTool,
		trainerTool:        *trainerTool,
		toolCenterTool:     *toolCenterTool,
		userDir:            *userDir,
		sharedDir:          *sharedDir,
		helpDir:            *helpDir,
		logDir:             *logDir,
		buttons:            map[int]syscall.Handle{},
		tooltipText:        map[int][]uint16{},
		experimental:       *experimental,
		previewPunctuation: *previewPunctuation,
	}
	if err := instance.run(); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func createPunctuationPreviewState() (string, func(), error) {
	directory, err := os.MkdirTemp("", "yime-punctuation-preview-*")
	if err != nil {
		return "", func() {}, err
	}
	cleanup := func() { _ = os.RemoveAll(directory) }
	path := filepath.Join(directory, toolbarstate.FileName)
	_, err = toolbarstate.Update(path, "punctuation-preview", func(state *toolbarstate.State) bool {
		state.Vertical = false
		state.OrientationSet = true
		state.ToolbarLayoutVersion = toolbarstate.LayoutVersion
		state.ToolbarDisplay = toolbarstate.ToolbarDisplayIcon
		return true
	})
	if err != nil {
		cleanup()
		return "", func() {}, err
	}
	return path, cleanup, nil
}

func (a *app) run() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	controls := commonControlsConfig{Size: uint32(unsafe.Sizeof(commonControlsConfig{})), Classes: 0x000000ff}
	initCommonControlsEx.Call(uintptr(unsafe.Pointer(&controls)))

	if !a.previewPunctuation && win32ui.ActivateExistingWindow(a.className()) {
		return nil
	}
	if a.experimental {
		a.state = loadExperimentalToolbarState(a.statePath)
	} else {
		a.state = loadToolbarState(a.statePath)
	}
	instance, _, _ := getModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString(a.className())
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
		Background: toolbarBackgroundBrush(),
		ClassName:  className,
	}
	if ret, _, _ := registerClassExW.Call(uintptr(unsafe.Pointer(&class))); ret == 0 {
		return errors.New("无法注册桌面浮动工具栏窗口")
	}

	title, _ := syscall.UTF16PtrFromString(a.windowTitle())
	windowStyle := a.windowStyle()
	windowExStyle := a.windowExStyle()
	layout := calculateToolbarLayoutFor(a.state, a.buttonDefinitions())
	width, height := windowSizeForClientWithStyle(layout.clientWidth, layout.clientHeight, windowStyle, windowExStyle)
	screenW, _, _ := getSystemMetrics.Call(0)
	screenH, _, _ := getSystemMetrics.Call(1)
	x, y := a.defaultWindowPosition(int32(screenW), int32(screenH), width, height)
	hwnd, _, _ := createWindowExW.Call(
		windowExStyle,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		windowStyle,
		uintptr(x), uintptr(y), uintptr(width), uintptr(height),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return errors.New("无法创建桌面浮动工具栏窗口")
	}
	a.hwnd = syscall.Handle(hwnd)
	a.createButtons()
	a.createTooltips()
	a.updateLabels()
	a.applyLayout()
	a.applyAppearance()
	setTimer.Call(hwnd, timerID, 200, 0)
	showWindow.Call(hwnd, swShowNoActivate)
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

func (a *app) className() string {
	if a.previewPunctuation {
		return previewWindowClass
	}
	if a.experimental {
		return experimentWindowClass
	}
	return windowClass
}

func (a *app) windowTitle() string {
	if a.previewPunctuation {
		return previewWindowTitle
	}
	if a.experimental {
		return experimentWindowTitle
	}
	return messageTitle
}

func loadToolbarState(path string) toolbarstate.State {
	state, err := toolbarstate.Update(path, "toolbar", func(state *toolbarstate.State) bool {
		if state.OrientationSet && state.ToolbarLayoutVersion >= toolbarstate.LayoutVersion {
			return false
		}
		state.Vertical = true
		state.OrientationSet = true
		state.ToolbarLayoutVersion = toolbarstate.LayoutVersion
		return true
	})
	if err == nil {
		return state
	}
	return toolbarstate.State{
		Version:              toolbarstate.FormatVersion,
		Vertical:             true,
		OrientationSet:       true,
		ToolbarLayoutVersion: toolbarstate.LayoutVersion,
	}
}

func loadExperimentalToolbarState(path string) toolbarstate.State {
	state, err := toolbarstate.Update(path, "yimecore-toolbar", func(state *toolbarstate.State) bool {
		changed := toolbarstate.NormalizeExperiment(state)
		if !state.OrientationSet || state.ToolbarLayoutVersion < toolbarstate.LayoutVersion {
			state.Vertical = true
			state.OrientationSet = true
			state.ToolbarLayoutVersion = toolbarstate.LayoutVersion
			changed = true
		}
		return changed
	})
	if err == nil {
		return state
	}
	state = toolbarstate.State{
		Version: toolbarstate.FormatVersion, Vertical: true, OrientationSet: true,
		ToolbarLayoutVersion: toolbarstate.LayoutVersion,
	}
	toolbarstate.NormalizeExperiment(&state)
	return state
}

func toolbarWindowStyle() uintptr {
	// The client-area drag handle replaces the native caption completely.
	return wsPopup | wsBorder
}

func (a *app) windowStyle() uintptr {
	if a.previewPunctuation {
		return wsCaption | wsSysMenu
	}
	return toolbarWindowStyle()
}

func (a *app) windowExStyle() uintptr {
	if a.previewPunctuation {
		return wsExTopmost | wsExLayered
	}
	return wsExToolWindow | wsExTopmost | wsExLayered | wsExNoActivate
}

func (a *app) defaultWindowPosition(screenWidth, screenHeight, width, height int32) (int32, int32) {
	if a.previewPunctuation {
		return (screenWidth - width) / 2, (screenHeight - height) / 2
	}
	return defaultToolbarPosition(screenWidth, screenHeight, width, height)
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
	for _, item := range a.buttonDefinitions() {
		if item.id == idHandle {
			a.buttons[item.id] = createDragHandle(a.hwnd, item.id, item.text)
			continue
		}
		button := createButton(
			a.hwnd, item.id, item.text,
			0, 0, toolbarMinTextWidth, toolbarButtonHeight,
		)
		a.buttons[item.id] = button
		if toolbarButtonUsesNativeIcon(item.id) {
			subclassToolbarIconButton(button)
		}
	}
}

func toolbarBackgroundBrush() syscall.Handle {
	// COLORREF uses 0x00BBGGRR; this is a restrained blue-gray (#F4F7F9).
	brush, _, _ := createSolidBrush.Call(0x00F9F7F4)
	if brush == 0 {
		return win32ui.ColorWindowBackground
	}
	return syscall.Handle(brush)
}

func (a *app) createTooltips() {
	className, _ := syscall.UTF16PtrFromString("tooltips_class32")
	tooltip, _, _ := createWindowExW.Call(
		wsExTopmost,
		uintptr(unsafe.Pointer(className)), 0,
		wsPopup|ttsAlwaysTip,
		0x80000000, 0x80000000, 0x80000000, 0x80000000,
		uintptr(a.hwnd), 0, 0, 0,
	)
	if tooltip == 0 {
		return
	}
	a.tooltip = syscall.Handle(tooltip)
	for _, button := range a.buttonDefinitions() {
		if button.id == idHandle {
			continue
		}
		text := syscall.StringToUTF16(buttonTooltip(button.id))
		a.tooltipText[button.id] = text
		info := toolInfo{
			Size:  uint32(unsafe.Sizeof(toolInfo{})),
			Flags: ttfIDIsHWND | ttfSubclass,
			Hwnd:  a.hwnd,
			ID:    uintptr(a.buttons[button.id]),
			Text:  &text[0],
		}
		sendMessageW.Call(tooltip, ttmAddToolW, 0, uintptr(unsafe.Pointer(&info)))
	}
}

func buttonTooltip(id int) string {
	switch id {
	case idLanguage:
		return "中文 / 英文"
	case idShape:
		return "半宽 / 全宽"
	case idPunct:
		return "中文标点 / 英文标点"
	case idScript:
		return "简体 / 繁体"
	case idUnicode:
		return "Unicode 字符"
	case idTrainer:
		return "指法练习"
	case idSettings:
		return "设置"
	default:
		return ""
	}
}

func toolbarButtons() []toolbarButton {
	return []toolbarButton{
		{idHandle, "handle", "│", "", false},
		{idLanguage, "language", "中文", "", true},
		{idShape, "shape", "半宽", "", true},
		{idPunct, "punctuation", "中标", "", true},
		{idScript, "script", "简体", "", true},
		{idUnicode, "unicode", "字符", "\ue8ef", true},
		{idTrainer, "trainer", "练习", "\ue7be", true},
		{idSettings, "settings", "设置", "\ue713", false},
	}
}

func (a *app) buttonDefinitions() []toolbarButton {
	if a.previewPunctuation {
		buttons := toolbarButtons()
		return []toolbarButton{buttons[0], buttons[1], buttons[3]}
	}
	return toolbarButtons()
}

func buttonWidthForLayout(button toolbarButton, state toolbarstate.State, vertical bool) int32 {
	if button.id == idHandle && !vertical {
		return toolbarHandleWidth
	}
	if usesToolbarIcons(state) && button.id != idHandle {
		return toolbarIconWidth
	}
	width := measureToolbarTextWidth(buttonDisplayLabel(button, state)) + toolbarTextPadding
	if width < toolbarMinTextWidth {
		return toolbarMinTextWidth
	}
	return width
}

func buttonHeightForLayout(button toolbarButton, vertical bool) int32 {
	if button.id == idHandle && vertical {
		return toolbarHandleHeight
	}
	return toolbarButtonHeight
}

func calculateToolbarLayout(state toolbarstate.State) toolbarLayout {
	return calculateToolbarLayoutFor(state, toolbarButtons())
}

func calculateToolbarLayoutFor(state toolbarstate.State, definitions []toolbarButton) toolbarLayout {
	hidden := make(map[string]bool, len(state.HiddenButtons))
	for _, key := range state.HiddenButtons {
		hidden[key] = true
	}
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
			width := buttonWidthForLayout(button, state, true)
			if width > maxWidth {
				maxWidth = width
			}
		}
		contentHeight := int32(0)
		for index, button := range visible {
			contentHeight += buttonHeightForLayout(button, true)
			if index > 0 {
				contentHeight += toolbarButtonGap
			}
		}
		layout.clientWidth = toolbarMargin*2 + maxWidth
		layout.clientHeight = toolbarMargin*2 + contentHeight
		y := toolbarMargin
		for _, button := range definitions {
			isVisible := !button.customizable || !hidden[button.key]
			placement := buttonPlacement{id: button.id, visible: isVisible}
			if isVisible {
				height := buttonHeightForLayout(button, true)
				placement.x = toolbarMargin
				placement.y = y
				placement.width = maxWidth
				placement.height = height
				y += height + toolbarButtonGap
			}
			layout.placements = append(layout.placements, placement)
		}
		return layout
	}

	totalWidth := int32(0)
	maxHeight := int32(0)
	for index, button := range visible {
		totalWidth += buttonWidthForLayout(button, state, false)
		height := buttonHeightForLayout(button, false)
		if height > maxHeight {
			maxHeight = height
		}
		if index > 0 {
			totalWidth += toolbarButtonGap
		}
	}
	layout.clientWidth = toolbarMargin*2 + totalWidth
	layout.clientHeight = toolbarMargin*2 + maxHeight
	x := toolbarMargin
	for _, button := range definitions {
		isVisible := !button.customizable || !hidden[button.key]
		placement := buttonPlacement{id: button.id, visible: isVisible}
		if isVisible {
			width := buttonWidthForLayout(button, state, false)
			height := buttonHeightForLayout(button, false)
			placement.x = x
			placement.y = toolbarMargin + (maxHeight-height)/2
			placement.width = width
			placement.height = height
			x += width + toolbarButtonGap
		}
		layout.placements = append(layout.placements, placement)
	}
	return layout
}

func (a *app) applyLayout() {
	layout := calculateToolbarLayoutFor(a.state, a.buttonDefinitions())
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
	width, height := windowSizeForClientWithStyle(
		layout.clientWidth, layout.clientHeight, a.windowStyle(), a.windowExStyle(),
	)
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
	return windowSizeForClientWithStyle(
		clientWidth, clientHeight, toolbarWindowStyle(),
		wsExToolWindow|wsExTopmost|wsExLayered,
	)
}

func windowSizeForClientWithStyle(clientWidth, clientHeight int32, style, exStyle uintptr) (int32, int32) {
	box := rect{Right: clientWidth, Bottom: clientHeight}
	ret, _, _ := adjustWindowRectEx.Call(
		uintptr(unsafe.Pointer(&box)),
		style,
		0,
		exStyle,
	)
	if ret == 0 {
		// The toolbar has no caption; reserve only a small border fallback.
		return clientWidth + 4, clientHeight + 4
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
	theme, _ := syscall.UTF16PtrFromString("Explorer")
	setWindowTheme.Call(uintptr(button), uintptr(unsafe.Pointer(theme)), 0)
	return button
}

func createDragHandle(parent syscall.Handle, id int, text string) syscall.Handle {
	className, _ := syscall.UTF16PtrFromString("STATIC")
	label, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := createWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(label)),
		dragHandleStyle(),
		0, 0, uintptr(toolbarHandleWidth), uintptr(toolbarButtonHeight),
		uintptr(parent), uintptr(id), 0, 0,
	)
	handle := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(handle)
	if handle != 0 {
		handleWindowProc = syscall.NewCallback(dragHandleWndProc)
		previous, _, _ := setWindowLongPtrW.Call(
			uintptr(handle), ^uintptr(3), handleWindowProc,
		)
		originalHandleProc = previous
	}
	return handle
}

func dragHandleStyle() uintptr {
	// SS_NOTIFY prevents the stock STATIC control from treating the handle as
	// mouse-transparent, so its subclass receives WM_LBUTTONDOWN and starts the
	// native caption-drag loop for the borderless parent window.
	return wsChild | wsVisible | ssCenter | ssCenterImage | ssNotify
}

func dragHandleWndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	if message == wmLButtonDown {
		beginToolbarDrag(hwnd)
		return 0
	}
	ret, _, _ := callWindowProcW.Call(
		originalHandleProc, uintptr(hwnd), uintptr(message), wParam, lParam,
	)
	return ret
}

func subclassToolbarIconButton(button syscall.Handle) {
	if button == 0 {
		return
	}
	if iconButtonWindowProc == 0 {
		iconButtonWindowProc = syscall.NewCallback(toolbarIconButtonWndProc)
	}
	previous, _, _ := setWindowLongPtrW.Call(uintptr(button), ^uintptr(3), iconButtonWindowProc)
	if previous != 0 {
		originalButtonProc = previous
	}
}

func toolbarIconButtonWndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	ret, _, _ := callWindowProcW.Call(originalButtonProc, uintptr(hwnd), uintptr(message), wParam, lParam)
	if !toolbarIconButtonNeedsOverlay(message) {
		return ret
	}
	if message == wmPrintClient && wParam != 0 {
		requestToolbarIconOverlay(hwnd, syscall.Handle(wParam))
		return ret
	}
	hdc, _, _ := getDC.Call(uintptr(hwnd))
	if hdc != 0 {
		requestToolbarIconOverlay(hwnd, syscall.Handle(hdc))
		releaseDC.Call(uintptr(hwnd), hdc)
	}
	return ret
}

func toolbarIconButtonNeedsOverlay(message uint32) bool {
	return message == wmPaint || message == wmPrintClient
}

func requestToolbarIconOverlay(button, hdc syscall.Handle) {
	parent, _, _ := getParent.Call(uintptr(button))
	if parent != 0 {
		sendMessageW.Call(parent, wmDrawToolbarIcon, uintptr(button), uintptr(hdc))
	}
}

func (a *app) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case wmMouseActivate:
		if !a.previewPunctuation {
			return maNoActivate
		}
	case wmClose:
		// Closing the independent toolbar must also release input-toolbar.exe
		// so upgrades can replace it. The language-bar command starts a fresh
		// process when the user asks to show the toolbar again.
		closeToolbarWindow(hwnd)
		return 0
	case wmCommand:
		if int((wParam>>16)&0xffff) == 0 {
			a.handleCommand(int(wParam & 0xffff))
		}
		return 0
	case wmDrawToolbarIcon:
		a.drawToolbarButtonOverlay(syscall.Handle(wParam), syscall.Handle(lParam))
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

func (a *app) drawToolbarButtonOverlay(button, hdc syscall.Handle) {
	if button == 0 || hdc == 0 || !usesToolbarIcons(a.state) {
		return
	}
	isShape := button == a.buttons[idShape]
	isPunctuation := button == a.buttons[idPunct]
	isLanguage := button == a.buttons[idLanguage]
	isScript := button == a.buttons[idScript]
	if !isShape && !isPunctuation && !isLanguage && !isScript {
		return
	}
	bounds := rect{}
	if ok, _, _ := getClientRect.Call(uintptr(button), uintptr(unsafe.Pointer(&bounds))); ok == 0 {
		return
	}
	dpi := uint32(96)
	if value, _, _ := getDpiForWindow.Call(uintptr(button)); value != 0 {
		dpi = uint32(value)
	}
	buttonState, _, _ := sendMessageW.Call(uintptr(button), bmGetState, 0, 0)
	pressed := buttonState&bstPushed != 0
	if isLanguage {
		drawLanguageIcon(hdc, bounds, dpi, a.state.ASCII, pressed)
	} else if isShape {
		drawShapeIcon(hdc, bounds, dpi, a.state.FullShape, pressed)
	} else if isPunctuation {
		drawPunctuationIcon(hdc, bounds, dpi, a.state.ASCIIPunctuation, pressed)
	} else {
		drawScriptIcon(hdc, bounds, dpi, a.state.Traditionalization, pressed)
	}
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
	appearance, _, _ := createPopupMenu.Call()
	if menu == 0 || customize == 0 || appearance == 0 {
		if menu != 0 {
			destroyMenu.Call(menu)
		}
		if customize != 0 {
			destroyMenu.Call(customize)
		}
		if appearance != 0 {
			destroyMenu.Call(appearance)
		}
		showError("无法创建桌面浮动工具栏设置菜单。")
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
	iconFlags := uintptr(mfString)
	textFlags := uintptr(mfString)
	transparentFlags := uintptr(mfString)
	opaqueFlags := uintptr(mfString)
	if usesToolbarIcons(a.state) {
		iconFlags |= mfChecked
	} else {
		textFlags |= mfChecked
	}
	if a.state.ToolbarTransparent {
		transparentFlags |= mfChecked
	} else {
		opaqueFlags |= mfChecked
	}
	appendPopupMenuItem(appearance, iconFlags, idMenuDisplayIcon, "图标")
	appendPopupMenuItem(appearance, textFlags, idMenuDisplayText, "文字")
	appendPopupMenuItem(appearance, mfSeparator, 0, "")
	appendPopupMenuItem(appearance, transparentFlags, idMenuTransparent, "半透明")
	appendPopupMenuItem(appearance, opaqueFlags, idMenuOpaque, "不透明")
	appendPopupMenuItem(menu, mfPopup, appearance, "外观")
	appendPopupMenuItem(menu, mfString, idMenuOrientation, orientationMenuLabel(a.state))
	appendPopupMenuItem(menu, mfString, idMenuHide, "隐藏")
	appendPopupMenuItem(menu, mfSeparator, 0, "")
	appendPopupMenuItem(menu, mfString, idMenuCandidate, "候选设置")
	if a.experimental {
		appendPopupMenuItem(menu, mfString, idMenuToolCenter, "工具中心")
	}
	appendPopupMenuItem(menu, mfString, idMenuSystem, "系统设置")

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

func dragHandleLabel(state toolbarstate.State) string {
	if state.Vertical {
		return "— —"
	}
	return "│"
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
	case idMenuDisplayIcon:
		a.updateState(func(state *toolbarstate.State) {
			state.ToolbarDisplay = toolbarstate.ToolbarDisplayIcon
		})
	case idMenuDisplayText:
		a.updateState(func(state *toolbarstate.State) {
			state.ToolbarDisplay = toolbarstate.ToolbarDisplayText
		})
	case idMenuTransparent:
		a.updateState(func(state *toolbarstate.State) {
			state.ToolbarTransparent = true
		})
	case idMenuOpaque:
		a.updateState(func(state *toolbarstate.State) {
			state.ToolbarTransparent = false
		})
	case idMenuHide:
		closeToolbarWindow(a.hwnd)
	case idMenuCandidate:
		a.openCandidateSettings()
	case idMenuToolCenter:
		if a.experimental {
			a.openToolCenter()
		}
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
	arguments := []string{
		"-SharedDir", a.sharedDir,
		"-UserDir", a.userDir,
		"-Mode", a.trainerMode(),
	}
	if a.experimental {
		arguments = append(arguments, "-Experimental")
	}
	if err := exec.Command(a.trainerTool, arguments...).Start(); err != nil {
		showError("无法打开指法练习：" + err.Error())
	}
}

func (a *app) trainerMode() string {
	if a.experimental {
		return a.state.ExperimentMode
	}
	return trainerModeFromSchema(a.state.SchemaID)
}

func (a *app) openToolCenter() {
	if a.toolCenterTool == "" {
		showError("没有找到工具中心。")
		return
	}
	arguments := []string{
		"-InstallRoot", filepath.Dir(a.sharedDir),
		"-StateRoot", a.userDir,
		"-StatePath", a.statePath,
		"-Mode", a.trainerMode(),
		"-Experimental",
	}
	if err := exec.Command(a.toolCenterTool, arguments...).Start(); err != nil {
		showError("无法打开工具中心：" + err.Error())
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
	arguments := []string{"-UserDir", a.userDir, "-SharedDir", a.sharedDir}
	if a.experimental {
		arguments = append(arguments, "-StatePath", a.statePath, "-Experimental")
	} else {
		arguments = append(arguments, "-HelpDir", a.helpDir, "-LogDir", a.logDir)
	}
	if err := exec.Command(a.settingsTool, arguments...).Start(); err != nil {
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
	source := "toolbar"
	if a.experimental {
		source = "yimecore-toolbar"
	}
	state, err := toolbarstate.Update(a.statePath, source, func(state *toolbarstate.State) bool {
		if a.experimental {
			toolbarstate.NormalizeExperiment(state)
		}
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
	a.applyAppearance()
}

func (a *app) refresh() {
	state, err := toolbarstate.Read(a.statePath)
	if err != nil || state.Revision <= a.state.Revision {
		return
	}
	if a.experimental {
		toolbarstate.NormalizeExperiment(&state)
	}
	a.state = state
	a.updateLabels()
	a.applyLayout()
	a.applyAppearance()
}

func (a *app) updateLabels() {
	for _, button := range a.buttonDefinitions() {
		hwnd := a.buttons[button.id]
		drawnIcon := usesDrawnToolbarIcon(button, a.state)
		setButtonText(hwnd, buttonDisplayLabel(button, a.state))
		if usesToolbarIcons(a.state) && button.id != idHandle && !drawnIcon {
			win32ui.ApplyFluentIconFont(a.buttons[button.id])
		} else {
			win32ui.ApplyDefaultGUIFont(a.buttons[button.id])
		}
		if drawnIcon && hwnd != 0 {
			invalidateRect.Call(uintptr(hwnd), 0, 1)
		}
	}
}

func usesToolbarIcons(state toolbarstate.State) bool {
	return state.ToolbarDisplay == toolbarstate.ToolbarDisplayIcon
}

func usesDrawnToolbarIcon(button toolbarButton, state toolbarstate.State) bool {
	return toolbarButtonUsesNativeIcon(button.id) && usesToolbarIcons(state)
}

func toolbarButtonUsesNativeIcon(id int) bool {
	return id == idLanguage || id == idShape || id == idPunct || id == idScript
}

func buttonDisplayLabel(button toolbarButton, state toolbarstate.State) string {
	if button.id == idHandle {
		return dragHandleLabel(state)
	}
	if usesToolbarIcons(state) {
		if toolbarButtonUsesNativeIcon(button.id) {
			return ""
		}
		return button.icon
	}
	switch button.id {
	case idLanguage:
		return choose(state.ASCII, "英文", "中文")
	case idShape:
		return choose(state.FullShape, "全宽", "半宽")
	case idPunct:
		return choose(state.ASCIIPunctuation, "英标", "中标")
	case idScript:
		return choose(state.Traditionalization, "繁体", "简体")
	default:
		return button.text
	}
}

func shapeIconGeometryFor(bounds rect, dpi uint32, full, pressed bool) shapeIconGeometry {
	outer, stroke := toolbarIconCanvasFor(bounds, dpi, pressed)
	if outer.Right <= outer.Left || outer.Bottom <= outer.Top {
		return shapeIconGeometry{}
	}
	if full {
		return shapeIconGeometry{Outer: outer, Dark: outer}
	}
	inner := rect{
		Left: outer.Left + stroke, Top: outer.Top + stroke,
		Right: outer.Right - stroke, Bottom: outer.Bottom - stroke,
	}
	dark := inner
	dark.Left = inner.Left + (inner.Right-inner.Left)/2
	return shapeIconGeometry{Outer: outer, Light: inner, Dark: dark}
}

func toolbarIconCanvasFor(bounds rect, dpi uint32, pressed bool) (rect, int32) {
	width := bounds.Right - bounds.Left
	height := bounds.Bottom - bounds.Top
	if width <= 0 || height <= 0 {
		return rect{}, 0
	}
	if dpi == 0 {
		dpi = 96
	}
	desired := int32((int64(18)*int64(dpi) + 48) / 96)
	available := width
	if height < available {
		available = height
	}
	available -= 10
	if desired > available {
		desired = available
	}
	// An even outer and inner width keeps the half-width split exact and
	// prevents either state from looking visually heavier.
	if desired%2 != 0 {
		desired--
	}
	if desired < 6 {
		return rect{}, 0
	}
	stroke := int32((int64(dpi) + 48) / 96)
	if stroke < 1 {
		stroke = 1
	}
	if desired-2*stroke < 4 {
		stroke = 1
	}
	left := bounds.Left + (width-desired)/2
	top := bounds.Top + (height-desired)/2
	if pressed {
		left++
		top++
	}
	return rect{Left: left, Top: top, Right: left + desired, Bottom: top + desired}, stroke
}

func drawShapeIcon(hdc syscall.Handle, bounds rect, dpi uint32, full, pressed bool) {
	geometry := shapeIconGeometryFor(bounds, dpi, full, pressed)
	if geometry.Outer.Right <= geometry.Outer.Left || geometry.Outer.Bottom <= geometry.Outer.Top {
		return
	}
	darkBrush, _, _ := getSysColorBrush.Call(colorWindowText)
	lightBrush, _, _ := getSysColorBrush.Call(colorWindow)
	if darkBrush == 0 || lightBrush == 0 {
		return
	}
	fillRect.Call(uintptr(hdc), uintptr(unsafe.Pointer(&geometry.Outer)), darkBrush)
	if !full {
		fillRect.Call(uintptr(hdc), uintptr(unsafe.Pointer(&geometry.Light)), lightBrush)
		fillRect.Call(uintptr(hdc), uintptr(unsafe.Pointer(&geometry.Dark)), darkBrush)
	}
}

func punctuationIconGeometryFor(bounds rect, dpi uint32, ascii, pressed bool) punctuationIconGeometry {
	canvas, _ := toolbarIconCanvasFor(bounds, dpi, pressed)
	if canvas.Right <= canvas.Left || canvas.Bottom <= canvas.Top {
		return punctuationIconGeometry{}
	}
	middle := canvas.Top + (canvas.Bottom-canvas.Top)/2
	geometry := punctuationIconGeometry{
		Canvas:       canvas,
		TopBounds:    rect{Left: canvas.Left, Top: canvas.Top, Right: canvas.Right, Bottom: middle},
		BottomBounds: rect{Left: canvas.Left, Top: middle, Right: canvas.Right, Bottom: canvas.Bottom},
		FontHeight:   (canvas.Bottom-canvas.Top)/2 + 8,
	}
	if ascii {
		geometry.TopGlyph = ","
		geometry.BottomGlyph = "."
		return geometry
	}
	geometry.TopGlyph = "、"
	geometry.BottomGlyph = "。"
	return geometry
}

func languageIconGeometryFor(bounds rect, dpi uint32, ascii, pressed bool) languageIconGeometry {
	canvas, _ := toolbarIconCanvasFor(bounds, dpi, pressed)
	if canvas.Right <= canvas.Left || canvas.Bottom <= canvas.Top {
		return languageIconGeometry{}
	}
	geometry := languageIconGeometry{
		Canvas:     canvas,
		Glyph:      "中",
		FontHeight: canvas.Bottom - canvas.Top - 2,
	}
	if ascii {
		geometry.Glyph = "A"
	}
	if geometry.FontHeight < 8 {
		geometry.FontHeight = 8
	}
	return geometry
}

func scriptIconGeometryFor(bounds rect, dpi uint32, traditional, pressed bool) scriptIconGeometry {
	canvas, _ := toolbarIconCanvasFor(bounds, dpi, pressed)
	if canvas.Right <= canvas.Left || canvas.Bottom <= canvas.Top {
		return scriptIconGeometry{}
	}
	glyph := "简"
	if traditional {
		glyph = "繁"
	}
	fontHeight := canvas.Bottom - canvas.Top - 2
	if fontHeight < 8 {
		fontHeight = 8
	}
	return scriptIconGeometry{Canvas: canvas, Glyph: glyph, FontHeight: fontHeight}
}

func scaleIconRect(canvas, coordinates rect) rect {
	return rect{
		Left:   scaleIconCoordinate(canvas.Left, canvas.Right-canvas.Left, coordinates.Left),
		Top:    scaleIconCoordinate(canvas.Top, canvas.Bottom-canvas.Top, coordinates.Top),
		Right:  scaleIconCoordinate(canvas.Left, canvas.Right-canvas.Left, coordinates.Right),
		Bottom: scaleIconCoordinate(canvas.Top, canvas.Bottom-canvas.Top, coordinates.Bottom),
	}
}

func scaleIconCoordinate(origin, size, coordinate int32) int32 {
	return origin + (coordinate*size+9)/18
}

func drawPunctuationIcon(hdc syscall.Handle, bounds rect, dpi uint32, ascii, pressed bool) {
	geometry := punctuationIconGeometryFor(bounds, dpi, ascii, pressed)
	if geometry.Canvas.Right <= geometry.Canvas.Left || geometry.Canvas.Bottom <= geometry.Canvas.Top {
		return
	}
	darkColor, _, _ := getSysColor.Call(colorWindowText)
	font := punctuationGlyphFont(geometry.FontHeight, ascii)
	if font == 0 {
		return
	}
	oldFont, _, _ := selectObject.Call(uintptr(hdc), font)
	oldBackgroundMode, _, _ := setBkMode.Call(uintptr(hdc), bkModeTransparent)
	oldTextColor, _, _ := setTextColor.Call(uintptr(hdc), darkColor)
	drawCenteredPunctuationGlyph(hdc, geometry.TopGlyph, geometry.TopBounds)
	drawCenteredPunctuationGlyph(hdc, geometry.BottomGlyph, geometry.BottomBounds)
	setTextColor.Call(uintptr(hdc), oldTextColor)
	setBkMode.Call(uintptr(hdc), oldBackgroundMode)
	selectObject.Call(uintptr(hdc), oldFont)
}

func drawCenteredPunctuationGlyph(hdc syscall.Handle, glyph string, bounds rect) {
	text, err := syscall.UTF16FromString(glyph)
	if err != nil || len(text) != 2 {
		return
	}
	metrics := glyphMetrics{}
	transform := mat2{M11: fixed{Value: 1}, M22: fixed{Value: 1}}
	const (
		ggoMetrics = 0
		gdiError   = 0xffffffff
		taBaseline = 24
	)
	result, _, _ := getGlyphOutlineW.Call(
		uintptr(hdc), uintptr(text[0]), ggoMetrics,
		uintptr(unsafe.Pointer(&metrics)), 0, 0, uintptr(unsafe.Pointer(&transform)),
	)
	if result == gdiError || metrics.BlackBoxX == 0 || metrics.BlackBoxY == 0 {
		drawTextW.Call(uintptr(hdc), uintptr(unsafe.Pointer(&text[0])), 1,
			uintptr(unsafe.Pointer(&bounds)), punctuationDrawTextFlags())
		return
	}
	centerX := bounds.Left + (bounds.Right-bounds.Left)/2
	centerY := bounds.Top + (bounds.Bottom-bounds.Top)/2
	x := centerX - int32(metrics.BlackBoxX)/2 - metrics.Origin.X
	baseline := centerY - int32(metrics.BlackBoxY)/2 + metrics.Origin.Y
	oldAlignment, _, _ := setTextAlign.Call(uintptr(hdc), taBaseline)
	textOutW.Call(uintptr(hdc), uintptr(x), uintptr(baseline), uintptr(unsafe.Pointer(&text[0])), 1)
	setTextAlign.Call(uintptr(hdc), oldAlignment)
}

func punctuationDrawTextFlags() uintptr {
	return dtCenter | dtVCenter | dtSingleLine | dtNoClip | dtNoPrefix
}

func drawLanguageIcon(hdc syscall.Handle, bounds rect, dpi uint32, ascii, pressed bool) {
	geometry := languageIconGeometryFor(bounds, dpi, ascii, pressed)
	if geometry.Canvas.Right <= geometry.Canvas.Left || geometry.Canvas.Bottom <= geometry.Canvas.Top {
		return
	}
	font := punctuationGlyphFont(geometry.FontHeight, ascii)
	if font == 0 {
		return
	}
	darkColor, _, _ := getSysColor.Call(colorWindowText)
	oldFont, _, _ := selectObject.Call(uintptr(hdc), font)
	oldBackgroundMode, _, _ := setBkMode.Call(uintptr(hdc), bkModeTransparent)
	oldTextColor, _, _ := setTextColor.Call(uintptr(hdc), darkColor)
	drawCenteredPunctuationGlyph(hdc, geometry.Glyph, geometry.Canvas)
	setTextColor.Call(uintptr(hdc), oldTextColor)
	setBkMode.Call(uintptr(hdc), oldBackgroundMode)
	selectObject.Call(uintptr(hdc), oldFont)
}

func drawScriptIcon(hdc syscall.Handle, bounds rect, dpi uint32, traditional, pressed bool) {
	geometry := scriptIconGeometryFor(bounds, dpi, traditional, pressed)
	if geometry.Canvas.Right <= geometry.Canvas.Left || geometry.Canvas.Bottom <= geometry.Canvas.Top {
		return
	}
	font := scriptGlyphFont(geometry.FontHeight)
	text, err := syscall.UTF16FromString(geometry.Glyph)
	if font == 0 || err != nil || len(text) <= 1 {
		return
	}
	darkColor, _, _ := getSysColor.Call(colorWindowText)
	oldFont, _, _ := selectObject.Call(uintptr(hdc), font)
	oldBackgroundMode, _, _ := setBkMode.Call(uintptr(hdc), bkModeTransparent)
	oldTextColor, _, _ := setTextColor.Call(uintptr(hdc), darkColor)
	drawTextW.Call(
		uintptr(hdc), uintptr(unsafe.Pointer(&text[0])), uintptr(len(text)-1),
		uintptr(unsafe.Pointer(&geometry.Canvas)), dtCenter|dtVCenter|dtSingleLine|dtNoPrefix,
	)
	setTextColor.Call(uintptr(hdc), oldTextColor)
	setBkMode.Call(uintptr(hdc), oldBackgroundMode)
	selectObject.Call(uintptr(hdc), oldFont)
}

func scriptGlyphFont(pixelHeight int32) uintptr {
	if font := scriptGlyphFonts[pixelHeight]; font != 0 {
		return font
	}
	family, _ := syscall.UTF16PtrFromString(win32ui.DefaultGUIFontFamily)
	height := -pixelHeight
	font, _, _ := createFontW.Call(
		uintptr(height), 0, 0, 0, 400, 0, 0, 0,
		1, 0, 0, 5, 0, uintptr(unsafe.Pointer(family)),
	)
	if font != 0 {
		scriptGlyphFonts[pixelHeight] = font
	}
	return font
}

func punctuationGlyphFontFamily(ascii bool) string {
	if ascii {
		return "Georgia"
	}
	return "Microsoft YaHei UI"
}

func punctuationGlyphFont(pixelHeight int32, ascii bool) uintptr {
	familyName := punctuationGlyphFontFamily(ascii)
	cacheKey := familyName + ":" + fmt.Sprint(pixelHeight)
	if font := punctuationGlyphFonts[cacheKey]; font != 0 {
		return font
	}
	family, _ := syscall.UTF16PtrFromString(familyName)
	font, _, _ := createFontW.Call(
		uintptr(-pixelHeight), 0, 0, 0, 400, 0, 0, 0,
		1, 0, 0, 5, 0, uintptr(unsafe.Pointer(family)),
	)
	if font != 0 {
		punctuationGlyphFonts[cacheKey] = font
	}
	return font
}

func toolbarAlpha(state toolbarstate.State) byte {
	if state.ToolbarTransparent {
		return 224
	}
	return 255
}

func (a *app) applyAppearance() {
	if a.hwnd == 0 {
		return
	}
	const lwaAlpha = 0x00000002
	setLayeredAttributes.Call(uintptr(a.hwnd), 0, uintptr(toolbarAlpha(a.state)), lwaAlpha)
	cornerPreference := uint32(2) // DWMWCP_ROUND
	borderColor := uint32(0x00D8CEC4)
	dwmSetWindowAttribute.Call(uintptr(a.hwnd), 33, uintptr(unsafe.Pointer(&cornerPreference)), unsafe.Sizeof(cornerPreference))
	dwmSetWindowAttribute.Call(uintptr(a.hwnd), 34, uintptr(unsafe.Pointer(&borderColor)), unsafe.Sizeof(borderColor))
}

func choose(value bool, whenTrue, whenFalse string) string {
	if value {
		return whenTrue
	}
	return whenFalse
}

func setButtonText(hwnd syscall.Handle, text string) {
	setWindowLabel(hwnd, text)
}

func setWindowLabel(hwnd syscall.Handle, text string) {
	if hwnd == 0 {
		return
	}
	value, _ := syscall.UTF16PtrFromString(text)
	setWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(value)))
}

func showInformation(message string) {
	showMessage(message, messageTitle, 0x40)
}

func showError(message string) {
	showMessage(message, messageTitle, 0x10)
}

func showMessage(message, title string, flags uintptr) {
	text, _ := syscall.UTF16PtrFromString(message)
	caption, _ := syscall.UTF16PtrFromString(title)
	messageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(caption)), flags)
}
