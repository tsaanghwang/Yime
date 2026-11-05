//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestInstalledDiagnosticViewCannotDispatchOrResetFailure(t *testing.T) {
	t.Setenv("LOCALAPPDATA", t.TempDir())
	a := touchUIFixture(t)
	calls := 0
	a.installed = &installedPreviewSessions{lease: "lease", call: func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		t.Fatal("diagnostic viewer sent host request")
		return touchbroker.DesktopResponse{}, nil
	}}
	d := touchdiagnostic.New("broker-receipt", "completion-unknown")
	a.preview.lastDiagnostic = &d
	a.preview.fault = true
	before := a.preview.snapshot
	revision := a.cancelGeneration
	a.previewTouches[111] = &previewGesture{action: "candidate", stamp: a.preview.stamp()}
	a.showDiagnostics()
	if a.touchSettingLabel("diagnostics") != "最近诊断" || !a.diagnosticOpen || !a.preview.fault || a.installed.lease != "lease" || !reflect.DeepEqual(before, a.preview.snapshot) || a.cancelGeneration != revision+1 {
		t.Fatal("view changed input state")
	}
	a.up(111, 0, 0)
	for _, id := range []string{"TU-BIND", "TU-LEFT", "R01K02", "R01K03", "TU-BACKSPACE"} {
		r := touchToolbarKeyRect(t, a, id)
		x, y := (r.L+r.R)/2, (r.T+r.B)/2
		a.down(120, x, y)
		a.up(120, x, y)
	}
	r := a.candidateRect(0)
	a.down(121, r.L+1, r.T+1)
	a.up(121, r.L+1, r.T+1)
	if calls != 0 || !a.preview.fault || a.installed.lease != "lease" || !reflect.DeepEqual(before, a.preview.snapshot) {
		t.Fatal("host action escaped overlay")
	}
	if !strings.Contains(strings.Join(a.diagnosticPages, " "), "completion-unknown") {
		t.Fatal("in-memory failure lost")
	}
	if err := a.applyTouchImmediate("diagnostic-close"); err != nil {
		t.Fatal(err)
	}
	if !a.preview.fault || a.installed.lease != "lease" || calls != 0 {
		t.Fatal("view close recovered or replayed")
	}
}
func TestInstalledCloseLeaseFailureIsRecordedBeforeInvalidation(t *testing.T) {
	for _, raw := range []string{
		"{\"ok\":false,\"diagnostic\":{\"stage\":\"tip-completion\",\"reason\":\"operation-failed\",\"hresult\":2147500037}}",
		"{\"ok\":", "{}", "{\"ok\":true,\"pending\":true}",
	} {
		t.Run(raw, func(t *testing.T) {
			a := touchUIFixture(t)
			calls := 0
			a.installed = &installedPreviewSessions{lease: "lease", call: func(q touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
				calls++
				if q.Operation != "close" {
					t.Fatal("unexpected operation")
				}
				return touchbroker.DesktopResponse{OK: true, Result: json.RawMessage(raw)}, nil
			}}
			primary := touchdiagnostic.New("broker-receipt", "completion-unknown")
			a.preview.lastDiagnostic = &primary
			path := filepath.Join(t.TempDir(), "stderr.jsonl")
			file, err := os.Create(path)
			if err != nil {
				t.Fatal(err)
			}
			original := os.Stderr
			os.Stderr = file
			defer func() { os.Stderr = original; file.Close() }()
			a.closeInstalledLease("local view closed")
			a.closeInstalledLease("again")
			file.Sync()
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if _, ok := touchdiagnostic.DecodeLine([]byte(strings.TrimSpace(string(data)))); !ok {
				t.Fatal("close failure not recorded")
			}
			if calls != 1 || a.installed.lease != "" || !a.preview.fault || a.preview.lastDiagnostic.Reason != "completion-unknown" {
				t.Fatal("close replayed or replaced primary failure")
			}
		})
	}
}
func TestInstalledDiagnosticModeSwitchRejectsIncompleteAndUnknownCancellation(t *testing.T) {
	cases := []struct {
		raw string
		err error
	}{
		{"{}", nil}, {"{\"ok\":", nil}, {"{\"ok\":true,\"pending\":true}", nil},
		{"{\"ok\":false,\"diagnostic\":{\"stage\":\"broker-receipt\",\"reason\":\"completion-unknown\"}}", nil},
		{"", touchdiagnostic.New("transport-read", "read-failed")},
	}
	for _, tc := range cases {
		calls := 0
		s := &installedPreviewSessions{lease: "lease", mode: "variable", layout: "layout", snapshot: diagnosticSnapshot()}
		s.call = func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
			calls++
			return touchbroker.DesktopResponse{OK: true, Result: json.RawMessage(tc.raw)}, tc.err
		}
		p := &preview{sessions: s, installed: true, layout: "layout", mode: "variable", snapshot: s.snapshot}
		if p.switchMode("full") == nil || !p.fault || calls != 1 || s.lease != "" || s.snapshot.Revision != 7 || p.mode != "variable" {
			t.Fatal("unconfirmed cancellation advanced mode")
		}
		if p.dispatch(keyboardlab.Event{Type: "input", Code: "PRIVATE"}) == nil || p.switchMode("full") == nil || calls != 1 {
			t.Fatal("unknown cancellation replayed")
		}
	}
}
