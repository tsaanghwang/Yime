//go:build windows

package main

import (
	"path/filepath"
	"slices"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolhub"
)

func TestExperimentalToolHubUsesIndependentIdentityAndIsolatedManifest(t *testing.T) {
	if got := toolHubWindowClass(false); got != "YimeToolHub" {
		t.Fatalf("production tool hub class=%q", got)
	}
	if got := toolHubWindowClass(true); got != "YimeCoreTrialToolHub" {
		t.Fatalf("trial tool hub class=%q", got)
	}
	if got := toolHubWindowTitle(true, "ignored"); got != "Yime 试验版工具中心" {
		t.Fatalf("trial tool hub title=%q", got)
	}

	installRoot := filepath.Join(`C:\Program Files`, "YimeCore Experimental Trial", "package")
	stateRoot := filepath.Join(`C:\Users\tester`, "AppData", "Local", "YimeCore Experimental Trial")
	statePath := filepath.Join(stateRoot, "yimecore_experimental_toolbar_state.json")
	manifest, err := buildExperimentalManifest(installRoot, stateRoot, statePath, "shorthand")
	if err != nil {
		t.Fatal(err)
	}
	if manifest.Title != "Yime 试验版工具中心" || len(manifest.Tools) != 6 {
		t.Fatalf("trial manifest=%#v", manifest)
	}
	entries := map[string]toolhub.Entry{}
	for _, entry := range manifest.Tools {
		entries[entry.ID] = entry
	}
	for _, id := range []string{"typing-trainer", "lexicon-manager", "reverse-lookup-tool", "settings-tool", "trial-user-data", "trial-shared-data"} {
		if _, ok := entries[id]; !ok {
			t.Fatalf("trial manifest missing %q", id)
		}
	}
	for _, id := range []string{"typing-trainer", "lexicon-manager", "reverse-lookup-tool", "settings-tool"} {
		entry := entries[id]
		if filepath.Dir(entry.TargetPath) != filepath.Join(installRoot, "bin") {
			t.Fatalf("%s escaped Trial bin: %#v", id, entry)
		}
	}
	if !slices.Contains(entries["typing-trainer"].Arguments, "-Experimental") ||
		!slices.Contains(entries["lexicon-manager"].Arguments, "-Experimental") ||
		!slices.Contains(entries["settings-tool"].Arguments, "-Experimental") {
		t.Fatalf("Trial identity flags missing: %#v", entries)
	}
	if !slices.Contains(entries["typing-trainer"].Arguments, "shorthand") ||
		!slices.Contains(entries["reverse-lookup-tool"].Arguments, "shorthand") {
		t.Fatalf("Trial mode missing: %#v", entries)
	}
	if entries["trial-user-data"].TargetPath != stateRoot ||
		entries["trial-shared-data"].TargetPath != filepath.Join(installRoot, "data") {
		t.Fatalf("Trial directories escaped isolation: %#v", entries)
	}
}

func TestToolHubButtonsFormAlignedTwoColumnGrid(t *testing.T) {
	boxes := toolHubButtonRects(620, toolHubMinimumClientHeight(10), 10)
	if len(boxes) != 10 {
		t.Fatalf("expected ten tool buttons, got %d", len(boxes))
	}
	if boxes[0].Left != 16 || boxes[1].Right != 604 {
		t.Fatalf("button grid must align with both content edges: %#v", boxes[:2])
	}
	leftWidth := boxes[0].Right - boxes[0].Left
	rightWidth := boxes[1].Right - boxes[1].Left
	if leftWidth != rightWidth {
		t.Fatalf("columns must be symmetric: left=%d right=%d", leftWidth, rightWidth)
	}
	for index := 2; index < len(boxes); index++ {
		if boxes[index].Left != boxes[index%2].Left || boxes[index].Right != boxes[index%2].Right {
			t.Fatalf("button %d is not column-aligned: %#v", index, boxes[index])
		}
	}
}

func TestToolHubButtonsExpandAndStayVerticallyCentered(t *testing.T) {
	compact := toolHubButtonRects(620, toolHubMinimumClientHeight(10), 10)
	expanded := toolHubButtonRects(820, toolHubMinimumClientHeight(10)+120, 10)
	if expanded[0].Right-expanded[0].Left <= compact[0].Right-compact[0].Left {
		t.Fatal("buttons should expand with the window width")
	}
	if expanded[0].Top <= compact[0].Top {
		t.Fatal("button grid should remain vertically centered in a taller window")
	}
	if expanded[len(expanded)-1].Bottom >= toolHubMinimumClientHeight(10)+120 {
		t.Fatal("expanded grid must stay inside the client area")
	}
}

func TestToolHubOddEntryCountKeepsLastButtonInLeftColumn(t *testing.T) {
	boxes := toolHubButtonRects(620, toolHubMinimumClientHeight(9), 9)
	if len(boxes) != 9 || boxes[8].Left != boxes[0].Left {
		t.Fatalf("odd final entry should occupy the left column: %#v", boxes)
	}
}
