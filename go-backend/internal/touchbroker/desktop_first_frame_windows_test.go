//go:build windows

package touchbroker

import (
	"bytes"
	"context"
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
