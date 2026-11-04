//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"syscall"
	"time"
	"unsafe"
)

type calibrationDisplayDevice struct {
	Size         uint32
	Name         [32]uint16
	Description  [128]uint16
	StateFlags   uint32
	ID, Registry [128]uint16
}

func identifyCalibrationDisplay(m monitor) (calibrationDisplay, error) {
	display := calibrationDisplay{Device: syscall.UTF16ToString(m.Device[:]), Width: int(m.Monitor.R - m.Monitor.L), Height: int(m.Monitor.B - m.Monitor.T)}
	if display.Device == "" || display.Width <= 0 || display.Height <= 0 {
		return display, errors.New("cannot identify the current physical-pixel monitor")
	}
	for i := 0; i < 16; i++ {
		d := calibrationDisplayDevice{}
		d.Size = uint32(unsafe.Sizeof(d))
		ok, _, _ := U("EnumDisplayDevicesW").Call(ptr(str(display.Device)), uintptr(i), uintptr(unsafe.Pointer(&d)), 1) // EDD_GET_DEVICE_INTERFACE_NAME
		if ok == 0 {
			break
		}
		if d.StateFlags&1 == 0 { // DISPLAY_DEVICE_ACTIVE
			continue
		}
		id := syscall.UTF16ToString(d.ID[:])
		if id == "" || display.InterfaceID != "" {
			return display, errors.New("monitor interface identity is unavailable or ambiguous; calibration was not applied")
		}
		display.InterfaceID = id
	}
	if display.InterfaceID == "" {
		return display, errors.New("monitor interface identity unavailable; calibration was not applied")
	}
	return display, nil
}

func installedCalibration(o options, m monitor, originalPPM float64) (float64, *calibrationRecord, string, error) {
	root, err := os.UserCacheDir() // Windows: this initiating user's LocalAppData.
	if err != nil {
		return 0, nil, "", err
	}
	directory := calibrationDirectory(root)
	if o.SaveRulerObservedMM == "" {
		if _, err = os.Stat(directory); os.IsNotExist(err) {
			return originalPPM, nil, "", nil // Preserve the unconfigured startup path.
		} else if err != nil {
			return 0, nil, "", err
		}
	}
	display, err := identifyCalibrationDisplay(m)
	if err != nil {
		return 0, nil, "", err
	}
	path := calibrationFile(directory, display)
	var record *calibrationRecord
	if o.SaveRulerObservedMM != "" {
		observed, parseErr := strconv.ParseFloat(o.SaveRulerObservedMM, 64)
		if parseErr != nil {
			return 0, nil, "", fmt.Errorf("invalid physical ruler measurement: %w", parseErr)
		}
		record = &calibrationRecord{Schema: calibrationSchema, MonitorDevice: display.Device, MonitorInterfaceID: display.InterfaceID, WidthPixels: display.Width, HeightPixels: display.Height, BaselineScreenWidthMM: o.ScreenMM, ReferenceMM: 100, ObservedMM: observed, MeasurementSource: "physical-ruler", RecordedUTC: time.Now().UTC().Format(time.RFC3339)}
	} else {
		record, err = readCalibration(path)
		if err != nil || record == nil {
			return originalPPM, nil, path, err
		}
	}
	ppm, err := record.pixelsPerMM(display, o.ScreenMM, o.ObservedMM)
	return ppm, record, path, err
}

func (a *ui) saveInstalledCalibration(path string, record calibrationRecord, m monitor) error {
	// Validate the full calibrated window before replacing any existing setting.
	header := a.touchHeaderLayout().height
	w, h, margin, err := calibratedWindowSize(a.s.Board.Bounds.Width, a.s.Board.Bounds.Height, a.ppm, header, border, int(m.Work.R-m.Work.L), int(m.Work.B-m.Work.T), true)
	if err != nil {
		return err
	}
	if err = saveCalibration(path, record); err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{
		"status": "saved-for-next-start", "configurationPath": path, "measurement": record,
		"baselinePixelsPerMM":   float64(record.WidthPixels) / record.BaselineScreenWidthMM,
		"calibratedPixelsPerMM": a.ppm, "referencePixels": math.Round(100 * a.ppm),
		"keyboardBodyWidthPixels": w - 2*margin, "outerMarginPixels": margin, "windowWidthPixels": w, "windowHeightPixels": h,
		"liveProcessUnchanged": true, "physicalAcceptance": false,
	})
}
