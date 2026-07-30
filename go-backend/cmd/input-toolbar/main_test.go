//go:build windows

package main

import "testing"

func TestWindowSizeReservesARealClientAreaForButtons(t *testing.T) {
	width, height := windowSizeForClient(toolbarClientWidth, toolbarClientHeight)
	if width < toolbarClientWidth {
		t.Fatalf("outer width %d is smaller than requested client width %d",
			width, toolbarClientWidth)
	}
	if height <= toolbarClientHeight {
		t.Fatalf("outer height %d did not reserve space for the title bar above client height %d",
			height, toolbarClientHeight)
	}
	if toolbarButtonTop+toolbarButtonHeight > toolbarClientHeight {
		t.Fatalf("button row bottom %d exceeds client height %d",
			toolbarButtonTop+toolbarButtonHeight, toolbarClientHeight)
	}
}
