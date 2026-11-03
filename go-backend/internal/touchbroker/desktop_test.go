package touchbroker

import (
	"context"
	"encoding/json"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"testing"
	"time"
)

func relayFixture() (*DesktopRelay, *tipPeer, *bool) {
	focused := true
	r := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { return focused }, func(c yimebroker.TrustedClient) bool { return c.ID == "ui" })
	p := r.newPeer(yimebroker.TrustedClient{ID: "tip"})
	p.lease = "lease"
	p.window = 10
	p.thread = 20
	p.generation = 1
	return r, p, &focused
}
func queuedCall(t *testing.T, r *DesktopRelay, p *tipPeer, q DesktopRequest) <-chan DesktopResponse {
	t.Helper()
	result := make(chan DesktopResponse, 1)
	go func() { result <- r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, q) }()
	deadline := time.Now().Add(time.Second)
	for len(p.queue) == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if len(p.queue) == 0 {
		t.Fatal("action not queued")
	}
	return result
}
func TestDesktopRelayCompletesOnlyMatchingFocusedTIP(t *testing.T) {
	r, p, focused := relayFixture()
	defer r.closePeer(p)
	result := queuedCall(t, r, p, DesktopRequest{Operation: "bind", Mode: "full"})
	task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Thread: 20, Generation: 1})
	if !task.OK || task.Operation != "bind" || task.Mode != "full" || task.Ticket == "" {
		t.Fatalf("bad forwarded action: %+v", task)
	}
	select {
	case <-result:
		t.Fatal("UI answered before actual TIP completion")
	default:
	}
	if r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: "other", Result: json.RawMessage(`{"ok":true}`)}).OK {
		t.Fatal("foreign receipt accepted")
	}
	if r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{}`)}).OK {
		t.Fatal("overlapping edit accepted")
	}
	raw := json.RawMessage(`{"ok":true,"snapshot":{"revision":1},"commit":{"text":"private"},"receipt":{"outcome":"applied"}}`)
	if !r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Result: raw}).OK {
		t.Fatal("completion rejected")
	}
	out := <-result
	var body map[string]any
	_ = json.Unmarshal(out.Result, &body)
	if !out.OK || out.Lease == "" || out.Lease == "lease" || body["commit"] != nil || body["receipt"] != nil {
		t.Fatalf("leaked write capability: %+v", out)
	}
	if r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{"kind":"input","revision":0,"code":"a"}`)}).OK {
		t.Fatal("old lease survived same-context rebind")
	}
	if r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Result: raw}).OK {
		t.Fatal("duplicate completion accepted")
	}
	*focused = false
	if r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "bind", Mode: "variable"}).OK {
		t.Fatal("unfocused TIP selected")
	}
}
func TestDesktopRelayFocusLossAndInvalidResultStopPending(t *testing.T) {
	for _, kind := range []string{"focus", "close", "invalid"} {
		t.Run(kind, func(t *testing.T) {
			r, p, focused := relayFixture()
			defer r.closePeer(p)
			done := queuedCall(t, r, p, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{"kind":"input","revision":0,"code":"a"}`)})
			task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Thread: 20, Generation: 1})
			raw := json.RawMessage(`{"ok":true}`)
			if kind == "focus" {
				*focused = false
			}
			if kind == "invalid" {
				raw = []byte(`[]`)
			}
			if kind == "close" {
				r.closePeer(p)
			} else {
				r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Result: raw})
			}
			select {
			case out := <-done:
				if out.OK || p.lease != "" {
					t.Fatal("revoked action reported success")
				}
			case <-time.After(time.Second):
				t.Fatal("lost pending completion")
			}
		})
	}
}
func TestDesktopRelayRejectsForeignFrontendAndStaleLease(t *testing.T) {
	r, p, _ := relayFixture()
	defer r.closePeer(p)
	if r.call(context.Background(), yimebroker.TrustedClient{ID: "other"}, DesktopRequest{Operation: "bind", Mode: "variable"}).OK {
		t.Fatal("wrong executable accepted")
	}
	if r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "action", Lease: "old", Action: json.RawMessage(`{}`)}).OK {
		t.Fatal("old lease accepted")
	}
}
