//go:build windows

package main

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/trainer"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wmSetFont        = 0x0030
	wmEraseBkgnd     = 0x0014
	wmCtlColorEdit   = 0x0133
	wmCtlColorBtn    = 0x0135
	wmCtlColorStatic = 0x0138

	ssCenter          = 0x00000001
	ssCenterImage     = 0x00000200
	ssLeftNoWordWrap  = 0x0000000C
	ssNoPrefix        = 0x00000080
	swpNoZOrder       = 0x0004
	swpNoActivate     = 0x0010
	fontNormalWeight  = 400
	defaultCharset    = 1
	clearTypeQuality  = 5
	minimumInputWidth = 260
)

var (
	modgdi32 = syscall.NewLazyDLL("gdi32.dll")

	procCreateFontW           = modgdi32.NewProc("CreateFontW")
	procCreateSolidBrush      = modgdi32.NewProc("CreateSolidBrush")
	procDeleteObject          = modgdi32.NewProc("DeleteObject")
	procFillRect              = moduser32.NewProc("FillRect")
	procGetClientRect         = moduser32.NewProc("GetClientRect")
	procGetDC                 = moduser32.NewProc("GetDC")
	procGetDpiForWindow       = moduser32.NewProc("GetDpiForWindow")
	procGetTextExtentPoint32W = modgdi32.NewProc("GetTextExtentPoint32W")
	procInvalidateRect        = moduser32.NewProc("InvalidateRect")
	procReleaseDC             = moduser32.NewProc("ReleaseDC")
	procSelectObject          = modgdi32.NewProc("SelectObject")
	procSetBkColor            = modgdi32.NewProc("SetBkColor")
	procSetTextColor          = modgdi32.NewProc("SetTextColor")
	procSetWindowPos          = moduser32.NewProc("SetWindowPos")
	procShowWindow            = moduser32.NewProc("ShowWindow")
)

type fontOption struct {
	label string
	value string
	point int32
}

type backgroundOption struct {
	label string
	value string
	color uint32
}

var trainerFontOptions = []fontOption{
	{label: "常规", value: trainer.FontSizeNormal, point: 10},
	{label: "中等", value: trainer.FontSizeMedium, point: 12},
	{label: "大号", value: trainer.FontSizeLarge, point: 15},
	{label: "特大", value: trainer.FontSizeXLarge, point: 18},
}

var trainerBackgroundOptions = []backgroundOption{
	{label: "柔和灰", value: trainer.BackgroundSoftGray, color: rgb(232, 232, 228)},
	{label: "暖米色", value: trainer.BackgroundWarmBeige, color: rgb(235, 226, 207)},
	{label: "灰蓝", value: trainer.BackgroundGrayBlue, color: rgb(216, 225, 232)},
}

type selectorMetrics struct {
	labelWidth int32
	comboWidth int32
}

type layoutMetrics struct {
	lineHeight       int32
	detailLines      int32
	contentTextWidth int32
	inputLabelWidth  int32
	inputWidth       int32
	mode             selectorMetrics
	section          selectorMetrics
	font             selectorMetrics
	background       selectorMetrics
	review           selectorMetrics
	segment          selectorMetrics
	category         selectorMetrics
	group            selectorMetrics
	showSegment      bool
	showCategory     bool
	showGroup        bool
	nextWidth        int32
	restartWidth     int32
	revealWidth      int32
	playWidth        int32
	reportWidth      int32
	clearWidth       int32
}

type trainerLayout struct {
	clientWidth, clientHeight                     int32
	comboVisibleHeight                            int32
	modeLabel, modeCombo                          rect
	sectionLabel, sectionCombo                    rect
	fontLabel, fontCombo                          rect
	backgroundLabel, backgroundCombo              rect
	reviewLabel, reviewCombo                      rect
	segmentLabel, segmentCombo                    rect
	categoryLabel, categoryCombo                  rect
	groupLabel, groupCombo                        rect
	progress, instruction, prompt, detail, target rect
	inputLabel, input, next, restart              rect
	play, reveal, report, clear, feedback, score  rect
	showSegment, showCategory, showGroup          bool
}

type textSize struct {
	Width  int32
	Height int32
}

func rgb(red, green, blue byte) uint32 {
	return uint32(red) | uint32(green)<<8 | uint32(blue)<<16
}

func max32(values ...int32) int32 {
	var result int32
	for _, value := range values {
		if value > result {
			result = value
		}
	}
	return result
}

func calculateTrainerLayout(metrics layoutMetrics) trainerLayout {
	lineHeight := max32(metrics.lineHeight, 20)
	margin := max32(18, lineHeight)
	gap := max32(10, lineHeight/2)
	groupGap := gap * 2
	controlHeight := lineHeight + 12
	comboVisibleHeight := controlHeight

	topWidth := metrics.mode.labelWidth + gap + metrics.mode.comboWidth + groupGap +
		metrics.section.labelWidth + gap + metrics.section.comboWidth + groupGap +
		metrics.font.labelWidth + gap + metrics.font.comboWidth + groupGap +
		metrics.background.labelWidth + gap + metrics.background.comboWidth
	filterWidth := int32(0)
	addFilterWidth := func(show bool, selector selectorMetrics) {
		if !show {
			return
		}
		if filterWidth > 0 {
			filterWidth += groupGap
		}
		filterWidth += selector.labelWidth + gap + selector.comboWidth
	}
	addFilterWidth(metrics.showSegment, metrics.segment)
	addFilterWidth(true, metrics.review)
	addFilterWidth(metrics.showCategory, metrics.category)
	addFilterWidth(metrics.showGroup, metrics.group)
	inputRowWidth := metrics.inputWidth + gap + metrics.nextWidth + gap + metrics.restartWidth
	secondaryWidth := metrics.playWidth + gap + metrics.revealWidth + gap + metrics.reportWidth + gap + metrics.clearWidth
	contentWidth := max32(topWidth, filterWidth, metrics.contentTextWidth, metrics.inputLabelWidth,
		inputRowWidth, secondaryWidth, 720)

	layout := trainerLayout{
		clientWidth:        margin*2 + contentWidth,
		comboVisibleHeight: comboVisibleHeight,
		showSegment:        metrics.showSegment,
		showCategory:       metrics.showCategory,
		showGroup:          metrics.showGroup,
	}
	top := margin
	x := margin
	labelTop := top + (controlHeight-lineHeight)/2
	comboDropHeight := controlHeight + 180
	placeSelector := func(metrics selectorMetrics, label *rect, combo *rect) {
		*label = rect{x, labelTop, x + metrics.labelWidth, labelTop + lineHeight}
		x += metrics.labelWidth + gap
		*combo = rect{x, top, x + metrics.comboWidth, top + comboDropHeight}
		x += metrics.comboWidth + groupGap
	}
	placeSelector(metrics.mode, &layout.modeLabel, &layout.modeCombo)
	placeSelector(metrics.section, &layout.sectionLabel, &layout.sectionCombo)
	placeSelector(metrics.font, &layout.fontLabel, &layout.fontCombo)
	placeSelector(metrics.background, &layout.backgroundLabel, &layout.backgroundCombo)

	row := top + controlHeight + gap
	top = row
	x = margin
	labelTop = top + (controlHeight-lineHeight)/2
	placeSelector(metrics.review, &layout.reviewLabel, &layout.reviewCombo)
	if metrics.showSegment {
		placeSelector(metrics.segment, &layout.segmentLabel, &layout.segmentCombo)
	}
	if metrics.showCategory {
		placeSelector(metrics.category, &layout.categoryLabel, &layout.categoryCombo)
	}
	if metrics.showGroup {
		placeSelector(metrics.group, &layout.groupLabel, &layout.groupCombo)
	}
	row += controlHeight + gap
	fullRow := func(height int32) rect {
		box := rect{margin, row, margin + contentWidth, row + height}
		row += height + gap
		return box
	}
	layout.progress = fullRow(lineHeight)
	layout.instruction = fullRow(lineHeight)
	layout.prompt = fullRow(lineHeight + 8)
	detailLines := max32(metrics.detailLines, 1)
	layout.detail = fullRow(detailLines*lineHeight + 8)
	layout.target = fullRow(lineHeight + 8)
	layout.inputLabel = fullRow(lineHeight)

	layout.input = rect{margin, row, margin + metrics.inputWidth, row + controlHeight}
	x = layout.input.Right + gap
	layout.next = rect{x, row, x + metrics.nextWidth, row + controlHeight}
	x = layout.next.Right + gap
	layout.restart = rect{x, row, x + metrics.restartWidth, row + controlHeight}
	row += controlHeight + gap

	layout.play = rect{margin, row, margin + metrics.playWidth, row + controlHeight}
	layout.reveal = rect{layout.play.Right + gap, row, layout.play.Right + gap + metrics.revealWidth, row + controlHeight}
	layout.report = rect{layout.reveal.Right + gap, row, layout.reveal.Right + gap + metrics.reportWidth, row + controlHeight}
	layout.clear = rect{layout.report.Right + gap, row, layout.report.Right + gap + metrics.clearWidth, row + controlHeight}
	row += controlHeight + gap
	layout.feedback = fullRow(lineHeight + 8)
	layout.score = fullRow(lineHeight)
	layout.clientHeight = row - gap + margin
	return layout
}

func (state *appState) selectedFontOption() fontOption {
	for _, option := range trainerFontOptions {
		if option.value == state.preferences.FontSize {
			return option
		}
	}
	return trainerFontOptions[1]
}

func (state *appState) selectedBackgroundOption() backgroundOption {
	for _, option := range trainerBackgroundOptions {
		if option.value == state.preferences.Background {
			return option
		}
	}
	return trainerBackgroundOptions[0]
}

func (state *appState) dpi() int32 {
	if procGetDpiForWindow.Find() == nil {
		value, _, _ := procGetDpiForWindow.Call(uintptr(state.mainHWND))
		if value >= 96 {
			return int32(value)
		}
	}
	return 96
}

func (state *appState) applySelectedFont() {
	option := state.selectedFontOption()
	pixelHeight := (option.point*state.dpi() + 36) / 72
	face, _ := syscall.UTF16PtrFromString("Microsoft YaHei UI")
	font, _, _ := procCreateFontW.Call(
		uintptr(-pixelHeight), 0, 0, 0, fontNormalWeight,
		0, 0, 0, defaultCharset, 0, 0, clearTypeQuality, 0,
		uintptr(unsafe.Pointer(face)),
	)
	if font == 0 {
		return
	}
	for _, control := range state.ui.all() {
		if control != 0 {
			procSendMessageW.Call(uintptr(control), wmSetFont, font, 1)
		}
	}
	old := state.displayFont
	state.displayFont = syscall.Handle(font)
	state.lineHeight = pixelHeight + max32(6, pixelHeight/3)
	if old != 0 {
		procDeleteObject.Call(uintptr(old))
	}
}

func (state *appState) applySelectedBackground() {
	option := state.selectedBackgroundOption()
	brush, _, _ := procCreateSolidBrush.Call(uintptr(option.color))
	if brush == 0 {
		return
	}
	old := state.backgroundBrush
	state.backgroundBrush = syscall.Handle(brush)
	state.backgroundColor = option.color
	if old != 0 {
		procDeleteObject.Call(uintptr(old))
	}
	procInvalidateRect.Call(uintptr(state.mainHWND), 0, 1)
	win32ui.RedrawChildrenNow(state.mainHWND)
}

func (state *appState) measureText(value string) int32 {
	dc, _, _ := procGetDC.Call(uintptr(state.mainHWND))
	if dc == 0 {
		return int32(len([]rune(value))) * max32(state.lineHeight/2, 8)
	}
	defer procReleaseDC.Call(uintptr(state.mainHWND), dc)
	old, _, _ := procSelectObject.Call(dc, uintptr(state.displayFont))
	if old != 0 {
		defer procSelectObject.Call(dc, old)
	}
	var widest int32
	for _, line := range splitDisplayLines(value) {
		encoded, _ := syscall.UTF16FromString(line)
		if len(encoded) <= 1 {
			continue
		}
		var size textSize
		ret, _, _ := procGetTextExtentPoint32W.Call(
			dc, uintptr(unsafe.Pointer(&encoded[0])), uintptr(len(encoded)-1), uintptr(unsafe.Pointer(&size)),
		)
		if ret != 0 && size.Width > widest {
			widest = size.Width
		}
	}
	return widest
}

func splitDisplayLines(value string) []string {
	value = strings.ReplaceAll(value, "\r\n", "\n")
	value = strings.ReplaceAll(value, "\r", "\n")
	return strings.Split(value, "\n")
}

func (state *appState) measureLayout() layoutMetrics {
	measureOption := func(label string, values []string, minimum int32) selectorMetrics {
		comboWidth := minimum
		for _, value := range values {
			comboWidth = max32(comboWidth, state.measureText(value)+42)
		}
		return selectorMetrics{labelWidth: state.measureText(label) + 6, comboWidth: comboWidth}
	}
	modeLabels := make([]string, 0, len(state.modeOptions))
	for _, option := range state.modeOptions {
		modeLabels = append(modeLabels, option.label)
	}
	sectionLabels := make([]string, 0, len(state.lesson.Sections))
	for _, section := range state.lesson.Sections {
		sectionLabels = append(sectionLabels, section.Title)
	}
	fontLabels := make([]string, 0, len(trainerFontOptions))
	for _, option := range trainerFontOptions {
		fontLabels = append(fontLabels, option.label)
	}
	backgroundLabels := make([]string, 0, len(trainerBackgroundOptions))
	for _, option := range trainerBackgroundOptions {
		backgroundLabels = append(backgroundLabels, option.label)
	}
	categoryLabels := make([]string, 0, len(state.groupCategories))
	for _, category := range state.groupCategories {
		categoryLabels = append(categoryLabels, category.Title)
	}
	groupLabels := make([]string, 0, len(state.keymapGroups))
	for _, group := range state.keymapGroups {
		groupLabels = append(groupLabels, group.Title)
	}
	for _, group := range state.ganyinGroups {
		categoryLabels = append(categoryLabels, group.Title)
		for _, tone := range group.ToneGroups {
			groupLabels = append(groupLabels, tone.Title)
		}
	}
	for _, group := range state.syllableGroups {
		categoryLabels = append(categoryLabels, group.Title)
	}
	for _, group := range state.wordGroups {
		categoryLabels = append(categoryLabels, group.Title)
	}

	stringsToMeasure := []string{
		state.lesson.Title,
		"请按目标键位输入，按 Enter 确认（此框已关闭输入法）：",
		"请先输入目标键位。",
		"本组完成一轮；上一音：不对，目标键位是 Shift+Space。",
		"音频播放失败，请检查课程音频文件。",
		"本轮：已答 9999，正确 9999，正确率 100.0%",
		"无法保存显示设置；本次显示仍然有效。",
		"上一题提示：错误音元：主音 M01 高调[i]乐音，目标键 J。",
		"练习记录已清空；PIME/Rime 正式数据未改动。",
	}
	detailLines := int32(1)
	longestExpected := int32(minimumInputWidth)
	for _, exercises := range state.sectionExercises {
		for _, exercise := range exercises {
			stringsToMeasure = append(stringsToMeasure,
				exercise.Instruction, exercise.Prompt, exercise.Detail,
				exercise.AnswerLabel+"：尚未显示",
				exercise.AnswerLabel+"："+exercise.Expected,
			)
			detailLines = max32(detailLines, int32(len(splitDisplayLines(exercise.Detail))))
			longestExpected = max32(longestExpected, state.measureText(exercise.Expected)+32)
		}
	}
	for _, group := range state.keymapGroups {
		for _, exercise := range group.Exercises {
			stringsToMeasure = append(stringsToMeasure,
				exercise.Instruction, exercise.Prompt, exercise.Detail,
				exercise.AnswerLabel+"：尚未显示",
				exercise.AnswerLabel+"："+exercise.Expected,
			)
			detailLines = max32(detailLines, int32(len(splitDisplayLines(exercise.Detail))))
			longestExpected = max32(longestExpected, state.measureText(exercise.Expected)+32)
		}
	}
	for _, group := range state.ganyinGroups {
		for _, tone := range group.ToneGroups {
			for _, exercise := range tone.Exercises {
				stringsToMeasure = append(stringsToMeasure,
					exercise.Instruction, exercise.Prompt, exercise.Detail,
					exercise.AnswerLabel+"：尚未显示",
					exercise.AnswerLabel+"："+exercise.Expected,
				)
				detailLines = max32(detailLines, int32(len(splitDisplayLines(exercise.Detail))))
				longestExpected = max32(longestExpected, state.measureText(exercise.Expected)+32)
			}
		}
	}
	if state.selectedSectionIsSyllablePractice() || state.selectedSectionIsWordPractice() || state.selectedSectionIsSentencePractice() || state.selectedSectionIsCandidatePractice() {
		for _, exercise := range state.currentExercises() {
			stringsToMeasure = append(stringsToMeasure,
				exercise.Instruction, exercise.Prompt, exercise.Detail,
				exercise.AnswerLabel+"：尚未显示",
				exercise.AnswerLabel+"："+exercise.Expected,
			)
			detailLines = max32(detailLines, int32(len(splitDisplayLines(exercise.Detail))))
			longestExpected = max32(longestExpected, state.measureText(exercise.Expected)+32)
		}
	}
	contentWidth := int32(0)
	for _, value := range stringsToMeasure {
		contentWidth = max32(contentWidth, state.measureText(value)+12)
	}
	buttonWidth := func(label string) int32 {
		return max32(88, state.measureText(label)+32)
	}
	return layoutMetrics{
		lineHeight:       state.lineHeight,
		detailLines:      detailLines,
		contentTextWidth: contentWidth,
		inputLabelWidth:  state.measureText("请按目标键位输入，按 Enter 确认（此框已关闭输入法）：") + 6,
		inputWidth:       longestExpected,
		mode:             measureOption("输入方案：", modeLabels, 104),
		section:          measureOption("练习类型：", sectionLabels, 150),
		font:             measureOption("字号：", fontLabels, 96),
		background:       measureOption("背景：", backgroundLabels, 112),
		review:           measureOption("练习范围：", []string{"全部题目", "只练错题", "今日复习"}, 120),
		segment:          measureOption("音节分段：", []string{"首音", "干音"}, 112),
		category:         measureOption("韵音类别：", categoryLabels, 128),
		group:            measureOption("干音调型：", groupLabels, 150),
		showSegment:      state.selectedSectionIsComposition(),
		showCategory:     state.selectedSectionIsKeymap() || state.selectedSectionIsSyllablePractice() || state.selectedSectionIsWordPractice() || (state.selectedSectionIsComposition() && state.compositionSegmentIndex == 1),
		showGroup:        state.selectedSectionIsKeymap() || state.selectedSectionIsComposition(),
		nextWidth:        buttonWidth("跳过"),
		restartWidth:     buttonWidth("重新开始"),
		revealWidth:      buttonWidth("显示答案"),
		playWidth:        max32(buttonWidth("播放音频"), buttonWidth("暂无音频")),
		reportWidth:      buttonWidth("学习报告"),
		clearWidth:       buttonWidth("清空记录"),
	}
}

func (state *appState) resizeToContent() {
	if state.mainHWND == 0 || state.ui.modeLabel == 0 || state.displayFont == 0 {
		return
	}
	state.minimumLayout = calculateTrainerLayout(state.measureLayout())
	windowWidth, windowHeight := windowSizeForClient(state.minimumLayout.clientWidth, state.minimumLayout.clientHeight)
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	x := (int32(screenWidth) - windowWidth) / 2
	y := (int32(screenHeight) - windowHeight) / 2
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	procSetWindowPos.Call(
		uintptr(state.mainHWND), 0, uintptr(x), uintptr(y),
		uintptr(windowWidth), uintptr(windowHeight), swpNoZOrder|swpNoActivate,
	)
	state.layoutControls(state.minimumLayout.clientWidth, state.minimumLayout.clientHeight)
}

func offsetRight(box rect, delta int32) rect {
	box.Right += delta
	return box
}

func shiftHorizontal(box rect, delta int32) rect {
	box.Left += delta
	box.Right += delta
	return box
}

func (state *appState) layoutControls(clientWidth, clientHeight int32) {
	layout := state.minimumLayout
	if layout.clientWidth == 0 {
		return
	}
	deltaWidth := max32(0, clientWidth-layout.clientWidth)
	deltaHeight := max32(0, clientHeight-layout.clientHeight)
	move(state.ui.modeLabel, layout.modeLabel)
	move(state.ui.modeCombo, layout.modeCombo)
	move(state.ui.sectionLabel, layout.sectionLabel)
	move(state.ui.sectionCombo, layout.sectionCombo)
	move(state.ui.fontLabel, layout.fontLabel)
	move(state.ui.fontCombo, layout.fontCombo)
	move(state.ui.backgroundLabel, layout.backgroundLabel)
	move(state.ui.backgroundCombo, layout.backgroundCombo)
	move(state.ui.reviewLabel, layout.reviewLabel)
	move(state.ui.reviewCombo, layout.reviewCombo)
	move(state.ui.segmentLabel, layout.segmentLabel)
	move(state.ui.segmentCombo, layout.segmentCombo)
	move(state.ui.categoryLabel, layout.categoryLabel)
	move(state.ui.categoryCombo, layout.categoryCombo)
	move(state.ui.groupLabel, layout.groupLabel)
	move(state.ui.groupCombo, layout.groupCombo)
	show := func(visible bool, controls ...syscall.Handle) {
		command := uintptr(0)
		if visible {
			command = 5 // SW_SHOW
		}
		for _, control := range controls {
			procShowWindow.Call(uintptr(control), command)
		}
	}
	show(layout.showSegment, state.ui.segmentLabel, state.ui.segmentCombo)
	show(layout.showCategory, state.ui.categoryLabel, state.ui.categoryCombo)
	show(layout.showGroup, state.ui.groupLabel, state.ui.groupCombo)
	move(state.ui.progress, offsetRight(layout.progress, deltaWidth))
	move(state.ui.instruction, offsetRight(layout.instruction, deltaWidth))
	move(state.ui.prompt, offsetRight(layout.prompt, deltaWidth))
	move(state.ui.detail, offsetRight(layout.detail, deltaWidth))
	move(state.ui.target, offsetRight(layout.target, deltaWidth))
	move(state.ui.inputLabel, offsetRight(layout.inputLabel, deltaWidth))
	move(state.ui.input, offsetRight(layout.input, deltaWidth))
	move(state.ui.next, shiftHorizontal(layout.next, deltaWidth))
	move(state.ui.restart, shiftHorizontal(layout.restart, deltaWidth))
	move(state.ui.play, layout.play)
	move(state.ui.reveal, layout.reveal)
	move(state.ui.report, layout.report)
	move(state.ui.clear, layout.clear)
	move(state.ui.feedback, offsetRight(layout.feedback, deltaWidth))
	score := offsetRight(layout.score, deltaWidth)
	score.Top += deltaHeight
	score.Bottom += deltaHeight
	move(state.ui.score, score)
}

func (state *appState) selectFontSize() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.fontCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(trainerFontOptions) {
		return
	}
	state.preferences.FontSize = trainerFontOptions[index].value
	state.applySelectedFont()
	state.resizeToContent()
	state.savePreferences()
}

func (state *appState) selectBackground() {
	index, _, _ := procSendMessageW.Call(uintptr(state.ui.backgroundCombo), cbGetcursel, 0, 0)
	if int(index) < 0 || int(index) >= len(trainerBackgroundOptions) {
		return
	}
	state.preferences.Background = trainerBackgroundOptions[index].value
	state.applySelectedBackground()
	state.savePreferences()
}

func (state *appState) savePreferences() {
	if err := trainer.SavePreferences(state.preferencesDir, state.preferences); err != nil {
		setText(state.ui.feedback, fmt.Sprintf("无法保存显示设置：%v；本次显示仍然有效。", err))
	}
}

func (state *appState) paintBackground(deviceContext uintptr) uintptr {
	if state.backgroundBrush == 0 {
		return 0
	}
	var bounds rect
	procGetClientRect.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(&bounds)))
	procFillRect.Call(deviceContext, uintptr(unsafe.Pointer(&bounds)), uintptr(state.backgroundBrush))
	return 1
}

func (state *appState) colorControl(deviceContext uintptr) uintptr {
	if state.backgroundBrush == 0 {
		return 0
	}
	procSetBkColor.Call(deviceContext, uintptr(state.backgroundColor))
	procSetTextColor.Call(deviceContext, 0)
	return uintptr(state.backgroundBrush)
}

func (state *appState) releaseDisplayResources() {
	if state.displayFont != 0 {
		procDeleteObject.Call(uintptr(state.displayFont))
		state.displayFont = 0
	}
	if state.backgroundBrush != 0 {
		procDeleteObject.Call(uintptr(state.backgroundBrush))
		state.backgroundBrush = 0
	}
}
