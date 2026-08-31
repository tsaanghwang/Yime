//go:build windows

package main

import (
	"path/filepath"
	"syscall"
	"testing"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
)

func TestWindowSizeReservesARealClientAreaForButtons(t *testing.T) {
	layout := calculateToolbarLayout(toolbarstate.State{})
	width, height := windowSizeForClient(layout.clientWidth, layout.clientHeight)
	if width < layout.clientWidth {
		t.Fatalf("outer width %d is smaller than requested client width %d",
			width, layout.clientWidth)
	}
	if height < layout.clientHeight {
		t.Fatalf("outer height %d is smaller than borderless client height %d",
			height, layout.clientHeight)
	}
	for _, placement := range layout.placements {
		if placement.visible && placement.y+placement.height > layout.clientHeight {
			t.Fatalf("button %d bottom %d exceeds client height %d",
				placement.id, placement.y+placement.height, layout.clientHeight)
		}
	}
}

func TestToolbarLayoutShrinksForHiddenButtonsAndSupportsVerticalStack(t *testing.T) {
	defaultLayout := calculateToolbarLayout(toolbarstate.State{})
	hiddenLayout := calculateToolbarLayout(toolbarstate.State{
		HiddenButtons: []string{"shape", "unicode"},
	})
	if hiddenLayout.clientWidth >= defaultLayout.clientWidth {
		t.Fatalf("hidden buttons did not shrink horizontal toolbar: default=%d hidden=%d",
			defaultLayout.clientWidth, hiddenLayout.clientWidth)
	}
	if countVisible(hiddenLayout) != 6 {
		t.Fatalf("expected six visible horizontal controls, got %d", countVisible(hiddenLayout))
	}

	vertical := calculateToolbarLayout(toolbarstate.State{Vertical: true})
	if vertical.clientWidth >= defaultLayout.clientWidth {
		t.Fatalf("vertical toolbar should be narrower: horizontal=%d vertical=%d",
			defaultLayout.clientWidth, vertical.clientWidth)
	}
	if vertical.clientHeight <= defaultLayout.clientHeight {
		t.Fatalf("vertical toolbar should be taller: horizontal=%d vertical=%d",
			defaultLayout.clientHeight, vertical.clientHeight)
	}
}

func TestSettingsButtonCannotBeHiddenAndCustomizationToggleIsReversible(t *testing.T) {
	layout := calculateToolbarLayout(toolbarstate.State{
		HiddenButtons: []string{"language", "shape", "punctuation", "script", "unicode", "trainer", "settings"},
	})
	if countVisible(layout) != 2 {
		t.Fatalf("drag handle and settings anchor must remain visible, got %d visible controls", countVisible(layout))
	}
	for _, placement := range layout.placements {
		if placement.id == idSettings && !placement.visible {
			t.Fatal("settings anchor was hidden")
		}
	}

	hidden := toggleHiddenButton(nil, "shape")
	if len(hidden) != 1 || hidden[0] != "shape" {
		t.Fatalf("expected shape to become hidden, got %#v", hidden)
	}
	hidden = toggleHiddenButton(hidden, "shape")
	if len(hidden) != 0 {
		t.Fatalf("expected second toggle to restore shape, got %#v", hidden)
	}
}

func TestToolbarUsesClientDragHandleWithoutNativeCaption(t *testing.T) {
	if got := dragHandleLabel(toolbarstate.State{}); got != "│" {
		t.Fatalf("horizontal drag handle=%q want │", got)
	}
	if got := dragHandleLabel(toolbarstate.State{Vertical: true}); got != "— —" {
		t.Fatalf("vertical drag handle=%q want — —", got)
	}
	if toolbarWindowStyle()&(wsDlgFrame|wsSysMenu) != 0 {
		t.Fatalf("toolbar style %#x must not expose a native caption", toolbarWindowStyle())
	}
	if got := (&app{}).windowExStyle(); got&wsExNoActivate == 0 {
		t.Fatalf("toolbar extended style %#x must not activate or replace the host input profile", got)
	}
	if dragHandleStyle()&ssNotify == 0 {
		t.Fatalf("drag handle style %#x must receive mouse notifications", dragHandleStyle())
	}
	horizontal := calculateToolbarLayout(toolbarstate.State{})
	vertical := calculateToolbarLayout(toolbarstate.State{Vertical: true})
	if horizontal.placements[0].id != idHandle || horizontal.placements[0].width != toolbarHandleWidth {
		t.Fatalf("horizontal drag handle placement=%#v", horizontal.placements[0])
	}
	if vertical.placements[0].id != idHandle || vertical.placements[0].height != toolbarHandleHeight {
		t.Fatalf("vertical drag handle placement=%#v", vertical.placements[0])
	}
}

func TestDragHandleStartsNativeWindowMove(t *testing.T) {
	original := beginToolbarDrag
	defer func() { beginToolbarDrag = original }()

	want := syscall.Handle(321)
	called := syscall.Handle(0)
	beginToolbarDrag = func(hwnd syscall.Handle) {
		called = hwnd
	}
	if ret := dragHandleWndProc(want, wmLButtonDown, 0, 0); ret != 0 || called != want {
		t.Fatalf("drag callback ret=%d hwnd=%v want %v", ret, called, want)
	}
}

func TestToolbarDefaultsToVerticalAndRemembersExplicitHorizontal(t *testing.T) {
	path := filepath.Join(t.TempDir(), toolbarstate.FileName)
	initial := loadToolbarState(path)
	if !initial.Vertical || !initial.OrientationSet {
		t.Fatalf("new toolbar state must default to vertical: %#v", initial)
	}
	if initial.ToolbarLayoutVersion != toolbarstate.LayoutVersion {
		t.Fatalf("new toolbar layout version=%d want %d", initial.ToolbarLayoutVersion, toolbarstate.LayoutVersion)
	}

	horizontal, err := toolbarstate.Update(path, "toolbar", func(state *toolbarstate.State) bool {
		state.Vertical = false
		state.OrientationSet = true
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	loaded := loadToolbarState(path)
	if loaded.Vertical || !loaded.OrientationSet || loaded.Revision != horizontal.Revision {
		t.Fatalf("explicit horizontal state was not preserved: %#v", loaded)
	}
	if got := orientationMenuLabel(initial); got != "垂直" {
		t.Fatalf("vertical menu label=%q", got)
	}
	if got := orientationMenuLabel(loaded); got != "水平" {
		t.Fatalf("horizontal menu label=%q", got)
	}
}

func TestExperimentalToolbarUsesProductionSurfaceWithIsolatedIdentity(t *testing.T) {
	trial := &app{experimental: true}
	if got := trial.className(); got != "YimeCoreInputToolbarWindow" {
		t.Fatalf("experimental input toolbar class=%q", got)
	}
	if got := trial.windowTitle(); got != "Yime 元版桌面浮动工具栏" {
		t.Fatalf("experimental input toolbar title=%q", got)
	}
	production := &app{}
	if production.className() != windowClass || production.windowTitle() != messageTitle {
		t.Fatal("trial window identity leaked into the production toolbar")
	}

	path := filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName)
	state := loadExperimentalToolbarState(path)
	if state.ExperimentMode != toolbarstate.ExperimentModeVariable ||
		state.CandidateFontPreset != toolbarstate.CandidateFontMedium ||
		state.CandidateAnnotation != toolbarstate.AnnotationKeySequence || !state.Vertical ||
		state.ToolbarLayoutVersion != toolbarstate.LayoutVersion {
		t.Fatalf("experimental toolbar defaults = %#v", state)
	}
	layout := calculateToolbarLayoutFor(state, trial.buttonDefinitions())
	if countVisible(layout) != countVisible(calculateToolbarLayout(state)) ||
		layout.clientHeight <= 0 || layout.clientWidth <= 0 {
		t.Fatalf("experimental toolbar layout = %#v", layout)
	}
	if got, want := trial.buttonDefinitions(), toolbarButtons(); len(got) != len(want) {
		t.Fatalf("Trial toolbar button count=%d want production count=%d", len(got), len(want))
	} else {
		for index := range want {
			if got[index] != want[index] {
				t.Fatalf("Trial button %d=%#v want production %#v", index, got[index], want[index])
			}
		}
	}
}

func TestPunctuationPreviewUsesIsolatedWindowAndProductionButton(t *testing.T) {
	preview := &app{previewPunctuation: true}
	if preview.className() != previewWindowClass || preview.windowTitle() != previewWindowTitle {
		t.Fatalf("punctuation preview identity class=%q title=%q", preview.className(), preview.windowTitle())
	}
	buttons := preview.buttonDefinitions()
	if len(buttons) != 3 || buttons[0].id != idHandle || buttons[1].id != idLanguage || buttons[2].id != idPunct {
		t.Fatalf("toolbar icon preview buttons=%#v want handle, language, and punctuation buttons", buttons)
	}
	if preview.windowStyle()&(wsCaption|wsSysMenu) != wsCaption|wsSysMenu {
		t.Fatalf("punctuation preview style %#x must expose a caption and close button", preview.windowStyle())
	}
	if preview.windowExStyle()&wsExToolWindow != 0 {
		t.Fatalf("punctuation preview extended style %#x must remain visible in the taskbar", preview.windowExStyle())
	}
	if preview.windowExStyle()&wsExNoActivate != 0 {
		t.Fatalf("interactive punctuation preview extended style %#x must remain activatable", preview.windowExStyle())
	}
	if x, y := preview.defaultWindowPosition(1920, 1080, 100, 80); x != 910 || y != 500 {
		t.Fatalf("punctuation preview position=(%d,%d) want centered (910,500)", x, y)
	}
	path, cleanup, err := createPunctuationPreviewState()
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	state, err := toolbarstate.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.Vertical || !state.OrientationSet || state.ToolbarDisplay != toolbarstate.ToolbarDisplayIcon {
		t.Fatalf("punctuation preview state=%#v", state)
	}
}

func TestToolbarMigratesLegacyHorizontalStateToNewVerticalDefaultOnce(t *testing.T) {
	path := filepath.Join(t.TempDir(), toolbarstate.FileName)
	legacy, err := toolbarstate.Update(path, "toolbar", func(state *toolbarstate.State) bool {
		state.Vertical = false
		state.OrientationSet = true
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	migrated := loadToolbarState(path)
	if !migrated.Vertical || migrated.ToolbarLayoutVersion != toolbarstate.LayoutVersion || migrated.Revision <= legacy.Revision {
		t.Fatalf("legacy horizontal state was not migrated to the new vertical default: %#v", migrated)
	}
}

func TestToolbarDefaultPositionIsRightInsetAndVerticallyCentered(t *testing.T) {
	x, y := defaultToolbarPosition(1920, 1080, 100, 300)
	if x != 1788 || y != 390 {
		t.Fatalf("default position=(%d,%d) want (1788,390)", x, y)
	}
}

func TestToolbarResizeKeepsExpandedHorizontalLayoutOnScreen(t *testing.T) {
	x, y := fitToolbarPosition(1800, 900, 1920, 1080, 500, 220)
	if x != 1388 || y != 860 {
		t.Fatalf("fitted position=(%d,%d) want (1388,860)", x, y)
	}
}

func TestTrainerButtonPrecedesSettingsAndUsesCurrentSchemaMode(t *testing.T) {
	buttons := toolbarButtons()
	if len(buttons) < 2 || buttons[len(buttons)-2].id != idTrainer || buttons[len(buttons)-1].id != idSettings {
		t.Fatalf("trainer and settings must be the final two buttons: %#v", buttons)
	}
	for schemaID, want := range map[string]string{
		"yime_variable":  "variable",
		"yime_full":      "full",
		"yime_shorthand": "shorthand",
	} {
		if got := trainerModeFromSchema(schemaID); got != want {
			t.Fatalf("trainer mode for %s=%q want %q", schemaID, got, want)
		}
	}
}

func TestHideCommandDestroysToolbarProcessWindow(t *testing.T) {
	original := closeToolbarWindow
	defer func() { closeToolbarWindow = original }()

	want := syscall.Handle(123)
	called := make([]syscall.Handle, 0, 2)
	closeToolbarWindow = func(hwnd syscall.Handle) {
		called = append(called, hwnd)
	}
	instance := &app{hwnd: want}
	instance.handleSettingsMenuCommand(idMenuHide)
	instance.wndProc(syscall.Handle(456), wmClose, 0, 0)
	if len(called) != 2 || called[0] != want || called[1] != syscall.Handle(456) {
		t.Fatalf("hide paths destroyed windows %#v", called)
	}
}

func TestPrimaryStateButtonsUseTwoCharacterLabels(t *testing.T) {
	expected := map[int]string{
		idLanguage: "中文",
		idShape:    "半宽",
		idScript:   "简体",
	}
	for _, button := range toolbarButtons() {
		if want, ok := expected[button.id]; ok && button.text != want {
			t.Fatalf("button %d label=%q want %q", button.id, button.text, want)
		}
	}
	for id := range expected {
		found := false
		for _, button := range toolbarButtons() {
			if button.id == id {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("missing primary state button %d", id)
		}
	}
}

func TestToolbarDisplayModeControlsLabelsWidthsAndAlpha(t *testing.T) {
	buttons := toolbarButtons()
	textState := toolbarstate.State{}
	iconState := toolbarstate.State{ToolbarDisplay: toolbarstate.ToolbarDisplayIcon, ToolbarTransparent: true}
	for _, button := range buttons {
		if button.id == idHandle {
			continue
		}
		got := buttonDisplayLabel(button, iconState)
		if toolbarButtonUsesNativeIcon(button.id) {
			if got != "" || !usesDrawnToolbarIcon(button, iconState) {
				t.Fatalf("button %d must reserve its icon for native drawing, label=%q", button.id, got)
			}
			if button.icon != "" {
				t.Fatalf("native-drawn button %d still retains borrowed font icon %q", button.id, button.icon)
			}
		} else if got == "" || got == button.text {
			t.Fatalf("button %d icon label=%q text=%q", button.id, got, button.text)
		}
		if width := buttonWidthForLayout(button, iconState, false); width != toolbarIconWidth {
			t.Fatalf("button %d icon width=%d want %d", button.id, width, toolbarIconWidth)
		}
	}
	if text := buttonDisplayLabel(buttons[1], textState); text != "中文" {
		t.Fatalf("default text label=%q want 中文", text)
	}
	if toolbarAlpha(textState) != 255 || toolbarAlpha(iconState) == 255 {
		t.Fatalf("toolbar alpha text=%d transparent=%d", toolbarAlpha(textState), toolbarAlpha(iconState))
	}
	if calculateToolbarLayout(iconState).clientWidth >= calculateToolbarLayout(textState).clientWidth {
		t.Fatal("compact icon mode did not reduce horizontal toolbar width")
	}
	for _, button := range buttons {
		if button.id != idHandle && buttonTooltip(button.id) == "" {
			t.Fatalf("button %d has no icon tooltip", button.id)
		}
	}
}

func TestShapeIconsShareOneCenteredOuterGeometry(t *testing.T) {
	bounds := rect{Left: 0, Top: 0, Right: 40, Bottom: 34}
	half := shapeIconGeometryFor(bounds, 96, false, false)
	full := shapeIconGeometryFor(bounds, 96, true, false)
	wantOuter := rect{Left: 11, Top: 8, Right: 29, Bottom: 26}
	if half.Outer != wantOuter || full.Outer != wantOuter {
		t.Fatalf("shape icon outer geometry half=%#v full=%#v want=%#v", half.Outer, full.Outer, wantOuter)
	}
	if full.Dark != full.Outer || full.Light != (rect{}) {
		t.Fatalf("full-width icon must fill the complete outer square: %#v", full)
	}
	if half.Light != (rect{Left: 12, Top: 9, Right: 28, Bottom: 25}) {
		t.Fatalf("half-width light interior=%#v", half.Light)
	}
	if half.Dark != (rect{Left: 20, Top: 9, Right: 28, Bottom: 25}) {
		t.Fatalf("half-width dark half=%#v", half.Dark)
	}
	if half.Dark.Right-half.Dark.Left != (half.Light.Right-half.Light.Left)/2 {
		t.Fatalf("half-width dark fill is not exactly half of the interior: %#v", half)
	}
}

func TestShapeIconGeometryScalesWithoutStateSizeDrift(t *testing.T) {
	bounds := rect{Left: 3, Top: 5, Right: 63, Bottom: 56}
	half := shapeIconGeometryFor(bounds, 144, false, false)
	full := shapeIconGeometryFor(bounds, 144, true, false)
	pressed := shapeIconGeometryFor(bounds, 144, false, true)
	if half.Outer != full.Outer {
		t.Fatalf("scaled state switch changed outer size: half=%#v full=%#v", half.Outer, full.Outer)
	}
	if width := half.Outer.Right - half.Outer.Left; width != 26 {
		t.Fatalf("150%% DPI outer width=%d want 26", width)
	}
	if pressed.Outer.Left != half.Outer.Left+1 || pressed.Outer.Top != half.Outer.Top+1 ||
		pressed.Outer.Right != half.Outer.Right+1 || pressed.Outer.Bottom != half.Outer.Bottom+1 {
		t.Fatalf("pressed icon should move one pixel without resizing: normal=%#v pressed=%#v", half.Outer, pressed.Outer)
	}
}

func TestPunctuationIconsShareOneCenteredCanvas(t *testing.T) {
	bounds := rect{Left: 0, Top: 0, Right: 40, Bottom: 34}
	chinese := punctuationIconGeometryFor(bounds, 96, false, false)
	english := punctuationIconGeometryFor(bounds, 96, true, false)
	wantCanvas := rect{Left: 11, Top: 8, Right: 29, Bottom: 26}
	if chinese.Canvas != wantCanvas || english.Canvas != wantCanvas {
		t.Fatalf("punctuation canvases Chinese=%#v English=%#v want=%#v", chinese.Canvas, english.Canvas, wantCanvas)
	}
	for name, icon := range map[string]punctuationIconGeometry{"Chinese": chinese, "English": english} {
		if icon.TopBounds.Left != wantCanvas.Left || icon.TopBounds.Right != wantCanvas.Right ||
			icon.BottomBounds.Left != wantCanvas.Left || icon.BottomBounds.Right != wantCanvas.Right ||
			icon.TopBounds.Bottom != icon.BottomBounds.Top {
			t.Fatalf("%s punctuation glyph rows are not centered and stacked: %#v", name, icon)
		}
		if icon.FontHeight != 17 {
			t.Fatalf("%s punctuation font height=%d want 17", name, icon.FontHeight)
		}
	}
	if chinese.TopGlyph != "、" || chinese.BottomGlyph != "。" {
		t.Fatalf("Chinese punctuation glyphs=%q over %q want 、 over 。", chinese.TopGlyph, chinese.BottomGlyph)
	}
	if english.TopGlyph != "," || english.BottomGlyph != "." {
		t.Fatalf("English punctuation glyphs=%q over %q want , over .", english.TopGlyph, english.BottomGlyph)
	}
}

func TestPunctuationIconGeometryScalesWithoutStateSizeDrift(t *testing.T) {
	bounds := rect{Left: 3, Top: 5, Right: 63, Bottom: 56}
	chinese := punctuationIconGeometryFor(bounds, 144, false, false)
	english := punctuationIconGeometryFor(bounds, 144, true, false)
	if chinese.Canvas != english.Canvas {
		t.Fatalf("punctuation state switch changed canvas: Chinese=%#v English=%#v", chinese.Canvas, english.Canvas)
	}
	if width := chinese.Canvas.Right - chinese.Canvas.Left; width != 26 {
		t.Fatalf("150%% DPI punctuation canvas width=%d want 26", width)
	}
	if chinese.FontHeight != 21 || english.FontHeight != 21 {
		t.Fatalf("150%% DPI punctuation font height Chinese=%d English=%d want 21", chinese.FontHeight, english.FontHeight)
	}
}

func TestPunctuationStatesUseScriptAppropriateFonts(t *testing.T) {
	if got := punctuationGlyphFontFamily(false); got != "Microsoft YaHei UI" {
		t.Fatalf("Chinese punctuation font=%q want Microsoft YaHei UI", got)
	}
	if got := punctuationGlyphFontFamily(true); got != "Georgia" {
		t.Fatalf("English punctuation font=%q want Georgia", got)
	}
}

func TestPunctuationGlyphsCanExtendPastPositioningRows(t *testing.T) {
	if punctuationDrawTextFlags()&dtNoClip == 0 {
		t.Fatal("enlarged punctuation glyphs will be clipped to their half-height positioning rows")
	}
}

func TestLanguageIconsUseCenteredChineseAndLatinGlyphs(t *testing.T) {
	bounds := rect{Left: 0, Top: 0, Right: 40, Bottom: 34}
	chinese := languageIconGeometryFor(bounds, 96, false, false)
	english := languageIconGeometryFor(bounds, 96, true, false)
	wantCanvas := rect{Left: 11, Top: 8, Right: 29, Bottom: 26}
	if chinese.Canvas != wantCanvas || english.Canvas != wantCanvas {
		t.Fatalf("language canvases Chinese=%#v English=%#v want=%#v", chinese.Canvas, english.Canvas, wantCanvas)
	}
	if chinese.Glyph != "中" || english.Glyph != "A" {
		t.Fatalf("language glyphs Chinese=%q English=%q", chinese.Glyph, english.Glyph)
	}
	if chinese.FontHeight != 16 || english.FontHeight != 16 {
		t.Fatalf("language font heights Chinese=%d English=%d want 16", chinese.FontHeight, english.FontHeight)
	}
}

func TestLanguageIconGeometryScalesWithoutStateSizeDrift(t *testing.T) {
	bounds := rect{Left: 3, Top: 5, Right: 63, Bottom: 56}
	chinese := languageIconGeometryFor(bounds, 144, false, false)
	english := languageIconGeometryFor(bounds, 144, true, false)
	if chinese.Canvas != english.Canvas {
		t.Fatalf("language switch changed canvas: Chinese=%#v English=%#v", chinese.Canvas, english.Canvas)
	}
	if width := chinese.Canvas.Right - chinese.Canvas.Left; width != 26 {
		t.Fatalf("150%% DPI language canvas width=%d want 26", width)
	}
	if chinese.FontHeight != 24 || english.FontHeight != 24 {
		t.Fatalf("150%% DPI language font heights Chinese=%d English=%d want 24", chinese.FontHeight, english.FontHeight)
	}
}

func TestScriptIconsUseOneCenteredCanvasAndExplicitGlyphs(t *testing.T) {
	bounds := rect{Left: 0, Top: 0, Right: 40, Bottom: 34}
	simplified := scriptIconGeometryFor(bounds, 96, false, false)
	traditional := scriptIconGeometryFor(bounds, 96, true, false)
	wantCanvas := rect{Left: 11, Top: 8, Right: 29, Bottom: 26}
	if simplified.Canvas != wantCanvas || traditional.Canvas != wantCanvas {
		t.Fatalf("script canvases simplified=%#v traditional=%#v want=%#v", simplified.Canvas, traditional.Canvas, wantCanvas)
	}
	if simplified.Glyph != "简" || traditional.Glyph != "繁" {
		t.Fatalf("script glyphs simplified=%q traditional=%q", simplified.Glyph, traditional.Glyph)
	}
	if simplified.FontHeight != 16 || traditional.FontHeight != 16 {
		t.Fatalf("script font heights simplified=%d traditional=%d want 16", simplified.FontHeight, traditional.FontHeight)
	}
}

func TestScriptIconGeometryScalesWithoutStateSizeDrift(t *testing.T) {
	bounds := rect{Left: 3, Top: 5, Right: 63, Bottom: 56}
	simplified := scriptIconGeometryFor(bounds, 144, false, false)
	traditional := scriptIconGeometryFor(bounds, 144, true, false)
	if simplified.Canvas != traditional.Canvas {
		t.Fatalf("script switch changed canvas: simplified=%#v traditional=%#v", simplified.Canvas, traditional.Canvas)
	}
	if width := simplified.Canvas.Right - simplified.Canvas.Left; width != 26 {
		t.Fatalf("150%% DPI script canvas width=%d want 26", width)
	}
	if simplified.FontHeight != 24 || traditional.FontHeight != 24 {
		t.Fatalf("150%% DPI script font heights simplified=%d traditional=%d want 24", simplified.FontHeight, traditional.FontHeight)
	}
}

func TestPunctuationIconsRenderDistinctNonEmptyGDIInk(t *testing.T) {
	chineseInk, chineseFingerprint := renderPunctuationIconForTest(t, false)
	englishInk, englishFingerprint := renderPunctuationIconForTest(t, true)
	t.Logf("GDI ink pixels: Chinese=%d English=%d", chineseInk, englishInk)
	if chineseInk == 0 || englishInk == 0 {
		t.Fatalf("punctuation drawing produced blank output: Chinese=%d English=%d", chineseInk, englishInk)
	}
	if chineseFingerprint == englishFingerprint {
		t.Fatalf("Chinese and English punctuation rendered identically: fingerprint=%#x", chineseFingerprint)
	}
}

func TestLanguageIconsRenderDistinctNonEmptyGDIInk(t *testing.T) {
	chineseInk, chineseFingerprint := renderLanguageIconForTest(t, false)
	englishInk, englishFingerprint := renderLanguageIconForTest(t, true)
	t.Logf("GDI ink pixels: 中=%d A=%d", chineseInk, englishInk)
	if chineseInk == 0 || englishInk == 0 {
		t.Fatalf("language drawing produced blank output: Chinese=%d English=%d", chineseInk, englishInk)
	}
	if chineseFingerprint == englishFingerprint {
		t.Fatalf("Chinese and English language icons rendered identically: fingerprint=%#x", chineseFingerprint)
	}
}

func TestScriptIconsRenderDistinctNonEmptyGDIInk(t *testing.T) {
	simplifiedInk, simplifiedFingerprint := renderScriptIconForTest(t, false)
	traditionalInk, traditionalFingerprint := renderScriptIconForTest(t, true)
	t.Logf("GDI ink pixels: 简=%d 繁=%d", simplifiedInk, traditionalInk)
	if simplifiedInk == 0 || traditionalInk == 0 {
		t.Fatalf("script drawing produced blank output: simplified=%d traditional=%d", simplifiedInk, traditionalInk)
	}
	if simplifiedFingerprint == traditionalFingerprint {
		t.Fatalf("simplified and traditional icons rendered identically: fingerprint=%#x", simplifiedFingerprint)
	}
}

func renderPunctuationIconForTest(t *testing.T, ascii bool) (int, uint64) {
	t.Helper()
	return renderToolbarIconForTest(t, func(hdc syscall.Handle, bounds rect) {
		drawPunctuationIcon(hdc, bounds, 96, ascii, false)
	})
}

func renderLanguageIconForTest(t *testing.T, ascii bool) (int, uint64) {
	t.Helper()
	return renderToolbarIconForTest(t, func(hdc syscall.Handle, bounds rect) {
		drawLanguageIcon(hdc, bounds, 96, ascii, false)
	})
}

func renderScriptIconForTest(t *testing.T, traditional bool) (int, uint64) {
	t.Helper()
	return renderToolbarIconForTest(t, func(hdc syscall.Handle, bounds rect) {
		drawScriptIcon(hdc, bounds, 96, traditional, false)
	})
}

func renderToolbarIconForTest(t *testing.T, draw func(syscall.Handle, rect)) (int, uint64) {
	t.Helper()
	createCompatibleDC := gdi32.NewProc("CreateCompatibleDC")
	createCompatibleBitmap := gdi32.NewProc("CreateCompatibleBitmap")
	deleteDC := gdi32.NewProc("DeleteDC")
	getPixel := gdi32.NewProc("GetPixel")
	screenDC, _, _ := getDC.Call(0)
	if screenDC == 0 {
		t.Fatal("GetDC desktop failed")
	}
	defer releaseDC.Call(0, screenDC)
	memoryDC, _, _ := createCompatibleDC.Call(screenDC)
	if memoryDC == 0 {
		t.Fatal("CreateCompatibleDC failed")
	}
	defer deleteDC.Call(memoryDC)
	bitmap, _, _ := createCompatibleBitmap.Call(screenDC, 40, 34)
	if bitmap == 0 {
		t.Fatal("CreateCompatibleBitmap failed")
	}
	oldBitmap, _, _ := selectObject.Call(memoryDC, bitmap)
	defer func() {
		selectObject.Call(memoryDC, oldBitmap)
		deleteObject.Call(bitmap)
	}()
	bounds := rect{Right: 40, Bottom: 34}
	backgroundBrush, _, _ := getSysColorBrush.Call(colorWindow)
	fillRect.Call(memoryDC, uintptr(unsafe.Pointer(&bounds)), backgroundBrush)
	draw(syscall.Handle(memoryDC), bounds)
	background, _, _ := getSysColor.Call(colorWindow)
	ink := 0
	fingerprint := uint64(1469598103934665603)
	for y := int32(0); y < bounds.Bottom; y++ {
		for x := int32(0); x < bounds.Right; x++ {
			pixel, _, _ := getPixel.Call(memoryDC, uintptr(x), uintptr(y))
			if uint32(pixel) != uint32(background) {
				ink++
				fingerprint ^= uint64(uint32(pixel)) + uint64(x+1)<<24 + uint64(y+1)<<32
				fingerprint *= 1099511628211
			}
		}
	}
	return ink, fingerprint
}

func TestDrawnToolbarIconsOverlayEveryNativePaintPath(t *testing.T) {
	if !toolbarIconButtonNeedsOverlay(wmPaint) {
		t.Fatal("normal WM_PAINT must redraw native toolbar icons after the stock button")
	}
	if !toolbarIconButtonNeedsOverlay(wmPrintClient) {
		t.Fatal("WM_PRINTCLIENT must include native toolbar icons in captures and redirected paints")
	}
	for _, message := range []uint32{wmNull, wmCommand, wmLButtonDown} {
		if toolbarIconButtonNeedsOverlay(message) {
			t.Fatalf("unrelated message %#x unexpectedly requests an icon overlay", message)
		}
	}
}

func TestTextButtonsUseMeasuredLabelWidth(t *testing.T) {
	original := measureToolbarTextWidth
	defer func() { measureToolbarTextWidth = original }()
	measureToolbarTextWidth = func(text string) int32 {
		return map[string]int32{"中文": 27, "较长文字标签": 73}[text]
	}

	state := toolbarstate.State{}
	buttons := toolbarButtons()
	longButton := toolbarButton{id: 999, key: "long", text: "较长文字标签"}
	if got, want := buttonWidthForLayout(buttons[1], state, false), int32(27)+toolbarTextPadding; got != want {
		t.Fatalf("Chinese text button width=%d want measured width plus padding=%d", got, want)
	}
	if got, want := buttonWidthForLayout(longButton, state, false), int32(73)+toolbarTextPadding; got != want {
		t.Fatalf("long text button width=%d want measured width plus padding=%d", got, want)
	}
	if buttonWidthForLayout(longButton, state, false) <= buttonWidthForLayout(buttons[1], state, false) {
		t.Fatal("longer measured label did not produce a wider button")
	}
}

func TestAppearanceMenuCommandsPersistDisplayAndTransparency(t *testing.T) {
	path := filepath.Join(t.TempDir(), toolbarstate.FileName)
	instance := &app{statePath: path, buttons: map[int]syscall.Handle{}}
	instance.handleSettingsMenuCommand(idMenuDisplayIcon)
	instance.handleSettingsMenuCommand(idMenuTransparent)
	state, err := toolbarstate.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.ToolbarDisplay != toolbarstate.ToolbarDisplayIcon || !state.ToolbarTransparent {
		t.Fatalf("icon/transparent selection was not persisted: %#v", state)
	}
	instance.handleSettingsMenuCommand(idMenuDisplayText)
	instance.handleSettingsMenuCommand(idMenuOpaque)
	state, err = toolbarstate.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.ToolbarDisplay != toolbarstate.ToolbarDisplayText || state.ToolbarTransparent {
		t.Fatalf("text/opaque selection was not persisted: %#v", state)
	}
}

func TestLanguageBarStateRefreshesAllToolbarButtonLabels(t *testing.T) {
	path := filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName)
	initial, err := toolbarstate.Update(path, "test", func(state *toolbarstate.State) bool {
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	instance := &app{
		statePath: path,
		buttons:   map[int]syscall.Handle{},
		state:     initial,
	}
	_, err = toolbarstate.Update(path, "yimecore-language-bar", func(state *toolbarstate.State) bool {
		state.ASCII = true
		state.FullShape = true
		state.ASCIIPunctuation = true
		state.Traditionalization = true
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	instance.refresh()
	if !instance.state.ASCII || !instance.state.FullShape ||
		!instance.state.ASCIIPunctuation || !instance.state.Traditionalization {
		t.Fatalf("language-bar state did not reach toolbar: %#v", instance.state)
	}
	want := map[int]string{idLanguage: "英文", idShape: "全宽", idPunct: "英标", idScript: "繁体"}
	for _, button := range toolbarButtons() {
		if label, ok := want[button.id]; ok && buttonDisplayLabel(button, instance.state) != label {
			t.Fatalf("button %d label=%q want %q", button.id, buttonDisplayLabel(button, instance.state), label)
		}
	}
}

func countVisible(layout toolbarLayout) int {
	count := 0
	for _, placement := range layout.placements {
		if placement.visible {
			count++
		}
	}
	return count
}
