//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/runtimechange"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userbackup"
)

func TestExecuteTrialApplyUsesOnlyIsolatedToolbarState(t *testing.T) {
	path := filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName)
	_, err := toolbarstate.Update(path, "test", func(state *toolbarstate.State) bool {
		state.ASCII = true
		return true
	})
	if err != nil {
		t.Fatal(err)
	}
	err = executeTrialApply(path, trialApplyRequest{
		mode: toolbarstate.ExperimentModeFull, pageSize: 7, layout: toolbarstate.CandidateLayoutHorizontal,
		font:       toolbarstate.CandidateFontLarge,
		fontFamily: toolbarstate.CandidateFontSystemUI,
		annotation: toolbarstate.AnnotationStandardPinyin,
	})
	if err != nil {
		t.Fatal(err)
	}
	state, err := toolbarstate.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.ExperimentMode != toolbarstate.ExperimentModeFull ||
		state.CandidatePageSize != 7 || state.CandidateLayout != toolbarstate.CandidateLayoutHorizontal ||
		state.CandidateFontPreset != toolbarstate.CandidateFontLarge ||
		state.CandidateFontFamily != toolbarstate.CandidateFontSystemUI ||
		state.CandidateAnnotation != toolbarstate.AnnotationStandardPinyin || !state.ASCII {
		t.Fatalf("trial settings mismatch: %+v", state)
	}
}

func TestTrialCandidateFontOptionsIncludeRequiredYinyuanFont(t *testing.T) {
	options := trialFontFamilyOptions()
	if len(options) != 3 || options[0].Value != toolbarstate.CandidateFontMicrosoftYaHeiUI ||
		options[1].Value != toolbarstate.CandidateFontSystemUI ||
		options[2].Value != toolbarstate.CandidateFontYinyuan ||
		options[2].Label != "音元自制字体（音元拼音时强制）" {
		t.Fatalf("candidate font options = %#v", options)
	}
}

func TestTrialCandidateFontPresetOptionsUseRuntimeValues(t *testing.T) {
	options := trialFontPresetOptions()
	if len(options) != 3 ||
		options[0].Label != "小（10 磅）" || options[0].Value != toolbarstate.CandidateFontSmall ||
		options[1].Label != "中（12 磅）" || options[1].Value != toolbarstate.CandidateFontMedium ||
		options[2].Label != "大（16 磅）" || options[2].Value != toolbarstate.CandidateFontLarge {
		t.Fatalf("candidate font preset options = %#v", options)
	}
}

func TestTrialAnnotationOptionNamesYinyuanPinyin(t *testing.T) {
	options := trialAnnotationOptions()
	if len(options) < 2 || options[1].Value != toolbarstate.AnnotationYinyuan ||
		options[1].Label != "音元拼音" {
		t.Fatalf("candidate annotation options = %#v", options)
	}
}

func TestSettingsUILayoutFitsVisibleControls(t *testing.T) {
	withoutHelp := buildSettingsUILayout(false, false)
	withHelp := buildSettingsUILayout(true, false)

	if withoutHelp.clientW != withoutHelp.layoutCombo.Right+16 {
		t.Fatalf("window should fit the widest visible row: width=%d right=%d", withoutHelp.clientW, withoutHelp.layoutCombo.Right)
	}
	if withHelp.clientW != withHelp.openHelpButton.Right+16 {
		t.Fatalf("optional help should fit inside the settings width: width=%d right=%d", withHelp.clientW, withHelp.openHelpButton.Right)
	}
	if withHelp.clientH != withHelp.applyButton.Bottom+16 {
		t.Fatalf("window should fit the button row: height=%d bottom=%d", withHelp.clientH, withHelp.applyButton.Bottom)
	}
	if withoutHelp.applyButton.Right >= withoutHelp.backupButton.Left || withoutHelp.backupButton.Right >= withoutHelp.restoreButton.Left {
		t.Fatal("apply, backup, and restore buttons must be separate and ordered")
	}
	if gap := withHelp.applyButton.Top - withHelp.layoutLabel.Bottom; gap < 8 || gap > 24 {
		t.Fatalf("button row should be compact below the final setting row, gap=%d", gap)
	}
	if withHelp.openHelpButton.Right > withHelp.clientW-16 {
		t.Fatal("the optional help button must stay inside the content area")
	}
	if withHelp.clientW >= 820 || withHelp.clientH >= 680 {
		t.Fatalf("content-sized layout should be smaller than the former fixed client area: %dx%d", withHelp.clientW, withHelp.clientH)
	}
}

func TestSettingsUILayoutReplacesOpenDirectoryWithBackupAndRestore(t *testing.T) {
	layout := buildSettingsUILayout(true, false)
	if layout.backupButton.Right <= layout.backupButton.Left || layout.restoreButton.Right <= layout.restoreButton.Left {
		t.Fatal("backup and restore buttons must both be visible")
	}
	if layout.restoreButton.Right >= layout.openHelpButton.Left {
		t.Fatal("restore button must not overlap settings help")
	}
	buttons := []rect{layout.applyButton, layout.backupButton, layout.restoreButton, layout.openHelpButton}
	if buttons[0].Left != layout.schemaLabel.Left || buttons[len(buttons)-1].Right != layout.layoutCombo.Right {
		t.Fatalf("button row must align with content edges: %#v", buttons)
	}
	wantWidth := buttons[0].Right - buttons[0].Left
	for index, button := range buttons {
		if button.Right-button.Left != wantWidth {
			t.Fatalf("button %d is not equally sized: %#v", index, buttons)
		}
	}
	if layout.restoreButton.Left-layout.backupButton.Right != 8 ||
		(layout.backupButton.Left+layout.restoreButton.Right)/2 !=
			(layout.schemaLabel.Left+layout.layoutCombo.Right)/2 {
		t.Fatalf("backup and restore are not a centered compact pair: %#v", buttons)
	}
}

func TestTrialSettingsUILayoutMergesProductionAndTrialControls(t *testing.T) {
	layout := buildSettingsUILayout(true, true)
	rows := []struct {
		label rect
		combo rect
	}{
		{layout.schemaLabel, layout.schemaCombo},
		{layout.pageLabel, layout.pageCombo},
		{layout.reverseLabel, layout.reverseCombo},
		{layout.layoutLabel, layout.layoutCombo},
		{layout.fontLabel, layout.fontCombo},
		{layout.familyLabel, layout.familyCombo},
	}
	for index, row := range rows {
		if row.label.Right <= row.label.Left || row.combo.Right <= row.combo.Left {
			t.Fatalf("trial settings row %d is not visible: %#v", index, row)
		}
		if index > 0 && row.label.Top <= rows[index-1].label.Bottom {
			t.Fatalf("trial settings rows %d and %d overlap: %#v", index-1, index, rows)
		}
	}
	if layout.applyButton.Top <= layout.familyLabel.Bottom || layout.clientH != layout.applyButton.Bottom+16 {
		t.Fatalf("trial button row does not follow all merged controls: %#v", layout)
	}
	buttonsCenter := (layout.backupButton.Left + layout.restoreButton.Right) / 2
	contentCenter := (layout.schemaLabel.Left + layout.layoutCombo.Right) / 2
	if buttonsCenter != contentCenter || layout.restoreButton.Left-layout.backupButton.Right != 8 {
		t.Fatalf("backup and restore must form a centered compact pair: %#v", layout)
	}
}

func TestExecuteApplyNotifiesActiveSession(t *testing.T) {
	oldApply := applySettings
	oldNotify := notifyRuntimeChange
	defer func() {
		applySettings = oldApply
		notifyRuntimeChange = oldNotify
	}()

	applySettings = func(userDir, sharedDir, schemaID string, pageSize int, reverseMode, layout string, runBuild bool) error {
		if userDir != "user" || sharedDir != "shared" || schemaID != "yime_full" || pageSize != 7 || reverseMode != "hidden" || layout != "vertical" || !runBuild {
			t.Fatalf("unexpected apply request: %q %q %q %d %q %q %t", userDir, sharedDir, schemaID, pageSize, reverseMode, layout, runBuild)
		}
		return nil
	}
	notified := false
	notifyRuntimeChange = func(userDir, scope string, requiresRedeploy bool) (runtimechange.Event, error) {
		notified = true
		if userDir != "user" || scope != runtimechange.ScopeSettings || !requiresRedeploy {
			t.Fatalf("unexpected notification: %q %q %t", userDir, scope, requiresRedeploy)
		}
		return runtimechange.Event{}, nil
	}

	err := executeApply("user", "shared", applyRequest{schemaID: "yime_full", pageSize: 7, reverseMode: "hidden", layout: "vertical"})
	if err != nil {
		t.Fatal(err)
	}
	if !notified {
		t.Fatal("expected active-session notification")
	}
}

func TestExecuteApplyForwardsBothCodeDisplaysForEveryInputSchema(t *testing.T) {
	oldApply := applySettings
	oldNotify := notifyRuntimeChange
	defer func() {
		applySettings = oldApply
		notifyRuntimeChange = oldNotify
	}()

	var gotSchema, gotReverse string
	applySettings = func(_, _ string, schemaID string, _ int, reverseMode, _ string, _ bool) error {
		gotSchema, gotReverse = schemaID, reverseMode
		return nil
	}
	notifyRuntimeChange = func(string, string, bool) (runtimechange.Event, error) {
		return runtimechange.Event{}, nil
	}

	for _, schemaID := range []string{"yime_variable", "yime_full", "yime_shorthand"} {
		for _, reverseMode := range []string{"yime_pinyin", "key_sequence"} {
			if err := executeApply("user", "shared", applyRequest{
				schemaID: schemaID, pageSize: 5, reverseMode: reverseMode, layout: "vertical",
			}); err != nil {
				t.Fatal(err)
			}
			if gotSchema != schemaID || gotReverse != reverseMode {
				t.Fatalf("settings tool forwarded schema=%q display=%q, want %q/%q", gotSchema, gotReverse, schemaID, reverseMode)
			}
		}
	}
}

func TestExecuteApplyDoesNotNotifyAfterApplyFailure(t *testing.T) {
	oldApply := applySettings
	oldNotify := notifyRuntimeChange
	defer func() {
		applySettings = oldApply
		notifyRuntimeChange = oldNotify
	}()
	want := errors.New("build failed")
	applySettings = func(string, string, string, int, string, string, bool) error { return want }
	notifyRuntimeChange = func(string, string, bool) (runtimechange.Event, error) {
		t.Fatal("notification must not run after apply failure")
		return runtimechange.Event{}, nil
	}
	if err := executeApply("user", "shared", applyRequest{}); !errors.Is(err, want) {
		t.Fatalf("expected %v, got %v", want, err)
	}
}

func TestExecuteRestoreCreatesSafetyBackupRebuildsAndNotifiesBothScopes(t *testing.T) {
	oldBuild := invokeRimeBuild
	oldNotify := notifyRuntimeChange
	defer func() {
		invokeRimeBuild = oldBuild
		notifyRuntimeChange = oldNotify
	}()

	backupSource := t.TempDir()
	if err := os.WriteFile(filepath.Join(backupSource, "default.custom.yaml"), []byte("restored"), 0o644); err != nil {
		t.Fatal(err)
	}
	backupRoot := t.TempDir()
	snapshot, err := userbackup.Create(backupSource, backupRoot, "用户数据", time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	live := t.TempDir()
	if err := os.WriteFile(filepath.Join(live, "default.custom.yaml"), []byte("current"), 0o644); err != nil {
		t.Fatal(err)
	}

	built := false
	invokeRimeBuild = func(userDir, sharedDir string) error {
		built = userDir == live && sharedDir == "shared"
		return nil
	}
	var scopes []string
	notifyRuntimeChange = func(userDir, scope string, requiresRedeploy bool) (runtimechange.Event, error) {
		if userDir != live || !requiresRedeploy {
			t.Fatalf("unexpected restore notification: %q %q %t", userDir, scope, requiresRedeploy)
		}
		scopes = append(scopes, scope)
		return runtimechange.Event{}, nil
	}

	safety, err := executeRestore(live, "shared", backupRoot, snapshot, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if safety.Path == "" || safety.Manifest.Purpose != "pre-restore-safety" {
		t.Fatalf("expected pre-restore safety snapshot, got %#v", safety)
	}
	if !built {
		t.Fatal("restore must rebuild Rime")
	}
	if len(scopes) != 2 || scopes[0] != runtimechange.ScopeSettings || scopes[1] != runtimechange.ScopeLexicon {
		t.Fatalf("restore must notify settings and lexicon, got %#v", scopes)
	}
	data, err := os.ReadFile(filepath.Join(live, "default.custom.yaml"))
	if err != nil || string(data) != "restored" {
		t.Fatalf("restored config mismatch: %q, %v", data, err)
	}
}

func TestExecuteTrialRestoreStaysIndependentFromRime(t *testing.T) {
	oldBuild := invokeRimeBuild
	oldNotify := notifyRuntimeChange
	defer func() {
		invokeRimeBuild = oldBuild
		notifyRuntimeChange = oldNotify
	}()
	invokeRimeBuild = func(string, string) error {
		t.Fatal("Trial restore must not rebuild production Rime")
		return nil
	}
	notifyRuntimeChange = func(string, string, bool) (runtimechange.Event, error) {
		t.Fatal("Trial restore must not notify the production runtime")
		return runtimechange.Event{}, nil
	}

	backupSource := t.TempDir()
	if err := os.WriteFile(filepath.Join(backupSource, toolbarstate.ExperimentFileName), []byte("restored"), 0o644); err != nil {
		t.Fatal(err)
	}
	backupRoot := t.TempDir()
	snapshot, err := userbackup.Create(backupSource, backupRoot, "试验版用户数据", time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	live := t.TempDir()
	if err := os.WriteFile(filepath.Join(live, toolbarstate.ExperimentFileName), []byte("current"), 0o644); err != nil {
		t.Fatal(err)
	}
	safety, err := executeTrialRestore(live, backupRoot, snapshot, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if safety.Manifest.Purpose != "pre-restore-safety" {
		t.Fatalf("Trial restore did not create a safety snapshot: %#v", safety)
	}
	data, err := os.ReadFile(filepath.Join(live, toolbarstate.ExperimentFileName))
	if err != nil || string(data) != "restored" {
		t.Fatalf("Trial restored state mismatch: %q, %v", data, err)
	}
}

func TestExecuteRestoreDoesNotModifyLiveDataWhenBackupValidationFails(t *testing.T) {
	backupSource := t.TempDir()
	if err := os.WriteFile(filepath.Join(backupSource, "user.yaml"), []byte("backup"), 0o644); err != nil {
		t.Fatal(err)
	}
	backupRoot := t.TempDir()
	snapshot, err := userbackup.Create(backupSource, backupRoot, "用户数据", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(snapshot.Path, userbackup.DataDirectory, "user.yaml"), []byte("damaged"), 0o644); err != nil {
		t.Fatal(err)
	}
	live := t.TempDir()
	if err := os.WriteFile(filepath.Join(live, "user.yaml"), []byte("current"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := executeRestore(live, "shared", backupRoot, snapshot, time.Now()); err == nil {
		t.Fatal("corrupt backup must be rejected")
	}
	data, _ := os.ReadFile(filepath.Join(live, "user.yaml"))
	if string(data) != "current" {
		t.Fatalf("live data changed after validation failure: %q", data)
	}
}
