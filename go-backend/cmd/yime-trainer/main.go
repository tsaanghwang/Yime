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
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/trainer"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsExClientedge     = 0x00000200
	wsOverlappedwindow = 0x00CF0000
	wsChild            = 0x40000000
	wsVisible          = 0x10000000
	wsTabstop          = 0x00010000

	cbsDropdownlist = 0x0003
	cbAddstring     = 0x0143
	cbSetcursel     = 0x014E
	cbGetcursel     = 0x0147
	cbSelchange     = 1
	emSetlimittext  = 0x00C5

	idModeCombo    = 101
	idSectionCombo = 102
	idInputEdit    = 103
	idCheckButton  = 104
	idNextButton   = 105
	idRestart      = 106
	idRevealButton = 107
	idPlayButton   = 108

	bnClicked = 0
)

var (
	moduser32 = syscall.NewLazyDLL("user32.dll")
	modkernel = syscall.NewLazyDLL("kernel32.dll")
	modcomctl = syscall.NewLazyDLL("comctl32.dll")
	modimm32  = syscall.NewLazyDLL("imm32.dll")
	modwinmm  = syscall.NewLazyDLL("winmm.dll")

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
	procMoveWindow           = moduser32.NewProc("MoveWindow")
	procSetFocus             = moduser32.NewProc("SetFocus")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procEnableWindow         = moduser32.NewProc("EnableWindow")
	procGetModuleHandleW     = modkernel.NewProc("GetModuleHandleW")
	procInitCommonControlsEx = modcomctl.NewProc("InitCommonControlsEx")
	procImmAssociateContext  = modimm32.NewProc("ImmAssociateContext")
	procPlaySoundW           = modwinmm.NewProc("PlaySoundW")

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

type initCommonControlsEx struct {
	Size uint32
	ICC  uint32
}

type modeOption struct {
	label string
	value reverselookup.Mode
}

type controls struct {
	modeLabel, modeCombo       syscall.Handle
	sectionLabel, sectionCombo syscall.Handle
	progress, instruction      syscall.Handle
	prompt, detail, target     syscall.Handle
	inputLabel, input          syscall.Handle
	check, next, restart       syscall.Handle
	reveal, play               syscall.Handle
	feedback, score            syscall.Handle
}

type appState struct {
	lesson           trainer.Lesson
	resolver         *trainer.Resolver
	mode             reverselookup.Mode
	modeOptions      []modeOption
	sectionExercises [][]trainer.Exercise
	sectionIndex     int
	itemIndex        int
	attempted        int
	correct          int
	mainHWND         syscall.Handle
	ui               controls
	answerRevealed   bool
}

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared runtime data directory")
	userDir := flag.String("UserDir", "", "Yime user data directory")
	mode := flag.String("Mode", "variable", "Yime mode: variable, full, shorthand")
	lessonPath := flag.String("LessonPath", "", "Optional Yime trainer lesson JSON")
	flag.Parse()

	if strings.TrimSpace(*sharedDir) == "" {
		showError("缺少 SharedDir 参数。")
		os.Exit(1)
	}
	effectiveDir, err := layoutdesigner.EffectiveDataDir(strings.TrimSpace(*sharedDir), strings.TrimSpace(*userDir))
	if err != nil {
		showError(err.Error())
		os.Exit(1)
	}
	path := strings.TrimSpace(*lessonPath)
	if path == "" {
		path = filepath.Join(strings.TrimSpace(*sharedDir), "trainer", "foundation.json")
	}
	lesson, err := trainer.Load(path)
	if err != nil {
		showError("无法加载练习课程：" + err.Error())
		os.Exit(1)
	}
	resolver, err := trainer.NewResolver(effectiveDir)
	if err != nil {
		showError("无法读取当前 Yime 编码：" + err.Error())
		os.Exit(1)
	}
	state := &appState{
		lesson:   lesson,
		resolver: resolver,
		mode:     normalizedMode(*mode),
		modeOptions: []modeOption{
			{label: "变长", value: reverselookup.ModeVariable},
			{label: "等长", value: reverselookup.ModeFull},
			{label: "省键", value: reverselookup.ModeShorthand},
		},
	}
	if err := state.resolveExercises(); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
	if err := runApp(state); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func normalizedMode(value string) reverselookup.Mode {
	switch reverselookup.Mode(strings.TrimSpace(value)) {
	case reverselookup.ModeFull:
		return reverselookup.ModeFull
	case reverselookup.ModeShorthand:
		return reverselookup.ModeShorthand
	default:
		return reverselookup.ModeVariable
	}
}

func (state *appState) resolveExercises() error {
	all, err := state.resolver.Resolve(state.lesson, state.mode)
	if err != nil {
		return err
	}
	state.sectionExercises = make([][]trainer.Exercise, len(state.lesson.Sections))
	offset := 0
	for index, section := range state.lesson.Sections {
		count := len(section.Items)
		if offset+count > len(all) {
			return fmt.Errorf("课程分段解析数量不一致")
		}
		state.sectionExercises[index] = append([]trainer.Exercise(nil), all[offset:offset+count]...)
		offset += count
	}
	return nil
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if win32ui.ActivateExistingWindow("YimeTrainer") {
		return nil
	}
	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeTrainer")
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

	const clientW, clientH = int32(900), int32(560)
	winW, winH := windowSizeForClient(clientW, clientH)
	screenW, _, _ := procGetSystemMetrics.Call(0)
	screenH, _, _ := procGetSystemMetrics.Call(1)
	title, _ := syscall.UTF16PtrFromString("Yime 音元指法练习")
	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(wsExControlparent|wsExAppwindow),
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		uintptr(wsOverlappedwindow),
		uintptr((int32(screenW)-winW)/2), uintptr((int32(screenH)-winH)/2),
		uintptr(winW), uintptr(winH),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowEx failed")
	}
	state.mainHWND = syscall.Handle(hwnd)
	state.createControls()
	state.layout(clientW, clientH)
	state.populateCombos()
	state.refreshExercise()
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)

	var message winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		isDialog, _, _ := procIsDialogMessageW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(&message)))
		if isDialog != 0 {
			continue
		}
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) createControls() {
	state.ui.modeLabel = createControl("STATIC", "输入方案：", wsChild|wsVisible, 0, state.mainHWND, 0)
	state.ui.modeCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idModeCombo)
	state.ui.sectionLabel = createControl("STATIC", "练习类型：", wsChild|wsVisible, 0, state.mainHWND, 0)
	state.ui.sectionCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idSectionCombo)
	state.ui.progress = createControl("STATIC", "", wsChild|wsVisible, 0, state.mainHWND, 0)
	state.ui.instruction = createControl("STATIC", "", wsChild|wsVisible, 0, state.mainHWND, 0)
	state.ui.prompt = createControl("STATIC", "", wsChild|wsVisible|0x00000001, 0, state.mainHWND, 0)
	state.ui.detail = createControl("STATIC", "", wsChild|wsVisible|0x00000001, 0, state.mainHWND, 0)
	state.ui.target = createControl("STATIC", "", wsChild|wsVisible|0x00000001, 0, state.mainHWND, 0)
	state.ui.inputLabel = createControl("STATIC", "请按目标键位输入（此框已关闭输入法）：", wsChild|wsVisible, 0, state.mainHWND, 0)
	state.ui.input = createControl("EDIT", "", wsChild|wsVisible|wsTabstop|0x0080, wsExClientedge, state.mainHWND, idInputEdit)
	state.ui.check = createControl("BUTTON", "检查", wsChild|wsVisible|wsTabstop|0x00000001, 0, state.mainHWND, idCheckButton)
	state.ui.next = createControl("BUTTON", "下一题", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idNextButton)
	state.ui.restart = createControl("BUTTON", "重新开始", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idRestart)
	state.ui.reveal = createControl("BUTTON", "显示答案", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idRevealButton)
	state.ui.play = createControl("BUTTON", "暂无音频", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idPlayButton)
	state.ui.feedback = createControl("STATIC", "", wsChild|wsVisible|0x00000001, 0, state.mainHWND, 0)
	state.ui.score = createControl("STATIC", "", wsChild|wsVisible, 0, state.mainHWND, 0)
	procSendMessageW.Call(uintptr(state.ui.input), emSetlimittext, 256, 0)
	// The exercise field must receive physical key text instead of starting a
	// PIME composition. This affects only this child control and never changes
	// the user's system input-method state.
	procImmAssociateContext.Call(uintptr(state.ui.input), 0)
}

func (state *appState) populateCombos() {
	for index, option := range state.modeOptions {
		addComboString(state.ui.modeCombo, option.label)
		if option.value == state.mode {
			procSendMessageW.Call(uintptr(state.ui.modeCombo), cbSetcursel, uintptr(index), 0)
		}
	}
	for _, section := range state.lesson.Sections {
		addComboString(state.ui.sectionCombo, section.Title)
	}
	procSendMessageW.Call(uintptr(state.ui.sectionCombo), cbSetcursel, 0, 0)
}

func (state *appState) currentExercise() (trainer.Exercise, bool) {
	if state.sectionIndex < 0 || state.sectionIndex >= len(state.sectionExercises) {
		return trainer.Exercise{}, false
	}
	items := state.sectionExercises[state.sectionIndex]
	if state.itemIndex < 0 || state.itemIndex >= len(items) {
		return trainer.Exercise{}, false
	}
	return items[state.itemIndex], true
}

func (state *appState) refreshExercise() {
	exercise, ok := state.currentExercise()
	if !ok {
		setText(state.ui.prompt, "课程中没有可用题目")
		return
	}
	total := len(state.sectionExercises[state.sectionIndex])
	setText(state.ui.progress, fmt.Sprintf("%s    第 %d / %d 题", state.lesson.Title, state.itemIndex+1, total))
	setText(state.ui.instruction, exercise.Instruction)
	setText(state.ui.prompt, exercise.Prompt)
	setText(state.ui.detail, exercise.Detail)
	state.answerRevealed = false
	setText(state.ui.target, exercise.AnswerLabel+"：尚未显示")
	setText(state.ui.reveal, "显示答案")
	if exercise.AudioPath != "" {
		setText(state.ui.play, "播放音频")
		procEnableWindow.Call(uintptr(state.ui.play), 1)
	} else {
		setText(state.ui.play, "暂无音频")
		procEnableWindow.Call(uintptr(state.ui.play), 0)
	}
	setText(state.ui.input, "")
	setText(state.ui.feedback, "")
	state.refreshScore()
	procSetFocus.Call(uintptr(state.ui.input))
}

func (state *appState) refreshScore() {
	accuracy := float64(0)
	if state.attempted > 0 {
		accuracy = float64(state.correct) / float64(state.attempted) * 100
	}
	setText(state.ui.score, fmt.Sprintf("本轮：已答 %d，正确 %d，正确率 %.1f%%", state.attempted, state.correct, accuracy))
}

func (state *appState) checkAnswer() {
	exercise, ok := state.currentExercise()
	if !ok {
		return
	}
	input := getText(state.ui.input)
	if strings.TrimSpace(input) == "" {
		setText(state.ui.feedback, "请先输入目标键位。")
		procSetFocus.Call(uintptr(state.ui.input))
		return
	}
	state.attempted++
	if trainer.Evaluate(input, exercise.Expected) {
		state.correct++
		setText(state.ui.feedback, "正确。可以继续下一题。")
		state.showAnswer()
	} else {
		setText(state.ui.feedback, "还不对。答案已经显示，可以对照后重试。")
		state.showAnswer()
	}
	state.refreshScore()
}

func (state *appState) showAnswer() {
	exercise, ok := state.currentExercise()
	if !ok {
		return
	}
	state.answerRevealed = true
	setText(state.ui.target, exercise.AnswerLabel+"："+exercise.Expected)
	setText(state.ui.reveal, "隐藏答案")
}

func (state *appState) toggleAnswer() {
	if !state.answerRevealed {
		state.showAnswer()
		return
	}
	exercise, ok := state.currentExercise()
	if !ok {
		return
	}
	state.answerRevealed = false
	setText(state.ui.target, exercise.AnswerLabel+"：尚未显示")
	setText(state.ui.reveal, "显示答案")
}

func (state *appState) playAudio() {
	exercise, ok := state.currentExercise()
	if !ok || exercise.AudioPath == "" {
		return
	}
	path, _ := syscall.UTF16PtrFromString(exercise.AudioPath)
	const sndAsync = 0x0001
	const sndNodefault = 0x0002
	const sndFilename = 0x00020000
	ret, _, _ := procPlaySoundW.Call(uintptr(unsafe.Pointer(path)), 0, sndAsync|sndNodefault|sndFilename)
	if ret == 0 {
		setText(state.ui.feedback, "音频播放失败，请检查课程音频文件。")
	}
}

func (state *appState) nextExercise() {
	items := state.sectionExercises[state.sectionIndex]
	if len(items) == 0 {
		return
	}
	state.itemIndex = (state.itemIndex + 1) % len(items)
	state.refreshExercise()
}

func (state *appState) restartRound() {
	state.itemIndex = 0
	state.attempted = 0
	state.correct = 0
	state.refreshExercise()
}

func (state *appState) selectMode() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.modeCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(state.modeOptions) {
		return
	}
	state.mode = state.modeOptions[index].value
	if err := state.resolveExercises(); err != nil {
		showError(err.Error())
		return
	}
	state.restartRound()
}

func (state *appState) selectSection() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.sectionCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(state.sectionExercises) {
		return
	}
	state.sectionIndex = int(index)
	state.restartRound()
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0005: // WM_SIZE
		state.layout(int32(lParam&0xffff), int32((lParam>>16)&0xffff))
		return 0
	case 0x0111: // WM_COMMAND
		id := int(wParam & 0xffff)
		notify := int((wParam >> 16) & 0xffff)
		switch {
		case id == idModeCombo && notify == cbSelchange:
			state.selectMode()
		case id == idSectionCombo && notify == cbSelchange:
			state.selectSection()
		case id == idCheckButton && notify == bnClicked:
			state.checkAnswer()
		case id == idNextButton && notify == bnClicked:
			state.nextExercise()
		case id == idRestart && notify == bnClicked:
			state.restartRound()
		case id == idRevealButton && notify == bnClicked:
			state.toggleAnswer()
		case id == idPlayButton && notify == bnClicked:
			state.playAudio()
		}
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
			win32ui.PresentMainWindow(state.mainHWND)
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0002: // WM_DESTROY
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func (state *appState) layout(clientW, clientH int32) {
	if state.ui.modeLabel == 0 || clientW < 620 || clientH < 500 {
		return
	}
	const margin, gap = int32(18), int32(10)
	move(state.ui.modeLabel, rect{margin, 18, margin + 76, 42})
	move(state.ui.modeCombo, rect{margin + 78, 14, margin + 190, 180})
	move(state.ui.sectionLabel, rect{margin + 220, 18, margin + 300, 42})
	move(state.ui.sectionCombo, rect{margin + 304, 14, clientW - margin, 180})
	move(state.ui.progress, rect{margin, 58, clientW - margin, 82})
	move(state.ui.instruction, rect{margin, 86, clientW - margin, 112})
	move(state.ui.prompt, rect{margin, 122, clientW - margin, 156})
	move(state.ui.detail, rect{margin, 164, clientW - margin, 278})
	move(state.ui.target, rect{margin, 286, clientW - margin, 316})
	move(state.ui.inputLabel, rect{margin, 326, clientW - margin, 350})
	buttonW := int32(88)
	inputRight := clientW - margin - buttonW*3 - gap*3
	move(state.ui.input, rect{margin, 354, inputRight, 388})
	move(state.ui.check, rect{inputRight + gap, 354, inputRight + gap + buttonW, 388})
	move(state.ui.next, rect{inputRight + gap*2 + buttonW, 354, inputRight + gap*2 + buttonW*2, 388})
	move(state.ui.restart, rect{inputRight + gap*3 + buttonW*2, 354, clientW - margin, 388})
	move(state.ui.play, rect{margin, 400, margin + 112, 434})
	move(state.ui.reveal, rect{margin + 122, 400, margin + 234, 434})
	move(state.ui.feedback, rect{margin, 446, clientW - margin, 478})
	move(state.ui.score, rect{margin, clientH - 42, clientW - margin, clientH - 18})
}

func createControl(className, text string, style, exStyle int32, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(exStyle),
		uintptr(unsafe.Pointer(classPtr)),
		uintptr(unsafe.Pointer(textPtr)),
		uintptr(style),
		0, 0, 10, 10,
		uintptr(parent), uintptr(id), 0, 0,
	)
	control := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(control)
	return control
}

func move(hwnd syscall.Handle, box rect) {
	procMoveWindow.Call(
		uintptr(hwnd),
		uintptr(box.Left), uintptr(box.Top),
		uintptr(box.Right-box.Left), uintptr(box.Bottom-box.Top),
		1,
	)
}

func addComboString(hwnd syscall.Handle, value string) {
	ptr, _ := syscall.UTF16PtrFromString(value)
	procSendMessageW.Call(uintptr(hwnd), cbAddstring, 0, uintptr(unsafe.Pointer(ptr)))
}

func setText(hwnd syscall.Handle, value string) {
	ptr, _ := syscall.UTF16PtrFromString(value)
	procSetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(ptr)))
}

func getText(hwnd syscall.Handle) string {
	length, _, _ := procGetWindowTextLengthW.Call(uintptr(hwnd))
	buffer := make([]uint16, int(length)+1)
	if len(buffer) == 0 {
		return ""
	}
	procGetWindowTextW.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)))
	return syscall.UTF16ToString(buffer)
}

func windowSizeForClient(clientW, clientH int32) (int32, int32) {
	box := rect{Right: clientW, Bottom: clientH}
	ret, _, _ := procAdjustWindowRectEx.Call(uintptr(unsafe.Pointer(&box)), uintptr(wsOverlappedwindow), 0, 0)
	if ret == 0 {
		return clientW + 16, clientH + 39
	}
	return box.Right - box.Left, box.Bottom - box.Top
}

func showError(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 指法练习")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
