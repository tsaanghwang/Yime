//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func routingTrace(t *testing.T, a *ui) func() []map[string]any {
	t.Helper()
	path := filepath.Join(t.TempDir(), "routing.jsonl")
	tr, err := openInputTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	a.inputTrace = tr
	t.Cleanup(func() { tr.file.Close() })
	return func() []map[string]any {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(raw), "PRIVATE_SENTINEL") {
			t.Fatal("private content in trace")
		}
		var rows []map[string]any
		for _, line := range strings.Split(strings.TrimSpace(string(raw)), "\n") {
			if line == "" {
				continue
			}
			var row map[string]any
			if err := json.Unmarshal([]byte(line), &row); err != nil {
				t.Fatal(err)
			}
			if row["schemaVersion"] != float64(2) || row["diagnosticVersion"] != "pr87-routing-v1" {
				t.Fatal("missing diagnostic identity")
			}
			rows = append(rows, row)
		}
		return rows
	}
}
func hasRoutingReason(rows []map[string]any, stage, reason string) bool {
	for _, r := range rows {
		if r["stage"] == stage && r["reason"] == reason {
			return true
		}
	}
	return false
}
func TestRoutingTraceReadAndPalmPrivacy(t *testing.T) {
	a := touchUIFixture(t)
	rows := routingTrace(t, a)
	a.preview.editor.insert("PRIVATE_SENTINEL")
	a.touchReader = func(w, l uintptr) ([]touch, error) { return nil, errors.New("PRIVATE_SENTINEL") }
	a.touch(0, 0)
	if !hasRoutingReason(rows(), "touch-read", "failed") {
		t.Fatal("missing read failure")
	}
	a.touchReader = func(w, l uintptr) ([]touch, error) { return []touch{{ID: 81, Flags: 0x82}}, nil }
	a.touch(0, 0)
	if !hasRoutingReason(rows(), "touch-route", "palm-down-skipped") || len(a.previewTouches) != 0 {
		t.Fatal("palm handling changed or not observed")
	}
}
func TestRoutingTracePageAndStaleGesture(t *testing.T) {
	for _, enabled := range []bool{false, true} {
		a := touchUIFixture(t)
		var rows func() []map[string]any
		if enabled {
			rows = routingTrace(t, a)
		}
		previewAction(t, a.preview, "input", "p", "")
		h := a.touchHeaderLayout()
		c := a.candidateRect(0)
		cx, cy := (c.L+c.R)/2, (c.T+c.B)/2
		nx, ny := (h.next.L+h.next.R)/2, (h.next.T+h.next.B)/2
		a.down(100, cx, cy)
		a.down(101, nx, ny)
		a.up(101, nx, ny)
		a.up(100, cx, cy)
		a.up(100, cx, cy)
		if a.preview.snapshot.State.PageNumber != 1 || len(a.preview.editor.text) != 0 || a.preview.snapshot.State.RawInput != "p" {
			t.Fatal("trace changed paging")
		}
		if enabled && (!hasRoutingReason(rows(), "page-result", "page-changed") || !hasRoutingReason(rows(), "gesture-result", "stale-version") || !hasRoutingReason(rows(), "gesture-up", "no-pending-gesture")) {
			t.Fatal("missing page rejection evidence")
		}
	}
}
func TestRoutingTraceLifecycleAndWriterFailurePassive(t *testing.T) {
	a := touchUIFixture(t)
	rows := routingTrace(t, a)
	a.traceLifecycle("minimized")
	a.traceLifecycle("minimized")
	a.traceLifecycle("size-visible")
	if a.inputTrace.epoch != 1 || !hasRoutingReason(rows(), "lifecycle", "restored-reprepare-required") {
		t.Fatal("missing lifecycle")
	}
	if len(a.preview.editor.text) != 0 || len(a.previewTouches) != 0 {
		t.Fatal("logger mutated input")
	}
	a.inputTrace.file.Close()
	previewAction(t, a.preview, "input", "p", "")
	h := a.touchHeaderLayout()
	x, y := (h.next.L+h.next.R)/2, (h.next.T+h.next.B)/2
	a.down(10, x, y)
	a.up(10, x, y)
	if a.preview.snapshot.State.PageNumber != 1 || a.inputTrace.err == nil {
		t.Fatal("failed writer affected action or error missing")
	}
}

func TestRoutingTraceIdleMovesAreNotLogged(t *testing.T) {
	for _, msg := range []uint32{0x0200, 0x0245} {
		if tracedInputMessage(msg, false) || !tracedInputMessage(msg, true) {
			t.Fatal("idle move trace policy", msg)
		}
	}
	for _, msg := range []uint32{0x0246, 0x0247} {
		if !tracedInputMessage(msg, false) {
			t.Fatal("contact boundary missing")
		}
	}
}

func TestRoutingTraceIdleMouseRouteProducesNoRows(t *testing.T) {
	a := touchUIFixture(t)
	rows := routingTrace(t, a)
	a.traceMouseRoute(0x0200, "accepted")
	a.traceMouseRoute(0x0200, "compatibility-duplicate-suppressed")
	if len(rows()) != 0 {
		t.Fatal("idle mouse route was logged")
	}
	a.traceMouseRoute(0x0201, "accepted")
	if !hasRoutingReason(rows(), "mouse-route", "accepted") {
		t.Fatal("mouse down route missing")
	}
}

func TestRoutingTraceWindowIdleMouseDoesNotLog(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a := touchUIFixture(t)
	rows := routingTrace(t, a)
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create isolated window")
	}
	previous := active
	a.h, active = h, a
	defer func() { active = previous; U("DestroyWindow").Call(h) }()
	before, _ := json.Marshal(a.preview.snapshot)
	windowProc(h, 0x0200, 0, 0)
	after, _ := json.Marshal(a.preview.snapshot)
	if len(rows()) != 0 || string(before) != string(after) || len(a.previewTouches) != 0 {
		t.Fatal("idle mouse changed state or logged")
	}
}

func TestRoutingTraceDisabledPageHitReasons(t *testing.T) {
	a := touchUIFixture(t)
	rows := routingTrace(t, a)
	previewAction(t, a.preview, "input", "p", "")
	h := a.touchHeaderLayout()
	if a.preview.snapshot.State.HasPrevious || !a.preview.snapshot.State.HasNext {
		t.Fatal("fixture page availability")
	}
	a.down(1, (h.previous.L+h.previous.R)/2, (h.previous.T+h.previous.B)/2)
	if !hasRoutingReason(rows(), "page-hit", "boundary-unavailable") || len(a.previewTouches) != 0 {
		t.Fatal("missing boundary rejection")
	}
	previewAction(t, a.preview, "toggle-language", "", "")
	a.down(2, (h.next.L+h.next.R)/2, (h.next.T+h.next.B)/2)
	if !hasRoutingReason(rows(), "page-hit", "candidates-disabled") || len(a.previewTouches) != 0 {
		t.Fatal("missing paused candidate rejection")
	}
}
