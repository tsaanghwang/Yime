//go:build windows && (amd64 || arm64)

package main

import (
	"errors"
	"runtime"
	"testing"
	"time"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func countKeyClicks(a *ui, succeeds bool) *int {
	calls := new(int)
	a.o.KeySound = "click"
	a.soundPlayer = func() bool { (*calls)++; return succeeds }
	return calls
}

func TestKeySoundOnlyAfterAcceptedRelease(t *testing.T) {
	a := previewUI(t)
	calls := countKeyClicks(a, true)
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(1, x, y)
	if *calls != 0 {
		t.Fatal("sound before accepted release")
	}
	a.up(1, x, y)
	a.up(1, x, y)
	if *calls != 1 || a.preview.snapshot.State.RawInput != "a" {
		t.Fatal("accepted release or duplicate sound", *calls)
	}
	a.down(2, x, y)
	a.move(2, -10, -10)
	a.move(2, x, y)
	a.up(2, x, y)
	a.down(3, x, y)
	a.cancel()
	a.up(3, x, y)
	if *calls != 1 {
		t.Fatal("cancelled/moved-out gesture sounded", *calls)
	}
	// Old candidate must neither select nor confirm audibly after a state update.
	box := a.candidateRect(0)
	cx, cy := (box.L+box.R)/2, (box.T+box.B)/2
	a.down(4, cx, cy)
	previewAction(t, a.preview, "input", "a", "")
	a.up(4, cx, cy)
	if *calls != 1 {
		t.Fatal("stale candidate sounded")
	}
}

func TestKeySoundMuteDisabledKeysAndPlaybackFailure(t *testing.T) {
	a := previewUI(t)
	previewAction(t, a.preview, "toggle-language", "", "")
	a.s.Original = a.preview.original()
	calls := countKeyClicks(a, false)
	dx, dy := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Disabled })
	a.down(1, dx, dy)
	a.up(1, dx, dy)
	fx, fy := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "unsupported" && v.Action.Label == "F1" })
	a.down(2, fx, fy)
	a.up(2, fx, fy)
	if *calls != 0 {
		t.Fatal("inactive key sounded")
	}
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(3, x, y)
	a.up(3, x, y)
	if *calls != 1 || !a.soundUnavailable || string(a.preview.editor.text) != "a" || a.preview.fault {
		t.Fatal("audio failure affected input")
	}
	a.o.KeySound = "off"
	a.down(4, x, y)
	a.up(4, x, y)
	if *calls != 1 || string(a.preview.editor.text) != "aa" {
		t.Fatal("muted input or sound", *calls)
	}
}

func TestKeySoundTogglePreservesCompositionAndRejectsOldContact(t *testing.T) {
	a := previewUI(t)
	calls := countKeyClicks(a, true)
	a.o.KeySound = "off"
	previewAction(t, a.preview, "input", "a", "")
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(1, x, y)
	a.down(2, 920, 130)
	if *calls != 0 {
		t.Fatal("toggle played before release")
	}
	a.up(2, 920, 130)
	a.up(1, x, y)
	if *calls != 1 || a.preview.snapshot.State.RawInput != "a" || a.o.KeySound != "click" {
		t.Fatal("toggle lost composition or revived old key")
	}
	a.down(3, 920, 130)
	a.up(3, 920, 130)
	if *calls != 1 || a.o.KeySound != "off" {
		t.Fatal("mute did not stay silent")
	}
}

func TestKeySoundDoesNotConfirmFailedHostSend(t *testing.T) {
	a, _, _ := navigationHostFixture(t)
	previewAction(t, a.preview, "toggle-language", "", "")
	a.s.Original = a.preview.original()
	calls := countKeyClicks(a, true)
	a.host.send = func(hostTarget, tk.Output) error { return errors.New("injected send failure") }
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(1, x, y)
	a.up(1, x, y)
	if *calls != 0 || !a.preview.fault {
		t.Fatal("failed host delivery sounded successful")
	}
}

func TestStartupSoundWaitsForWindowAndRetriesAsyncFailure(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, cleanup := penCompatibilityFixture(t)
	defer cleanup()
	a.o.KeySound = "click"
	failed := startWaveClickStream(func() (*waveDevice, error) { return nil, errors.New("transient initial open failure") })
	select {
	case <-failed.done:
	case <-time.After(time.Second):
		t.Fatal("fixture did not fail")
	}
	opened := 0
	replacement := &fakeClickStream{}
	a.soundFactory = func() (clickSound, error) {
		opened++
		if opened == 1 {
			return failed, nil
		}
		return replacement, nil
	}
	windowProc(a.h, 0x0005, 0, 0) // Creation/resize before dictionaries/fonts ready.
	if opened != 0 {
		t.Fatal("audio started before window initialization finished")
	}
	windowProc(a.h, wmKeySoundReady, 0, 0)
	if opened != 1 || !a.soundTimerActive {
		t.Fatal("ready window did not start audio maintenance")
	}
	windowProc(a.h, 0x0113, keySoundTimer, 0)
	if !a.soundUnavailable || opened != 1 || !a.soundTimerActive {
		t.Fatal("asynchronous failure was not detected with bounded retry")
	}
	a.soundRetryAfter = time.Now().Add(-time.Second) // Advance past retry delay.
	windowProc(a.h, 0x0113, keySoundTimer, 0)
	if opened != 2 {
		t.Fatal("startup failure required minimize to recover")
	}
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	a.down(70, x, y)
	a.up(70, x, y)
	if replacement.plays != 1 || string(a.preview.editor.text) != "a" || a.soundUnavailable {
		t.Fatal("recovered startup did not preserve input and feedback")
	}
	a.suspendForMinimize()
	windowProc(a.h, 0x0113, keySoundTimer, 0) // Already queued timer must not restart audio.
	if opened != 2 || a.soundTimerActive {
		t.Fatal("minimized audio restarted from queued timer")
	}
}
