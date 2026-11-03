//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

type installedPreviewSessions struct {
	client              *touchbroker.DesktopClient
	call                func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error)
	lease, layout, mode string
	snapshot            keyboardlab.Response
}

func installedReply(status int, s keyboardlab.Response) keyboardlab.Reply {
	raw, _ := json.Marshal(s)
	return keyboardlab.Reply{Status: status, Body: raw}
}
func (s *installedPreviewSessions) failure(err error) keyboardlab.Reply {
	v := s.snapshot
	v.OK = false
	v.Commit = ""
	v.Error = err.Error()
	return installedReply(503, v)
}
func (s *installedPreviewSessions) decode(result touchbroker.DesktopResponse, mode string) (keyboardlab.Response, error) {
	var reply struct {
		OK       bool                 `json:"ok"`
		Identity touchbroker.Identity `json:"identity"`
		Snapshot keyboardlab.Response `json:"snapshot"`
		Error    string               `json:"error"`
	}
	if json.Unmarshal(result.Result, &reply) != nil || !reply.OK || reply.Identity.Layout != s.layout || reply.Identity.Dictionary != touchbroker.DesktopDictionaryHashes[mode] || reply.Identity.Mode != mode || reply.Identity.Policy != keyboardlab.SessionPolicy || !reply.Snapshot.OK || reply.Snapshot.SessionID == "" || reply.Snapshot.Commit != "" || result.Lease == "" {
		return keyboardlab.Response{}, errors.New("TIP响应或实际编辑未完成；不重放，请重新绑定")
	}
	return reply.Snapshot, nil
}
func (s *installedPreviewSessions) Open(mode, layout string) keyboardlab.Reply {
	if layout != s.layout {
		return s.failure(errors.New("installed layout mismatch"))
	}
	result, e := s.call(touchbroker.DesktopRequest{Operation: "bind", Mode: mode})
	if e != nil {
		return s.failure(e)
	}
	v, e := s.decode(result, mode)
	if e != nil {
		return s.failure(e)
	}
	s.lease, s.mode, s.snapshot = result.Lease, mode, v
	return installedReply(200, v)
}
func (s *installedPreviewSessions) Dispatch(e keyboardlab.Event) keyboardlab.Reply {
	if s.lease == "" || e.SessionID != s.snapshot.SessionID || e.BaseRevision != s.snapshot.Revision {
		return s.failure(errors.New("旧会话或焦点已失效；请重新绑定"))
	}
	if e.Type == "close" {
		_, err := s.call(touchbroker.DesktopRequest{Operation: "close", Lease: s.lease})
		s.lease = ""
		if err != nil {
			return s.failure(err)
		}
		s.snapshot.Revision++
		return installedReply(200, s.snapshot)
	}
	a := touchbroker.Action{Kind: e.Type, Code: e.Code, CandidateID: e.CandidateID, Revision: e.BaseRevision, Delta: e.Delta, InputMode: e.InputMode, PunctuationMode: e.PunctuationMode}
	v, err := s.action(a)
	if err != nil {
		return s.failure(err)
	}
	return installedReply(200, v)
}
func (s *installedPreviewSessions) action(a touchbroker.Action) (keyboardlab.Response, error) {
	raw, e := json.Marshal(a)
	if e != nil {
		return keyboardlab.Response{}, e
	}
	result, e := s.call(touchbroker.DesktopRequest{Operation: "action", Lease: s.lease, Action: raw})
	if e != nil {
		return keyboardlab.Response{}, e
	}
	v, e := s.decode(result, s.mode)
	if e != nil {
		return keyboardlab.Response{}, e
	}
	if result.Lease != s.lease || v.SessionID != s.snapshot.SessionID || v.Revision != s.snapshot.Revision+1 {
		return keyboardlab.Response{}, errors.New("TIP状态版本不一致；不重放")
	}
	s.snapshot = v
	return v, nil
}
func (a *ui) initInstalled() error {
	base, e := touchbroker.DesktopPipeName()
	if e != nil {
		return e
	}
	client, e := touchbroker.OpenDesktopClient(base, uint32(a.o.BrokerPID), filepath.Join(a.o.InstallRoot, filepath.FromSlash(installed18uhost.BrokerPath)))
	if e != nil {
		return e
	}
	s := &installedPreviewSessions{client: client, layout: a.s.Board.LayoutID}
	a.installed = s
	s.call = a.callInstalled
	a.preview = &preview{sessions: s, layout: s.layout, mode: "variable", fault: true, installed: true, englishView: a.o.KeyView != "original"}
	a.preview.snapshot.Modes.Input = "chinese"
	a.preview.snapshot.Modes.Punctuation = "chinese"
	return nil
}
func (a *ui) callInstalled(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
	type result struct {
		value touchbroker.DesktopResponse
		err   error
	}
	ch := make(chan result, 1)
	generation := a.cancelGeneration
	wasBusy := a.hostBusy
	a.hostBusy = true
	defer func() { a.hostBusy = wasBusy }()
	go func() { v, e := a.installed.client.Call(q); ch <- result{v, e} }()
	ticker := time.NewTicker(8 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case r := <-ch:
			if generation != a.cancelGeneration {
				return touchbroker.DesktopResponse{}, errors.New("等待TIP期间动作已取消；结果不明，不重放")
			}
			return r.value, r.err
		case <-ticker.C:
			if !pumpHostMessages() {
				_ = a.installed.client.Close()
				return touchbroker.DesktopResponse{}, errors.New("键盘已关闭；不重放")
			}
		}
	}
}
func (a *ui) bindInstalled() error {
	if a.hostBusy {
		return errors.New("等待当前TIP操作完成")
	}
	a.cancel()
	if !pumpHostMessages() {
		return errors.New("消息队列未稳定")
	}
	old := a.preview
	mode := old.mode
	if mode == "" {
		mode = "variable"
	}
	s := a.installed
	s.lease = ""
	p := &preview{sessions: s, layout: s.layout, installed: true, englishView: old.englishView, literalEntries: old.literalEntries}
	if e := p.switchMode(mode); e != nil {
		a.invalidateInstalled(e.Error())
		return e
	}
	a.preview = p
	p.emit = func(_ string, o tk.Output) error {
		edit, e := installedHostEdit(o)
		if e != nil {
			return e
		}
		v, e := s.action(touchbroker.Action{Kind: "hostEdit", Revision: p.snapshot.Revision, Edit: &edit})
		if e != nil {
			return e
		}
		p.snapshot = v
		return nil
	}
	tick, _, _ := k32.NewProc("GetTickCount").Call()
	a.focusStarted = uint32(tick)
	a.s.Original = p.original()
	a.status = "18u TIP已绑定当前文本上下文；确认与编辑由TSF完成"
	return nil
}
func installedHostEdit(o tk.Output) (bridge.HostEdit, error) {
	if o.Alt {
		return bridge.HostEdit{}, errors.New("此TSF文本入口不执行Alt应用菜单快捷键")
	}
	key := o.Key
	if o.Ctrl && o.Text != "" {
		switch strings.ToLower(o.Text) {
		case "a":
			key = "SelectAll"
		case "c":
			key = "Copy"
		case "x":
			key = "Cut"
		case "v":
			key = "Paste"
		default:
			return bridge.HostEdit{}, fmt.Errorf("未支持的TSF宿主快捷键 Ctrl+%s", o.Text)
		}
		o.Ctrl = false
		o.Shift = false
	}
	e := bridge.HostEdit{Key: key, Ctrl: o.Ctrl, Shift: o.Shift}
	return e, bridge.ValidateHostEdit(e)
}
func (a *ui) invalidateInstalled(reason string) {
	if a.installed == nil {
		return
	}
	a.installed.lease = ""
	a.cancel()
	if a.preview != nil {
		a.preview.fault = true
		a.preview.snapshot.State.RawInput = ""
		a.preview.snapshot.State.Candidates = nil
		a.preview.snapshot.PendingMiddleDots = 0
		a.preview.snapshot.SymbolChoice = false
	}
	a.status = reason
	a.invalidate()
}
func (a *ui) closeInstalledLease(reason string) {
	if a.installed == nil {
		return
	}
	lease := a.installed.lease
	if lease != "" && !a.hostBusy {
		_, _ = a.callInstalled(touchbroker.DesktopRequest{Operation: "close", Lease: lease})
	}
	a.invalidateInstalled(reason)
}
