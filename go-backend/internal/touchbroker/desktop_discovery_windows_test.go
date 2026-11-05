//go:build windows

package touchbroker

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
)

// This is an injected authenticated-handler identity, not OS authentication
// evidence. It deliberately matches the other connection's process identity.
const discoveryOfflineOwner = "windows:S-1-5-21-test:session:2:logon:test:pid:1234:created:01dd000000000001"

func desktopDiscoveryFrame(reason, codes string) string {
	return "{\"operation\":\"diagnostic\",\"version\":1,\"diagnostic\":{\"stage\":\"tip-discovery\",\"reason\":\"" + reason + "\"" + codes + "}}"
}

func discoveryOtherConnection(relay *DesktopRelay) (*tipPeer, *desktopCall, *desktopCall) {
	p := relay.newPeer(yimebroker.TrustedClient{ID: discoveryOfflineOwner})
	p.window, p.thread, p.generation, p.lease = 71, 72, 73, "other-live-lease"
	pending := &desktopCall{ticket: "other-pending", lease: p.lease, result: make(chan DesktopResponse, 1)}
	queued := &desktopCall{ticket: "other-queued", lease: p.lease, result: make(chan DesktopResponse, 1)}
	p.pending = pending
	p.queue <- queued
	return p, pending, queued
}

func assertDiscoveryOtherConnection(t *testing.T, relay *DesktopRelay, other *tipPeer, pending, queued *desktopCall) {
	t.Helper()
	if len(relay.peers) != 1 || !relay.peers[other] || other.closed || other.window != 71 || other.thread != 72 || other.generation != 73 || other.lease != "other-live-lease" || other.pending != pending || len(other.queue) != 1 || len(pending.result) != 0 || len(queued.result) != 0 {
		t.Fatal("discovery connection changed another live connection's lease or work")
	}
	got := <-other.queue
	if got != queued || got.ticket != "other-queued" || got.lease != "other-live-lease" || pending.ticket != "other-pending" || pending.lease != "other-live-lease" {
		t.Fatal("another connection's pending input was changed")
	}
	other.queue <- got
	// Prove that the unaffected connection can still complete its own pending
	// action; this is an in-memory relay receipt, never a real host operation.
	completed := relay.tip(context.Background(), other, tipRequest{Operation: "complete", Ticket: pending.ticket, Result: json.RawMessage("{\"ok\":true}")})
	if !completed.OK || other.pending != nil || other.closed || other.lease != "other-live-lease" || len(other.queue) != 1 {
		t.Fatal("another live connection could not continue after discovery rejection")
	}
	select {
	case result := <-pending.result:
		if !result.OK || result.Lease != "other-live-lease" {
			t.Fatal("another connection's completion was revoked")
		}
	default:
		t.Fatal("another connection lost its pending result")
	}
}

func discoveryCallbackRecord(t *testing.T, err error, sink *connectionDiagnosticSink) touchdiagnostic.Diagnostic {
	t.Helper()
	var returned touchdiagnostic.Diagnostic
	d, ok := touchdiagnostic.DecodeLine(sink.Bytes())
	if !ok || !errors.As(err, &returned) || sink.writes != 1 || sink.Len() > touchdiagnostic.MaxLine || strings.Count(sink.String(), "\n") != 1 || returned.Error() != d.Error() {
		t.Fatal("terminal report did not reach one bounded typed-error callback")
	}
	if strings.Contains(sink.String(), "PRIVATE") || strings.Contains(sink.String(), "S-1-5") || strings.Contains(sink.String(), "other-live-lease") {
		t.Fatal("diagnostic callback exposed request, owner or lease text")
	}
	return d
}

func TestDesktopDiscoveryFirstFrameReportsWithoutPeerOrInput(t *testing.T) {
	for _, tc := range []struct{ reason, codes string }{
		{"tip-not-focused", ""},
		{"foreground-missing", ""},
		{"foreground-query-failed", ""},
		{"foreground-other-process", ""},
		{"foreground-thread-mismatch", ""},
		{"tsf-document-missing", ""},
		{"tsf-context-missing", ""},
		{"get-focus-failed", ",\"hresult\":2147500037"},
		{"get-top-failed", ",\"hresult\":2147942405"},
		{"tip-endpoint-unavailable", ",\"win32\":2"},
	} {
		t.Run(tc.reason, func(t *testing.T) {
			foregroundCalls := 0
			relay := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { foregroundCalls++; return true }, nil)
			other, pending, queued := discoveryOtherConnection(relay)
			sink := &connectionDiagnosticSink{}
			// A following business frame must not be processed on this connection.
			body := desktopDiscoveryFrame(tc.reason, tc.codes) + "\n{\"operation\":\"next\",\"window\":1,\"thread\":2,\"generation\":1}\n"
			err, protocol := runDesktopHandlerOffline(t, relay.serveTIP, yimebroker.TrustedClient{ID: discoveryOfflineOwner}, body, sink)
			d := discoveryCallbackRecord(t, err, sink)
			if len(protocol) != 0 || foregroundCalls != 0 || d.Stage != "tip-discovery" || d.Reason != tc.reason || d.Reported == nil {
				t.Fatal("discovery report created a normal session or success response")
			}
			origin := d.Reported
			if origin.PID != 1234 || origin.Created != 0x01dd000000000001 || origin.ReceivedMS <= 0 || len(origin.Event) != 32 || strings.ToLower(origin.Event) != origin.Event {
				t.Fatal("server-derived origin did not match the authenticated handler identity")
			}
			if _, err := hex.DecodeString(origin.Event); err != nil {
				t.Fatal("event identity is not bounded hexadecimal")
			}
			wire, ok := touchdiagnostic.DecodeDiscoveryFrame([]byte(desktopDiscoveryFrame(tc.reason, tc.codes)))
			if !ok || (wire.HRESULT == nil) != (d.HRESULT == nil) || wire.HRESULT != nil && *wire.HRESULT != *d.HRESULT || (wire.Win32 == nil) != (d.Win32 == nil) || wire.Win32 != nil && *wire.Win32 != *d.Win32 {
				t.Fatal("applicable code was lost or fabricated by the callback")
			}
			assertDiscoveryOtherConnection(t, relay, other, pending, queued)
		})
	}
}

func TestDesktopDiscoveryMalformedFirstFrameCannotBecomeBusinessPeer(t *testing.T) {
	valid := desktopDiscoveryFrame("tip-not-focused", "")
	for _, body := range []string{
		"{\"operation\":\"diagnostic\"}",
		strings.Replace(valid, "\"version\":1", "\"version\":2", 1),
		strings.Replace(valid, "\"version\":1", "\"version\":null", 1),
		strings.Replace(valid, "\"version\":1", "\"version\":4294967296", 1),
		strings.Replace(valid, "\"version\":1", "\"version\":1,\"version\":1", 1),
		strings.Replace(valid, "\"operation\":", "\"operation\":\"diagnostic\",\"operation\":", 1),
		"{\"operation\":\"diagnostic\",\"version\":1,\"diagnostic\":null}",
		strings.TrimSuffix(valid, "}") + ",\"private\":\"PRIVATE\"}",
		desktopDiscoveryFrame("get-focus-failed", ",\"hresult\":0"),
		desktopDiscoveryFrame("foreground-query-failed", ",\"win32\":5"),
		desktopDiscoveryFrame("tip-endpoint-unavailable", ",\"win32\":4294967296"),
		desktopDiscoveryFrame("tip-not-focused", ",\"reported\":{\"at\":1,\"event\":\"0123456789abcdef0123456789abcdef\",\"pid\":99,\"created\":99}"),
		valid + " " + valid,
		valid + strings.Repeat(" ", touchdiagnostic.MaxLine+65-len(valid)),
	} {
		foregroundCalls := 0
		relay := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { foregroundCalls++; return true }, nil)
		other, pending, queued := discoveryOtherConnection(relay)
		sink := &connectionDiagnosticSink{}
		err, protocol := runDesktopHandlerOffline(t, relay.serveTIP, yimebroker.TrustedClient{ID: discoveryOfflineOwner}, body+"\n", sink)
		d := discoveryCallbackRecord(t, err, sink)
		if len(protocol) != 0 || foregroundCalls != 0 || d.Stage == "tip-discovery" || d.Reported != nil {
			t.Fatal("malformed discovery was acknowledged or recorded as a client report")
		}
		assertDiscoveryOtherConnection(t, relay, other, pending, queued)
	}
}

func TestDesktopDiscoveryInjectedAfterNormalPollIsRejected(t *testing.T) {
	var relay *DesktopRelay
	var other, normal *tipPeer
	ordinary := &desktopCall{ticket: "normal-ticket", lease: "normal-lease", request: DesktopRequest{Operation: "action", Action: json.RawMessage("{\"kind\":\"clear\",\"revision\":0}")}, result: make(chan DesktopResponse, 1)}
	foregroundCalls := 0
	fixturePeerMissing := false
	relay = NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool {
		foregroundCalls++
		if normal == nil {
			for p := range relay.peers {
				if p != other {
					normal = p
				}
			}
			if normal == nil {
				fixturePeerMissing = true
				return false
			}
			// Seed a ready action synchronously while tip holds the relay lock;
			// next consumes it immediately, without a timer or a sleep race.
			normal.window, normal.thread, normal.generation, normal.lease = 1, 2, 1, ordinary.lease
			normal.queue <- ordinary
		}
		return true
	}, nil)
	var pending, queued *desktopCall
	other, pending, queued = discoveryOtherConnection(relay)
	input := "{\"operation\":\"next\",\"window\":1,\"thread\":2,\"generation\":1}\n" + desktopDiscoveryFrame("tip-not-focused", "") + "\n"
	sink := &connectionDiagnosticSink{}
	err, protocol := runDesktopHandlerOffline(t, relay.serveTIP, yimebroker.TrustedClient{ID: discoveryOfflineOwner}, input, sink)
	d := discoveryCallbackRecord(t, err, sink)
	var response tipResponse
	if fixturePeerMissing || json.Unmarshal(protocol, &response) != nil || !response.OK || response.Ticket != ordinary.ticket || response.Operation != "action" || strings.Count(string(protocol), "\n") != 1 || foregroundCalls != 2 {
		t.Fatal("fixture did not reach exactly one ordinary TIP action")
	}
	if d.Stage != "broker-request" || d.Reported != nil || normal == nil || !normal.closed || normal.lease != "" || normal.pending != nil || len(ordinary.result) != 1 {
		t.Fatal("in-session discovery was accepted or its connection remained usable")
	}
	retired := <-ordinary.result
	if retired.OK || retired.Diagnostic == nil || retired.Diagnostic.Reason != "focus-revoked" {
		t.Fatal("pending work received a success or was not retired")
	}
	assertDiscoveryOtherConnection(t, relay, other, pending, queued)
}

func TestDesktopCompletionCannotForgeDiscoveryReportOrigin(t *testing.T) {
	type spelling struct{ diagnostic, reported string }
	for _, tc := range []struct {
		name   string
		fields []spelling
	}{
		{"lowercase", []spelling{{"diagnostic", "reported"}}},
		{"titlecase", []spelling{{"Diagnostic", "Reported"}}},
		{"uppercase", []spelling{{"DIAGNOSTIC", "REPORTED"}}},
		{"coexisting-case-variants", []spelling{{"diagnostic", "reported"}, {"Diagnostic", "reported"}}},
		{"coexisting-mixed-fields", []spelling{{"diagnostic", "reported"}, {"Diagnostic", "Reported"}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			relay := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { return true }, nil)
			other, otherPending, otherQueued := discoveryOtherConnection(relay)
			owner := yimebroker.TrustedClient{ID: discoveryOfflineOwner}
			normal := relay.newPeer(owner)
			normal.window, normal.thread, normal.generation, normal.lease = 21, 22, 23, "completion-lease"
			pending := &desktopCall{ticket: "completion-ticket", lease: normal.lease, result: make(chan DesktopResponse, 1)}
			normal.pending = pending
			inner := map[string]any{
				"ok": false, "error": "synthetic completion failure",
				"snapshot": map[string]any{"ok": false, "sessionId": "completion-session", "revision": 7},
				"pending":  false, "other": map[string]any{"retained": true},
				"commit": "not-a-frontend-capability", "receipt": map[string]any{"private": true},
			}
			for _, field := range tc.fields {
				inner[field.diagnostic] = map[string]any{
					"stage": "tip-discovery", "reason": "get-focus-failed", "hresult": uint32(0x80004005),
					field.reported: map[string]any{"at": int64(1793793600000), "event": "0123456789abcdef0123456789abcdef", "pid": uint32(9999), "created": uint64(0x01dd000000000099)},
				}
			}
			raw, err := json.Marshal(inner)
			if err != nil {
				t.Fatal(err)
			}
			ack := relay.tip(context.Background(), normal, tipRequest{Operation: "complete", Ticket: pending.ticket, Result: raw})
			if !ack.OK || normal.closed || normal.pending != nil || normal.lease != "completion-lease" || len(relay.peers) != 2 {
				t.Fatal("ordinary completion was rejected or changed its session")
			}
			var forwarded DesktopResponse
			select {
			case forwarded = <-pending.result:
			default:
				t.Fatal("ordinary completion was not forwarded")
			}
			if !forwarded.OK || forwarded.Lease != normal.lease || forwarded.Diagnostic != nil {
				t.Fatal("completion envelope was changed or gained trusted diagnostic metadata")
			}
			// Existing commit/receipt filtering remains; the only new removals are
			// case variants of untrusted origin. Failure and ordinary state survive.
			delete(inner, "commit")
			delete(inner, "receipt")
			for _, field := range tc.fields {
				delete(inner[field.diagnostic].(map[string]any), field.reported)
			}
			expectedRaw, err := json.Marshal(inner)
			if err != nil {
				t.Fatal(err)
			}
			var expected, got map[string]any
			if json.Unmarshal(expectedRaw, &expected) != nil || json.Unmarshal(forwarded.Result, &got) != nil || !reflect.DeepEqual(got, expected) {
				t.Fatal("forged origin survived or unrelated completion fields changed")
			}
			// Match the frontend's case-insensitive struct decoder as well as the
			// exact map shape, including multiple spellings in the same result.
			var decoded struct {
				OK         bool                        `json:"ok"`
				Error      string                      `json:"error"`
				Diagnostic *touchdiagnostic.Diagnostic `json:"diagnostic"`
			}
			if json.Unmarshal(forwarded.Result, &decoded) != nil || decoded.OK || decoded.Error != "synthetic completion failure" || decoded.Diagnostic == nil || decoded.Diagnostic.Reported != nil || decoded.Diagnostic.Reason != "get-focus-failed" || decoded.Diagnostic.HRESULT == nil || *decoded.Diagnostic.HRESULT != 0x80004005 {
				t.Fatal("frontend decoding gained a forged origin or lost the failed completion")
			}
			if !relay.peers[other] || other.closed || other.pending != otherPending || other.lease != "other-live-lease" || other.window != 71 || other.thread != 72 || other.generation != 73 || len(other.queue) != 1 || len(otherPending.result) != 0 || len(otherQueued.result) != 0 {
				t.Fatal("same-owner completion modified the other connection")
			}
			// Retire only this fixture connection, then prove the other can continue.
			relay.closePeer(normal)
			assertDiscoveryOtherConnection(t, relay, other, otherPending, otherQueued)
		})
	}
}
