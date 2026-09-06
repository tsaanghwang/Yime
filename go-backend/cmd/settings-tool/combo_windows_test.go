//go:build windows

package main

import (
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/settings"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/toolbarstate"
)

// D2-S-UI-01 must exercise a native ComboBox: a state-file-only test misses
// CB_GETLBTEXTLEN being sent instead of CB_GETLBTEXT during refresh. All HWNDs
// belong to the test and remain hidden; no installed runtime is launched.
func TestTrialPageSizeRefreshUsesNativeComboText(t *testing.T) {
	for pageSize := 5; pageSize <= 9; pageSize++ {
		t.Run(fmt.Sprint(pageSize), func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			path := filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName)
			state, closeWindow := newHiddenTrialSettings(t, path)
			defer closeWindow()
			seedTrialComboState(t, path, pageSize)
			state.refreshView()
			assertNativePageSelection(t, state.pageHWND, pageSize)
		})
	}
}

func TestTrialPageSizeNativeApplyCompletionAndReopen(t *testing.T) {
	for pageSize := 5; pageSize <= 9; pageSize++ {
		t.Run(fmt.Sprint(pageSize), func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			path := filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName)
			seedTrialComboState(t, path, 5)
			state, closeWindow := newHiddenTrialSettings(t, path)
			defer closeWindow()
			state.refreshView()
			selected, _, _ := procSendMessageW.Call(uintptr(state.pageHWND), 0x014E /* CB_SETCURSEL */, uintptr(pageSize-5), 0)
			if int32(selected) != int32(pageSize-5) {
				t.Fatalf("native selection failed: index=%d", int32(selected))
			}
			applyHiddenTrialSettings(t, state)
			first := assertStoredPageSize(t, path, pageSize)
			assertNativePageSelection(t, state.pageHWND, pageSize)

			// Clicking Apply again without editing must not replace a nondefault
			// value with the first item displayed by a broken refresh.
			applyHiddenTrialSettings(t, state)
			unchanged := assertStoredPageSize(t, path, pageSize)
			if unchanged.Revision != first.Revision {
				t.Errorf("unchanged re-apply advanced state revision")
			}
			closeWindow()

			reopened, closeReopened := newHiddenTrialSettings(t, path)
			defer closeReopened()
			reopened.refreshView()
			assertNativePageSelection(t, reopened.pageHWND, pageSize)
			applyHiddenTrialSettings(t, reopened)
			afterReopen := assertStoredPageSize(t, path, pageSize)
			if afterReopen.Revision != first.Revision {
				t.Errorf("unchanged re-apply after reopening advanced state revision")
			}
		})
	}
}

func TestNativeComboTextReadbackMatchesWholeItem(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	state, closeWindow := newHiddenTrialSettings(t, filepath.Join(t.TempDir(), toolbarstate.ExperimentFileName))
	defer closeWindow()
	// Exercise an item beyond the old fixed-size buffer and non-ASCII UTF-16.
	// This is generated fixture text, never captured user text.
	longLabel := strings.Repeat("设置", 160)
	label, err := syscall.UTF16PtrFromString(longLabel)
	if err != nil {
		t.Fatal(err)
	}
	index, _, _ := procSendMessageW.Call(uintptr(state.pageHWND), 0x0143 /* CB_ADDSTRING */, 0, uintptr(unsafe.Pointer(label)))
	if int32(index) < 0 {
		t.Fatalf("could not add fixture label: %d", int32(index))
	}
	setComboByText(state.pageHWND, longLabel)
	if got := selectedComboText(state.pageHWND); got != longLabel {
		t.Errorf("whole-item readback mismatch: got %d runes, want %d", len([]rune(got)), len([]rune(longLabel)))
	}
	setComboByText(state.pageHWND, "not-an-item")
	assertNativePageSelection(t, state.pageHWND, 5)
	procSendMessageW.Call(uintptr(state.pageHWND), 0x014E /* CB_SETCURSEL */, ^uintptr(0), 0)
	if got := selectedComboText(state.pageHWND); got != "" {
		t.Errorf("no selection should return empty text, got %d runes", len([]rune(got)))
	}
	if _, ok := comboItemText(state.pageHWND, ^uintptr(0)); ok {
		t.Error("invalid item index should not produce a valid text readback")
	}
	procSendMessageW.Call(uintptr(state.pageHWND), 0x014B /* CB_RESETCONTENT */, 0, 0)
	setComboByText(state.pageHWND, "5")
	if got := selectedComboText(state.pageHWND); got != "" {
		t.Errorf("empty ComboBox should return empty text, got %d runes", len([]rune(got)))
	}
}

func newHiddenTrialSettings(t *testing.T, path string) (*appState, func()) {
	t.Helper()
	// A built-in parent class avoids the application's launch/presentation and
	// quit-message paths. WS_VISIBLE is never set on this top-level window.
	parent := createControl("STATIC", "", 0, rect{0, 0, 400, 400}, 0, 0)
	if parent == 0 {
		t.Fatal("could not create hidden settings fixture parent")
	}
	closed := false
	closeWindow := func() {
		if !closed {
			closed = true
			if result, _, err := moduser32.NewProc("DestroyWindow").Call(uintptr(parent)); result == 0 {
				t.Errorf("could not destroy fixture parent: %v", err)
			}
		}
	}
	state := &appState{
		mainHWND: parent, experimental: true, statePath: path,
		userDir: filepath.Dir(path), sharedDir: filepath.Dir(path),
		layout: buildSettingsUILayout(false, true),
		schemaOptions: []settings.SchemaOption{
			{ID: toolbarstate.ExperimentModeVariable, Label: "变长模式", Enabled: true},
			{ID: toolbarstate.ExperimentModeFull, Label: "等长模式", Enabled: true},
			{ID: toolbarstate.ExperimentModeShorthand, Label: "省键模式", Enabled: true},
		},
	}
	state.createControls()
	for _, hwnd := range []syscall.Handle{parent, state.schemaHWND, state.pageHWND, state.reverseHWND, state.layoutHWND, state.fontHWND, state.familyHWND} {
		if hwnd == 0 {
			closeWindow()
			t.Fatal("could not create a native settings fixture control")
		}
		if visible, _, _ := moduser32.NewProc("IsWindowVisible").Call(uintptr(hwnd)); visible != 0 {
			closeWindow()
			t.Fatal("settings fixture must never be visible")
		}
	}
	return state, closeWindow
}

func seedTrialComboState(t *testing.T, path string, pageSize int) {
	t.Helper()
	if err := executeTrialApply(path, trialApplyRequest{
		mode: toolbarstate.ExperimentModeFull, pageSize: pageSize,
		layout: toolbarstate.CandidateLayoutHorizontal, font: toolbarstate.CandidateFontLarge,
		fontFamily: toolbarstate.CandidateFontSystemUI, annotation: toolbarstate.AnnotationStandardPinyin,
	}); err != nil {
		t.Fatal(err)
	}
}

func assertNativePageSelection(t *testing.T, hwnd syscall.Handle, pageSize int) {
	t.Helper()
	if got := selectedComboText(hwnd); got != fmt.Sprint(pageSize) {
		t.Errorf("settings ComboBox displays %q; want persisted page size %d", got, pageSize)
	}
	index, _, _ := procSendMessageW.Call(uintptr(hwnd), 0x0147 /* CB_GETCURSEL */, 0, 0)
	if int32(index) != int32(pageSize-5) {
		t.Errorf("settings ComboBox index=%d; want %d", int32(index), pageSize-5)
	}
}

func assertStoredPageSize(t *testing.T, path string, pageSize int) toolbarstate.State {
	t.Helper()
	snapshot, err := toolbarstate.Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.CandidatePageSize != pageSize {
		t.Errorf("stored page size=%d; want %d", snapshot.CandidatePageSize, pageSize)
	}
	if snapshot.ExperimentMode != toolbarstate.ExperimentModeFull || snapshot.CandidateLayout != toolbarstate.CandidateLayoutHorizontal ||
		snapshot.CandidateFontPreset != toolbarstate.CandidateFontLarge || snapshot.CandidateFontFamily != toolbarstate.CandidateFontSystemUI ||
		snapshot.CandidateAnnotation != toolbarstate.AnnotationStandardPinyin {
		t.Error("applying candidate count changed unrelated isolated settings")
	}
	return snapshot
}

func applyHiddenTrialSettings(t *testing.T, state *appState) {
	t.Helper()
	state.handleCommand(idBtnApply)
	if !state.isApplyRunning() {
		t.Fatal("Apply command did not begin the isolated operation")
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var message winMsg
		// Remove only this hidden window's completion message. Other windows'
		// input, focus, and messages are never pumped or synthesized.
		found, _, _ := moduser32.NewProc("PeekMessageW").Call(uintptr(unsafe.Pointer(&message)), uintptr(state.mainHWND), wmAppApplyDone, wmAppApplyDone, 1)
		if found != 0 {
			state.applyMu.Lock()
			err := state.applyErr
			state.applyMu.Unlock()
			if err != nil {
				t.Fatalf("isolated apply failed: %v", err)
			}
			state.wndProc(state.mainHWND, message.Message, message.WParam, message.LParam)
			if state.isApplyRunning() {
				t.Fatal("apply completion did not finish the operation")
			}
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("timed out waiting for isolated apply completion")
}
