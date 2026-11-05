package touchdiagnostic

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

type privateError struct{}

func (privateError) Error() string { panic("arbitrary error text must never be requested") }

type wrappedError struct{ cause error }

func (wrappedError) Error() string   { return "private path and input" }
func (e wrappedError) Unwrap() error { return e.cause }

func TestDiagnosticNeverCopiesUnknownContent(t *testing.T) {
	secret := "正文/组码/候选/secret-path\n\"injected\":true"
	for _, err := range []error{errors.New(secret), privateError{}, nil} {
		d := FromError(err, secret, secret)
		if d.Error() != "unknown/unknown" {
			t.Fatal("arbitrary error or classification entered diagnostic")
		}
		b, e := json.Marshal(d)
		if e != nil || string(b) != `{"stage":"unknown","reason":"unknown"}` {
			t.Fatal("unsafe diagnostic serialization")
		}
	}
	// Public fields are sanitized even if a caller forgets to use New.
	b, _ := json.Marshal(Diagnostic{Stage: secret, Reason: secret})
	if strings.Contains(string(b), secret) || string(b) != `{"stage":"unknown","reason":"unknown"}` {
		t.Fatal("directly constructed diagnostic leaked content")
	}
}

func TestDiagnosticPreservesTypedMetadataAndDetachesPointers(t *testing.T) {
	hr := uint32(0x80004005)
	d := Diagnostic{Stage: "tip-completion", Reason: "operation-failed", HRESULT: &hr}
	for _, err := range []error{wrappedError{d}, wrappedError{&d}} {
		got := FromError(err, "frontend-session", "unknown")
		if got.Stage != "tip-completion" || got.Reason != "operation-failed" || got.HRESULT == nil || *got.HRESULT != 0x80004005 {
			t.Fatal("typed origin or unsigned HRESULT was lost")
		}
		*got.HRESULT = 7
		if hr != 0x80004005 {
			t.Fatal("diagnostic retained caller-owned mutable code")
		}
	}
	if d.Error() != "tip-completion/operation-failed hresult=0x80004005" {
		t.Fatal("HRESULT was not formatted as unsigned numeric metadata")
	}
}

func TestDiagnosticAllFrontendAndNativeVocabulary(t *testing.T) {
	for _, stage := range []string{"frontend-session", "tip-response", "frontend-wait", "tip-completion"} {
		for _, reason := range []string{"layout-mismatch", "stale-session", "invalid-response", "identity-mismatch", "snapshot-invalid", "lease-missing", "revision-mismatch", "operation-cancelled", "frontend-closed", "message-queue-unstable", "operation-pending", "unknown", "operation-failed", "completion-rejected", "cancellation-pending", "cancellation-failed", "unsupported-host-edit"} {
			if d := New(stage, reason); d.Stage != stage || d.Reason != reason {
				t.Fatal("documented caller vocabulary was dropped")
			}
		}
	}
}

func TestDiagnosticNumericMetadataSurvivesJSON(t *testing.T) {
	w, hr := uint32(5), uint32(0xffffffff)
	d := Diagnostic{Stage: "tip-completion", Reason: "cancellation-failed", Win32: &w, HRESULT: &hr}
	b, err := json.Marshal(d)
	var got Diagnostic
	if err != nil || json.Unmarshal(b, &got) != nil || got.Win32 == nil || *got.Win32 != w || got.HRESULT == nil || *got.HRESULT != hr {
		t.Fatal("numeric metadata did not survive the wire")
	}
	var fields map[string]json.RawMessage
	if json.Unmarshal(b, &fields) != nil || len(fields) != 4 {
		t.Fatal("unexpected diagnostic fields")
	}
}
