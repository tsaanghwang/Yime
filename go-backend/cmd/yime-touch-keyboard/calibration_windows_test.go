//go:build windows && (amd64 || arm64)

package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"math"
	"os"
	"testing"
)

func TestMeasuredCalibrationAndCentre(t *testing.T) {
	ppm, err := measuredPPM(2, "58")
	if err != nil || math.Abs(ppm-2*100.0/58) > 1e-9 {
		t.Fatal(ppm, err)
	}
	for _, input := range []string{"", "0", "-1", "NaN", "Inf", "1001", "1.2.3"} {
		if _, err := measuredPPM(2, input); err == nil {
			t.Fatal("invalid measurement", input)
		}
	}
	current, work := rect{300, 200, 700, 400}, rect{0, 0, 1000, 800}
	if got := centeredResize(current, work, 600, 300); got != (rect{200, 150, 800, 450}) {
		t.Fatal(got)
	}
	if got := centeredResize(rect{0, 0, 400, 200}, work, 600, 300); got != (rect{0, 0, 600, 300}) {
		t.Fatal(got)
	}
	a := &ui{calibrationOpen: true}
	for _, action := range []string{"measure:9", "measure:9", "measure:.", "measure:5"} {
		if !touchLocalConfiguration(action) || !touchImmediateAction(action) {
			t.Fatal("numeric pad needs host")
		}
		if err := a.calibrationAction(action); err != nil {
			t.Fatal(err)
		}
	}
	if a.calibrationInput != "99.5" {
		t.Fatal(a.calibrationInput)
	}
	before := a.ppm
	a.calibrationAction("measure:cancel")
	if a.calibrationOpen || a.ppm != before {
		t.Fatal("cancel changed scale")
	}
}

func TestBindingDiagnosticFilesDoNotOverwrite(t *testing.T) {
	dir := t.TempDir()
	d := frontendDiagnostic{Stage: "endpoint-connect-and-bind", Error: "TSF bind rejected: no-focused-document"}
	first, err := saveFrontendDiagnostic(dir, d)
	if err != nil {
		t.Fatal(err)
	}
	d.Error = "second"
	second, err := saveFrontendDiagnostic(dir, d)
	if err != nil || first == second {
		t.Fatal(second, err)
	}
	b, err := os.ReadFile(first)
	if err != nil || len(b) == 0 {
		t.Fatal(err)
	}
	a := &ui{s: &tk.State{}, diagnosticSummary: "first failure", diagnosticPages: []string{string(b)}, diagnosticOpen: true}
	a.suspendForMinimize()
	if a.diagnosticSummary != "first failure" || a.helpPages()[0] != string(b) {
		t.Fatal("minimize lost diagnostic")
	}
	if _, err = saveFrontendDiagnostic(first, d); err == nil {
		t.Fatal("write failure hidden")
	}
}
