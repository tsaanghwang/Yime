//go:build windows

package touchbroker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"io"
	"os"
	"strings"
	"testing"
	"time"
)

type firstFrameReader struct {
	reader    io.Reader
	deadlines []time.Time
	setError  error
	reads     int
}

func (r *firstFrameReader) SetReadDeadline(at time.Time) error {
	r.deadlines = append(r.deadlines, at)
	return r.setError
}
func (r *firstFrameReader) Read(p []byte) (int, error) {
	r.reads++
	if r.reader == nil {
		return 0, os.ErrDeadlineExceeded
	}
	return r.reader.Read(p)
}

func TestDesktopDiscoveryFirstFrameDeadlineAndOrdinaryPollCompatibility(t *testing.T) {
	owner := yimebroker.TrustedClient{ID: "windows:fixture:session:1:logon:fixture:pid:12:created:01dd000000000001"}
	for _, tc := range []struct {
		name, frame string
		setError    error
		calls       int
	}{
		{"idle", "", nil, 1},
		{"deadline-failure", "", errors.New("private deadline error"), 1},
		{"discovery", `{"operation":"diagnostic","version":1,"diagnostic":{"stage":"tip-discovery","reason":"tip-not-focused"}}` + "\n", nil, 1},
		{"ordinary", `{"operation":"next","window":1,"thread":2,"generation":1}` + "\n", nil, 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			relay := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { return false }, nil)
			in := &firstFrameReader{setError: tc.setError}
			if tc.frame != "" {
				in.reader = strings.NewReader(tc.frame)
			}
			var output bytes.Buffer
			before := time.Now()
			err := relay.serveTIP(context.Background(), in, &output, owner)
			if (tc.name == "ordinary") != (err == nil) || len(in.deadlines) != tc.calls || in.deadlines[0].Before(before) || in.deadlines[0].After(time.Now().Add(time.Second)) || len(relay.peers) != 0 {
				t.Fatal("first-frame deadline or peer cleanup changed", err)
			}
			if tc.calls == 2 && !in.deadlines[1].IsZero() {
				t.Fatal("ordinary protocol kept the discovery deadline")
			}
			if tc.name == "idle" && !errors.Is(err, os.ErrDeadlineExceeded) {
				t.Fatal("idle read lost timeout", err)
			}
			if tc.setError != nil && in.reads != 0 {
				t.Fatal("read started after deadline setup failure")
			}
		})
	}
}

func TestDesktopDiscoveryServerDropClosesWithoutReportingOrBusinessPeer(t *testing.T) {
	relay := NewDesktopRelay(nil, nil)
	relay.diagnosticBudget.since = time.Now()
	relay.diagnosticBudget.used = desktopDiagnosticLimit
	in := &firstFrameReader{reader: strings.NewReader(`{"operation":"diagnostic","version":1,"diagnostic":{"stage":"tip-discovery","reason":"tip-not-focused"}}` + "\n")}
	var output, sink bytes.Buffer
	err := relay.serveTIP(context.Background(), in, &output, yimebroker.TrustedClient{ID: "unneeded-because-discarded"})
	writeDesktopConnectionDiagnostic(&sink, err)
	if !errors.Is(err, errDiagnosticDropped) || output.Len() != 0 || sink.Len() != 0 || len(relay.peers) != 0 {
		t.Fatal("over-budget diagnostic created output/state", err)
	}
}

func TestDesktopDiscoveryOriginIsServerGeneratedAndBounded(t *testing.T) {
	now := time.Date(2026, 11, 5, 12, 0, 0, 0, time.UTC)
	d := touchdiagnostic.New("tip-discovery", "foreground-thread-mismatch")
	owner := yimebroker.TrustedClient{ID: "windows:fixture:session:1:logon:fixture:pid:4294967295:created:ffffffffffffffff"}
	got := touchdiagnostic.FromError(receivedDiscovery(d, owner, now), "unknown", "unknown")
	if got.Reported == nil || got.Reported.ReceivedMS != now.UnixMilli() || got.Reported.PID != ^uint32(0) || got.Reported.Created != ^uint64(0) || len(got.Reported.Event) != 32 {
		t.Fatal("server origin not retained")
	}
	var sink bytes.Buffer
	writeDesktopConnectionDiagnostic(&sink, got)
	if sink.Len() == 0 || sink.Len() > touchdiagnostic.MaxLine {
		t.Fatal("maximum identity does not fit record bound")
	}
	parsed, ok := touchdiagnostic.DecodeLine(bytes.TrimSpace(sink.Bytes()))
	if !ok || parsed.Reported == nil || *parsed.Reported != *got.Reported {
		t.Fatal("record origin lost")
	}
	for _, id := range []string{"", ":pid:1", ":pid:0:created:0000000000000001", ":pid:1:created:PRIVATE"} {
		bad := touchdiagnostic.FromError(receivedDiscovery(d, yimebroker.TrustedClient{ID: id}, now), "unknown", "unknown")
		if bad.Reported != nil || bad.Reason != "request-identity-unavailable" {
			t.Fatal("unverified identity reported")
		}
	}
}

func TestDesktopFirstFrameRejectsAmbiguousFieldsBeforePeerCreation(t *testing.T) {
	cases := []struct{ name, frame string }{
		{"same-operation", `{"operation":"next","operation":"next","window":1,"thread":2,"generation":1}`},
		{"duplicate-window", `{"operation":"next","window":1,"window":1,"thread":2,"generation":1}`},
		{"window-case-alias", `{"operation":"next","window":1,"WINDOW":1,"thread":2,"generation":1}`},
		{"window-case-alias-reversed", `{"operation":"next","WINDOW":1,"window":1,"thread":2,"generation":1}`},
		{"thread-case-alias", `{"operation":"next","window":1,"thread":2,"Thread":2,"generation":1}`},
		{"thread-case-alias-reversed", `{"operation":"next","window":1,"Thread":2,"thread":2,"generation":1}`},
		{"generation-case-alias", `{"operation":"next","window":1,"thread":2,"generation":1,"GENERATION":1}`},
		{"generation-case-alias-reversed", `{"operation":"next","window":1,"thread":2,"GENERATION":1,"generation":1}`},
	}
	for _, keys := range []struct{ name, first, last string }{
		{"identical", `"operation"`, `"operation"`},
		{"lower-title", `"operation"`, `"Operation"`},
		{"title-lower", `"Operation"`, `"operation"`},
		{"lower-upper", `"operation"`, `"OPERATION"`},
		{"upper-lower", `"OPERATION"`, `"operation"`},
		{"mixed-case", `"oPeRaTiOn"`, `"OpErAtIoN"`},
		{"escaped", `"oper\u0061tion"`, `"operation"`},
		{"escaped-reversed", `"operation"`, `"oper\u0061tion"`},
	} {
		for _, order := range []struct{ name, first, last string }{
			{"diagnostic-next", "diagnostic", "next"},
			{"next-diagnostic", "next", "diagnostic"},
		} {
			frame := "{" + keys.first + `:"` + order.first + `",` + keys.last + `:"` + order.last + `","window":1,"thread":2,"generation":1}`
			cases = append(cases, struct{ name, frame string }{keys.name + "/" + order.name, frame})
		}
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			foregroundCalls := 0
			relay := NewDesktopRelay(func(_ yimebroker.TrustedClient, window uint64, thread uint32) bool {
				foregroundCalls++
				return window == 71 && thread == 72
			}, nil)
			other, pending, queued := discoveryOtherConnection(relay)
			// A later valid poll must not be reached after the ambiguous first frame.
			in := &firstFrameReader{reader: strings.NewReader(tc.frame + "\n" + `{"operation":"next","window":1,"thread":2,"generation":1}` + "\n")}
			var output bytes.Buffer
			err := relay.serveTIP(context.Background(), in, &output, yimebroker.TrustedClient{ID: discoveryOfflineOwner})
			var diagnostic touchdiagnostic.Diagnostic
			if !errors.As(err, &diagnostic) || diagnostic.Stage != "broker-request" || diagnostic.Reason != "invalid-response" || diagnostic.Reported != nil {
				t.Fatal("ambiguous first frame did not stop as an invalid response", err)
			}
			// Final peer count alone would miss a transient peer removed by defer.
			if len(in.deadlines) != 1 || in.deadlines[0].IsZero() || foregroundCalls != 0 || output.Len() != 0 {
				t.Fatal("ambiguous first frame entered the ordinary protocol")
			}
			assertDiscoveryOtherConnection(t, relay, other, pending, queued)
		})
	}
}

func TestDesktopFirstFramePreservesOrdinaryPollAndCompletion(t *testing.T) {
	for _, tc := range []struct{ name, frame string }{
		{"canonical", `{"operation":"next","window":1,"thread":2,"generation":1}`},
		{"single-case-aliases", `{"Operation":"next","WINDOW":1,"ThReAd":2,"Generation":1}`},
		{"reordered-escaped", `{"generation":1,"\u0074hread":2,"window":1,"oper\u0061tion":"next"}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			owner := yimebroker.TrustedClient{ID: discoveryOfflineOwner}
			call := &desktopCall{
				ticket: "ordinary-ticket", lease: "ordinary-lease",
				request: DesktopRequest{Operation: "action", Action: json.RawMessage(`{"kind":"clear","revision":0}`)},
				result:  make(chan DesktopResponse, 1),
			}
			var relay *DesktopRelay
			var normal *tipPeer
			foregroundCalls := 0
			fixtureInvalid := false
			relay = NewDesktopRelay(func(client yimebroker.TrustedClient, window uint64, thread uint32) bool {
				foregroundCalls++
				if client.ID != owner.ID || window != 1 || thread != 2 {
					fixtureInvalid = true
					return false
				}
				if normal == nil {
					for p := range relay.peers {
						normal = p
					}
					if normal == nil || len(relay.peers) != 1 {
						fixtureInvalid = true
						return false
					}
					// Seed the action synchronously under the relay lock, without a
					// goroutine, sleep, or dependence on the ordinary poll timeout.
					normal.window, normal.thread, normal.generation, normal.lease = 1, 2, 1, call.lease
					normal.queue <- call
				}
				return true
			}, nil)
			in := &firstFrameReader{reader: strings.NewReader(tc.frame + "\n" + `{"operation":"complete","ticket":"ordinary-ticket","result":{"ok":true}}` + "\n")}
			var output bytes.Buffer
			if err := relay.serveTIP(context.Background(), in, &output, owner); err != nil {
				t.Fatal("ordinary poll/completion protocol rejected", err)
			}
			if fixtureInvalid || foregroundCalls != 3 || len(in.deadlines) != 2 || in.deadlines[0].IsZero() || !in.deadlines[1].IsZero() || normal == nil || !normal.closed || normal.pending != nil || len(normal.queue) != 0 || len(relay.peers) != 0 {
				t.Fatal("ordinary protocol lifecycle or first-frame deadline changed")
			}
			decoder := json.NewDecoder(&output)
			var poll, complete tipResponse
			if decoder.Decode(&poll) != nil || decoder.Decode(&complete) != nil || decoder.Decode(new(any)) != io.EOF {
				t.Fatal("ordinary protocol did not produce exactly two replies")
			}
			if !poll.OK || poll.Ticket != call.ticket || poll.Operation != "action" || string(poll.Action) != string(call.request.Action) || poll.Diagnostic != nil || !complete.OK || complete.Ticket != "" || complete.Diagnostic != nil {
				t.Fatal("ordinary action or completion acknowledgement changed")
			}
			select {
			case result := <-call.result:
				if !result.OK || result.Lease != call.lease || string(result.Result) != `{"ok":true}` || len(call.result) != 0 {
					t.Fatal("ordinary pending action lost its single successful receipt")
				}
			default:
				t.Fatal("ordinary completion did not deliver its receipt")
			}
		})
	}
}
