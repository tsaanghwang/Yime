//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
)

func TestInstalledBindPreservesBrokerFailureWithoutReplay(t *testing.T) {
	calls := 0
	s := &installedPreviewSessions{layout: "fixture", call: func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		if q.Operation != "bind" {
			t.Fatalf("unexpected operation: %s", q.Operation)
		}
		return touchbroker.DesktopResponse{}, errors.New("[desktop/no-tip-peer] HRESULT=0x80004005")
	}}
	p := &preview{sessions: s, layout: s.layout, installed: true}
	err := p.switchMode("full")
	if err == nil || !strings.Contains(err.Error(), "[desktop/no-tip-peer]") || !strings.Contains(err.Error(), "0x80004005") {
		t.Fatalf("binding cause lost: %v", err)
	}
	if !p.fault || calls != 1 || s.lease != "" || p.snapshot.SessionID != "" {
		t.Fatal("failed binding retried or became usable")
	}
}

func TestInstalledReplyDistinguishesRejectionFromMalformedIdentity(t *testing.T) {
	s := &installedPreviewSessions{layout: "fixture"}
	for _, tt := range []struct{ name, raw, want string }{
		{"rejected", `{"ok":false,"error":"TSF lock failed HRESULT=0x80070005"}`, "0x80070005"},
		{"malformed", `{"ok":`, "[tip/decode]"},
		{"identity", `{"ok":true,"identity":{"layout":"wrong"},"error":"do not use this"}`, "[tip/identity]"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			_, err := s.decode(touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: []byte(tt.raw)}, "full")
			if err == nil || !strings.Contains(err.Error(), tt.want) || strings.Contains(err.Error(), "do not use this") {
				t.Fatalf("incorrect stage: %v", err)
			}
		})
	}
}

func TestInstalledActionPreservesFailureAndStopsSession(t *testing.T) {
	p := previewFixture(t)
	p.installed = true
	s := &installedPreviewSessions{layout: "fixture", lease: "lease", mode: "variable", snapshot: p.snapshot}
	calls := 0
	s.call = func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		return touchbroker.DesktopResponse{}, errors.New("[desktop/foreground-mismatch] no replay")
	}
	p.sessions = s
	err := p.dispatch(keyboardlab.Event{Type: "clear"})
	if err == nil || !strings.Contains(err.Error(), "[desktop/foreground-mismatch]") || !p.fault {
		t.Fatalf("action cause lost or session still active: %v", err)
	}
	_ = p.dispatch(keyboardlab.Event{Type: "clear"})
	if calls != 1 || len(p.editor.text) != 0 {
		t.Fatal("failed action was replayed or emitted text")
	}
}

func TestInstalledDiagnosticIsBoundedAndCannotAuthorizeContradictoryReply(t *testing.T) {
	if got := diagnosticDetail("[tip/rejected]\r\n\x00\u202e HRESULT=0x80004005"); strings.ContainsAny(got, "\r\n\x00\u202e") || !strings.Contains(got, "0x80004005") {
		t.Fatal("diagnostic controls or HRESULT mishandled", got)
	}
	if got := diagnosticDetail(strings.Repeat("错", 600)); len([]rune(got)) != 513 || !strings.HasSuffix(got, "…") {
		t.Fatal("diagnostic was not bounded")
	}
	fixture := previewFixture(t)
	snapshot := fixture.snapshot
	snapshot.Revision = 0
	snapshot.Error = "must not accept contradictory success"
	raw, err := json.Marshal(map[string]any{"ok": true, "identity": touchbroker.Identity{Layout: "fixture", Dictionary: touchbroker.DesktopDictionaryHashes["full"], Mode: "full", Policy: keyboardlab.SessionPolicy}, "snapshot": snapshot})
	if err != nil {
		t.Fatal(err)
	}
	s := &installedPreviewSessions{layout: "fixture"}
	if _, err := s.decode(touchbroker.DesktopResponse{OK: true, Lease: "lease", Result: raw}, "full"); err == nil || !strings.Contains(err.Error(), "[tip/snapshot]") {
		t.Fatal("contradictory reply accepted", err)
	}
}
