//go:build windows

package main

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userbackup"
)

func TestTrialSpeechApplyValidatesBeforeWritingAndPreservesOtherSettings(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "speech.json")
	other := filepath.Join(root, "unrelated.json")
	if err := os.WriteFile(other, []byte("fixture sentinel"), 0600); err != nil {
		t.Fatal(err)
	}
	reject := func(bool) error { return errors.New("fixture capability rejection") }
	if err := applyTrialSpeechWithValidation(path, true, reject); err == nil {
		t.Fatal("invalid capability accepted")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("rejected update created settings")
	}
	for _, enabled := range []bool{true, false, true} {
		if err := applyTrialSpeechWithValidation(path, enabled, func(actual bool) error {
			if actual != enabled {
				t.Fatal("explicit target changed")
			}
			return nil
		}); err != nil {
			t.Fatal(err)
		}
		got, err := speechruntime.LoadSettings(path)
		if err != nil || got.Enabled != enabled {
			t.Fatal("explicit setting did not persist")
		}
	}
	if err := applyTrialSpeechWithValidation(path, false, reject); err == nil {
		t.Fatal("rejected update succeeded")
	}
	got, err := speechruntime.LoadSettings(path)
	if err != nil || !got.Enabled {
		t.Fatal("rejected update changed the previous setting")
	}
	data, err := os.ReadFile(other)
	if err != nil || string(data) != "fixture sentinel" {
		t.Fatal("speech update touched other settings")
	}
}

func TestTrialSpeechApplyRequiresInstalledCapability(t *testing.T) {
	root := t.TempDir()
	packageRoot, stateRoot := filepath.Join(root, "package"), filepath.Join(root, "state")
	if err := os.Mkdir(packageRoot, 0700); err != nil {
		t.Fatal(err)
	}
	if err := executeTrialSpeechApply(packageRoot, stateRoot, true); err == nil {
		t.Fatal("missing capability allowed enable")
	}
	if _, err := os.Stat(stateRoot); !os.IsNotExist(err) {
		t.Fatal("missing capability created state")
	}
	if err := executeTrialSpeechApply("", stateRoot, false); err == nil {
		t.Fatal("empty product root used cwd")
	}
}

func TestTrialSpeechLayoutAndCommandAreIndependentOfNormalApply(t *testing.T) {
	l := buildSettingsUILayout(true, true)
	if l.speechLabel.Top <= l.familyLabel.Bottom || l.speechApplyButton.Right > l.clientW-16 ||
		l.speechCombo.Right >= l.speechApplyButton.Left || l.speechHint.Bottom >= l.applyButton.Top {
		t.Fatal("speech controls overlap existing rows or buttons")
	}
	if idBtnSpeechApply == idBtnApply || idSpeechCombo == idSchemaCombo || idSpeechCombo == idPageSizeCombo {
		t.Fatal("speech uses an existing command ID")
	}
	regular := buildSettingsUILayout(true, false)
	if regular.speechLabel != (rect{}) || regular.speechApplyButton != (rect{}) {
		t.Fatal("Rime settings acquired speech controls")
	}
}

func TestTrialSpeechPortableSettingBackupRestoreUsesSyntheticState(t *testing.T) {
	root := t.TempDir()
	stateRoot, backupRoot := filepath.Join(root, "state"), filepath.Join(root, "archives")
	path := filepath.Join(stateRoot, "speech.json")
	if err := speechruntime.SaveSettings(path, true, true); err != nil {
		t.Fatal(err)
	}
	snapshot, err := userbackup.Create(stateRoot, backupRoot, "fixture", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if err := speechruntime.SaveSettings(path, false, true); err != nil {
		t.Fatal(err)
	}
	if err := userbackup.Restore(snapshot, stateRoot); err != nil {
		t.Fatal(err)
	}
	setting, err := speechruntime.LoadSettings(path)
	if err != nil || !setting.Enabled {
		t.Fatal("portable setting restore failed")
	}
	if _, err := os.Stat(filepath.Join(stateRoot, "speech", "product.json")); !os.IsNotExist(err) {
		t.Fatal("restore created a package capability")
	}
}

func TestTrialSpeechRestoredEnabledMismatchRemainsExplicitlyDisableable(t *testing.T) {
	root := t.TempDir()
	if err := speechruntime.SaveSettings(filepath.Join(root, "speech.json"), true, true); err != nil {
		t.Fatal(err)
	}
	view := readTrialSpeechView(root, func(enabled bool) error {
		if enabled {
			return errors.New("fixture layout mismatch")
		}
		return nil
	})
	if !view.enabled || !view.canApply || !strings.Contains(view.hint, "未生效") || !strings.Contains(view.hint, "可关闭") {
		t.Fatal("restored incompatible setting was presented as effective or could not be disabled")
	}
	if err := applyTrialSpeechWithValidation(filepath.Join(root, "speech.json"), false, func(enabled bool) error {
		if enabled {
			t.Fatal("disable unexpectedly validated enable")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	view = readTrialSpeechView(root, func(bool) error { return nil })
	if view.enabled || !view.canApply {
		t.Fatal("disabled setting was not read back")
	}
}

func TestTrialSpeechNativeRejectedApplyReadsBackBeforeErrorPresentation(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	root := t.TempDir()
	state, closeWindow := newHiddenTrialSettings(t, filepath.Join(root, "yimecore_experimental_toolbar_state.json"))
	defer closeWindow()
	state.installRoot = filepath.Join(root, "package-without-capability")
	if err := os.Mkdir(state.installRoot, 0700); err != nil {
		t.Fatal(err)
	}
	setComboByValue(state.speechHWND, trialSpeechOptions(), "on")
	state.applyRunning, state.applyErr = true, errors.New("fixture rejected enable")
	if err := state.completeSpeechApply(); err == nil {
		t.Fatal("failed apply lost its error")
	}
	if state.isApplyRunning() || selectedComboValue(state.speechHWND, trialSpeechOptions()) != "off" {
		t.Fatal("rejected target remained displayed as enabled")
	}
	if enabled, _, _ := moduser32.NewProc("IsWindowEnabled").Call(uintptr(state.speechApplyHWND)); enabled != 0 {
		t.Fatal("missing capability left apply enabled")
	}
	if visible, _, _ := moduser32.NewProc("IsWindowVisible").Call(uintptr(state.speechHWND)); visible != 0 {
		t.Fatal("native fixture became visible")
	}
	if _, err := os.Stat(filepath.Join(root, "speech.json")); !os.IsNotExist(err) {
		t.Fatal("rejected apply changed state")
	}
}
