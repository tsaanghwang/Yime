//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
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

func TestInstalledDiagnosticPagesDistinguishUnreadableFromEmpty(t *testing.T) {
	busy := touchdiagnostic.New("diagnostic-storage", "storage-busy")
	stopped := touchdiagnostic.New("broker-receipt", "completion-unknown")
	for _, tc := range []struct {
		name      string
		health    touchdiagnostic.Health
		readError error
	}{
		{"storage-busy", touchdiagnostic.Health{State: "failed", Diagnostic: &busy}, nil},
		{"read-busy", touchdiagnostic.Health{State: "ready"}, busy},
		{"read-failed", touchdiagnostic.Health{State: "ready"}, errors.New("PRIVATE path and file error")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			reads := 0
			pages := installedDiagnosticPages(tc.health, &stopped, "diagnostic-location", nil, func(dir string) ([]touchdiagnostic.Diagnostic, error) {
				reads++
				if dir != "diagnostic-location" {
					t.Fatal("diagnostic reader changed location")
				}
				return nil, tc.readError
			})
			text := strings.Join(pages, "\n")
			if reads != 1 || !strings.Contains(text, "诊断暂时不可读，请稍后查看") || strings.Contains(text, "未读取到诊断记录") || strings.Contains(text, "暂无诊断") || strings.Contains(text, "PRIVATE") || !strings.Contains(text, "completion-unknown") {
				t.Fatal("unreadable storage was presented as an empty or successful diagnosis")
			}
		})
	}
	pages := installedDiagnosticPages(touchdiagnostic.Health{State: "ready"}, nil, "diagnostic-location", nil, func(string) ([]touchdiagnostic.Diagnostic, error) { return nil, nil })
	if text := strings.Join(pages, "\n"); !strings.Contains(text, "未读取到诊断记录") || strings.Contains(text, "诊断暂时不可读") {
		t.Fatal("readable empty storage lost its separate state")
	}
}

func TestInstalledDiscoveryPagesIdentifyClientReportsAndLegacyOrigin(t *testing.T) {
	legacy := touchdiagnostic.New("tip-discovery", "tip-not-focused")
	reported := touchdiagnostic.New("tip-discovery", "foreground-thread-mismatch")
	reported.Reported = &touchdiagnostic.ReportOrigin{ReceivedMS: 1793793600000, Event: "0123456789abcdef0123456789abcdef", PID: 1234, Created: 0x01dd000000000001}
	before := touchdiagnostic.Sanitize(reported)
	pages := installedDiagnosticPages(touchdiagnostic.Health{State: "ready", Saved: 2}, nil, "diagnostic-location", nil, func(string) ([]touchdiagnostic.Diagnostic, error) {
		return []touchdiagnostic.Diagnostic{legacy, reported}, nil
	})
	if len(pages) != 4 || !strings.Contains(pages[2], "客户端报告的拒绝原因") || !strings.Contains(pages[2], "接收时间（UTC）") || !strings.Contains(pages[2], "报告进程：1234") || !strings.Contains(pages[2], reported.Reported.Event) || !strings.Contains(pages[2], "不代表故障已查明") {
		t.Fatal("reported discovery lacks its source qualification or association metadata")
	}
	if !strings.Contains(pages[3], "客户端报告的拒绝原因") || !strings.Contains(pages[3], "缺少接收来源信息") || strings.Contains(pages[3], "已验证") || strings.Contains(pages[3], "接收时间（UTC）") || !reflect.DeepEqual(reported, before) {
		t.Fatal("legacy report acquired a verified source or display mutated metadata")
	}
	pages = installedDiagnosticPages(touchdiagnostic.Health{}, &legacy, "", errors.New("PRIVATE directory error"), func(string) ([]touchdiagnostic.Diagnostic, error) {
		t.Fatal("directory failure invoked storage reader")
		return nil, nil
	})
	text := strings.Join(pages, "\n")
	if !strings.Contains(text, "当前停止原因") || !strings.Contains(text, "客户端报告的拒绝原因") || !strings.Contains(text, "缺少接收来源信息") || strings.Contains(text, "PRIVATE") {
		t.Fatal("directory failure hid the in-memory client report or exposed private error text")
	}
}

func TestInstalledUnreadableDiagnosticViewPreservesStoppedInput(t *testing.T) {
	t.Setenv("LOCALAPPDATA", t.TempDir())
	dir, err := touchdiagnostic.DefaultDirectory()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(dir), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dir, []byte("occupied"), 0600); err != nil {
		t.Fatal(err)
	}
	a := touchUIFixture(t)
	calls := 0
	a.installed = &installedPreviewSessions{lease: "stopped-lease", call: func(touchbroker.DesktopRequest) (touchbroker.DesktopResponse, error) {
		calls++
		t.Fatal("unreadable diagnostic view dispatched input")
		return touchbroker.DesktopResponse{}, nil
	}}
	first := touchdiagnostic.New("broker-receipt", "completion-unknown")
	a.preview.fault, a.preview.lastDiagnostic = true, &first
	before := a.preview.snapshot
	a.showDiagnostics()
	text := strings.Join(a.diagnosticPages, "\n")
	if !strings.Contains(text, "诊断暂时不可读，请稍后查看") || strings.Contains(text, "未读取到诊断记录") || !strings.Contains(text, "completion-unknown") {
		t.Fatal("actual storage failure lost unreadable or stopped state")
	}
	if err := a.applyTouchImmediate("diagnostic-close"); err != nil {
		t.Fatal(err)
	}
	if !a.preview.fault || a.preview.lastDiagnostic.Reason != "completion-unknown" || a.installed.lease != "stopped-lease" || !reflect.DeepEqual(a.preview.snapshot, before) || calls != 0 {
		t.Fatal("view recovered, rewrote, or replayed stopped input")
	}
}
