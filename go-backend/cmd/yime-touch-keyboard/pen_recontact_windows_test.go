//go:build windows && (amd64 || arm64)

package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"runtime"
	"testing"
	"time"
)

func TestPenRecontactNativeAndCompatibilityRoutes(t *testing.T) {
	for _, route := range []string{"filtered-pen", "default-off-pen", "finger", "legacy-pen-mouse"} {
		t.Run(route, func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			a, cleanup := penCompatibilityFixture(t)
			defer cleanup()
			b, err := touchScreenBoard(a.s.Board)
			if err != nil {
				t.Fatal(err)
			}
			a.s = tk.NewState(b)
			a.s.Semantic = true
			a.s.Original = a.preview.original()
			a.o.Preview = true
			a.o.TouchUI = true
			a.top = touchHeaderHeight
			if route != "default-off-pen" {
				a.o.PenRecontactMS = 80
			}
			now := time.Unix(100, 0)
			a.penClock = func() time.Time { return now }
			sounds := countKeyClicks(a, true)
			x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
			tap := func(gap time.Duration) {
				now = now.Add(gap)
				if route == "legacy-pen-mouse" {
					promotedPenMouse(a, 0x0201, 0xff515702, x, y)
					promotedPenMouse(a, 0x0202, 0xff515702, x, y)
					return
				}
				down, up := uint32(0x5a), uint32(0x54)
				if route == "finger" {
					down, up = 0x1a, 0x14
				}
				nativePenFrame(a, 77, down, x, y)
				if route != "finger" {
					promotedPenMouse(a, 0x0201, 0xff515702, x, y)
				}
				now = now.Add(20 * time.Millisecond)
				nativePenFrame(a, 77, up, x, y)
				if route != "finger" {
					promotedPenMouse(a, 0x0202, 0xff515782, x, y)
				}
			}
			tap(0)
			tap(12 * time.Millisecond)
			want := "aa"
			n := 2
			if route == "filtered-pen" {
				want = "a"
				n = 1
			}
			if string(a.preview.editor.text) != want || *sounds != n {
				t.Fatal("recontact/compatibility commit or feedback mismatch", route, string(a.preview.editor.text), *sounds)
			}
			tap(80 * time.Millisecond)
			if string(a.preview.editor.text) != want+"a" || *sounds != n+1 {
				t.Fatal("deliberate later repeat lost")
			}
		})
	}
}

func TestPenRecontactPreservesDifferentKeysAndShiftToggle(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, cleanup := penCompatibilityFixture(t)
	defer cleanup()
	b, err := touchScreenBoard(a.s.Board)
	if err != nil {
		t.Fatal(err)
	}
	a.s = tk.NewState(b)
	a.s.Semantic = true
	a.s.Original = a.preview.original()
	a.o.Preview, a.o.TouchUI, a.o.PenRecontactMS = true, true, 80
	a.top = touchHeaderHeight
	now := time.Unix(100, 0)
	a.penClock = func() time.Time { return now }
	tap := func(action, ascii string) {
		x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool {
			return v.Action.Type == action && (ascii == "" || v.Action.ASCII == ascii)
		})
		now = now.Add(10 * time.Millisecond)
		nativePenFrame(a, 9, 0x5a, x, y)
		now = now.Add(10 * time.Millisecond)
		nativePenFrame(a, 9, 0x54, x, y)
	}
	tap("input", "a")
	tap("input", "b")
	tap("input", "a")
	tap("shift", "")
	tap("shift", "")
	tap("input", "a")
	tap("shift", "")
	tap("input", "a")
	if string(a.preview.editor.text) != "abaaA" {
		t.Fatal("different-key/toggle/uppercase path changed", string(a.preview.editor.text))
	}
	a.cancel()
	tap("input", "a")
	if string(a.preview.editor.text) != "abaaAa" {
		t.Fatal("cancelled context retained cooldown")
	}
}

func TestPenRecontactCNCompositionAndCancel(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a, cleanup := penCompatibilityFixture(t)
	defer cleanup()
	previewAction(t, a.preview, "toggle-language", "", "")
	b, err := touchScreenBoard(a.s.Board)
	if err != nil {
		t.Fatal(err)
	}
	a.s = tk.NewState(b)
	a.s.Semantic = true
	a.s.Original = a.preview.original()
	a.o.Preview, a.o.TouchUI, a.o.PenRecontactMS = true, true, 80
	a.top = touchHeaderHeight
	now := time.Unix(100, 0)
	a.penClock = func() time.Time { return now }
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	tap := func(gap, hold time.Duration) {
		now = now.Add(gap)
		nativePenFrame(a, 3017, 0x5a, x, y)
		now = now.Add(hold)
		nativePenFrame(a, 3017, 0x54, x, y)
	}
	tap(0, 19*time.Millisecond)
	tap(12*time.Millisecond, 168*time.Millisecond)
	if a.preview.snapshot.State.RawInput != "a" || len(a.preview.editor.text) != 0 {
		t.Fatal("CN bounce altered raw/committed text", a.preview.snapshot.State.RawInput)
	}
	tapTouchControl(t, a, "cancel")
	tap(10*time.Millisecond, 20*time.Millisecond)
	if a.preview.snapshot.State.RawInput != "a" || len(a.preview.editor.text) != 0 {
		t.Fatal("CN cancellation kept recontact history")
	}
}
