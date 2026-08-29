//go:build windows

package main

import (
	"path/filepath"
	"syscall"
	"testing"

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
		if got := buttonDisplayLabel(button, iconState); got == "" || got == button.text {
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
