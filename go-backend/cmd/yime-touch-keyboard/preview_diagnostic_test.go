package main

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

type diagnosticSessions struct {
	open, action keyboardlab.Reply
	opens, calls int
}

func (s *diagnosticSessions) Open(string, string) keyboardlab.Reply { s.opens++; return s.open }
func (s *diagnosticSessions) Dispatch(keyboardlab.Event) keyboardlab.Reply {
	s.calls++
	return s.action
}

func diagnosticSnapshot() keyboardlab.Response {
	s := keyboardlab.Response{OK: true, SessionID: "current-session", Revision: 7}
	s.Modes.Input, s.Modes.Punctuation = "chinese", "chinese"
	return s
}

func TestPreviewInstalledBindDiagnosticStopsWithoutDispatch(t *testing.T) {
	d := touchdiagnostic.New("broker-select", "no-eligible-tip")
	s := &diagnosticSessions{open: keyboardlab.Reply{Status: 503, Body: []byte(`{"ok":false}`), Diagnostic: &d}}
	p := &preview{sessions: s, installed: true, layout: "layout"}
	err := p.switchMode("variable")
	if err == nil || !strings.Contains(err.Error(), "no-eligible-tip") || !p.fault || p.lastDiagnostic == nil || s.opens != 1 || s.calls != 0 {
		t.Fatalf("binding failure lost or continued: error=%v fault=%v open=%d dispatch=%d", err, p.fault, s.opens, s.calls)
	}
	if err := p.dispatch(keyboardlab.Event{Type: "input", Code: "private-code"}); err == nil || s.calls != 0 {
		t.Fatal("stopped bind dispatched input")
	}
}

func TestPreviewInstalledActionDiagnosticPreservesFirstFailureAndRejectsLateOutput(t *testing.T) {
	const private = "PRIVATE-BODY-CODE-CANDIDATE"
	d := touchdiagnostic.New("tip-completion", "operation-failed")
	hr := uint32(0x80004005)
	d.HRESULT = &hr
	failed := diagnosticSnapshot()
	failed.OK, failed.Commit, failed.Error = false, private, private
	failed.Revision++
	body, _ := json.Marshal(failed)
	s := &diagnosticSessions{action: keyboardlab.Reply{Status: 503, Body: body, Diagnostic: &d}}
	p := &preview{sessions: s, installed: true, snapshot: diagnosticSnapshot()}
	err := p.dispatch(keyboardlab.Event{Type: "input", Code: private})
	if err == nil || !strings.Contains(err.Error(), "operation-failed") || strings.Contains(err.Error(), private) || !p.fault || p.snapshot.Revision != 7 || p.editor.display() != "│" || s.calls != 1 {
		t.Fatalf("failed action consumed output or lost diagnosis: %v", err)
	}
	first := err.Error()
	// A later apparently successful reply cannot reopen this stopped controller.
	s.action = keyboardlab.Reply{Status: 200, Body: body}
	err = p.dispatch(keyboardlab.Event{Type: "input", Code: private})
	if err == nil || err.Error() != first || s.calls != 1 || p.lastDiagnostic.HRESULT == nil || *p.lastDiagnostic.HRESULT != hr {
		t.Fatal("late action retried, replaced first failure, or lost HRESULT")
	}
	if p.candidatesEnabled() {
		t.Fatal("failed installed action left candidate touches enabled")
	}
}

func TestPreviewDiagnosticRejectsArbitraryFieldsAndBody(t *testing.T) {
	const private = "PRIVATE\n正文-组码-候选-C:/secret"
	d := touchdiagnostic.Diagnostic{Stage: private, Reason: private}
	s := &diagnosticSessions{open: keyboardlab.Reply{Status: 503, Body: []byte(private), Diagnostic: &d}}
	p := &preview{sessions: s, installed: true}
	err := p.switchMode("full")
	if err == nil || strings.Contains(err.Error(), "PRIVATE") || strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "正文") || !p.fault || s.opens != 1 || s.calls != 0 {
		t.Fatal("untrusted error text escaped or binding continued")
	}
	encoded, e := json.Marshal(p.lastDiagnostic)
	if e != nil || strings.Contains(string(encoded), "PRIVATE") {
		t.Fatal("stored diagnostic contains input data")
	}
}

func TestPreviewInstalledEditDiagnosticDoesNotRetry(t *testing.T) {
	p := &preview{installed: true, snapshot: diagnosticSnapshot()}
	calls := 0
	p.emit = func(string, tk.Output) error {
		calls++
		return touchdiagnostic.New("tip-response", "revision-mismatch")
	}
	o := tk.Output{Action: tk.Action{Type: "local", Key: "Delete"}}
	err := p.apply(o, p.stamp())
	if err == nil || !strings.Contains(err.Error(), "revision-mismatch") || !p.fault || calls != 1 {
		t.Fatal("host edit did not preserve diagnostic and stop")
	}
	if p.apply(o, p.stamp()) == nil || calls != 1 {
		t.Fatal("host edit was replayed after unknown result")
	}
}
