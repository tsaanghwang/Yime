//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"strconv"
	"strings"
)

var calibrationActions = []string{"measure:7", "measure:8", "measure:9", "measure:4", "measure:5", "measure:6", "measure:1", "measure:2", "measure:3", "measure:.", "measure:0", "measure:back", "measure:cancel", "measure:clear", "measure:apply"}

func (a *ui) settingsActions() []string {
	if a.calibrationOpen {
		return calibrationActions
	}
	return touchSettings
}

func measuredPPM(current float64, input string) (float64, error) {
	observed, err := strconv.ParseFloat(input, 64)
	if err != nil || observed < 1 || observed > 1000 {
		return current, fmt.Errorf("请输入 1–1000 mm 的实测长度")
	}
	ppm, err := tk.Calibrate(current, 100, observed)
	if err != nil {
		return current, err
	}
	return ppm, nil
}

func (a *ui) calibrationAction(action string) error {
	value := strings.TrimPrefix(action, "measure:")
	switch value {
	case "cancel":
		a.calibrationOpen = false
	case "clear":
		a.calibrationInput = ""
	case "back":
		if len(a.calibrationInput) > 0 {
			a.calibrationInput = a.calibrationInput[:len(a.calibrationInput)-1]
		}
	case "apply":
		ppm, err := measuredPPM(a.ppm, a.calibrationInput)
		if err != nil {
			return err
		}
		if err = a.changeCalibration(ppm); err != nil {
			return err
		}
		a.calibrationOpen = false
		a.touchRuler = true
	default:
		if len(value) != 1 || !strings.Contains("0123456789.", value) {
			return fmt.Errorf("无效校准按键")
		}
		if len(a.calibrationInput) >= 8 || value == "." && strings.Contains(a.calibrationInput, ".") {
			return nil
		}
		a.calibrationInput += value
	}
	return nil
}

func (a *ui) changeCalibration(ppm float64) error {
	oldPPM, oldTop := a.ppm, a.top
	oldFit := a.fitScreen
	a.ppm = ppm
	a.fitScreen = false
	if !a.resize() {
		a.ppm, a.top = oldPPM, oldTop
		a.fitScreen = oldFit
		return fmt.Errorf("当前尺寸超出屏幕或窗口调整失败；校准未改变")
	}
	if err := a.updateTouchFonts(); err != nil {
		a.ppm, a.top = oldPPM, oldTop
		a.fitScreen = oldFit
		if !a.resize() {
			return fmt.Errorf("%w；无法恢复窗口尺寸，请关闭后重新打开", err)
		}
		return err
	}
	return nil
}

func centeredResize(current, work rect, width, height int32) rect {
	// Preserve the existing centre, including a deliberately moved window.
	current.L += (current.R - current.L - width) / 2
	current.T += (current.B - current.T - height) / 2
	return clampWindow(current, work, width, height)
}
