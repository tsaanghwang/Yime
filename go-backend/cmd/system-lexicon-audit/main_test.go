//go:build windows

package main

import "testing"

func TestAuditColumnsExposeReviewFields(t *testing.T) {
	columns := auditColumns()
	want := []string{"规则", "词条", "编码", "权重"}
	if len(columns) != len(want) {
		t.Fatalf("columns = %#v", columns)
	}
	for index, title := range want {
		if columns[index].title != title {
			t.Fatalf("column %d = %q, want %q", index, columns[index].title, title)
		}
	}
}

func TestAuditLayoutCentersFiltersAndExpandsList(t *testing.T) {
	compact := buildUILayoutForSize(820, 600)
	expanded := buildUILayoutForSize(1020, 800)
	leftGap := compact.ruleLabel.Left - 12
	rightGap := (820 - 12) - compact.exportButton.Right
	if leftGap-rightGap > 1 || rightGap-leftGap > 1 {
		t.Fatalf("filter row is not centered: left=%d right=%d", leftGap, rightGap)
	}
	if expanded.resultList.Bottom-compact.resultList.Bottom != 200 {
		t.Fatalf("result list did not absorb height: compact=%#v expanded=%#v", compact.resultList, expanded.resultList)
	}
	if expanded.searchEdit.Right-compact.searchEdit.Right != 200 {
		t.Fatalf("search box did not absorb width")
	}
}

func TestAuditCodeColumnAbsorbsExtraWidth(t *testing.T) {
	compact := auditColumnWidths(796)
	expanded := auditColumnWidths(996)
	if expanded[2]-compact[2] != 200 {
		t.Fatalf("code column should absorb width: compact=%v expanded=%v", compact, expanded)
	}
	for _, index := range []int{0, 1, 3} {
		if compact[index] != expanded[index] {
			t.Fatalf("column %d should remain stable", index)
		}
	}
}

func TestAuditProgressSharesStatusRow(t *testing.T) {
	status := rect{12, 560, 808, 588}
	idle, none := statusProgressLayout(status, false)
	if idle != status || none != (rect{}) {
		t.Fatalf("idle layout changed")
	}
	busy, progress := statusProgressLayout(status, true)
	if progress.Right != status.Right || busy.Right >= progress.Left {
		t.Fatalf("status overlaps progress: %#v %#v", busy, progress)
	}
}
