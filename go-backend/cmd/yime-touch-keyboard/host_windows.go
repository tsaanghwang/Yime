//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

const hostHelp = "P4 中文宿主输入实验\n\n先在目标应用文本区点好光标，再点“绑定目标”。键盘不改变已安装输入法或默认选择。\n组合仅显示在键盘内；候选/空格/Enter 确认后一次性发送 Unicode。Esc 只取消键盘组合。\n焦点离开（即使再返回）、隐藏、显示环境变化或帮助打开后取消组合与旧触点；需要重新绑定。重新绑定不会清空宿主正文。\n无中文组合时，编辑键和 Ctrl/Alt 快捷键发往绑定目标；侧区仍保持 literal 旁路。\n发送失败、部分发送或发送期间失焦会停止后续提交。先人工核对正文，再重新绑定；绝不自动重放或回滚。\nSendInput 发送数不等于应用接受。Windows 没有原子绑定 HWND 的 SendInput，发送瞬间切换焦点有结果不明风险；不要在确认时切换应用。真实宿主、手指/笔和 ARM64 原生验收仍须分别记录。"

func currentHostTarget(own uintptr) hostTarget {
	t := foreground()
	if !valid(t, own) {
		return hostTarget{}
	}
	var pid uint32
	thread, _, _ := U("GetWindowThreadProcessId").Call(t.Focus, uintptr(unsafe.Pointer(&pid)))
	if thread == 0 || pid == 0 {
		return hostTarget{}
	}
	return hostTarget{t.Window, t.Focus, pid, uint32(thread)}
}
func (a *ui) initHost() {
	a.host = &deliveryGate{current: func() hostTarget { return currentHostTarget(a.h) }}
	a.host.send = func(t hostTarget, o tk.Output) error {
		if currentHostTarget(a.h) != t {
			return fmt.Errorf("绑定目标身份已变化，未发送")
		}
		return sendOutputTo(o, target{t.Window, t.Focus})
	}
	a.status = "请在目标文本区点光标，再点“绑定目标”；组合不会自动提交"
}

// Pump already queued focus callbacks before validating an action/commit. UI
// gesture handlers refuse reentrancy while hostBusy; callbacks only invalidate
// display/epoch, never call the engine. Dispatch itself stays synchronous.
func pumpHostMessages() bool {
	for i := 0; i < 256; i++ {
		var m message
		ok, _, _ := U("PeekMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0, 1)
		if ok == 0 {
			return true
		}
		if m.M == 0x12 {
			U("PostQuitMessage").Call(m.W)
			return false
		}
		U("TranslateMessage").Call(uintptr(unsafe.Pointer(&m)))
		U("DispatchMessageW").Call(uintptr(unsafe.Pointer(&m)))
	}
	return false
}
func (a *ui) loseHostFocus(reason string) {
	a.host.invalidate(reason)
	a.cancel()
	a.preview.fault = true
	a.preview.snapshot.State = engineapi.State{}
	a.status = reason
	a.invalidate()
}
func (a *ui) hostSink(ticket deliveryTicket) {
	a.preview.emit = func(id string, o tk.Output) error {
		if !pumpHostMessages() {
			a.loseHostFocus("消息队列未稳定；提交取消")
			return fmt.Errorf("消息队列未稳定，不发送")
		}
		// Standalone whitespace commits are editing keys at a Windows host;
		// Unicode LF is not equivalent to Return in every native EDIT control.
		if o.Text == "\n" {
			o.Text = ""
			o.Key = "Enter"
		}
		if o.Text == "\t" {
			o.Text = ""
			o.Key = "Tab"
		}
		return a.host.deliver(ticket, id, o)
	}
}
func (a *ui) bindHost() error {
	// No queued focus notification from the old epoch may be accepted as new.
	a.hostBusy = true
	defer func() { a.hostBusy = false }()
	if !pumpHostMessages() {
		a.loseHostFocus("消息队列未稳定；绑定取消")
		return fmt.Errorf("消息队列未稳定")
	}
	a.cancel()
	if err := a.host.bind(currentHostTarget(a.h)); err != nil {
		a.loseHostFocus("绑定失败；请在目标文本区放置光标")
		return err
	}
	tick, _, _ := k32.NewProc("GetTickCount").Call()
	a.focusStarted = uint32(tick)
	old := a.preview
	old.retire()
	p, err := newPreview(old.sessions, old.layout, old.englishView)
	if err != nil {
		a.host.invalidate("会话重建失败")
		return err
	}
	if old.mode != "variable" {
		if err = p.switchMode(old.mode); err != nil {
			p.retire()
			a.host.invalidate("会话重建失败")
			return err
		}
	}
	p.literalEntries = old.literalEntries
	if old.snapshot.Modes.Input == "english" {
		if err = p.dispatch(keyboardlab.Event{Type: "setModes", InputMode: "english", PunctuationMode: "english"}); err != nil {
			p.retire()
			a.host.invalidate("会话重建失败")
			return err
		}
	}
	a.preview = p
	a.hostSink(a.host.ticket())
	a.s.Original = p.original()
	a.status = a.host.last
	return nil
}
