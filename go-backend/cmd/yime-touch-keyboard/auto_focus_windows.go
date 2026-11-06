//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"time"
)

const autoFocusTimer = 0x18F0
const autoFocusReviewMessage = "上次提交结果未确认；请先核对正文，再点“核对后继续”。旧提交不会补发"

func (a *ui) autoFocusAllowed() bool {
	if a.follow == nil || a.follow.stopped || a.autoMinimized || a.touchHelpOpen || a.touchSettingsOpen || a.calibrationOpen || a.diagnosticOpen {
		return false
	}
	return true
}

// Focus events only revoke state. They never enter IPC, rebuild the engine, or
// authorize a gesture that began under another document/activation.
func (a *ui) autoFocusChanged() {
	if a.follow == nil {
		return
	}
	a.loseHostFocus("输入焦点已变化；旧组合已取消，等待当前正文")
}

func (a *ui) stopAutoFocus() {
	if a.follow != nil {
		a.follow.stop()
	}
	if a.tsf != nil {
		client := a.tsf
		a.tsf = nil
		go client.Close()
	}
}

func (a *ui) resumeAutoFocus() {
	if a.follow == nil || a.follow.stopped || a.hostBusy {
		return
	}
	a.loseHostFocus("已结束旧会话；等待当前正文，旧提交不会补发")
	a.host.blocked = false // This is the sole installed-UI acknowledgement path.
	a.status = "已核对；等待当前正文，只接受新的输入"
	a.touchMessage = ""
	a.diagnosticSummary = ""
	a.follow.lastAttempt = time.Time{}
}

// Called on the UI timer, never on a WinEvent callback. A single worker handles
// discovery or read-only status; only this UI thread adopts its result.
func (a *ui) pollAutoFocus(now time.Time) {
	f := a.follow
	if f == nil || f.stopped || a.hostBusy {
		return
	}
	allowed := a.autoFocusAllowed()
	if !allowed && !f.suspended {
		f.suspended = true
		a.loseHostFocus("键盘已暂停；返回后自动跟随当前正文")
	} else if allowed && f.suspended {
		f.suspended = false
		f.lastAttempt = time.Time{}
	}
	if r, ok := f.take(); ok {
		// Drain queued focus notifications before accepting a result. Nested
		// timer callbacks are inert while hostBusy; stale results cannot rebind.
		a.hostBusy = true
		stable := pumpHostMessages()
		a.hostBusy = false
		current := a.host.current()
		adopt := stable && a.autoFocusAllowed() && !a.host.blocked && f.matches(r, current)
		if r.binding {
			if !adopt || r.err != nil {
				if r.client != nil {
					go r.client.Close()
				}
				if adopt {
					a.status = "当前正文尚不可输入；请确认已选择专用18u输入法"
					a.recordAutoFocusDiagnostic(r.target, "auto-discovery", r.err)
				}
			} else {
				a.hostBusy = true
				a.cancel()
				err := a.host.bindAutomatic(current)
				if err == nil {
					a.tsf = r.client
					err = a.rebuildHostPreview()
				}
				if err != nil {
					if a.tsf != r.client {
						go r.client.Close()
					}
					a.loseHostFocus("输入会话建立失败；等待新的目标状态")
				} else {
					a.host.last = "已跟随当前正文；仅确认后的文字通过 TSF 提交"
					a.status = a.host.last
					a.touchMessage = ""
				}
				a.hostBusy = false
				a.recordAutoFocusDiagnostic(r.target, "auto-bound", err)
			}
		} else if adopt && a.tsf == r.client && r.err != nil {
			// A status failure has sent no mutation. Revoke and discover afresh;
			// it cannot clear a previous edit's independent review latch.
			a.loseHostFocus("正文或输入法状态已变化；旧组合已取消")
			a.recordAutoFocusDiagnostic(r.target, "auto-status", r.err)
		}
		a.invalidate()
	}
	if !a.autoFocusAllowed() || a.host.blocked || f.pending || len(a.previewTouches) != 0 {
		return
	}
	current := a.host.current()
	if current == (hostTarget{}) {
		if a.tsf != nil {
			a.loseHostFocus("等待可输入的正文")
		}
		return
	}
	if a.tsf != nil && !a.host.valid(a.host.ticket()) {
		a.loseHostFocus("输入目标已变化；旧组合已取消")
	}
	interval := time.Second // Bounded retries only for non-mutating discovery.
	if a.tsf != nil {
		interval = 300 * time.Millisecond
	}
	if now.Sub(f.lastAttempt) < interval {
		return
	}
	if a.tsf == nil {
		tick, _, _ := k32.NewProc("GetTickCount").Call()
		a.focusStarted = uint32(tick)
	}
	f.start(now, current, a.tsf)
}

// Validate the TIP context before accepting a completed logical action, even
// when its HWND is unchanged. An intervening switch cancels this action; it is
// never rebound or replayed against the newly discovered target.
func (a *ui) validateAutoFocus(ticket deliveryTicket, generation uint64) bool {
	if a.follow == nil {
		return true
	}
	client := a.tsf
	if !a.autoFocusAllowed() || client == nil || !a.host.valid(ticket) {
		return false
	}
	if err := a.awaitAutoFocusStatus(client, ticket, generation); err != nil {
		a.loseHostFocus("正文上下文已失效；本次动作取消")
		return false
	}
	if !pumpHostMessages() || a.tsf != client || generation != a.cancelGeneration || !a.host.valid(ticket) || !a.autoFocusAllowed() {
		a.loseHostFocus("输入焦点已变化；本次动作取消")
		return false
	}
	return true
}

// Only IPC runs on the worker. Keep painting and processing focus/minimize/quit
// notifications while the host is slow; hostBusy prevents gesture reentrancy.
// Abandoning this read-only request cannot create an unknown text mutation.
func (a *ui) awaitAutoFocusStatus(client frontendSession, ticket deliveryTicket, generation uint64) error {
	result := make(chan error, 1)
	go func() { result <- client.Status() }()
	timeout := time.NewTimer(5 * time.Second)
	pump := time.NewTicker(10 * time.Millisecond)
	defer timeout.Stop()
	defer pump.Stop()
	for {
		select {
		case err := <-result:
			return err
		case <-timeout.C:
			return fmt.Errorf("target status timed out; no edit sent")
		case <-pump.C:
			if !pumpHostMessages() || a.tsf != client || generation != a.cancelGeneration || !a.host.valid(ticket) || !a.autoFocusAllowed() {
				return fmt.Errorf("target changed while checking status; no edit sent")
			}
		}
	}
}

func (a *ui) recordAutoFocusDiagnostic(target hostTarget, stage string, err error) {
	key := fmt.Sprintf("%v/%s/%v", target, stage, err)
	if key == a.autoDiagnostic {
		return
	}
	a.autoDiagnostic = key
	if a.h == 0 {
		return
	} // Memory-only fixtures never write user diagnostics.
	d := diagnosticTarget()
	if d.Window != target.Window || d.Focus != target.Focus {
		return
	}
	a.recordFrontendDiagnostic(d, stage, err)
}
