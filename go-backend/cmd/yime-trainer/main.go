//go:build windows

package main

import (
	"flag"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
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
	cbResetcontent  = 0x014B
	cbSetcursel     = 0x014E
	cbGetcursel     = 0x0147
	cbSelchange     = 1
	emSetlimittext  = 0x00C5
	wmKeyDown       = 0x0100
	vkReturn        = 0x0D

	idModeCombo       = 101
	idSectionCombo    = 102
	idInputEdit       = 103
	idNextButton      = 105
	idRestart         = 106
	idRevealButton    = 107
	idPlayButton      = 108
	idFontCombo       = 109
	idBackgroundCombo = 110
	idCategoryCombo   = 111
	idGroupCombo      = 112
	idSegmentCombo    = 113
	idReviewCombo     = 114
	idReportButton    = 115
	idClearButton     = 116

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
	modeLabel, modeCombo             syscall.Handle
	sectionLabel, sectionCombo       syscall.Handle
	fontLabel, fontCombo             syscall.Handle
	backgroundLabel, backgroundCombo syscall.Handle
	segmentLabel, segmentCombo       syscall.Handle
	reviewLabel, reviewCombo         syscall.Handle
	categoryLabel, categoryCombo     syscall.Handle
	groupLabel, groupCombo           syscall.Handle
	progress, instruction            syscall.Handle
	prompt, detail, target           syscall.Handle
	inputLabel, input                syscall.Handle
	next, restart                    syscall.Handle
	reveal, play, report, clear      syscall.Handle
	feedback, score                  syscall.Handle
}

func (value controls) all() []syscall.Handle {
	return []syscall.Handle{
		value.modeLabel, value.modeCombo, value.sectionLabel, value.sectionCombo,
		value.fontLabel, value.fontCombo, value.backgroundLabel, value.backgroundCombo,
		value.segmentLabel, value.segmentCombo,
		value.reviewLabel, value.reviewCombo,
		value.categoryLabel, value.categoryCombo, value.groupLabel, value.groupCombo,
		value.progress, value.instruction, value.prompt, value.detail, value.target,
		value.inputLabel, value.input, value.next, value.restart,
		value.reveal, value.play, value.report, value.clear, value.feedback, value.score,
	}
}

type appState struct {
	lesson                       trainer.Lesson
	resolver                     *trainer.Resolver
	mode                         reverselookup.Mode
	modeOptions                  []modeOption
	sectionExercises             [][]trainer.Exercise
	keymapGroups                 []trainer.ExerciseGroup
	shouyinGroups                []trainer.ExerciseGroup
	ganyinGroups                 []trainer.GanyinRhymeGroup
	syllableGroups               []trainer.ExerciseGroup
	runtimePractice              trainer.RuntimePracticeSet
	runtimePracticeReady         bool
	wordGroups                   []trainer.ExerciseGroup
	wordGroupIndex               int
	sentenceExercises            []trainer.Exercise
	candidateExercises           []trainer.Exercise
	groupCategories              []trainer.GroupCategory
	visibleGroupIDs              []int
	categoryIndex                int
	groupIndex                   int
	compositionSegmentIndex      int
	compositionShouyinGroupIndex int
	compositionRhymeIndex        int
	compositionToneIndex         int
	syllableGroupIndex           int
	sectionIndex                 int
	itemIndex                    int
	attempted                    int
	correct                      int
	mainHWND                     syscall.Handle
	ui                           controls
	answerRevealed               bool
	preferencesDir               string
	preferences                  trainer.Preferences
	displayFont                  syscall.Handle
	lineHeight                   int32
	backgroundBrush              syscall.Handle
	backgroundColor              uint32
	minimumLayout                trainerLayout
	progressData                 trainer.Progress
	reviewFilter                 string
	roundExercises               []trainer.Exercise
	itemStarted                  time.Time
	lastDiagnosis                trainer.Diagnosis
	hintLevel                    int
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
	resolver, err := trainer.NewResolverWithTrainingData(effectiveDir, strings.TrimSpace(*sharedDir))
	if err != nil {
		showError("无法读取当前 Yime 编码：" + err.Error())
		os.Exit(1)
	}
	preferencesDir := trainer.PreferencesDirectoryFromRimeUserDir(strings.TrimSpace(*userDir))
	preferences, err := trainer.LoadPreferences(preferencesDir)
	if err != nil {
		preferences = trainer.DefaultPreferences()
	}
	progressData, err := trainer.LoadProgress(preferencesDir)
	if err != nil {
		progressData = trainer.NewProgress()
	}
	initialMode := normalizedMode(*mode)
	if preferences.LastMode != "" {
		initialMode = normalizedMode(preferences.LastMode)
	}
	state := &appState{
		lesson:         lesson,
		resolver:       resolver,
		mode:           initialMode,
		preferencesDir: preferencesDir,
		preferences:    preferences,
		progressData:   progressData,
		reviewFilter:   preferences.ReviewFilter,
		modeOptions: []modeOption{
			{label: "变长", value: reverselookup.ModeVariable},
			{label: "等长", value: reverselookup.ModeFull},
			{label: "省键", value: reverselookup.ModeShorthand},
		},
	}
	if lessonNeedsRuntimePractice(lesson) {
		practice, err := resolver.SelectRuntimePracticeSet(rand.New(rand.NewSource(time.Now().UnixNano())))
		if err != nil {
			showError("无法从系统运行库准备随机练习：" + err.Error())
			os.Exit(1)
		}
		state.runtimePractice = practice
		state.runtimePracticeReady = true
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

func lessonNeedsRuntimePractice(lesson trainer.Lesson) bool {
	for _, section := range lesson.Sections {
		if section.Type == trainer.SectionWordPractice || section.Type == trainer.SectionSentencePractice || section.Type == trainer.SectionCandidatePractice {
			return true
		}
	}
	return false
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
	groups, err := state.resolver.ResolveKeymapGroups()
	if err != nil {
		return err
	}
	state.keymapGroups = groups
	fingeringGroups, err := state.resolver.ResolveFingeringDrills()
	if err != nil {
		return err
	}
	state.keymapGroups = append(state.keymapGroups, fingeringGroups...)
	shouyinGroups, err := state.resolver.ResolveShouyinCompositionGroups()
	if err != nil {
		return err
	}
	state.shouyinGroups = shouyinGroups
	ganyinGroups, err := state.resolver.ResolveGanyinCompositionGroups()
	if err != nil {
		return err
	}
	state.ganyinGroups = ganyinGroups
	syllableGroups, err := state.resolver.ResolveSyllablePracticeGroups(state.mode)
	if err != nil {
		return err
	}
	state.syllableGroups = syllableGroups
	if state.runtimePracticeReady {
		wordGroups, err := state.resolver.ResolveWordPracticeGroups(state.runtimePractice, state.mode)
		if err != nil {
			return err
		}
		state.wordGroups = wordGroups
		sentenceExercises, err := state.resolver.ResolveSentencePractice(state.runtimePractice, state.mode)
		if err != nil {
			return err
		}
		state.sentenceExercises = sentenceExercises
		candidateExercises, err := state.resolver.ResolveCandidatePractice(state.runtimePractice, state.mode)
		if err != nil {
			return err
		}
		state.candidateExercises = candidateExercises
	}
	state.groupCategories = state.resolver.KeymapGroupCategories()
	state.groupCategories = append(state.groupCategories, trainer.GroupCategory{ID: trainer.GroupCategoryFingering, Title: "指法专项"})
	if state.groupIndex < 0 || state.groupIndex >= len(state.keymapGroups) {
		state.groupIndex = 0
	}
	if state.syllableGroupIndex < 0 || state.syllableGroupIndex >= len(state.syllableGroups) {
		state.syllableGroupIndex = 0
	}
	if state.wordGroupIndex < 0 || state.wordGroupIndex >= len(state.wordGroups) {
		state.wordGroupIndex = 0
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
	state.applySelectedFont()
	state.applySelectedBackground()
	state.populateCombos()
	state.refreshExercise()
	state.resizeToContent()
	win32ui.PresentMainWindowAfterLaunch(state.mainHWND)

	var message winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		if message.Hwnd == state.ui.input && message.Message == wmKeyDown && message.WParam == vkReturn {
			state.submitAndAdvance()
			continue
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
	leftLabelStyle := int32(wsChild | wsVisible | ssLeftNoWordWrap | ssNoPrefix)
	centerLabelStyle := int32(wsChild | wsVisible | ssCenter | ssCenterImage | ssNoPrefix)
	state.ui.modeLabel = createControl("STATIC", "输入方案：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.modeCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idModeCombo)
	state.ui.sectionLabel = createControl("STATIC", "练习类型：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.sectionCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idSectionCombo)
	state.ui.fontLabel = createControl("STATIC", "字号：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.fontCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idFontCombo)
	state.ui.backgroundLabel = createControl("STATIC", "背景：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.backgroundCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idBackgroundCombo)
	state.ui.segmentLabel = createControl("STATIC", "音节分段：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.segmentCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idSegmentCombo)
	state.ui.reviewLabel = createControl("STATIC", "练习范围：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.reviewCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idReviewCombo)
	state.ui.categoryLabel = createControl("STATIC", "音元类别：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.categoryCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idCategoryCombo)
	state.ui.groupLabel = createControl("STATIC", "分组：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.groupCombo = createControl("COMBOBOX", "", wsChild|wsVisible|wsTabstop|cbsDropdownlist, 0, state.mainHWND, idGroupCombo)
	state.ui.progress = createControl("STATIC", "", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.instruction = createControl("STATIC", "", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.prompt = createControl("STATIC", "", centerLabelStyle, 0, state.mainHWND, 0)
	state.ui.detail = createControl("STATIC", "", wsChild|wsVisible|ssCenter|ssNoPrefix, 0, state.mainHWND, 0)
	state.ui.target = createControl("STATIC", "", centerLabelStyle, 0, state.mainHWND, 0)
	state.ui.inputLabel = createControl("STATIC", "请按目标键位输入，按 Enter 确认（此框已关闭输入法）：", leftLabelStyle, 0, state.mainHWND, 0)
	state.ui.input = createControl("EDIT", "", wsChild|wsVisible|wsTabstop|0x0080, wsExClientedge, state.mainHWND, idInputEdit)
	state.ui.next = createControl("BUTTON", "跳过", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idNextButton)
	state.ui.restart = createControl("BUTTON", "重新开始", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idRestart)
	state.ui.reveal = createControl("BUTTON", "显示答案", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idRevealButton)
	state.ui.play = createControl("BUTTON", "暂无音频", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idPlayButton)
	state.ui.report = createControl("BUTTON", "学习报告", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idReportButton)
	state.ui.clear = createControl("BUTTON", "清空记录", wsChild|wsVisible|wsTabstop, 0, state.mainHWND, idClearButton)
	state.ui.feedback = createControl("STATIC", "", centerLabelStyle, 0, state.mainHWND, 0)
	state.ui.score = createControl("STATIC", "", leftLabelStyle, 0, state.mainHWND, 0)
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
	selectedSection := 0
	for index, section := range state.lesson.Sections {
		addComboString(state.ui.sectionCombo, section.Title)
		if section.ID == state.preferences.LastSectionID {
			selectedSection = index
		}
	}
	state.sectionIndex = selectedSection
	procSendMessageW.Call(uintptr(state.ui.sectionCombo), cbSetcursel, uintptr(selectedSection), 0)
	for _, option := range []struct{ label, value string }{
		{"全部题目", trainer.ReviewAll}, {"只练错题", trainer.ReviewWrong}, {"今日复习", trainer.ReviewToday},
	} {
		addComboString(state.ui.reviewCombo, option.label)
		if option.value == state.reviewFilter {
			index := map[string]int{trainer.ReviewAll: 0, trainer.ReviewWrong: 1, trainer.ReviewToday: 2}[option.value]
			procSendMessageW.Call(uintptr(state.ui.reviewCombo), cbSetcursel, uintptr(index), 0)
		}
	}
	for index, option := range trainerFontOptions {
		addComboString(state.ui.fontCombo, option.label)
		if option.value == state.preferences.FontSize {
			procSendMessageW.Call(uintptr(state.ui.fontCombo), cbSetcursel, uintptr(index), 0)
		}
	}
	for index, option := range trainerBackgroundOptions {
		addComboString(state.ui.backgroundCombo, option.label)
		if option.value == state.preferences.Background {
			procSendMessageW.Call(uintptr(state.ui.backgroundCombo), cbSetcursel, uintptr(index), 0)
		}
	}
	state.rebuildExerciseFilters()
	state.prepareRound()
}

func (state *appState) selectedSectionIsKeymap() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionKeymap
}

func (state *appState) selectedSectionIsComposition() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionSyllableComposition
}

func (state *appState) selectedSectionIsSyllablePractice() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionSyllablePractice
}

func (state *appState) selectedSectionIsWordPractice() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionWordPractice
}

func (state *appState) selectedSectionIsSentencePractice() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionSentencePractice
}

func (state *appState) selectedSectionIsCandidatePractice() bool {
	return state.sectionIndex >= 0 && state.sectionIndex < len(state.lesson.Sections) &&
		state.lesson.Sections[state.sectionIndex].Type == trainer.SectionCandidatePractice
}

func (state *appState) currentBaseExercises() []trainer.Exercise {
	if state.selectedSectionIsWordPractice() {
		if state.wordGroupIndex < 0 || state.wordGroupIndex >= len(state.wordGroups) {
			return nil
		}
		return state.wordGroups[state.wordGroupIndex].Exercises
	}
	if state.selectedSectionIsSentencePractice() {
		return state.sentenceExercises
	}
	if state.selectedSectionIsCandidatePractice() {
		return state.candidateExercises
	}
	if state.selectedSectionIsSyllablePractice() {
		if state.syllableGroupIndex < 0 || state.syllableGroupIndex >= len(state.syllableGroups) {
			return nil
		}
		return state.syllableGroups[state.syllableGroupIndex].Exercises
	}
	if state.selectedSectionIsKeymap() {
		if state.groupIndex < 0 || state.groupIndex >= len(state.keymapGroups) {
			return nil
		}
		return state.keymapGroups[state.groupIndex].Exercises
	}
	if state.selectedSectionIsComposition() {
		if state.compositionSegmentIndex == 0 {
			if state.compositionShouyinGroupIndex < 0 || state.compositionShouyinGroupIndex >= len(state.shouyinGroups) {
				return nil
			}
			return state.shouyinGroups[state.compositionShouyinGroupIndex].Exercises
		}
		if state.compositionRhymeIndex < 0 || state.compositionRhymeIndex >= len(state.ganyinGroups) {
			return nil
		}
		toneGroups := state.ganyinGroups[state.compositionRhymeIndex].ToneGroups
		if state.compositionToneIndex < 0 || state.compositionToneIndex >= len(toneGroups) {
			return nil
		}
		return toneGroups[state.compositionToneIndex].Exercises
	}
	if state.sectionIndex < 0 || state.sectionIndex >= len(state.sectionExercises) {
		return nil
	}
	return state.sectionExercises[state.sectionIndex]
}

func (state *appState) currentExercises() []trainer.Exercise {
	if state.roundExercises != nil {
		return state.roundExercises
	}
	return state.currentBaseExercises()
}

func (state *appState) prepareRound() {
	state.roundExercises = trainer.ScheduleExercises(state.currentBaseExercises(), state.progressData, state.reviewFilter, time.Now())
}

func (state *appState) currentExercise() (trainer.Exercise, bool) {
	items := state.currentExercises()
	if state.itemIndex < 0 || state.itemIndex >= len(items) {
		return trainer.Exercise{}, false
	}
	return items[state.itemIndex], true
}

func (state *appState) refreshExercise() {
	exercise, ok := state.currentExercise()
	if !ok {
		setText(state.ui.progress, "当前练习范围：0 题")
		setText(state.ui.instruction, "")
		setText(state.ui.prompt, "当前范围没有可用题目")
		setText(state.ui.detail, "可切换到“全部题目”，或先完成一些练习后再选择错题／今日复习。")
		setText(state.ui.target, "目标编码：尚无题目")
		setText(state.ui.input, "")
		setText(state.ui.feedback, "")
		state.refreshScore()
		return
	}
	total := len(state.currentExercises())
	if state.selectedSectionIsKeymap() && state.groupIndex >= 0 && state.groupIndex < len(state.keymapGroups) {
		group := state.keymapGroups[state.groupIndex]
		setText(state.ui.progress, fmt.Sprintf("音元练习 · %s · %s    第 %d / %d 音",
			state.categoryTitle(group.Category), group.Title, state.itemIndex+1, total))
	} else if state.selectedSectionIsSyllablePractice() && state.syllableGroupIndex < len(state.syllableGroups) {
		group := state.syllableGroups[state.syllableGroupIndex]
		setText(state.ui.progress, fmt.Sprintf("编码练习 · %s    第 %d / %d 个音节",
			group.Title, state.itemIndex+1, total))
	} else if state.selectedSectionIsWordPractice() && state.wordGroupIndex < len(state.wordGroups) {
		group := state.wordGroups[state.wordGroupIndex]
		setText(state.ui.progress, fmt.Sprintf("字词练习 · %s    第 %d / %d 题", group.Title, state.itemIndex+1, total))
	} else if state.selectedSectionIsSentencePractice() {
		setText(state.ui.progress, fmt.Sprintf("短句练习    第 %d / %d 句", state.itemIndex+1, total))
	} else if state.selectedSectionIsCandidatePractice() {
		setText(state.ui.progress, fmt.Sprintf("候选实战 · 隔离模拟    第 %d / %d 题", state.itemIndex+1, total))
	} else if state.selectedSectionIsComposition() {
		if state.compositionSegmentIndex == 0 && state.compositionShouyinGroupIndex < len(state.shouyinGroups) {
			group := state.shouyinGroups[state.compositionShouyinGroupIndex]
			setText(state.ui.progress, fmt.Sprintf("分段练习 · 首音 · %s    第 %d / %d 音", group.Title, state.itemIndex+1, total))
		} else if state.compositionRhymeIndex < len(state.ganyinGroups) {
			rhyme := state.ganyinGroups[state.compositionRhymeIndex]
			tone := rhyme.ToneGroups[state.compositionToneIndex]
			setText(state.ui.progress, fmt.Sprintf("分段练习 · 干音 · %s · %s    第 %d / %d 个",
				rhyme.Title, tone.Title, state.itemIndex+1, total))
		}
	} else {
		setText(state.ui.progress, fmt.Sprintf("%s    第 %d / %d 题", state.lesson.Title, state.itemIndex+1, total))
	}
	setText(state.ui.instruction, exercise.Instruction)
	setText(state.ui.prompt, exercise.Prompt)
	setText(state.ui.detail, exercise.Detail)
	state.answerRevealed = state.defaultAnswerVisible(exercise.SectionType)
	if state.answerRevealed {
		setText(state.ui.target, exercise.AnswerLabel+"："+exercise.Expected)
		setText(state.ui.reveal, "隐藏答案")
	} else {
		setText(state.ui.target, exercise.AnswerLabel+"：尚未显示")
		setText(state.ui.reveal, "显示答案")
	}
	if exercise.AudioPath != "" {
		setText(state.ui.play, "播放音频")
		procEnableWindow.Call(uintptr(state.ui.play), 1)
	} else {
		setText(state.ui.play, "暂无音频")
		procEnableWindow.Call(uintptr(state.ui.play), 0)
	}
	setText(state.ui.input, "")
	setText(state.ui.feedback, "")
	state.itemStarted = time.Now()
	state.refreshScore()
	procSetFocus.Call(uintptr(state.ui.input))
}

func (state *appState) refreshScore() {
	accuracy := float64(0)
	if state.attempted > 0 {
		accuracy = float64(state.correct) / float64(state.attempted) * 100
	}
	status := trainer.RecommendedStage(trainer.EvaluateCurriculum(state.progressData, state.resolver.Curriculum()))
	setText(state.ui.score, fmt.Sprintf("本轮：已答 %d，正确 %d，正确率 %.1f%%    建议阶段：%s（%d/%d）",
		state.attempted, state.correct, accuracy, status.Stage.Title, status.Attempts, status.Stage.RequiredAnswers))
}

func defaultAnswerVisible(sectionType string) bool {
	return sectionType == trainer.SectionKeymap || sectionType == trainer.SectionSyllableComposition
}

func (state *appState) defaultAnswerVisible(sectionType string) bool {
	for _, stage := range state.resolver.Curriculum() {
		for _, declared := range stage.SectionTypes {
			if declared == sectionType {
				return stage.AnswerVisible
			}
		}
	}
	return defaultAnswerVisible(sectionType)
}

func submissionTransition(input, expected string, index, total int) (accepted, correct bool, next int, wrapped bool) {
	if strings.TrimSpace(input) == "" || total <= 0 {
		return false, false, index, false
	}
	next = (index + 1) % total
	return true, trainer.Evaluate(input, expected), next, next == 0
}

func (state *appState) submitAndAdvance() {
	exercise, ok := state.currentExercise()
	if !ok {
		return
	}
	input := getText(state.ui.input)
	accepted, correct, next, wrapped := submissionTransition(input, exercise.Expected, state.itemIndex, len(state.currentExercises()))
	if !accepted {
		setText(state.ui.feedback, "请先输入目标键位。")
		procSetFocus.Call(uintptr(state.ui.input))
		return
	}
	state.attempted++
	diagnosis := trainer.Diagnose(exercise, input)
	state.progressData.Record(exercise, diagnosis, time.Since(state.itemStarted), time.Now())
	saveErr := trainer.SaveProgress(state.preferencesDir, state.progressData)
	message := "上一题：" + diagnosis.Summary()
	if correct {
		state.correct++
		message = "上一题：正确。"
		state.lastDiagnosis = trainer.Diagnosis{}
		state.hintLevel = 0
	} else {
		state.lastDiagnosis = diagnosis
		state.hintLevel = 0
	}
	if wrapped {
		message = "本组完成一轮；" + message
	}
	state.itemIndex = next
	state.refreshExercise()
	if !correct {
		setText(state.ui.reveal, "错误提示 1/3")
	}
	if saveErr != nil {
		message += fmt.Sprintf(" 练习记录保存失败：%v。", saveErr)
	}
	setText(state.ui.feedback, message)
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
	if !state.lastDiagnosis.Correct && state.lastDiagnosis.ErrorCount > 0 && state.hintLevel < 3 {
		state.hintLevel++
		setText(state.ui.feedback, "上一题提示："+state.lastDiagnosis.Hint(state.hintLevel))
		if state.hintLevel < 3 {
			setText(state.ui.reveal, "继续提示")
		} else {
			setText(state.ui.reveal, "显示本题答案")
		}
		return
	}
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
	items := state.currentExercises()
	if len(items) == 0 {
		return
	}
	state.itemIndex = (state.itemIndex + 1) % len(items)
	state.lastDiagnosis = trainer.Diagnosis{}
	state.hintLevel = 0
	state.refreshExercise()
}

func (state *appState) restartRound() {
	state.prepareRound()
	state.itemIndex = 0
	state.attempted = 0
	state.correct = 0
	state.lastDiagnosis = trainer.Diagnosis{}
	state.hintLevel = 0
	state.refreshExercise()
}

func (state *appState) selectMode() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.modeCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(state.modeOptions) {
		return
	}
	state.mode = state.modeOptions[index].value
	state.preferences.LastMode = string(state.mode)
	state.savePreferences()
	if err := state.resolveExercises(); err != nil {
		showError(err.Error())
		return
	}
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) selectSection() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.sectionCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(state.sectionExercises) {
		return
	}
	state.sectionIndex = int(index)
	state.preferences.LastSectionID = state.lesson.Sections[state.sectionIndex].ID
	state.savePreferences()
	state.rebuildExerciseFilters()
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) selectReviewFilter() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.reviewCombo), cbGetcursel, 0, 0)
	filters := []string{trainer.ReviewAll, trainer.ReviewWrong, trainer.ReviewToday}
	if int(index) < 0 || int(index) >= len(filters) {
		return
	}
	state.reviewFilter = filters[index]
	state.preferences.ReviewFilter = state.reviewFilter
	state.savePreferences()
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) showLearningReport() {
	report := trainer.BuildLearningReport(state.progressData)
	readiness := state.resolver.ContentReadiness()
	statuses := trainer.EvaluateCurriculum(state.progressData, state.resolver.Curriculum())
	lines := []string{report.Text(), fmt.Sprintf("内容：%d 个音元指法已覆盖 %d；正式音节 %d；可用音频 %d/%d（音频仍为可选资源）。",
		readiness.YinyuanTotal, readiness.FingeringCovered, readiness.EncodedSyllables, readiness.AudioAvailable, readiness.YinyuanTotal), "", "阶段进度："}
	for _, status := range statuses {
		mark := "未解锁"
		if status.Completed {
			mark = "已完成"
		} else if status.Unlocked {
			mark = "进行中"
		}
		lines = append(lines, fmt.Sprintf("%s：%s，%d/%d，正确率 %.1f%%", status.Stage.Title, mark, status.Attempts, status.Stage.RequiredAnswers, status.Accuracy*100))
	}
	if details := report.DetailLines(); len(details) > 0 {
		lines = append(lines, "", "分项统计：")
		lines = append(lines, details...)
	}
	if path, err := trainer.ExportLearningReport(state.preferencesDir, state.progressData); err != nil {
		lines = append(lines, "", "报告导出失败："+err.Error())
	} else if path != "" {
		lines = append(lines, "", "本地报告已导出："+path)
	}
	message, _ := syscall.UTF16PtrFromString(strings.Join(lines, "\r\n"))
	title, _ := syscall.UTF16PtrFromString("Yime 学习报告")
	procMessageBoxW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x00000040)
}

func (state *appState) clearLearningProgress() {
	message, _ := syscall.UTF16PtrFromString("只删除练习器自己的学习记录，不会触碰 Rime 用户词典、正式学习记录或屏蔽词表。确定清空吗？")
	title, _ := syscall.UTF16PtrFromString("清空练习记录")
	result, _, _ := procMessageBoxW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x00000004|0x00000030)
	if result != 6 { // IDYES
		return
	}
	if err := trainer.ClearProgress(state.preferencesDir); err != nil {
		setText(state.ui.feedback, "清空练习记录失败："+err.Error())
		return
	}
	state.progressData = trainer.NewProgress()
	state.restartRound()
	setText(state.ui.feedback, "练习记录已清空；PIME/Rime 正式数据未改动。")
}

func (state *appState) categoryTitle(id string) string {
	for _, category := range state.groupCategories {
		if category.ID == id {
			return category.Title
		}
	}
	return id
}

func resetCombo(hwnd syscall.Handle) {
	procSendMessageW.Call(uintptr(hwnd), cbResetcontent, 0, 0)
}

func (state *appState) rebuildExerciseFilters() {
	resetCombo(state.ui.segmentCombo)
	resetCombo(state.ui.categoryCombo)
	resetCombo(state.ui.groupCombo)
	if state.selectedSectionIsKeymap() {
		setText(state.ui.categoryLabel, "音元类别：")
		setText(state.ui.groupLabel, "分组：")
		for _, category := range state.groupCategories {
			addComboString(state.ui.categoryCombo, category.Title)
		}
		procSendMessageW.Call(uintptr(state.ui.categoryCombo), cbSetcursel, uintptr(state.categoryIndex), 0)
		state.rebuildKeymapGroupCombo()
		return
	}
	if state.selectedSectionIsSyllablePractice() {
		setText(state.ui.categoryLabel, "首音：")
		for _, group := range state.syllableGroups {
			addComboString(state.ui.categoryCombo, group.Title)
		}
		procSendMessageW.Call(uintptr(state.ui.categoryCombo), cbSetcursel, uintptr(state.syllableGroupIndex), 0)
		return
	}
	if state.selectedSectionIsWordPractice() {
		setText(state.ui.categoryLabel, "音节数：")
		for _, group := range state.wordGroups {
			addComboString(state.ui.categoryCombo, group.Title)
		}
		procSendMessageW.Call(uintptr(state.ui.categoryCombo), cbSetcursel, uintptr(state.wordGroupIndex), 0)
		return
	}
	if !state.selectedSectionIsComposition() {
		return
	}
	for _, title := range []string{"首音", "干音"} {
		addComboString(state.ui.segmentCombo, title)
	}
	procSendMessageW.Call(uintptr(state.ui.segmentCombo), cbSetcursel, uintptr(state.compositionSegmentIndex), 0)
	if state.compositionSegmentIndex == 0 {
		setText(state.ui.groupLabel, "首音分组：")
		for _, group := range state.shouyinGroups {
			addComboString(state.ui.groupCombo, group.Title)
		}
		procSendMessageW.Call(uintptr(state.ui.groupCombo), cbSetcursel, uintptr(state.compositionShouyinGroupIndex), 0)
		return
	}
	setText(state.ui.categoryLabel, "韵音类别：")
	setText(state.ui.groupLabel, "干音调型：")
	for _, group := range state.ganyinGroups {
		addComboString(state.ui.categoryCombo, group.Title)
	}
	procSendMessageW.Call(uintptr(state.ui.categoryCombo), cbSetcursel, uintptr(state.compositionRhymeIndex), 0)
	state.rebuildGanyinToneCombo()
}

func (state *appState) rebuildKeymapGroupCombo() {
	procSendMessageW.Call(uintptr(state.ui.groupCombo), cbResetcontent, 0, 0)
	state.visibleGroupIDs = state.visibleGroupIDs[:0]
	if state.categoryIndex < 0 || state.categoryIndex >= len(state.groupCategories) {
		state.groupIndex = -1
		return
	}
	categoryID := state.groupCategories[state.categoryIndex].ID
	for index, group := range state.keymapGroups {
		if group.Category != categoryID {
			continue
		}
		state.visibleGroupIDs = append(state.visibleGroupIDs, index)
		addComboString(state.ui.groupCombo, group.Title)
	}
	if len(state.visibleGroupIDs) > 0 {
		state.groupIndex = state.visibleGroupIDs[0]
		procSendMessageW.Call(uintptr(state.ui.groupCombo), cbSetcursel, 0, 0)
	}
}

func (state *appState) rebuildGanyinToneCombo() {
	resetCombo(state.ui.groupCombo)
	if state.compositionRhymeIndex < 0 || state.compositionRhymeIndex >= len(state.ganyinGroups) {
		state.compositionToneIndex = -1
		return
	}
	toneGroups := state.ganyinGroups[state.compositionRhymeIndex].ToneGroups
	for _, tone := range toneGroups {
		addComboString(state.ui.groupCombo, tone.Title)
	}
	if len(toneGroups) > 0 {
		state.compositionToneIndex = 0
		procSendMessageW.Call(uintptr(state.ui.groupCombo), cbSetcursel, 0, 0)
	}
}

func (state *appState) selectCategory() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.categoryCombo), cbGetcursel, 0, 0)
	if state.selectedSectionIsSyllablePractice() {
		if int(index) < 0 || int(index) >= len(state.syllableGroups) {
			return
		}
		state.syllableGroupIndex = int(index)
	} else if state.selectedSectionIsWordPractice() {
		if int(index) < 0 || int(index) >= len(state.wordGroups) {
			return
		}
		state.wordGroupIndex = int(index)
	} else if state.selectedSectionIsComposition() && state.compositionSegmentIndex == 1 {
		if int(index) < 0 || int(index) >= len(state.ganyinGroups) {
			return
		}
		state.compositionRhymeIndex = int(index)
		state.rebuildGanyinToneCombo()
	} else {
		if int(index) < 0 || int(index) >= len(state.groupCategories) {
			return
		}
		state.categoryIndex = int(index)
		state.rebuildKeymapGroupCombo()
	}
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) selectGroup() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.groupCombo), cbGetcursel, 0, 0)
	if state.selectedSectionIsComposition() {
		if state.compositionSegmentIndex == 0 {
			if int(index) < 0 || int(index) >= len(state.shouyinGroups) {
				return
			}
			state.compositionShouyinGroupIndex = int(index)
		} else {
			toneGroups := state.ganyinGroups[state.compositionRhymeIndex].ToneGroups
			if int(index) < 0 || int(index) >= len(toneGroups) {
				return
			}
			state.compositionToneIndex = int(index)
		}
	} else {
		if int(index) < 0 || int(index) >= len(state.visibleGroupIDs) {
			return
		}
		state.groupIndex = state.visibleGroupIDs[index]
	}
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) selectSegment() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.segmentCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) > 1 {
		return
	}
	state.compositionSegmentIndex = int(index)
	state.rebuildExerciseFilters()
	state.restartRound()
	state.resizeToContent()
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0005: // WM_SIZE
		state.layoutControls(int32(lParam&0xffff), int32((lParam>>16)&0xffff))
		return 0
	case 0x0111: // WM_COMMAND
		id := int(wParam & 0xffff)
		notify := int((wParam >> 16) & 0xffff)
		switch {
		case id == idModeCombo && notify == cbSelchange:
			state.selectMode()
		case id == idSectionCombo && notify == cbSelchange:
			state.selectSection()
		case id == idFontCombo && notify == cbSelchange:
			state.selectFontSize()
		case id == idBackgroundCombo && notify == cbSelchange:
			state.selectBackground()
		case id == idSegmentCombo && notify == cbSelchange:
			state.selectSegment()
		case id == idReviewCombo && notify == cbSelchange:
			state.selectReviewFilter()
		case id == idCategoryCombo && notify == cbSelchange:
			state.selectCategory()
		case id == idGroupCombo && notify == cbSelchange:
			state.selectGroup()
		case id == idNextButton && notify == bnClicked:
			state.nextExercise()
		case id == idRestart && notify == bnClicked:
			state.restartRound()
		case id == idRevealButton && notify == bnClicked:
			state.toggleAnswer()
		case id == idPlayButton && notify == bnClicked:
			state.playAudio()
		case id == idReportButton && notify == bnClicked:
			state.showLearningReport()
		case id == idClearButton && notify == bnClicked:
			state.clearLearningProgress()
		}
		return 0
	case wmEraseBkgnd:
		if result := state.paintBackground(wParam); result != 0 {
			return result
		}
	case wmCtlColorStatic, wmCtlColorBtn, wmCtlColorEdit:
		if result := state.colorControl(wParam); result != 0 {
			return result
		}
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
		state.releaseDisplayResources()
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
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
