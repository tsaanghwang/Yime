//go:build windows && (amd64 || arm64)

package main

import (
	"bytes"
	"os"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestCalibrationSaveRefusesOversizeBodyBeforeReplacingSettings(t *testing.T) {
	r, display := calibrationFixture()
	path := calibrationFile(t.TempDir(), display)
	if err := saveCalibration(path, r); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(path)
	r.ObservedMM = 50 // This would require a keyboard body wider than 3840px.
	ppm, err := r.pixelsPerMM(display, 597.73, 100)
	if err != nil {
		t.Fatal(err)
	}
	board := tk.Board{}
	board.Bounds.Width, board.Bounds.Height = 18, 5.7
	a := &ui{s: tk.NewState(board), ppm: ppm, border: 10}
	if err = a.saveInstalledCalibration(path, r, monitor{Work: rect{0, 0, 3840, 2400}}); err == nil {
		t.Fatal("oversize measurement was saved")
	}
	after, _ := os.ReadFile(path)
	if !bytes.Equal(before, after) {
		t.Fatal("failed fit replaced the prior calibration")
	}
}

func TestCalibrationResizeFailurePreservesCompactMarginAndState(t *testing.T) {
	board := tk.Board{}
	board.Bounds.Width, board.Bounds.Height = 18, 5.7
	a := &ui{s: tk.NewState(board), ppm: 1e6, border: 4, top: 250, calibrationApplied: true}
	if err := a.applyTouchImmediate("larger"); err == nil {
		t.Fatal("oversize calibration unexpectedly fitted the display")
	}
	if a.ppm != 1e6 || a.border != 4 || a.top != 250 {
		t.Fatal("failed resize retained changed scale, outer margin or header")
	}
}
