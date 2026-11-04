//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"math"
)

const ownDemoTimer = 0x5944

type ownDemo struct {
	client     *demoClient
	root, data string
	closeErr   error
}

func (a *ui) initOwnDemo() error {
	s, e := bridge.Open(a.o.Root, a.o.DataDir, "variable", bridge.Focus{Context: "own-demo-host", Epoch: 1})
	if e != nil {
		return e
	}
	identity := s.Identity()
	_ = s.Close()
	if a.s.Board.LayoutID != identity.LayoutSHA256 {
		return fmt.Errorf("UI layout and isolated dictionary identity mismatch")
	}
	c, e := startDemoClient(a.o.Root, identity, a.o.OwnTSFDemoSmoke)
	if e != nil {
		return e
	}
	a.demo = &ownDemo{client: c, root: a.o.Root, data: a.o.DataDir}
	p, e := newBridgePreview(a.o.Root, a.o.DataDir, bridge.Focus{Context: "own-demo-host", Epoch: c.epoch}, c.submit)
	if e != nil {
		c.stop()
		return e
	}
	a.preview = p
	a.stopDemoSession("自有 TSF 演示：点击“重绑”启用；固定 CN/变码")
	return nil
}
func (a *ui) stopDemoSession(reason string) {
	if a.preview != nil && !a.preview.fault {
		a.preview.retire()
		a.preview.snapshot.State = engineapi.State{}
		a.cancel()
	}
	a.status = reason
	a.touchMessage = reason
}
func (a *ui) pollOwnDemo() error {
	if a.demo == nil {
		return nil
	}
	c := a.demo.client
	if c.closed {
		return fmt.Errorf("自有宿主已关闭；不会自动重启")
	}
	r, e := c.call("read", nil)
	if e != nil {
		a.stopDemoSession("宿主断连：显示仅为最后确认读回；请关闭演示")
		return e
	}
	if !r.Active {
		a.stopDemoSession("绑定已失效；组合取消，请点击“重绑”")
		return fmt.Errorf("own host inactive")
	}
	return nil
}
func (a *ui) rebindOwnDemo() error {
	if a.demo == nil {
		return fmt.Errorf("missing own host")
	}
	c := a.demo.client
	// Always invalidate the previous session before asking for a new activation.
	a.stopDemoSession("正在显式重绑")
	a.cancel()
	if c.closed {
		return fmt.Errorf("宿主断连；禁止自动重启")
	}
	if c.last.Active {
		if _, e := c.call("invalidate", nil); e != nil {
			return e
		}
	}
	U("AllowSetForegroundWindow").Call(uintptr(c.cmd.Process.Pid)) // Only our verified child.
	if _, e := c.call("rebind", nil); e != nil {
		return e
	}
	p, e := newBridgePreview(a.demo.root, a.demo.data, bridge.Focus{Context: "own-demo-host", Epoch: c.epoch}, c.submit)
	if e != nil {
		c.stop()
		return e
	}
	if demoID(p.bridge.session.Identity()) != c.identity {
		p.retire()
		c.stop()
		return fmt.Errorf("resource identity changed")
	}
	a.preview = p
	p.bridge.before = a.pollOwnDemo
	a.cancel()
	a.touchMessage = ""
	a.status = "自有 TSF 已绑定；仅正文读回，不向其他应用输入"
	return nil
}
func (a *ui) invalidateOwnDemo() {
	if a.demo == nil {
		return
	}
	c := a.demo.client
	if !c.closed {
		_, _ = c.call("invalidate", nil)
	}
	a.stopDemoSession("演示已暂停；恢复后请显式重绑")
}
func (a *ui) closeOwnDemo() {
	if a.demo == nil {
		return
	}
	if a.preview != nil {
		a.preview.retire()
	}
	if a.demo.client.closed {
		return
	}
	if e := a.demo.client.close(); e != nil {
		a.demo.closeErr = e
		a.status = e.Error()
	}
}
func (a *ui) ownDemoOutput() string {
	if a.demo == nil {
		return ""
	}
	label := "宿主实际读回（只读）"
	if a.demo.client.closed {
		label = "最后确认读回（宿主已断连）"
	}
	return label + "：" + a.demo.client.last.ReadbackText
}

// Explicit CI-only development evidence. Same executable, verified full corpus,
// real windowProc hit testing and native own-document edits; no physical input.
func (a *ui) ownDemoSmoke() error {
	probe, e := hostProbeCodes(a.o.Root)
	if e != nil {
		return e
	}
	tap := func(x, y int32) {
		packed := uintptr(uint32(uint16(x)) | uint32(uint16(y))<<16)
		U("SendMessageW").Call(a.h, 0x0201, 0, packed)
		U("SendMessageW").Call(a.h, 0x0202, 0, packed)
	}
	key := func(code string) error {
		for _, k := range a.s.Board.Keys {
			v := a.s.View(k)
			if v.Action.Type == "input" && v.Action.ASCII == code {
				r := k.Rectangles[0]
				tap(int32(math.Round(float64(a.border)+(k.X+r.X+r.Width/2)*tk.UnitMM*a.displayPPM())), int32(math.Round(float64(a.top)+(k.Y+r.Y+r.Height/2)*tk.UnitMM*a.displayPPM())))
				return nil
			}
		}
		return fmt.Errorf("canonical input missing on own UI")
	}
	bind := func() error {
		for _, k := range a.s.Board.Keys {
			if k.Action.Type == "touch-ui" && k.Action.Key == "reset" {
				r := a.keyPixelRect(k)
				tap((r.L+r.R)/2, (r.T+r.B)/2)
				if a.preview.fault {
					return fmt.Errorf("actual UI rebind failed: %s", a.status)
				}
				return nil
			}
		}
		return fmt.Errorf("own UI rebind control missing")
	}
	if e = bind(); e != nil {
		return e
	}
	expected := ""
	for n := 0; n < 2; n++ {
		for _, code := range probe["variable"] {
			if e = key(string(code)); e != nil {
				return e
			}
		}
		if len(a.preview.snapshot.State.Candidates) == 0 {
			return fmt.Errorf("full corpus produced no candidates")
		}
		expected += a.preview.snapshot.State.Candidates[0].Text
		r := a.candidateRect(0)
		x, y := (r.L+r.R)/2, (r.T+r.B)/2
		tap(x, y)
		U("SendMessageW").Call(a.h, 0x0202, 0, uintptr(uint32(uint16(x))|uint32(uint16(y))<<16))
		if a.preview.fault || a.demo.client.last.ReadbackText != expected || !a.demo.client.last.ReadbackMatch {
			return fmt.Errorf("actual own-host readback mismatch")
		}
		if n == 0 {
			// Test-only native operation transfers real foreground to a second
			// window owned by the same child, without broad foreground grants.
			if _, e = a.demo.client.call("test-focus-away", nil); e != nil {
				return e
			}
			_ = a.pollOwnDemo()
			if a.demo.client.closed || a.demo.client.last.Active {
				return fmt.Errorf("native did not observe real focus loss")
			}
			if !a.preview.fault {
				return fmt.Errorf("invalidation retained old session")
			}
			if e = bind(); e != nil {
				return e
			}
			if a.demo.client.last.ReadbackText != expected {
				return fmt.Errorf("rebind changed actual body")
			}
		}
	}
	U("SendMessageW").Call(a.h, 0x0010, 0, 0)
	if alive, _, _ := U("IsWindow").Call(a.h); alive != 0 {
		return fmt.Errorf("own UI did not close")
	}
	if a.demo.closeErr != nil {
		return a.demo.closeErr
	}
	fmt.Println("PASS own-tsf-demo-package-ui: real full-resource UI, two native commits/readback, duplicate UP, explicit rebind, own UI/host close; not physical or installed acceptance")
	return nil
}

func demoUnsupportedControl(action string) bool {
	switch action {
	case "language", "select", "select-all", "left", "right", "home", "end", "delete", "variable", "full", "shorthand", "layout", "literal":
		return true
	}
	return false
}
