//go:build windows

package main

import (
	"errors"
	"testing"

	"github.com/EasyIME/pime-go/input_methods/yime/runtimechange"
)

func TestSettingsUILayoutFitsVisibleControls(t *testing.T) {
	withoutHelp := buildSettingsUILayout(false)
	withHelp := buildSettingsUILayout(true)

	if withoutHelp.clientW != withoutHelp.openUserButton.Right+16 {
		t.Fatalf("window should fit the last visible button: width=%d right=%d", withoutHelp.clientW, withoutHelp.openUserButton.Right)
	}
	if withHelp.clientW != withHelp.openHelpButton.Right+16 {
		t.Fatalf("window should fit the optional help button: width=%d right=%d", withHelp.clientW, withHelp.openHelpButton.Right)
	}
	if withHelp.clientH != withHelp.applyButton.Bottom+16 {
		t.Fatalf("window should fit the button row: height=%d bottom=%d", withHelp.clientH, withHelp.applyButton.Bottom)
	}
	if withHelp.clientW <= withoutHelp.clientW {
		t.Fatalf("help button should expand the content-sized window: with=%d without=%d", withHelp.clientW, withoutHelp.clientW)
	}
	if withHelp.clientW >= 820 || withHelp.clientH >= 680 {
		t.Fatalf("content-sized layout should be smaller than the former fixed client area: %dx%d", withHelp.clientW, withHelp.clientH)
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

	err := executeApply("user", "shared", applyRequest{schemaID: "yime_full", pageSize: 7, reverseMode: "hidden", layout: "vertical", runBuild: true})
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
