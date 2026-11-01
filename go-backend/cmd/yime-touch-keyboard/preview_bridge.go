package main

import (
	"fmt"
	cm "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"strings"
)

// The first UI integration is opt-in from tests only, not a new product CLI.
// The trusted sink owns an isolated native host, not an external HWND. It must
// report Applied only after actual edit completion and independent readback.
type bridgePreview struct {
	before  func() error
	session *bridge.Session
	focus   bridge.Focus
	submit  func(bridge.Commit) (bridge.Outcome, error)
}

func newBridgePreview(root, data string, focus bridge.Focus, submit func(bridge.Commit) (bridge.Outcome, error)) (*preview, error) {
	if submit == nil {
		return nil, fmt.Errorf("missing trusted own-host sink")
	}
	s, err := bridge.Open(root, data, "variable", focus)
	if err != nil {
		return nil, err
	}
	return &preview{bridge: &bridgePreview{session: s, focus: focus, submit: submit}, layout: s.Identity().LayoutSHA256, mode: "variable", snapshot: s.Snapshot()}, nil
}
func (p *preview) bridgeActionAllowed(o tk.Output) error {
	if o.Ctrl || o.Alt || o.Shift {
		return fmt.Errorf("own-host slice does not support modifiers")
	}
	switch o.Action.Type {
	case "input":
		if len(o.Action.ASCII) == 1 && strings.ContainsRune(cm.LayoutAlphabet, rune(o.Action.ASCII[0])) {
			return nil
		}
	case "clear":
		return nil
	case "confirm":
		if p.snapshot.State.RawInput != "" {
			return nil
		}
	case "backspace":
		if o.Zone != "left" && o.Zone != "right" && p.snapshot.State.RawInput != "" {
			return nil
		}
	}
	return fmt.Errorf("unsupported own-host UI action; no local or SendInput fallback")
}
func (p *preview) bridgeDispatch(e keyboardlab.Event) error {
	if p.bridge.before != nil {
		if err := p.bridge.before(); err != nil {
			return err
		}
	}
	if p.fault {
		return fmt.Errorf("own-host session stopped; no replay")
	}
	b := p.bridge
	c, err := b.session.Dispatch(b.session.Identity(), b.focus, bridge.Action{SessionID: p.snapshot.SessionID, Revision: p.snapshot.Revision, Kind: e.Type, Code: e.Code, CandidateID: e.CandidateID, Delta: e.Delta})
	if err != nil {
		return err
	}
	p.snapshot = b.session.Snapshot()
	if c == nil {
		return nil
	}
	outcome, err := b.submit(*c)
	if err != nil || (outcome != bridge.Applied && outcome != bridge.Failed) {
		outcome = bridge.Unknown
	}
	completeErr := b.session.Complete(c.ID, outcome)
	if outcome != bridge.Applied || completeErr != nil {
		p.fault = true
		return fmt.Errorf("own-host commit not confirmed applied; no replay")
	}
	return nil
}
