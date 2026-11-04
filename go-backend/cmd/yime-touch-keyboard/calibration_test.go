package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func calibrationFixture() (calibrationRecord, calibrationDisplay) {
	d := calibrationDisplay{Device: `\\.\DISPLAY1`, InterfaceID: `\\?\DISPLAY#ASUS#physical-panel-1`, Width: 3840, Height: 2400}
	r := calibrationRecord{Schema: calibrationSchema, MonitorDevice: d.Device, MonitorInterfaceID: d.InterfaceID, WidthPixels: d.Width, HeightPixels: d.Height, BaselineScreenWidthMM: 597.73, ReferenceMM: 100, ObservedMM: 57.5, MeasurementSource: "physical-ruler", RecordedUTC: "2026-11-04T00:00:00Z"}
	return r, d
}

func TestCalibrationUsesTheExistingProductStateDirectory(t *testing.T) {
	for _, name := range []string{"18u-touch-product-arm64.json", "18u-touch-product.json"} {
		raw, err := os.ReadFile(filepath.Join("..", "..", "..", "tools", "yimecore", name))
		if err != nil {
			t.Fatal(err)
		}
		var product struct {
			Identity struct {
				StateDirectory string `json:"state_directory"`
			} `json:"identity"`
		}
		if err = json.Unmarshal(raw, &product); err != nil || product.Identity.StateDirectory == "" {
			t.Fatal("product state identity missing", err)
		}
		root := t.TempDir()
		if got, want := calibrationDirectory(root), filepath.Join(root, product.Identity.StateDirectory, "display-calibration"); got != want {
			t.Fatalf("calibration created a second product state root: got %s, want %s", got, want)
		}
	}
}

func TestCalibrationMeasuredReferenceFitsASUSWithoutChangingKeyPitch(t *testing.T) {
	r, display := calibrationFixture()
	ppm, err := r.pixelsPerMM(display, 597.73, 100)
	if err != nil || math.Abs(ppm-11.172704849288502) > 1e-10 {
		t.Fatalf("measurement correction: ppm=%v err=%v", ppm, err)
	}
	width, _, margin, err := calibratedWindowSize(18, 5.7, ppm, 250, 10, 3840, 2400, true)
	if err != nil || width != 3840 || margin != 4 || width-2*margin != 3832 {
		t.Fatalf("body must remain 3832px with only 4px outer margins: %d %d %v", width, margin, err)
	}
	if math.Round(100*ppm) != 1117 {
		t.Fatal("reference length was altered to fit")
	}
	if _, _, _, err = calibratedWindowSize(18, 5.7, ppm*1.01, 250, 10, 3840, 2400, true); err == nil {
		t.Fatal("oversize key body must not be shrunk")
	}
	if _, _, _, err = calibratedWindowSize(18, 5.7, ppm, 250, 10, 3840, 2400, false); err == nil {
		t.Fatal("unconfigured behavior must retain the original 10px margin")
	}
}

func TestCalibrationNeverCompoundsOrUsesAnotherDisplay(t *testing.T) {
	r, d := calibrationFixture()
	first, err := r.pixelsPerMM(d, 597.73, 100)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		next, err := r.pixelsPerMM(d, 597.73, 100)
		if err != nil || next != first {
			t.Fatal("restart compounded the saved correction")
		}
	}
	for name, change := range map[string]func(*calibrationDisplay){
		"device":   func(d *calibrationDisplay) { d.Device += "-other" },
		"panel":    func(d *calibrationDisplay) { d.InterfaceID += "-other" },
		"width":    func(d *calibrationDisplay) { d.Width = 1920 },
		"height":   func(d *calibrationDisplay) { d.Height = 2160 },
		"rotation": func(d *calibrationDisplay) { d.Width, d.Height = d.Height, d.Width },
	} {
		t.Run(name, func(t *testing.T) {
			other := d
			change(&other)
			if _, err := r.pixelsPerMM(other, 597.73, 100); err == nil {
				t.Fatal("foreign monitor/resolution accepted")
			}
		})
	}
	if _, err = r.pixelsPerMM(d, 343.69, 100); err == nil {
		t.Fatal("different baseline accepted")
	}
	if _, err = r.pixelsPerMM(d, 597.73, 57.5); err == nil {
		t.Fatal("saved correction combined with CLI correction")
	}
	other := d
	other.InterfaceID += "-other"
	if calibrationFile("settings", d) == calibrationFile("settings", other) {
		t.Fatal("different physical panels share a settings file")
	}
}

func TestCalibrationStrictJSON(t *testing.T) {
	r, _ := calibrationFixture()
	raw, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = decodeCalibration(raw); err != nil {
		t.Fatal(err)
	}
	for name, bad := range map[string][]byte{
		"duplicate": append([]byte(`{"observedMM":57.5,`), raw[1:]...),
		"unknown":   append([]byte(`{"guessFromDPI":true,`), raw[1:]...),
		"trailing":  append(append([]byte{}, raw...), []byte(` {}`)...),
		"array":     []byte(`[]`),
		"null":      []byte(`null`),
		"missing":   []byte(`{}`),
		"oversize":  []byte(strings.Repeat(" ", 8193)),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeCalibration(bad); err == nil {
				t.Fatal("invalid calibration JSON accepted")
			}
		})
	}
	for _, bad := range []float64{0, -1, math.NaN(), math.Inf(1)} {
		r.ObservedMM = bad
		if err = r.validate(); err == nil {
			t.Fatal("invalid ruler measurement accepted", bad)
		}
	}
}

func TestCalibrationPersistenceDoesNotModifyExistingRecordOnFailure(t *testing.T) {
	r, d := calibrationFixture()
	path := calibrationFile(t.TempDir(), d)
	if missing, err := readCalibration(path); err != nil || missing != nil {
		t.Fatal("missing settings must preserve legacy behavior", err)
	}
	if err := saveCalibration(path, r); err != nil {
		t.Fatal(err)
	}
	old, _ := os.ReadFile(path)
	failed := r
	failed.ObservedMM = 58
	err := saveCalibrationReplacing(path, failed, func(_, _ string) error { return errors.New("injected replace failure") })
	if err == nil {
		t.Fatal("failed replacement reported success")
	}
	got, _ := os.ReadFile(path)
	if !bytes.Equal(old, got) {
		t.Fatal("failed replacement changed old measurement")
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil || len(entries) != 1 {
		t.Fatal("failed replacement left temporary files", err)
	}
	failed.ObservedMM = 0
	if err = saveCalibration(path, failed); err == nil {
		t.Fatal("invalid replacement accepted")
	}
	got, _ = os.ReadFile(path)
	if !bytes.Equal(old, got) {
		t.Fatal("invalid measurement replaced old measurement")
	}
	// Saving the same baseline measurement again, then loading it, is idempotent.
	if err = saveCalibration(path, r); err != nil {
		t.Fatal(err)
	}
	loaded, err := readCalibration(path)
	if err != nil || loaded == nil || *loaded != r {
		t.Fatal("saved calibration did not roundtrip", err)
	}
}

func TestCalibrationCommandRejectsLabAndLiveBrokerCombinations(t *testing.T) {
	for _, o := range []options{
		{SaveRulerObservedMM: "57.5"},
		{SaveRulerObservedMM: "57.5", InstalledTSF: true, BrokerPID: 1},
		{SaveRulerObservedMM: "57.5", InstalledTSF: true, InstalledSmoke: true},
	} {
		if err := execute(o); err == nil || !strings.Contains(err.Error(), "saving calibration requires") {
			t.Fatal("save command reached the interactive/lab path", err)
		}
	}
}

func TestCalibrationSaveRejectsNonRuntimeBaselineBeforeInstallationOrWrite(t *testing.T) {
	// No installation path is supplied: the specific baseline error must occur
	// before installation reads, monitor queries, directory creation or writes.
	err := execute(options{InstalledTSF: true, SaveRulerObservedMM: "57.5", ScreenMM: 500, ObservedMM: 100})
	if err == nil || !strings.Contains(err.Error(), "requires the ordinary Runtime baseline") || !strings.Contains(err.Error(), "nondefault baseline was not saved") {
		t.Fatal("nondefault screen baseline reached the save path", err)
	}
}
