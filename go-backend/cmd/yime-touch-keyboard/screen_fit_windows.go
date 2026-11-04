//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"math"
	"syscall"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// Screen fitting is display zoom, never a physical monitor calibration.
// The original ppm is retained for the ruler and explicit calibrated mode.
func (a *ui) displayPPM() float64 {
	if a.fitScreen && a.fittedPPM > 0 {
		return a.fittedPPM
	}
	return a.ppm
}

func (a *ui) windowGeometry(ppm float64) (width, height, header int) {
	header = a.top
	if a.o.TouchUI {
		view := *a
		view.fitScreen, view.ppm = false, ppm
		header = view.touchHeaderLayout().height
	}
	width = int(math.Ceil(a.s.Board.Bounds.Width*tk.UnitMM*ppm)) + 2*a.border
	height = int(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*ppm)) + header + a.border
	return
}

func (a *ui) fittedScale(work rect) (float64, error) {
	w, h := int(work.R-work.L), int(work.B-work.T)
	if !a.o.TouchUI || w <= 2*a.border || h <= 0 || a.s == nil || a.s.Board.Bounds.Width <= 0 {
		return 0, fmt.Errorf("当前屏幕工作区无法容纳触屏键盘")
	}
	fits := func(ppm float64) bool {
		width, height, _ := a.windowGeometry(ppm)
		return width <= w && height <= h
	}
	if !fits(0) {
		return 0, fmt.Errorf("当前屏幕工作区高度不足")
	}
	// Width gives an upper bound. Header rounding/minimum text sizes are
	// included in the height check, rather than fitting the key grid alone.
	lo, hi := 0.0, float64(w-2*a.border)/(a.s.Board.Bounds.Width*tk.UnitMM)
	for i := 0; i < 60; i++ {
		mid := (lo + hi) / 2
		if fits(mid) {
			lo = mid
		} else {
			hi = mid
		}
	}
	if lo <= 0 || math.IsNaN(lo) || math.IsInf(lo, 0) {
		return 0, fmt.Errorf("无法计算适应屏幕的盘面尺寸")
	}
	return lo, nil
}

func bottomCentered(work rect, width, height int32) rect {
	left := work.L + (work.R-work.L-width)/2
	return rect{left, work.B - height, left + width, work.B}
}

func (a *ui) fitCurrentScreen() error {
	if a.sizingBusy {
		return nil
	}
	a.sizingBusy = true
	defer func() { a.sizingBusy = false }()
	m := currentMonitor(a.h)
	ppm, err := a.fittedScale(m.Work)
	if err != nil {
		return err
	}
	oldFit, oldScale, oldTop := a.fitScreen, a.fittedPPM, a.top
	a.fitScreen, a.fittedPPM = true, ppm
	if !a.resize() {
		a.fitScreen, a.fittedPPM, a.top = oldFit, oldScale, oldTop
		return fmt.Errorf("适应屏幕失败；保留原尺寸")
	}
	if err := a.updateTouchFonts(); err != nil {
		a.fitScreen, a.fittedPPM, a.top = oldFit, oldScale, oldTop
		if !a.resize() {
			return fmt.Errorf("%w；无法恢复窗口尺寸，请关闭后重新打开", err)
		}
		return err
	}
	a.monitorName = syscall.UTF16ToString(m.Device[:])
	a.status = "已适应屏幕可用区域；盘面等比缩放，实测毫米校准保持独立"
	return nil
}

func (a *ui) displayChanged() {
	if a.sizingBusy {
		return
	}
	if a.host != nil {
		a.loseHostFocus("显示环境已变化；请复核后重新绑定")
	}
	a.cancel()
	if a.fitScreen {
		if err := a.fitCurrentScreen(); err != nil {
			a.status = err.Error()
		} else if a.host != nil {
			a.status = "已适应新的屏幕工作区；请在正文重新绑定"
		}
	} else {
		a.status = "Display changed. Recheck monitor width and ruler calibration before use."
	}
	a.invalidate()
}
