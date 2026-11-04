package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"strings"
	"time"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

const calibrationSchema = "yimecore-18u-display-calibration-v1"
const defaultScreenWidthMM = 597.73 // Also used by the ordinary Runtime's GUI launch.

func calibrationDirectory(localAppData string) string {
	return filepath.Join(localAppData, "YimeCore 18u Touch", "display-calibration")
}

type calibrationDisplay struct {
	Device, InterfaceID string
	Width, Height       int
}

// Measurements always refer to the baseline reference, never the previous
// saved correction. The display identity is supplied by Windows, not inferred
// from an EDID size, DPI scale, or the measured keyboard geometry.
type calibrationRecord struct {
	Schema                string  `json:"schema"`
	MonitorDevice         string  `json:"monitorDevice"`
	MonitorInterfaceID    string  `json:"monitorInterfaceID"`
	WidthPixels           int     `json:"widthPixels"`
	HeightPixels          int     `json:"heightPixels"`
	BaselineScreenWidthMM float64 `json:"baselineScreenWidthMM"`
	ReferenceMM           float64 `json:"referenceMM"`
	ObservedMM            float64 `json:"observedMM"`
	MeasurementSource     string  `json:"measurementSource"`
	RecordedUTC           string  `json:"recordedUTC"`
}

func calibrationFile(directory string, display calibrationDisplay) string {
	digest := sha256.Sum256([]byte(display.Device + "\x00" + display.InterfaceID))
	return filepath.Join(directory, hex.EncodeToString(digest[:])+".json")
}

func (r calibrationRecord) validate() error {
	if r.Schema != calibrationSchema || r.MeasurementSource != "physical-ruler" || r.ReferenceMM != 100 || strings.TrimSpace(r.MonitorDevice) == "" || strings.TrimSpace(r.MonitorInterfaceID) == "" || len(r.MonitorDevice) > 128 || len(r.MonitorInterfaceID) > 1024 || r.WidthPixels <= 0 || r.HeightPixels <= 0 {
		return errors.New("invalid 18u display calibration identity")
	}
	if _, err := time.Parse(time.RFC3339, r.RecordedUTC); err != nil {
		return errors.New("invalid calibration measurement timestamp")
	}
	p, err := tk.PixelsPerMM(r.WidthPixels, r.BaselineScreenWidthMM)
	if err != nil {
		return err
	}
	_, err = tk.Calibrate(p, r.ReferenceMM, r.ObservedMM)
	return err
}

func (r calibrationRecord) pixelsPerMM(display calibrationDisplay, baselineMM, observedMM float64) (float64, error) {
	if err := r.validate(); err != nil {
		return 0, err
	}
	if r.MonitorDevice != display.Device || r.MonitorInterfaceID != display.InterfaceID || r.WidthPixels != display.Width || r.HeightPixels != display.Height || r.BaselineScreenWidthMM != baselineMM {
		return 0, errors.New("saved calibration does not match this display, resolution or baseline; measure its baseline reference before saving")
	}
	if observedMM != 100 {
		return 0, errors.New("saved calibration cannot be combined with another ruler correction")
	}
	p, err := tk.PixelsPerMM(display.Width, baselineMM)
	if err != nil {
		return 0, err
	}
	return tk.Calibrate(p, r.ReferenceMM, r.ObservedMM)
}

func decodeCalibration(raw []byte) (calibrationRecord, error) {
	var r calibrationRecord
	if len(raw) > 8192 {
		return r, errors.New("calibration JSON exceeds 8192 bytes")
	}
	// encoding/json otherwise silently accepts duplicate fields. This schema is
	// deliberately flat, so reject duplicate root keys before typed decoding.
	d := json.NewDecoder(bytes.NewReader(raw))
	token, err := d.Token()
	if err != nil || token != json.Delim('{') {
		return r, errors.New("calibration must be one JSON object")
	}
	seen := map[string]bool{}
	for d.More() {
		token, err = d.Token()
		if err != nil {
			return r, err
		}
		key, ok := token.(string)
		if !ok || seen[key] {
			return r, errors.New("duplicate calibration JSON field")
		}
		seen[key] = true
		var value json.RawMessage
		if err = d.Decode(&value); err != nil {
			return r, err
		}
	}
	if _, err = d.Token(); err != nil {
		return r, err
	}
	if err = d.Decode(new(any)); err != io.EOF {
		return r, errors.New("calibration must contain exactly one JSON object")
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err = d.Decode(&r); err != nil {
		return r, err
	}
	return r, r.validate()
}

func readCalibration(path string) (*calibrationRecord, error) {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > 8192 {
		return nil, errors.New("calibration must be a regular JSON file of at most 8192 bytes")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	r, err := decodeCalibration(raw)
	return &r, err
}

func saveCalibration(path string, r calibrationRecord) error {
	return saveCalibrationReplacing(path, r, os.Rename)
}

func saveCalibrationReplacing(path string, r calibrationRecord, replace func(string, string) error) error {
	if err := r.validate(); err != nil {
		return err
	}
	if info, err := os.Lstat(path); err == nil && !info.Mode().IsRegular() {
		return errors.New("calibration destination is not a regular file")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	raw, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".calibration-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(append(raw, '\n')); err != nil {
		f.Close()
		return err
	}
	if err = f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	// Same-directory replacement: a failed write/rename leaves the old record.
	return replace(f.Name(), path)
}

func calibratedWindowSize(widthU, heightU, ppm float64, header, preferredBorder, workWidth, workHeight int, compactMargin bool) (width, height, margin int, err error) {
	if math.IsNaN(ppm) || math.IsInf(ppm, 0) || ppm <= 0 || workWidth <= 0 || workHeight <= 0 {
		return 0, 0, 0, errors.New("invalid calibrated window dimensions")
	}
	keyWidth := math.Ceil(widthU * tk.UnitMM * ppm)
	keyHeight := math.Ceil(heightU * tk.UnitMM * ppm)
	if keyWidth > float64(workWidth) || keyHeight+float64(header) > float64(workHeight) {
		return 0, 0, 0, fmt.Errorf("calibrated keyboard body exceeds the monitor; key pitch was not reduced")
	}
	margin = preferredBorder
	if compactMargin {
		margin = min(margin, (workWidth-int(keyWidth))/2, workHeight-int(keyHeight)-header)
	}
	width, height = int(keyWidth)+2*margin, int(keyHeight)+header+margin
	if width > workWidth || height > workHeight {
		return 0, 0, 0, errors.New("calibrated keyboard and outer margin exceed the monitor")
	}
	return width, height, margin, nil
}
