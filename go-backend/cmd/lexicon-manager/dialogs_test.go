//go:build windows

package main

import (
	"strconv"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

func TestAdjustWeightValue(t *testing.T) {
	tests := []struct {
		name      string
		current   string
		step      string
		direction int
		want      string
		wantErr   bool
	}{
		{name: "add", current: "10", step: "3", direction: 1, want: "13"},
		{name: "subtract", current: "10", step: "3", direction: -1, want: "7"},
		{name: "blank defaults", direction: 1, want: "1"},
		{name: "zero step", current: "10", step: "0", direction: -1, want: "10"},
		{name: "invalid current", current: "x", step: "1", direction: 1, wantErr: true},
		{name: "negative step", current: "10", step: "-1", direction: 1, wantErr: true},
		{name: "invalid direction", current: "10", step: "1", direction: 0, wantErr: true},
		{name: "positive overflow", current: strconv.Itoa(int(^uint(0) >> 1)), step: "1", direction: 1, wantErr: true},
		{name: "negative overflow", current: strconv.Itoa(-int(^uint(0)>>1) - 1), step: "1", direction: -1, wantErr: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := adjustWeightValue(test.current, test.step, test.direction)
			if test.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("adjustWeightValue returned error: %v", err)
			}
			if got != test.want {
				t.Fatalf("adjustWeightValue = %q, want %q", got, test.want)
			}
		})
	}
}

func TestCenteredButtonRectsCentersGroupAndPreservesGaps(t *testing.T) {
	buttons := centeredButtonRects(16, 504, 216, 28, 10, []int32{88, 96, 88})
	if len(buttons) != 3 {
		t.Fatalf("expected 3 buttons, got %d", len(buttons))
	}
	leftSpace := buttons[0].Left - 16
	rightSpace := 504 - buttons[len(buttons)-1].Right
	if leftSpace != rightSpace {
		t.Fatalf("button group is not centered: left=%d right=%d", leftSpace, rightSpace)
	}
	for index := 1; index < len(buttons); index++ {
		if buttons[index].Left-buttons[index-1].Right != 10 {
			t.Fatalf("unexpected gap between buttons %d and %d", index-1, index)
		}
	}
}

func TestWeightAdjustmentRectsFillContentRow(t *testing.T) {
	minus, step, plus := weightAdjustmentRects(16, 504, 214, 28, 74, 10)
	if minus.Left != 16 || plus.Right != 504 {
		t.Fatalf("adjustment row does not fill content width: minus=%#v plus=%#v", minus, plus)
	}
	if step.Left-minus.Right != 10 || plus.Left-step.Right != 10 {
		t.Fatalf("adjustment row gaps are inconsistent: minus=%#v step=%#v plus=%#v", minus, step, plus)
	}
	if step.Right <= step.Left {
		t.Fatalf("step input has invalid width: %#v", step)
	}
}

func TestModeDisplayNameUsesChineseLabels(t *testing.T) {
	tests := []struct {
		mode reverselookup.Mode
		want string
	}{
		{mode: reverselookup.ModeVariable, want: "变长模式"},
		{mode: reverselookup.ModeFull, want: "等长模式"},
		{mode: reverselookup.ModeShorthand, want: "省键模式"},
		{mode: reverselookup.Mode("custom"), want: "custom"},
	}
	for _, test := range tests {
		if got := modeDisplayName(test.mode); got != test.want {
			t.Fatalf("modeDisplayName(%q) = %q, want %q", test.mode, got, test.want)
		}
	}
}

func TestNoticeTitleForFlags(t *testing.T) {
	tests := []struct {
		flags uintptr
		want  string
	}{
		{flags: 0x10, want: "操作失败"},
		{flags: 0x30, want: "提示"},
		{flags: 0x40, want: "操作完成"},
		{flags: 0, want: "词库管理"},
	}
	for _, test := range tests {
		if got := noticeTitleForFlags(test.flags); got != test.want {
			t.Fatalf("noticeTitleForFlags(%#x) = %q, want %q", test.flags, got, test.want)
		}
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

func TestLexiconInfoRowsAreVerticallySeparated(t *testing.T) {
	layout := buildLexiconInfoLayout(8, 772, 440)
	rows := []rect{layout.list, layout.selection, layout.status}
	for index := 1; index < len(rows); index++ {
		if rows[index].Top <= rows[index-1].Bottom {
			t.Fatalf("rows %d and %d overlap: %#v", index-1, index, rows)
		}
	}
	if layout.status.Top-layout.selection.Bottom > 8 {
		t.Fatalf("removed path row must not leave unused vertical space: %#v", layout)
	}
}

func TestLexiconInfoLayoutExpandsWithClientHeight(t *testing.T) {
	compact := buildLexiconInfoLayout(8, 772, 440)
	expanded := buildLexiconInfoLayout(8, 772, 640)
	if expanded.list.Bottom-compact.list.Bottom != 200 {
		t.Fatalf("list height did not follow client height: compact=%#v expanded=%#v", compact, expanded)
	}
	if expanded.status.Bottom != 624 {
		t.Fatalf("status row must stay near the client bottom: %#v", expanded.status)
	}
}

func TestLexiconColumnsGiveExtraWidthToPinyin(t *testing.T) {
	compact := lexiconColumnWidths(764)
	expanded := lexiconColumnWidths(964)
	if expanded[0] != compact[0] || expanded[2] != compact[2] {
		t.Fatalf("phrase and weight columns should remain stable: compact=%v expanded=%v", compact, expanded)
	}
	if expanded[1]-compact[1] != 200 {
		t.Fatalf("extra width should go to pinyin: compact=%v expanded=%v", compact, expanded)
	}
}

func TestLexiconToolbarPlacesEditBeforeAdd(t *testing.T) {
	items := lexiconToolbarItems()
	if len(items) < 2 || items[0].id != idBtnEdit || items[1].id != idBtnAdd {
		t.Fatalf("toolbar must begin with edit then add: %#v", items)
	}
}

func TestLexiconToolbarNamesDocumentsButton(t *testing.T) {
	items := lexiconToolbarItems()
	last := items[len(items)-1]
	if last.id != idBtnOpenFolder || last.text != "文档" {
		t.Fatalf("last toolbar item must open Documents: %#v", last)
	}
}

func TestToolbarButtonsKeepDefaultLayoutAndCapExpandedWidth(t *testing.T) {
	compact := toolbarButtonRects(8, 772, 8)
	if compact[0].Left-8 > 1 || 772-compact[len(compact)-1].Right > 1 {
		t.Fatalf("default toolbar should fill the original row: %#v", compact)
	}
	expanded := toolbarButtonRects(8, 1172, 8)
	for _, box := range expanded {
		if box.Right-box.Left != 96 {
			t.Fatalf("expanded toolbar button must be capped at 96 px: %#v", expanded)
		}
	}
	leftGap := expanded[0].Left - 8
	rightGap := 1172 - expanded[len(expanded)-1].Right
	if leftGap-rightGap > 1 || rightGap-leftGap > 1 {
		t.Fatalf("expanded toolbar must remain centered: left=%d right=%d", leftGap, rightGap)
	}
}

func TestAddDialogOffersCloseAndContinueSaveActions(t *testing.T) {
	choices := entryDialogChoices(true, "保存")
	want := []string{"保存并关闭", "保存并继续", "取消"}
	if len(choices) != len(want) {
		t.Fatalf("add dialog choices = %#v", choices)
	}
	for index, label := range want {
		if choices[index].Label != label {
			t.Fatalf("choice %d = %q, want %q", index, choices[index].Label, label)
		}
	}
}

func TestEditDialogKeepsSingleSaveAction(t *testing.T) {
	choices := entryDialogChoices(false, "保存")
	if len(choices) != 2 || choices[0].Label != "保存" || choices[1].Label != "取消" {
		t.Fatalf("edit dialog choices = %#v", choices)
	}
}

func TestUndoButtonUsesConciseOperationLabel(t *testing.T) {
	cases := map[string]string{
		"":            "撤销",
		"删除词条":        "撤销删除",
		"编辑词条":        "撤销编辑",
		"添加/更新词条":     "撤销添加",
		"导入词库（合并）":    "撤销导入",
		"尚未分类的内部操作名称": "撤销操作",
	}
	for label, want := range cases {
		if got := undoButtonText(label); got != want {
			t.Fatalf("undoButtonText(%q) = %q, want %q", label, got, want)
		}
	}
}

func TestApplyProgressSharesStatusRowOnlyWhileBusy(t *testing.T) {
	status := rect{Left: 8, Top: 400, Right: 772, Bottom: 424}
	idleText, idleProgress := statusProgressLayout(status, false)
	if idleText != status || idleProgress != (rect{}) {
		t.Fatalf("idle status layout changed: text=%#v progress=%#v", idleText, idleProgress)
	}
	busyText, busyProgress := statusProgressLayout(status, true)
	if busyProgress.Right != status.Right || busyProgress.Right-busyProgress.Left != 180 {
		t.Fatalf("unexpected progress layout: %#v", busyProgress)
	}
	if busyText.Right >= busyProgress.Left {
		t.Fatalf("status and progress overlap: text=%#v progress=%#v", busyText, busyProgress)
	}
}

func TestExistingImportFileOffersDirectAndAlternatePaths(t *testing.T) {
	choices := existingImportFileChoices()
	want := []string{"使用现有", "另存副本", "选择其他", "取消"}
	if len(choices) != len(want) {
		t.Fatalf("import choices = %#v", choices)
	}
	for index, label := range want {
		if choices[index].Label != label {
			t.Fatalf("choice %d = %q, want %q", index, choices[index].Label, label)
		}
	}
}

func TestLexiconColumnsRestoreOriginalFields(t *testing.T) {
	columns := lexiconColumns()
	want := []string{"词条", "数字标调拼音", "权重"}
	if len(columns) != len(want) {
		t.Fatalf("column count = %d, want %d", len(columns), len(want))
	}
	for index, title := range want {
		if columns[index].title != title {
			t.Fatalf("column %d title = %q, want %q", index, columns[index].title, title)
		}
		if columns[index].width <= 0 {
			t.Fatalf("column %d must have a positive width", index)
		}
	}
}
