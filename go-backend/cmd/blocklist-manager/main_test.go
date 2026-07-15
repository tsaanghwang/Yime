//go:build windows

package main

import "testing"

func TestBlocklistToolbarIsCenteredAndComplete(t *testing.T) {
	items := toolbarItems()
	layout := buildLayout(680, 480)
	if len(items) != 6 || len(layout.toolbar) != 6 {
		t.Fatalf("toolbar mismatch: items=%#v layout=%#v", items, layout.toolbar)
	}
	left := layout.toolbar[0].Left
	right := 680 - layout.toolbar[len(layout.toolbar)-1].Right
	if left-right > 1 || right-left > 1 {
		t.Fatalf("toolbar not centered: left=%d right=%d", left, right)
	}
	if items[2].id != idBtnUndo {
		t.Fatalf("undo must follow delete: %#v", items)
	}
}

func TestBlocklistLayoutExpandsList(t *testing.T) {
	compact := buildLayout(680, 480)
	expanded := buildLayout(880, 680)
	if expanded.list.Bottom-compact.list.Bottom != 200 {
		t.Fatalf("list did not absorb height")
	}
	if expanded.searchEdit.Right-compact.searchEdit.Right != 200 {
		t.Fatalf("search did not absorb width")
	}
	if expanded.selection.Top <= expanded.list.Bottom || expanded.status.Top <= expanded.selection.Bottom {
		t.Fatalf("rows overlap: %#v", expanded)
	}
}

func TestBlocklistColumnAndUndoLabels(t *testing.T) {
	if blocklistColumnTitle != "屏蔽词" {
		t.Fatalf("unexpected column title %q", blocklistColumnTitle)
	}
	if undoButtonText("") != "撤销" || undoButtonText("删除") != "撤销删除" || undoButtonText("导入") != "撤销导入" {
		t.Fatalf("unexpected undo labels")
	}
}
