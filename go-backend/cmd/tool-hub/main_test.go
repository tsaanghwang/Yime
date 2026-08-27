//go:build windows

package main

import (
	"path/filepath"
	"slices"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolhub"
)

func TestExperimentalToolHubUsesIndependentIdentityAndIsolatedManifest(t *testing.T) {
	if got := toolHubWindowClass(false, false); got != "YimeToolHub" {
		t.Fatalf("production tool hub class=%q", got)
	}
	if got := toolHubWindowClass(true, false); got != "YimeCoreTrialToolHub" {
		t.Fatalf("trial tool hub class=%q", got)
	}
	if got := toolHubWindowTitle(true, false, "ignored"); got != "Yime 试验版工具中心" {
		t.Fatalf("trial tool hub title=%q", got)
	}

	installRoot := filepath.Join(`C:\Program Files`, "YimeCore Experimental Trial", "package")
	stateRoot := filepath.Join(`C:\Users\tester`, "AppData", "Local", "YimeCore Experimental Trial")
	statePath := filepath.Join(stateRoot, "yimecore_experimental_toolbar_state.json")
	manifest, err := buildExperimentalManifest(installRoot, stateRoot, statePath, "shorthand")
	if err != nil {
		t.Fatal(err)
	}
	if manifest.Title != "Yime 试验版工具中心" || len(manifest.Tools) != 10 {
		t.Fatalf("trial manifest=%#v", manifest)
	}
	entries := map[string]toolhub.Entry{}
	for _, entry := range manifest.Tools {
		entries[entry.ID] = entry
	}
	for _, id := range []string{"typing-trainer", "keyboard-layout", "lexicon-center", "reverse-lookup-tool", "settings-tool", "diagnostics-tool", "trial-user-data", "trial-shared-data", "usage-help", "user-feedback"} {
		if _, ok := entries[id]; !ok {
			t.Fatalf("trial manifest missing %q", id)
		}
	}
	for _, id := range []string{"typing-trainer", "keyboard-layout", "lexicon-center", "reverse-lookup-tool", "settings-tool", "diagnostics-tool"} {
		entry := entries[id]
		if filepath.Dir(entry.TargetPath) != filepath.Join(installRoot, "bin") {
			t.Fatalf("%s escaped Trial bin: %#v", id, entry)
		}
	}
	if entries["keyboard-layout"].Label != "键盘布局" || entries["lexicon-center"].Label != "词库管理" ||
		entries["diagnostics-tool"].Label != "诊断工具" ||
		entries["usage-help"].Label != "使用帮助" || entries["user-feedback"].Label != "用户反馈" {
		t.Fatalf("Trial labels were not migrated: %#v", entries)
	}
	if !slices.Contains(entries["typing-trainer"].Arguments, "-Experimental") ||
		!slices.Contains(entries["keyboard-layout"].Arguments, "-Experimental") ||
		!slices.Contains(entries["lexicon-center"].Arguments, "-Experimental") ||
		!slices.Contains(entries["lexicon-center"].Arguments, "-LexiconCenter") ||
		!slices.Contains(entries["settings-tool"].Arguments, "-Experimental") ||
		!slices.Contains(entries["diagnostics-tool"].Arguments, "-Experimental") {
		t.Fatalf("Trial identity flags missing: %#v", entries)
	}
	for _, required := range []string{installRoot, stateRoot, filepath.Join(installRoot, "data"), filepath.Join(installRoot, "indexes"), "shorthand"} {
		if !slices.Contains(entries["lexicon-center"].Arguments, required) {
			t.Fatalf("Trial lexicon center missing %q: %#v", required, entries["lexicon-center"])
		}
	}
	if !slices.Contains(entries["typing-trainer"].Arguments, "shorthand") ||
		!slices.Contains(entries["reverse-lookup-tool"].Arguments, "shorthand") {
		t.Fatalf("Trial mode missing: %#v", entries)
	}
	if !slices.Contains(entries["settings-tool"].Arguments, filepath.Join(installRoot, "help")) {
		t.Fatalf("Trial settings tool is missing its isolated help directory: %#v", entries["settings-tool"])
	}
	if entries["trial-user-data"].TargetPath != stateRoot ||
		entries["trial-shared-data"].TargetPath != filepath.Join(installRoot, "data") {
		t.Fatalf("Trial directories escaped isolation: %#v", entries)
	}
	if entries["usage-help"].TargetPath != filepath.Join(installRoot, "help", "README.html") ||
		entries["user-feedback"].TargetPath != filepath.Join(installRoot, "help", "trial-feedback.html") {
		t.Fatalf("Trial help escaped installed help root: %#v", entries)
	}
}

func TestExperimentalLexiconCenterHasSixIsolatedEntries(t *testing.T) {
	installRoot := filepath.Join(`C:\Program Files`, "YimeCore Experimental Trial", "package")
	userDir := filepath.Join(`C:\Users\tester`, "AppData", "Local", "YimeCore Experimental Trial")
	sharedDir := filepath.Join(userDir, "layout", "generations", "layout-v2", "data")
	indexRoot := filepath.Join(userDir, "layout", "generations", "layout-v2", "indexes")
	manifest, err := buildExperimentalLexiconManifest(installRoot, userDir, sharedDir, indexRoot, "full")
	if err != nil {
		t.Fatal(err)
	}
	if got := toolHubWindowClass(true, true); got != "YimeCoreTrialLexiconCenter" {
		t.Fatalf("lexicon center class=%q", got)
	}
	if got := toolHubWindowTitle(true, true, "ignored"); got != "Yime 试验版词库管理" {
		t.Fatalf("lexicon center title=%q", got)
	}
	want := []string{"用户词库管理", "用户屏蔽词语", "自学词语管理", "内置词库审查", "高频新词扫描", "专业词库加载"}
	if len(manifest.Tools) != len(want) {
		t.Fatalf("lexicon tools=%#v", manifest.Tools)
	}
	for index, entry := range manifest.Tools {
		if entry.Label != want[index] {
			t.Fatalf("tool %d label=%q, want %q", index, entry.Label, want[index])
		}
		if filepath.Dir(entry.TargetPath) != filepath.Join(installRoot, "bin") || !slices.Contains(entry.Arguments, "-Experimental") {
			t.Fatalf("tool %d escaped Trial identity: %#v", index, entry)
		}
		for _, argument := range entry.Arguments {
			if slices.Contains([]string{`C:\Program Files (x86)\YIME`, `C:\Users\tester\AppData\Roaming\PIME\Rime`}, argument) {
				t.Fatalf("tool %d references production data: %#v", index, entry)
			}
		}
	}
	entries := map[string]toolhub.Entry{}
	for _, entry := range manifest.Tools {
		entries[entry.ID] = entry
	}
	for id, required := range map[string][]string{
		"user-blocklist-manager":       {userDir},
		"self-learning-manager":        {installRoot, userDir, indexRoot, "full"},
		"system-lexicon-audit":         {userDir, sharedDir, indexRoot, "full"},
		"lexicon-promotion-scan":       {installRoot, userDir, indexRoot, "full"},
		"professional-lexicon-manager": {installRoot, userDir, indexRoot, "full"},
	} {
		for _, argument := range required {
			if !slices.Contains(entries[id].Arguments, argument) {
				t.Fatalf("%s missing Trial argument %q: %#v", id, argument, entries[id])
			}
		}
	}
	if filepath.Base(entries["lexicon-promotion-scan"].TargetPath) != "YimeCorePromotionScan.exe" ||
		filepath.Base(entries["professional-lexicon-manager"].TargetPath) != "YimeCoreProfessionalLexicon.exe" {
		t.Fatalf("Trial lexicon executable contract mismatch: %#v", entries)
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
