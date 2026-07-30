//go:build windows

package main

import (
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
	if height <= layout.clientHeight {
		t.Fatalf("outer height %d did not reserve space for the title bar above client height %d",
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
	if countVisible(hiddenLayout) != 4 {
		t.Fatalf("expected four visible horizontal buttons, got %d", countVisible(hiddenLayout))
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
		HiddenButtons: []string{"language", "shape", "punctuation", "script", "unicode", "settings"},
	})
	if countVisible(layout) != 1 {
		t.Fatalf("settings anchor must remain visible, got %d visible buttons", countVisible(layout))
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
