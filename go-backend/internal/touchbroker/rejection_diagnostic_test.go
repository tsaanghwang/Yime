package touchbroker

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"testing"
)

func TestDiagnosticKnownDispatchReasons(t *testing.T) {
	cases := map[string]string{
		"session stopped; no replay": "session-stopped",
		"identity or focus mismatch": "identity-or-focus-mismatch",
		"host edit awaiting actual completion": "host-edit-awaiting-completion",
		"foreign session": "foreign-session",
		"stale revision": "stale-revision",
		"unsupported first-phase action": "unsupported-first-phase-action",
		"invalid engine response; no replay": "invalid-engine-response",
		"engine rejected action": "engine-rejected-action",
		"invalid engine revision; no replay": "invalid-engine-revision",
	}
	for message, want := range cases {
		t.Run(want, func(t *testing.T) {
			var out bytes.Buffer
			writeRejectionDiagnostic(&out, "dispatch", errors.New(message))
			var record map[string]string
			if err := json.Unmarshal(out.Bytes(), &record); err != nil || len(record) != 2 || record["stage"] != "broker-dispatch-rejected" || record["reason"] != want {
				t.Fatalf("invalid classification: %q", out.String())
			}
		})
	}
}

func TestDiagnosticRequestBranches(t *testing.T) {
	for _, message := range []string{"connection owner mismatch", "protocol/product/sequence mismatch", "invalid TIP focus lease", "invalid open", "dedicated runtime unavailable", "loaded resource identity mismatch", "session identity or lease mismatch", "session stopped; no replay", "invalid action", "action rejected", "invalid completion", "completion rejected", "invalid termination", "unsupported dedicated operation"} {
		var out bytes.Buffer
		writeRejectionDiagnostic(&out, "request", errors.New(message))
		if !strings.Contains(out.String(), `"stage":"broker-request-rejected"`) || strings.Contains(out.String(), `"reason":"unclassified"`) {
			t.Fatalf("missing fixed request branch: %q", message)
		}
	}
}

func TestDiagnosticUnknownDataNeverCopied(t *testing.T) {
	secret := "private-input/path/token/候选正文\n\"injected\":true"
	for _, cause := range []error{errors.New(secret), errors.New("stale revision: " + secret), nil} {
		var out bytes.Buffer
		writeRejectionDiagnostic(&out, secret, cause)
		if out.String() != "{\"stage\":\"broker-rejected\",\"reason\":\"unclassified\"}\n" {
			t.Fatalf("untrusted data entered log: %q", out.String())
		}
	}
}

type faultyDiagnosticWriter struct { mode string; calls int }
func (w *faultyDiagnosticWriter) Write(p []byte) (int, error) {
	w.calls++
	switch w.mode {
	case "panic": panic("private writer failure")
	case "error": return 0, errors.New("private writer failure")
	default: return len(p)-1, nil
	}
}
type panickingDiagnosticError struct{}
func (panickingDiagnosticError) Error() string { panic("private error failure") }

func TestDiagnosticWriterFailuresDoNotEscapeOrRetry(t *testing.T) {
	for _, mode := range []string{"panic", "error", "short"} {
		w := &faultyDiagnosticWriter{mode: mode}
		writeRejectionDiagnostic(w, "dispatch", errors.New("stale revision"))
		if w.calls != 1 { t.Fatal("diagnostic retried") }
	}
	writeRejectionDiagnostic(nil, "dispatch", errors.New("stale revision"))
	var out bytes.Buffer
	writeRejectionDiagnostic(&out, "dispatch", panickingDiagnosticError{})
	if out.Len() != 0 { t.Fatal("panicking error emitted partial content") }
}

func TestDiagnosticSingleBoundedFrame(t *testing.T) {
	var out bytes.Buffer
	writeRejectionDiagnostic(&out, "dispatch", errors.New("host edit awaiting actual completion"))
	if out.Len() > 128 || strings.Count(out.String(), "\n") != 1 { t.Fatal("unbounded frame") }
	decoder := json.NewDecoder(&out)
	var value map[string]string
	if decoder.Decode(&value) != nil || decoder.Decode(&value) != io.EOF { t.Fatal("not exactly one frame") }
}
