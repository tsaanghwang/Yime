//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
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
	d := touchdiagnostic.FromError(err, "frontend-session", "unknown")
	v := s.snapshot
	v.OK = false
	v.Commit = ""
	v.Error = d.Error()
	r := installedReply(503, v)
	r.Diagnostic = &d
	return r
}
func (s *installedPreviewSessions) decode(result touchbroker.DesktopResponse, mode string) (keyboardlab.Response, error) {
	var reply struct {
		OK         bool                        `json:"ok"`
		Pending    bool                        `json:"pending"`
		Identity   touchbroker.Identity        `json:"identity"`
		Snapshot   keyboardlab.Response        `json:"snapshot"`
		Error      string                      `json:"error"`
		Diagnostic *touchdiagnostic.Diagnostic `json:"diagnostic"`
	}
	if json.Unmarshal(result.Result, &reply) != nil {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "invalid-response")
	}
	// The relay envelope confirms delivery, not completion. Reject contradictory
	// inner success before either Open or action can adopt a snapshot/lease.
	if reply.Pending {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "operation-pending")
	}
	if reply.OK && (reply.Diagnostic != nil || reply.Error != "") {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "invalid-response")
	}
	if !reply.OK {
		if reply.Diagnostic != nil {
			return keyboardlab.Response{}, touchdiagnostic.Sanitize(*reply.Diagnostic)
		}
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "completion-rejected")
	}
	if reply.Identity.Layout != s.layout || reply.Identity.Dictionary != touchbroker.DesktopDictionaryHashes[mode] || reply.Identity.Mode != mode || reply.Identity.Policy != keyboardlab.SessionPolicy {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "identity-mismatch")
	}
	if !reply.Snapshot.OK || reply.Snapshot.Error != "" || reply.Snapshot.SessionID == "" || reply.Snapshot.Commit != "" {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "snapshot-invalid")
	}
	if result.Lease == "" {
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "lease-missing")
	}
	return reply.Snapshot, nil
}
func (s *installedPreviewSessions) Open(mode, layout string) keyboardlab.Reply {
	if layout != s.layout {
		return s.failure(touchdiagnostic.New("frontend-session", "layout-mismatch"))
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
		return s.failure(touchdiagnostic.New("frontend-session", "stale-session"))
	}
	if e.Type == "close" {
		result, err := s.call(touchbroker.DesktopRequest{Operation: "close", Lease: s.lease})
		s.lease = ""
		if err != nil {
			return s.failure(err)
		}
		// The relay envelope only confirms receipt. Cancellation completes in
		// the TIP; its close reply intentionally has no session snapshot.
		if err := installedCloseResult(result.Result); err != nil {
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

func installedCloseResult(raw json.RawMessage) error {
	var result struct {
		Pending    bool                        `json:"pending"`
		OK         bool                        `json:"ok"`
		Diagnostic *touchdiagnostic.Diagnostic `json:"diagnostic"`
	}
	if json.Unmarshal(raw, &result) != nil {
		return touchdiagnostic.New("tip-response", "invalid-response")
	}
	if result.Pending {
		return touchdiagnostic.New("tip-response", "operation-pending")
	}
	if result.OK && result.Diagnostic != nil {
		return touchdiagnostic.New("tip-response", "invalid-response")
	}
	if !result.OK {
		if result.Diagnostic != nil {
			return touchdiagnostic.Sanitize(*result.Diagnostic)
		}
		return touchdiagnostic.New("tip-response", "completion-rejected")
	}
	return nil
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
		return keyboardlab.Response{}, touchdiagnostic.New("tip-response", "revision-mismatch")
	}
	s.snapshot = v
	return v, nil
}
func (a *ui) initInstalled() error {
	if !a.o.InstalledSmoke {
		go receiveDiagnosticHealth()
	}
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
				return touchbroker.DesktopResponse{}, touchdiagnostic.New("frontend-wait", "operation-cancelled")
			}
			return r.value, r.err
		case <-ticker.C:
			if !pumpHostMessages() {
				_ = a.installed.client.Close()
				return touchbroker.DesktopResponse{}, touchdiagnostic.New("frontend-wait", "frontend-closed")
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
		retainInstalledBindFailure(old, p)
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

// A failed explicit bind discards its attempted controller, but its diagnostic
// must survive on the retained stopped UI. Do not transfer snapshots or leases.
func retainInstalledBindFailure(current, attempt *preview) {
	if attempt.lastDiagnostic != nil {
		d := touchdiagnostic.Sanitize(*attempt.lastDiagnostic)
		current.lastDiagnostic = &d
	}
	current.fault = true
}

func installedHostEdit(o tk.Output) (bridge.HostEdit, error) {
	if o.Alt {
		return bridge.HostEdit{}, touchdiagnostic.New("frontend-session", "unsupported-host-edit")
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
			return bridge.HostEdit{}, touchdiagnostic.New("frontend-session", "unsupported-host-edit")
		}
		o.Ctrl = false
		o.Shift = false
	}
	e := bridge.HostEdit{Key: key, Ctrl: o.Ctrl, Shift: o.Shift}
	if err := bridge.ValidateHostEdit(e); err != nil {
		return e, touchdiagnostic.FromError(err, "frontend-session", "unsupported-host-edit")
	}
	return e, nil
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
		result, err := a.installed.call(touchbroker.DesktopRequest{Operation: "close", Lease: lease})
		if err == nil {
			err = installedCloseResult(result.Result)
		}
		if err != nil {
			d := touchdiagnostic.FromError(err, "tip-response", "completion-unknown")
			_ = json.NewEncoder(os.Stderr).Encode(d)
			if a.preview != nil && a.preview.lastDiagnostic == nil {
				safe := touchdiagnostic.Sanitize(d)
				a.preview.lastDiagnostic = &safe
			}
		}
	}
	a.invalidateInstalled(reason)
}
