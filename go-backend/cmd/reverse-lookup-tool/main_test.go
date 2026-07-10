//go:build windows

package main

import "testing"

func TestBuildUILayoutPlacesSearchControlsInOneRow(t *testing.T) {
	layout := buildUILayout()
	controls := []rect{
		layout.searchLabel,
		layout.searchEdit,
		layout.containsCheck,
		layout.modeLabel,
		layout.modeCombo,
		layout.searchButton,
	}

	for index := 1; index < len(controls); index++ {
		if controls[index-1].Right >= controls[index].Left {
			t.Fatalf("control %d overlaps or precedes control %d: %#v", index-1, index, controls)
		}
	}
	if layout.containsCheck.Left <= layout.searchEdit.Right {
		t.Fatal("contains checkbox must follow the search edit")
	}
	if layout.modeLabel.Left <= layout.containsCheck.Right || layout.searchButton.Left <= layout.modeCombo.Right {
		t.Fatal("mode controls must sit between contains checkbox and search button")
	}
}

func TestBuildUILayoutUsesEqualRowWidthsAndContentSizedWindow(t *testing.T) {
	layout := buildUILayout()
	wantLeft := layout.searchLabel.Left
	wantRight := layout.searchButton.Right

	rows := []rect{layout.resultList, layout.detailView, layout.statusLabel}
	for index, row := range rows {
		if row.Left != wantLeft || row.Right != wantRight {
			t.Fatalf("row %d spans %d..%d, want %d..%d", index, row.Left, row.Right, wantLeft, wantRight)
		}
	}
	if layout.clientW-wantRight != wantLeft {
		t.Fatalf("client width %d does not preserve symmetric margin %d", layout.clientW, wantLeft)
	}
	if layout.clientH-layout.statusLabel.Bottom != wantLeft {
		t.Fatalf("client height %d does not follow content bottom %d with margin %d", layout.clientH, layout.statusLabel.Bottom, wantLeft)
	}
}
