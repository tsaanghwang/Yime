//go:build windows

package main

import (
	"testing"

	"github.com/EasyIME/pime-go/input_methods/yime/win32ui"
)

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

func TestShowWindowDoesNotReenterPresentation(t *testing.T) {
	if !shouldPresentForWindowMessage(win32ui.WmDeferredPresent) {
		t.Fatal("the explicit deferred-present message must present the window")
	}
	if shouldPresentForWindowMessage(0x0018) { // WM_SHOWWINDOW
		t.Fatal("WM_SHOWWINDOW must not reenter PresentMainWindow")
	}
}

func TestResultColumnsRestoreOriginalComparisonFields(t *testing.T) {
	columns := resultColumns()
	want := []string{"词条", "来源", "标准拼音", "当前编码", "等长", "变长", "省键"}
	if len(columns) != len(want) {
		t.Fatalf("column count = %d, want %d", len(columns), len(want))
	}
	for index, title := range want {
		if columns[index].title != title {
			t.Fatalf("column %d = %q, want %q", index, columns[index].title, title)
		}
	}
}

func TestUILayoutExpandsResultListAndKeepsDetailReadable(t *testing.T) {
	compact := buildUILayoutForSize(820, 560)
	expanded := buildUILayoutForSize(1020, 760)
	if expanded.resultList.Bottom-compact.resultList.Bottom != 200 {
		t.Fatalf("result list did not absorb added height: compact=%#v expanded=%#v", compact.resultList, expanded.resultList)
	}
	if compact.detailView.Bottom-compact.detailView.Top != 140 || expanded.detailView.Bottom-expanded.detailView.Top != 140 {
		t.Fatalf("detail area must remain fully readable: compact=%#v expanded=%#v", compact.detailView, expanded.detailView)
	}
	if expanded.searchEdit.Right-compact.searchEdit.Right != 200 {
		t.Fatalf("search edit did not absorb added width: compact=%#v expanded=%#v", compact.searchEdit, expanded.searchEdit)
	}
}

func TestResultColumnsGiveExtraWidthToPinyin(t *testing.T) {
	compact := resultColumnWidths(796)
	expanded := resultColumnWidths(996)
	for index := range compact {
		if index == 2 {
			continue
		}
		if compact[index] != expanded[index] {
			t.Fatalf("column %d should remain stable: compact=%v expanded=%v", index, compact, expanded)
		}
	}
	if expanded[2]-compact[2] != 200 {
		t.Fatalf("pinyin column should absorb extra width: compact=%v expanded=%v", compact, expanded)
	}
}

func TestBusyProgressSharesStatusRow(t *testing.T) {
	status := rect{Left: 12, Top: 520, Right: 808, Bottom: 548}
	idleStatus, idleProgress := statusProgressLayout(status, false)
	if idleStatus != status || idleProgress != (rect{}) {
		t.Fatalf("idle status layout changed: status=%#v progress=%#v", idleStatus, idleProgress)
	}
	busyStatus, busyProgress := statusProgressLayout(status, true)
	if busyProgress.Right != status.Right || busyProgress.Right-busyProgress.Left != 180 || busyStatus.Right >= busyProgress.Left {
		t.Fatalf("busy status and progress layout invalid: status=%#v progress=%#v", busyStatus, busyProgress)
	}
}
