//go:build windows && (amd64 || arm64)

package main

import (
	"math"
	"runtime"
	"testing"
	"unsafe"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestInstalledScreenFitDefaultsAndExplicitCalibration(t *testing.T) {
	for _, test := range []struct {
		options options
		want    bool
	}{
		{options{InstalledTSF: true, TouchUI: true}, true},
		{options{InstalledTSF: true, TouchUI: true, WindowSizing: "auto"}, true},
		{options{InstalledTSF: true, TouchUI: true, WindowSizing: "calibrated"}, false},
		{options{TouchUI: true, WindowSizing: "fit"}, true},
		{options{TouchUI: true}, false},
		{options{Profile: "main-17u.json"}, false},
		{options{Profile: "full-23u.json"}, false},
	} {
		if got := startsScreenFitted(test.options); got != test.want {
			t.Fatalf("options %+v: fit=%t want=%t", test.options, got, test.want)
		}
	}
}

func TestScreenFitUsesFullWorkAreaAndPreservesCalibrationAndHitTargets(t *testing.T) {
	for _, work := range []rect{
		{0, 0, 2880, 1720}, {0, 0, 1920, 1040}, {0, 48, 3840, 2160},
		{-1920, 0, 0, 1040}, {40, -1920, 1080, 0}, {0, 0, 800, 360},
	} {
		a := touchUIFixture(t)
		original := a.ppm
		ppm, err := a.fittedScale(work)
		if err != nil {
			t.Fatal(work, err)
		}
		a.fitScreen, a.fittedPPM = true, ppm
		width, height, header := a.windowGeometry(a.displayPPM())
		a.top = header
		if width > int(work.R-work.L) || height > int(work.B-work.T) {
			t.Fatalf("keyboard exceeds work area: %v %dx%d", work, width, height)
		}
		if int(work.R-work.L)-width > 1 && int(work.B-work.T)-height > 1 {
			t.Fatalf("keyboard did not maximize available space: %v %dx%d", work, width, height)
		}
		position := bottomCentered(work, int32(width), int32(height))
		if position.B != work.B || position.T < work.T || position.L < work.L || position.R > work.R {
			t.Fatal("fit is outside the usable monitor", work, position)
		}
		if a.ppm != original || a.s.Board.Bounds.Width != 18 {
			t.Fatal("screen fit changed physical calibration or 18u layout")
		}
		for i, key := range a.s.Board.Keys {
			for _, part := range key.Rectangles {
				u := tk.UnitMM * a.displayPPM()
				x := int32(float64(a.border) + (key.X+part.X+part.Width/2)*u)
				y := int32(float64(a.top) + (key.Y+part.Y+part.Height/2)*u)
				got := a.s.Hit((float64(x)-float64(a.border))/u, (float64(y)-float64(a.top))/u)
				if got != i {
					t.Fatalf("fitted hit missed key %s: %d want %d", key.ID, got, i)
				}
			}
		}
		for i := range touchSettings {
			box := a.touchSettingRect(i)
			if box.L < 0 || box.R > int32(width) || box.B > int32(height) {
				t.Fatal("fitted settings clipped", work, i, box)
			}
		}
		x, y := previewKeyPoint(t, a, func(_ tk.Key, view tk.View) bool { return view.Action.ASCII == "a" })
		a.down(77, x, y)
		a.up(77, x, y)
		if a.preview.snapshot.State.RawInput != "a" {
			t.Fatal("scaled real gesture did not reach the expected composition key")
		}
	}
}

func TestScreenFitResizesOwnWindowAndRestoresManualMode(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a := touchUIFixture(t)
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, keyboardWindowStyle, 0, 0, 800, 400, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create hidden own window")
	}
	defer U("DestroyWindow").Call(h)
	a.h = h
	beforeFocus := foreground()
	original := a.ppm
	if err := a.applyTouchImmediate("fit-screen"); err != nil {
		t.Fatal(err)
	}
	m := currentMonitor(h)
	width, height, _ := a.windowGeometry(a.displayPPM())
	want := bottomCentered(m.Work, int32(width), int32(height))
	actual := rect{}
	U("GetWindowRect").Call(h, uintptr(unsafe.Pointer(&actual)))
	if actual != want || foreground() != beforeFocus || a.ppm != original {
		t.Fatal("native fit changed focus/calibration or window position", actual, want)
	}
	if err := a.changeCalibration(1e6); err == nil || !a.fitScreen || a.ppm != original {
		t.Fatal("rejected manual calibration did not preserve fitted mode")
	}
	if err := a.changeCalibration(original); err != nil || a.fitScreen {
		t.Fatal("explicit manual calibration did not select calibrated mode", err)
	}
	if math.Abs(a.displayPPM()-original) > 1e-9 {
		t.Fatal("manual mode retained display zoom")
	}
	if err := a.applyTouchImmediate("fit-screen"); err != nil {
		t.Fatal(err)
	}
	x, y := previewKeyPoint(t, a, func(_ tk.Key, view tk.View) bool { return view.Action.ASCII == "a" })
	a.down(78, x, y)
	a.displayChanged()
	a.up(78, x, y)
	if a.preview.snapshot.State.RawInput != "" || len(a.previewTouches) != 0 || !a.fitScreen || a.ppm != original {
		t.Fatal("display change accepted an old touch or lost sizing/calibration mode")
	}
}
