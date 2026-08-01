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

func countVisible(layout toolbarLayout) int {
	count := 0
	for _, placement := range layout.placements {
		if placement.visible {
			count++
		}
	}
	return count
}
