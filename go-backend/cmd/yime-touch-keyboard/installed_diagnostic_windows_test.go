//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"syscall"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestInstalledDiagnosticSystemErrorReachesBindingWithoutPrivateText(t *testing.T) {
	calls := 0
	s := &installedPreviewSessions{layout: "layout", call: func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		return touchbroker.DesktopResponse{}, fmt.Errorf("PRIVATE body/code/candidate/path: %w", syscall.Errno(5))
	}}
	p := &preview{sessions: s, layout: "layout", installed: true}
	err := p.switchMode("variable")
	if err == nil || strings.Contains(err.Error(), "PRIVATE") || !strings.Contains(err.Error(), "win32=5") || !p.fault || calls != 1 || s.lease != "" {
		t.Fatalf("binding did not preserve numeric error and stop: %v calls=%d", err, calls)
	}
	if p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || calls != 1 {
		t.Fatal("failed binding allowed input or retried")
	}
}

func TestInstalledDiagnosticTIPFailureKeepsActualHRESULT(t *testing.T) {
	const private = "PRIVATE正文组码候选"
	s := &installedPreviewSessions{layout: "layout", call: func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		return touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: []byte(`{"ok":false,"error":"` + private + `","diagnostic":{"stage":"tip-completion","reason":"operation-failed","hresult":2147500037}}`)}, nil
	}}
	r := s.Open("variable", "layout")
	v, err := r.Decode()
	if err != nil || r.Status != 503 || r.Diagnostic == nil || r.Diagnostic.HRESULT == nil || *r.Diagnostic.HRESULT != 0x80004005 || strings.Contains(v.Error, private) || v.OK || v.Commit != "" || s.lease != "" {
		t.Fatal("native failure was accepted, exposed text, or lost HRESULT")
	}
}

func TestInstalledDiagnosticRejectsBadTIPStateWithoutUpdatingSession(t *testing.T) {
	for _, tc := range []struct {
		name, reason string
		change       func(map[string]any, *touchbroker.DesktopResponse)
	}{
		{"identity", "identity-mismatch", func(v map[string]any, _ *touchbroker.DesktopResponse) { v["identity"] = touchbroker.Identity{} }},
		{"commit", "snapshot-invalid", func(v map[string]any, _ *touchbroker.DesktopResponse) {
			x := v["snapshot"].(keyboardlab.Response)
			x.Commit = "PRIVATE"
			v["snapshot"] = x
		}},
		{"lease", "lease-missing", func(_ map[string]any, r *touchbroker.DesktopResponse) { r.Lease = "" }},
		{"revision", "revision-mismatch", func(v map[string]any, _ *touchbroker.DesktopResponse) {
			x := v["snapshot"].(keyboardlab.Response)
			x.Revision++
			v["snapshot"] = x
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			s := &installedPreviewSessions{layout: "layout", mode: "variable", lease: "lease", snapshot: diagnosticSnapshot()}
			s.call = func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				x := diagnosticSnapshot()
				x.Revision++
				v := map[string]any{"ok": true, "identity": touchbroker.Identity{Layout: "layout", Dictionary: touchbroker.DesktopDictionaryHashes["variable"], Mode: "variable", Policy: keyboardlab.SessionPolicy}, "snapshot": x}
				r := touchbroker.DesktopResponse{OK: true, Lease: "lease"}
				tc.change(v, &r)
				r.Result, _ = json.Marshal(v)
				return r, nil
			}
			p := &preview{sessions: s, snapshot: s.snapshot, installed: true}
			err := p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"})
			if err == nil || !strings.Contains(err.Error(), tc.reason) || strings.Contains(err.Error(), "PRIVATE") || !p.fault || s.snapshot.Revision != 7 || p.snapshot.Revision != 7 || calls != 1 {
				t.Fatalf("invalid response changed session or lost reason: %v", err)
			}
			if p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || calls != 1 {
				t.Fatal("invalid action was retried")
			}
		})
	}
}

func TestInstalledDiagnosticStaleSessionAndCloseFailureKeepStopRules(t *testing.T) {
	calls := 0
	s := &installedPreviewSessions{layout: "layout", mode: "variable", lease: "lease", snapshot: diagnosticSnapshot(), call: func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		return touchbroker.DesktopResponse{}, touchdiagnostic.New("broker-receipt", "completion-unknown")
	}}
	r := s.Dispatch(keyboardlab.Event{Type: "input", SessionID: "old-session", BaseRevision: 7})
	if r.Diagnostic == nil || r.Diagnostic.Reason != "stale-session" || calls != 0 {
		t.Fatal("stale session reached relay")
	}
	r = s.Dispatch(keyboardlab.Event{Type: "close", SessionID: "current-session", BaseRevision: 7})
	if r.Status != 503 || r.Diagnostic == nil || r.Diagnostic.Reason != "completion-unknown" || s.lease != "" || s.snapshot.Revision != 7 || calls != 1 {
		t.Fatal("close failure renewed lease, advanced revision, or lost diagnosis")
	}
}

func TestInstalledDiagnosticUnsupportedEditDoesNotEchoText(t *testing.T) {
	_, err := installedHostEdit(tk.Output{Ctrl: true, Text: "PRIVATE正文组码候选"})
	if err == nil || strings.Contains(err.Error(), "PRIVATE") || !strings.Contains(err.Error(), "unsupported-host-edit") {
		t.Fatal("host edit error contains input text or lacks fixed reason")
	}
}

func TestInstalledDiagnosticCloseUsesActualCancellationResult(t *testing.T) {
	for _, tc := range []struct {
		name, raw, reason string
		success           bool
	}{
		{"complete", `{"ok":true}`, "", true},
		{"cancel-failed", `{"ok":false,"error":"PRIVATE","diagnostic":{"stage":"tip-completion","reason":"operation-failed","hresult":2147500037}}`, "operation-failed", false},
		{"malformed", `{"ok":`, "invalid-response", false},
		{"missing", `{}`, "completion-rejected", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			s := &installedPreviewSessions{lease: "lease", snapshot: diagnosticSnapshot(), call: func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				if q.Operation != "close" || q.Lease != "lease" {
					t.Fatal("close request changed")
				}
				return touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: json.RawMessage(tc.raw)}, nil
			}}
			p := &preview{sessions: s, snapshot: s.snapshot, installed: true}
			err := p.dispatch(keyboardlab.Event{Type: "close"})
			if s.lease != "" || calls != 1 {
				t.Fatal("close did not retire lease exactly once")
			}
			if tc.success {
				if err != nil || p.fault || s.snapshot.Revision != 8 {
					t.Fatalf("confirmed close rejected: %v", err)
				}
			} else {
				if err == nil || !p.fault || s.snapshot.Revision != 7 || !strings.Contains(err.Error(), tc.reason) || strings.Contains(err.Error(), "PRIVATE") {
					t.Fatalf("cancel failure was treated as complete: %v", err)
				}
				if tc.name == "cancel-failed" && (p.lastDiagnostic.HRESULT == nil || *p.lastDiagnostic.HRESULT != 0x80004005) {
					t.Fatal("cancellation HRESULT lost")
				}
				if p.dispatch(keyboardlab.Event{Type: "close"}) == nil || calls != 1 {
					t.Fatal("failed cancellation replayed")
				}
			}
		})
	}
}

func TestInstalledDiagnosticFailedRebindReplacesOnlyRetainedFailure(t *testing.T) {
	previous := touchdiagnostic.New("tip-response", "revision-mismatch")
	current := &preview{installed: true, fault: true, snapshot: diagnosticSnapshot(), lastDiagnostic: &previous}
	before := current.snapshot
	fresh := touchdiagnostic.New("broker-select", "no-eligible-tip")
	sessions := &diagnosticSessions{open: keyboardlab.Reply{Status: 503, Body: []byte(`{"ok":false}`), Diagnostic: &fresh}}
	attempt := &preview{installed: true, sessions: sessions}
	if attempt.switchMode("variable") == nil {
		t.Fatal("fixture bind unexpectedly succeeded")
	}
	retainInstalledBindFailure(current, attempt)
	// Later input must report this bind's failure, not the preceding action's
	// failure, and must not dispatch using either controller's session.
	err := current.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"})
	if err == nil || !strings.Contains(err.Error(), "no-eligible-tip") || strings.Contains(err.Error(), "revision-mismatch") || !current.fault || !reflect.DeepEqual(current.snapshot, before) || sessions.calls != 0 {
		t.Fatal("failed rebind lost its diagnostic or changed the old session")
	}
	attempt.lastDiagnostic.Reason = "PRIVATE"
	if current.lastDiagnostic.Reason != "no-eligible-tip" {
		t.Fatal("retained diagnostic aliases discarded controller")
	}
}

func TestInstalledDiagnosticModeSwitchStopsAtFailedCancellation(t *testing.T) {
	var operations []string
	s := &installedPreviewSessions{layout: "layout", mode: "variable", lease: "lease", snapshot: diagnosticSnapshot(), call: func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		operations = append(operations, q.Operation)
		return touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: []byte(`{"ok":false,"diagnostic":{"stage":"tip-completion","reason":"operation-failed","hresult":2147942658}}`)}, nil
	}}
	p := &preview{sessions: s, installed: true, layout: "layout", mode: "variable", snapshot: s.snapshot}
	err := p.switchMode("full")
	if err == nil || !p.fault || !reflect.DeepEqual(operations, []string{"close"}) || s.lease != "" || s.snapshot.Revision != 7 || p.mode != "variable" {
		t.Fatal("mode switch opened a new session before cancellation completed")
	}
}
