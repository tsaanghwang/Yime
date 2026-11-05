package touchbroker

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

func TestDesktopDiagnosticSelectionAndRequestFailures(t *testing.T) {
	cases := []struct {
		name, stage, reason string
		setup               func(*DesktopRelay, *tipPeer, *bool, *DesktopRequest) yimebroker.TrustedClient
	}{
		{"unauthorized", "broker-auth", "frontend-not-authorized", func(*DesktopRelay, *tipPeer, *bool, *DesktopRequest) yimebroker.TrustedClient {
			return yimebroker.TrustedClient{ID: "foreign"}
		}},
		{"operation", "broker-request", "invalid-operation", func(_ *DesktopRelay, _ *tipPeer, _ *bool, q *DesktopRequest) yimebroker.TrustedClient {
			q.Operation = "private-input"
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"bind", "broker-request", "invalid-bind", func(_ *DesktopRelay, _ *tipPeer, _ *bool, q *DesktopRequest) yimebroker.TrustedClient {
			q.Mode = "private-mode"
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"action", "broker-request", "invalid-action-lease", func(_ *DesktopRelay, _ *tipPeer, _ *bool, q *DesktopRequest) yimebroker.TrustedClient {
			q.Operation = "action"
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"unfocused", "broker-select", "no-eligible-tip", func(_ *DesktopRelay, _ *tipPeer, f *bool, _ *DesktopRequest) yimebroker.TrustedClient {
			*f = false
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"missing-lease", "broker-select", "no-eligible-tip", func(_ *DesktopRelay, p *tipPeer, _ *bool, _ *DesktopRequest) yimebroker.TrustedClient {
			p.lease = ""
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"ambiguous", "broker-select", "ambiguous-tip", func(r *DesktopRelay, _ *tipPeer, _ *bool, _ *DesktopRequest) yimebroker.TrustedClient {
			p := r.newPeer(yimebroker.TrustedClient{ID: "second-tip"})
			p.lease = "second-lease"
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"pending", "broker-queue", "edit-pending", func(_ *DesktopRelay, p *tipPeer, _ *bool, _ *DesktopRequest) yimebroker.TrustedClient {
			p.pending = &desktopCall{result: make(chan DesktopResponse, 1)}
			return yimebroker.TrustedClient{ID: "ui"}
		}},
		{"queued", "broker-queue", "action-queued", func(_ *DesktopRelay, p *tipPeer, _ *bool, _ *DesktopRequest) yimebroker.TrustedClient {
			p.queue <- &desktopCall{result: make(chan DesktopResponse, 1)}
			return yimebroker.TrustedClient{ID: "ui"}
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r, p, focus := relayFixture()
			q := DesktopRequest{Operation: "bind", Mode: "variable"}
			owner := c.setup(r, p, focus, &q)
			out := r.call(context.Background(), owner, q)
			if out.OK || out.Diagnostic == nil || out.Diagnostic.Stage != c.stage || out.Diagnostic.Reason != c.reason || out.Lease != "" || len(out.Result) != 0 {
				t.Fatal("failure classification or output boundary changed")
			}
			if out.Error != c.stage+"/"+c.reason {
				t.Fatal("request data entered failure text")
			}
		})
	}
}

func TestDesktopDiagnosticRevocationRetainsLeaseBarrier(t *testing.T) {
	r, p, _ := relayFixture()
	pending := &desktopCall{result: make(chan DesktopResponse, 1)}
	queued := &desktopCall{result: make(chan DesktopResponse, 1)}
	p.pending = pending
	p.queue <- queued
	r.revoke(p)
	if p.lease != "" || p.pending != nil || len(p.queue) != 0 {
		t.Fatal("diagnostics changed revocation state")
	}
	for _, c := range []struct {
		call   *desktopCall
		reason string
	}{{pending, "focus-revoked"}, {queued, "lease-revoked"}} {
		out := <-c.call.result
		if out.OK || out.Diagnostic == nil || out.Diagnostic.Reason != c.reason {
			t.Fatal("revoked operation lacks fixed diagnostic")
		}
		if len(c.call.result) != 0 {
			t.Fatal("revoked operation completed more than once")
		}
	}
}

func TestDesktopDiagnosticInvalidCompletionStillRevokes(t *testing.T) {
	r, p, _ := relayFixture()
	done := queuedCall(t, r, p, DesktopRequest{Operation: "action", Lease: "lease", Action: json.RawMessage(`{"kind":"input","revision":0,"code":"private"}`)})
	q := r.tip(context.Background(), p, tipRequest{Operation: "next", Window: 10, Thread: 20, Generation: 1})
	receipt := r.tip(context.Background(), p, tipRequest{Operation: "complete", Ticket: q.Ticket, Result: json.RawMessage(`[]`)})
	out := <-done
	if receipt.OK || receipt.Diagnostic == nil || out.OK || out.Diagnostic == nil || out.Diagnostic.Stage != "broker-receipt" || out.Diagnostic.Reason != "invalid-response" || p.lease != "" || p.pending != nil {
		t.Fatal("invalid completion did not preserve failure-stop and lease revocation")
	}
}
