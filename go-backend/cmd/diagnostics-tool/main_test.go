//go:build windows

package main

import (
	"path/filepath"
	"testing"
)

func TestExperimentalDiagnosticsUsesIndependentIdentityAndLogs(t *testing.T) {
	if got := diagnosticsWindowClass(false); got != "YimeDiagnosticsTool" {
		t.Fatalf("production diagnostics class=%q", got)
	}
	if got := diagnosticsWindowClass(true); got != "YimeCoreTrialDiagnosticsTool" {
		t.Fatalf("Trial diagnostics class=%q", got)
	}
	if got := diagnosticsWindowTitle(true); got != "Yime 试验版诊断" {
		t.Fatalf("Trial diagnostics title=%q", got)
	}
	stateRoot := filepath.Join(`C:\Users\tester`, "AppData", "Local", "YimeCore Experimental Trial")
	if got := diagnosticsLogDirectory(stateRoot, true); got != filepath.Join(stateRoot, "logs") {
		t.Fatalf("Trial diagnostics log dir=%q", got)
	}
}

func TestDiagnosticsUILayoutUsesEqualCenteredRows(t *testing.T) {
	l := buildDiagnosticsUILayout()
	contentCenter := (l.statusView.Left + l.statusView.Right) / 2

	for index := 1; index < len(l.optionBoxes); index++ {
		if width(l.optionBoxes[index]) != width(l.optionBoxes[0]) {
			t.Fatalf("option %d width=%d, want %d", index, width(l.optionBoxes[index]), width(l.optionBoxes[0]))
		}
	}
	for index := 1; index < len(l.buttons); index++ {
		if width(l.buttons[index]) != width(l.buttons[0]) {
			t.Fatalf("button %d width=%d, want %d", index, width(l.buttons[index]), width(l.buttons[0]))
		}
	}
	if rowCenter(l.optionBoxes[0], l.optionBoxes[3]) != contentCenter {
		t.Fatalf("option row is not centered in the report width")
	}
	if rowCenter(l.buttons[0], l.buttons[3]) != contentCenter {
		t.Fatalf("button row is not centered in the report width")
	}
	if width(l.description) != width(l.statusView) {
		t.Fatalf("description width=%d, report width=%d", width(l.description), width(l.statusView))
	}
	if l.clientW != l.statusView.Right+16 {
		t.Fatalf("client width=%d should fit content right edge=%d", l.clientW, l.statusView.Right)
	}
}

func width(box rect) int32 {
	return box.Right - box.Left
}

func rowCenter(first, last rect) int32 {
	return (first.Left + last.Right) / 2
}
