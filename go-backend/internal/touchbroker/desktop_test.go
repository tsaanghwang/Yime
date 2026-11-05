package touchbroker

import (
	"context"
	"encoding/json"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"strings"
	"testing"
	"time"
)

func relayFixture() (*DesktopRelay, *tipPeer, *bool) {
	focused := true
	r := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint64, uint32) bool { return focused }, func(c yimebroker.TrustedClient) bool { return c.ID == "ui" })
	p := r.newPeer(yimebroker.TrustedClient{ID: "tip"})
	p.lease = "lease"
	p.window = 10
	p.focus = 11
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
	task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Focus: 11, Thread: 20, Generation: 1})
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
			task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Focus: 11, Thread: 20, Generation: 1})
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

func TestDesktopRelayRejectsPollWithoutFocusedControl(t *testing.T) {
	r, p, _ := relayFixture()
	defer r.closePeer(p)
	for _, field := range []string{"window", "focus", "thread", "generation"} {
		t.Run(field, func(t *testing.T) {
			q := tipRequest{Operation: "next", Window: 10, Focus: 11, Thread: 20, Generation: 1}
			switch field {
			case "window":
				q.Window = 0
			case "focus":
				q.Focus = 0 // Old poll envelopes cannot silently bind a top-level window.
			case "thread":
				q.Thread = 0
			case "generation":
				q.Generation = 0
			}
			if r.tip(context.Background(), p, q).OK || p.lease != "lease" || p.pending != nil {
				t.Fatal("incomplete poll changed the lease")
			}
		})
	}
}

func TestDesktopRelayFocusChangeRetiresQueuedAction(t *testing.T) {
	r, p, _ := relayFixture()
	defer r.closePeer(p)
	done := queuedCall(t, r, p, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{"kind":"input","revision":0,"code":"a"}`)})
	// The top-level window and TIP thread stay the same. A different editor
	// must still retire the old capability and must never receive its action.
	out := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Focus: 12, Thread: 20, Generation: 1})
	if !out.OK || out.Ticket != "" || p.focus != 12 || p.lease == "" || p.lease == "lease" || p.pending != nil {
		t.Fatalf("focus change did not isolate the new lease: %+v", out)
	}
	if result := <-done; result.OK || !strings.Contains(result.Error, "no replay") {
		t.Fatalf("queued old action survived focus change: %+v", result)
	}
	if result := r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{}`)}); result.OK {
		t.Fatal("retired focus lease accepted")
	}
}

func TestDesktopRelayCompletionCannotReplaceFocus(t *testing.T) {
	r, p, _ := relayFixture()
	defer r.closePeer(p)
	done := queuedCall(t, r, p, DesktopRequest{Operation: "bind", Mode: "full"})
	task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Focus: 11, Thread: 20, Generation: 1})
	raw := json.RawMessage(`{"ok":true}`)
	if r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Focus: 12, Result: raw}).OK {
		t.Fatal("completion changed the focused control")
	}
	if p.pending == nil || p.focus != 11 {
		t.Fatal("invalid completion consumed or retargeted the pending action")
	}
	if !r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Result: raw}).OK {
		t.Fatal("matching completion rejected")
	}
	if result := <-done; !result.OK {
		t.Fatalf("valid original completion lost: %+v", result)
	}
}

func TestDesktopRelayFocusChangeBeforeCompletionFails(t *testing.T) {
	r, p, _ := relayFixture()
	defer r.closePeer(p)
	currentFocus := uint64(11)
	r.foreground = func(_ yimebroker.TrustedClient, window, focus uint64, thread uint32) bool {
		return window == 10 && focus == currentFocus && thread == 20
	}
	done := queuedCall(t, r, p, DesktopRequest{Operation: "bind", Mode: "full"})
	task := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Focus: 11, Thread: 20, Generation: 1})
	currentFocus = 12 // Same window, process and thread; different editor.
	if !r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: task.Ticket, Result: json.RawMessage(`{"ok":true}`)}).OK {
		t.Fatal("completion should acknowledge disposal of the stale receipt")
	}
	if out := <-done; out.OK || out.Lease != "" || !strings.Contains(out.Error, "no replay") || p.lease != "" {
		t.Fatalf("old control's completion revived a changed focus: %+v", out)
	}
}

func TestDesktopRelayBindFailureStages(t *testing.T) {
	for _, stage := range []string{"no-tip-peer", "no-active-lease", "foreground-mismatch", "ambiguous-tip"} {
		t.Run(stage, func(t *testing.T) {
			r, p, focused := relayFixture()
			defer r.closePeer(p)
			switch stage {
			case "no-tip-peer":
				r.closePeer(p)
			case "no-active-lease":
				p.lease = ""
			case "foreground-mismatch":
				*focused = false
			case "ambiguous-tip":
				other := r.newPeer(yimebroker.TrustedClient{ID: "tip-other"})
				defer r.closePeer(other)
				other.lease, other.window, other.focus, other.thread = "other", 10, 11, 20
			}
			out := r.call(context.Background(), yimebroker.TrustedClient{ID: "ui"}, DesktopRequest{Operation: "bind", Mode: "full"})
			if out.OK || out.Lease != "" || !strings.HasPrefix(out.Error, "[bind:"+stage+"]") || len(p.queue) != 0 || p.pending != nil {
				t.Fatalf("missing or unsafe bind diagnostic: %+v", out)
			}
		})
	}
}
