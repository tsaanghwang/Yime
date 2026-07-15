//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/runtimechange"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userbackup"
)

func TestSettingsUILayoutFitsVisibleControls(t *testing.T) {
	withoutHelp := buildSettingsUILayout(false)
	withHelp := buildSettingsUILayout(true)

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
	layout := buildSettingsUILayout(true)
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
	wantGap := buttons[1].Left - buttons[0].Right
	for index, button := range buttons {
		if button.Right-button.Left != wantWidth {
			t.Fatalf("button %d is not equally sized: %#v", index, buttons)
		}
		if index > 0 && button.Left-buttons[index-1].Right != wantGap {
			t.Fatalf("button %d is not evenly distributed: %#v", index, buttons)
		}
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
