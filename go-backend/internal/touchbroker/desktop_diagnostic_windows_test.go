//go:build windows

package touchbroker

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
)

type diagnosticPipe struct {
	writes int
	err    error
}

func (p *diagnosticPipe) Write(b []byte) (int, error) {
	p.writes++
	if p.err != nil {
		return 0, p.err
	}
	return len(b), nil
}
func (*diagnosticPipe) SetDeadline(time.Time) error { return nil }
func (*diagnosticPipe) Close() error                { return nil }

type diagnosticReader struct{ err error }

func (r diagnosticReader) Read([]byte) (int, error) { return 0, r.err }

func offlineDesktopClient(in io.Reader, p *diagnosticPipe) *DesktopClient {
	return &DesktopClient{file: p, reader: bufio.NewReaderSize(in, MaxFrame+1)}
}

func TestDesktopClientDiagnosticTransportFailureStopsWithoutRetry(t *testing.T) {
	for _, write := range []bool{true, false} {
		err := &os.PathError{Op: "private", Path: "正文/候选/private-path", Err: syscall.Errno(5)}
		pipe := &diagnosticPipe{}
		var input io.Reader = strings.NewReader("")
		stage, reason := "transport-read", "read-failed"
		if write {
			pipe.err = err
			stage, reason = "transport-write", "write-failed"
		} else {
			input = diagnosticReader{err}
		}
		c := offlineDesktopClient(input, pipe)
		_, got := c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
		d := touchdiagnostic.FromError(got, "unknown", "unknown")
		if d.Stage != stage || d.Reason != reason || d.Win32 == nil || *d.Win32 != 5 || !c.failed || pipe.writes != 1 {
			t.Fatal("transport failure metadata or stop behavior changed")
		}
		_, got = c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
		if got == nil || pipe.writes != 1 || c.sequence != 1 {
			t.Fatal("failed connection retried or advanced its sequence")
		}
	}
}

func TestDesktopClientDiagnosticPeerErrorsAreNeverEchoed(t *testing.T) {
	for _, body := range []string{
		`{"ok":false,"error":"正文/组码/候选/private-path"}`,
		`{"ok":false,"error":"private","diagnostic":{"stage":"private-input","reason":"private-candidate"}}`,
		`{"ok":false,"error":"private","diagnostic":{"stage":"broker-select","reason":"no-eligible-tip"}}`,
	} {
		pipe := &diagnosticPipe{}
		c := offlineDesktopClient(strings.NewReader(body+"\n"), pipe)
		out, err := c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
		if err == nil || out.Diagnostic == nil || strings.Contains(err.Error(), "private") || strings.Contains(out.Error, "private") || strings.Contains(out.Error, "正文") || pipe.writes != 1 {
			t.Fatal("peer error content leaked or request retried")
		}
		if out.Error != out.Diagnostic.Error() {
			t.Fatal("auxiliary error field was not sanitized")
		}
	}
}

func TestDesktopClientDiagnosticMalformedResponseStops(t *testing.T) {
	for _, body := range []string{
		`{"ok":false,"private-content":"候选"}`,
		`{"ok":false,"diagnostic":{"stage":"tip-completion","reason":"operation-failed","hresult":4294967296}}`,
		`{"ok":false,"diagnostic":{"stage":"tip-completion","reason":"operation-failed","hresult":"private"}}`,
	} {
		pipe := &diagnosticPipe{}
		c := offlineDesktopClient(strings.NewReader(body+"\n"), pipe)
		out, err := c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
		if err == nil || err.Error() != "transport-response/invalid-response" || !c.failed || out.Error != "" || out.Diagnostic != nil || pipe.writes != 1 {
			t.Fatal("malformed diagnostic was accepted or raw content returned")
		}
	}
}

func TestDesktopClientDiagnosticBoundedMissingResponse(t *testing.T) {
	for _, in := range []io.Reader{strings.NewReader(""), diagnosticReader{errors.New("private input failure")}, strings.NewReader(strings.Repeat("x", MaxFrame+1) + "\n")} {
		pipe := &diagnosticPipe{}
		c := offlineDesktopClient(in, pipe)
		_, err := c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
		if err == nil || strings.Contains(err.Error(), "private") || !c.failed || pipe.writes != 1 {
			t.Fatal("missing or oversized response did not stop safely")
		}
	}
}

func TestDesktopClientDiagnosticSuccessDoesNotExposePeerError(t *testing.T) {
	pipe := &diagnosticPipe{}
	c := offlineDesktopClient(strings.NewReader("{\"ok\":true,\"error\":\"private-input\",\"diagnostic\":{\"stage\":\"broker-request\",\"reason\":\"invalid-bind\"},\"lease\":\"lease\",\"result\":{\"ok\":true}}\n"), pipe)
	out, err := c.Call(DesktopRequest{Operation: "bind", Mode: "variable"})
	if err != nil || !out.OK || out.Error != "" || out.Diagnostic != nil || out.Lease != "lease" || c.failed || pipe.writes != 1 {
		t.Fatal("success envelope changed or retained peer error content")
	}
}

type connectionDiagnosticSink struct {
	bytes.Buffer
	writes int
	mode   string
}

func (s *connectionDiagnosticSink) Write(p []byte) (int, error) {
	s.writes++
	switch s.mode {
	case "panic":
		panic("private diagnostic sink error")
	case "error":
		return 0, errors.New("private diagnostic sink error")
	case "short":
		return len(p) - 1, nil
	}
	return s.Buffer.Write(p)
}

// Exercise the actual production connection handlers and callback wiring. This
// stub replaces only the OS listener; it never opens a pipe or starts a product.
type offlineDeadlineReader struct{ io.Reader }

func (offlineDeadlineReader) SetReadDeadline(time.Time) error { return nil }

func runDesktopHandlerOffline(t *testing.T, handler desktopHandler, owner yimebroker.TrustedClient, body string, diagnostic io.Writer) (error, []byte) {
	t.Helper()
	var protocol bytes.Buffer
	var original error
	listening, calls, reports := 0, 0, 0
	serve := func(ctx context.Context, cfg yimebroker.NamedPipeConfig, h desktopHandler) error {
		calls++
		if cfg.Name != "offline-only" || !cfg.RequireSameLogon || cfg.MaxConnections != 32 || cfg.MaxConnectionsPerClient != 8 || cfg.OnConnectionError == nil || cfg.OnListening == nil {
			t.Fatal("production pipe configuration or diagnostic hook missing")
		}
		cfg.OnListening()
		original = h(ctx, offlineDeadlineReader{strings.NewReader(body)}, &protocol, owner)
		if original != nil {
			reports++
			cfg.OnConnectionError(original)
		}
		return original
	}
	err := serveDesktopPipe(context.Background(), "offline-only", func() { listening++ }, handler, diagnostic, serve)
	if calls != 1 || listening != 1 || reports != 1 || err == nil || err != original {
		t.Fatal("connection error was replaced, retried, or not reported")
	}
	return err, protocol.Bytes()
}

func TestDesktopHandlerDiagnosticsReachConnectionCallback(t *testing.T) {
	for _, tc := range []struct {
		name, role, owner, input, stage, reason string
	}{
		{"ui-auth", "ui", "private-owner-pid", "private-input\n", "broker-auth", "frontend-not-authorized"},
		{"ui-sequence", "ui", "ui", "{\"sequence\":2,\"operation\":\"bind\",\"mode\":\"variable\",\"lease\":\"private-lease\"}\n", "broker-request", "sequence-mismatch"},
		{"ui-malformed", "ui", "ui", "{\"private-input\":\"正文候选\"}\n", "broker-request", "invalid-response"},
		{"tip-poll", "tip", "private-tip-owner", "{\"operation\":\"next\",\"generation\":1,\"ticket\":\"private-ticket\"}\n", "broker-request", "invalid-poll"},
		{"tip-complete", "tip", "private-tip-owner", "{\"operation\":\"complete\",\"ticket\":\"private-ticket\",\"result\":{\"private\":\"正文候选\"}}\n", "broker-receipt", "pending-action-mismatch"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			relay := NewDesktopRelay(func(yimebroker.TrustedClient, uint64, uint32) bool { return true }, func(c yimebroker.TrustedClient) bool { return c.ID == "ui" })
			handler := relay.serveUI
			if tc.role == "tip" {
				handler = relay.serveTIP
			}
			sink := &connectionDiagnosticSink{}
			err, protocol := runDesktopHandlerOffline(t, handler, yimebroker.TrustedClient{ID: tc.owner}, tc.input, sink)
			if len(protocol) != 0 || len(relay.peers) != 0 || sink.writes != 1 || sink.Len() > 256 || strings.Count(sink.String(), "\n") != 1 {
				t.Fatal("rejection wrote a response/retried or lost its peer cleanup")
			}
			var record map[string]json.RawMessage
			var d touchdiagnostic.Diagnostic
			if json.Unmarshal(sink.Bytes(), &record) != nil || json.Unmarshal(sink.Bytes(), &d) != nil || len(record) != 2 || d.Stage != tc.stage || d.Reason != tc.reason || err.Error() != d.Error() {
				t.Fatal("handler diagnostic did not reach the bounded callback")
			}
			if strings.Contains(sink.String(), "private") || strings.Contains(sink.String(), "正文") || strings.Contains(sink.String(), "候选") {
				t.Fatal("connection diagnostic included private request or owner data")
			}
		})
	}
}

func TestDesktopHandlerDiagnosticSinkFailureDoesNotChangeStop(t *testing.T) {
	for _, mode := range []string{"panic", "error", "short"} {
		relay := NewDesktopRelay(nil, func(yimebroker.TrustedClient) bool { return false })
		sink := &connectionDiagnosticSink{mode: mode}
		err, protocol := runDesktopHandlerOffline(t, relay.serveUI, yimebroker.TrustedClient{ID: "private-owner"}, "private-request\n", sink)
		if len(protocol) != 0 || err.Error() != "broker-auth/frontend-not-authorized" || sink.writes != 1 {
			t.Fatal("diagnostic sink failure changed connection failure or retried")
		}
	}
}

type panickingConnectionError struct{}

func (panickingConnectionError) Error() string { panic("private error text requested") }

func TestDesktopConnectionCallbackOnlyRecordsTypedCodes(t *testing.T) {
	for _, tc := range []struct {
		err   error
		win32 *uint32
	}{
		{err: &os.PathError{Op: "private-operation", Path: "private-path", Err: syscall.Errno(5)}, win32: func() *uint32 { v := uint32(5); return &v }()},
		{err: errors.New("reject named pipe client private-owner: connection quota exceeded")},
		{err: panickingConnectionError{}},
	} {
		sink := &connectionDiagnosticSink{}
		serve := func(_ context.Context, cfg yimebroker.NamedPipeConfig, _ desktopHandler) error {
			cfg.OnConnectionError(tc.err)
			return tc.err
		}
		err := serveDesktopPipe(context.Background(), "offline-only", nil, nil, sink, serve)
		var d touchdiagnostic.Diagnostic
		if err != tc.err || json.Unmarshal(sink.Bytes(), &d) != nil || d.Stage != "broker-connection" || d.Reason != "unknown" || sink.writes != 1 || strings.Contains(sink.String(), "private") {
			t.Fatal("connection callback altered the error or disclosed its text")
		}
		if (d.Win32 == nil) != (tc.win32 == nil) || d.Win32 != nil && *d.Win32 != *tc.win32 {
			t.Fatal("typed system error code lost or fabricated")
		}
	}
}
