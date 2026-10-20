package main

import (
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// A delivery epoch is explicitly bound by the user, never inferred from an UP
// or a response. Process/thread identity also rejects recycled window handles.
type hostTarget struct {
	Window, Focus   uintptr
	Process, Thread uint32
}
type deliveryTicket struct {
	target hostTarget
	epoch  uint64
}
type deliveryGate struct {
	target  hostTarget
	epoch   uint64
	blocked bool
	seen    map[string]bool
	current func() hostTarget
	send    func(hostTarget, tk.Output) error
	last    string
}

// Diagnostics pin their target provider for the entire run, including recovery
// binds. A foreign foreground window must never become an authorized fixture.
func (g *deliveryGate) restrictTarget(allowed hostTarget) {
	current := g.current
	g.current = func() hostTarget {
		if t := current(); t == allowed {
			return t
		}
		return hostTarget{}
	}
}

func (g *deliveryGate) bind(t hostTarget) error {
	if t.Window == 0 || t.Focus == 0 || t.Process == 0 || t.Thread == 0 || t != g.current() {
		return fmt.Errorf("请先在目标应用文本区放置光标")
	}
	g.epoch++
	g.target, g.blocked, g.seen = t, false, map[string]bool{}
	g.last = "目标已绑定；仅明确确认的文本会提交"
	return nil
}
func (g *deliveryGate) ticket() deliveryTicket { return deliveryTicket{g.target, g.epoch} }
func (g *deliveryGate) valid(t deliveryTicket) bool {
	return !g.blocked && t.target.Window != 0 && t.epoch == g.epoch && t.target == g.target && t.target == g.current()
}
func (g *deliveryGate) invalidate(reason string) {
	g.epoch++
	g.target = hostTarget{}
	g.last = reason
}
func (g *deliveryGate) deliver(t deliveryTicket, id string, o tk.Output) error {
	if !g.valid(t) {
		return fmt.Errorf("目标或焦点世代已失效；取消本次输出，请重新绑定")
	}
	if id == "" || g.seen[id] {
		return fmt.Errorf("重复或无身份输出已拒绝")
	}
	// Consume before calling the OS. A failed/partial/unknown send is never replayed.
	g.seen[id] = true
	if err := g.send(t.target, o); err != nil {
		g.blocked = true
		g.last = "发送失败或结果不明；核对目标文本后重新绑定，不自动补发"
		return fmt.Errorf("%s: %w", g.last, err)
	}
	if !g.valid(t) {
		g.blocked = true
		g.last = "发送期间焦点变化；结果不明，请核对文本并重新绑定"
		return fmt.Errorf("%s", g.last)
	}
	g.last = "输入事件已发送；实际宿主接收仍需观察"
	return nil
}
