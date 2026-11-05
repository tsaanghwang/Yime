// Package touchdiagnostic carries content-free installed 18u failure metadata.
// It does not decide recovery, retry, lease validity, or whether an edit applied.
package touchdiagnostic

import (
	"encoding/json"
	"errors"
	"strconv"
)

type Diagnostic struct {
	Stage   string  `json:"stage"`
	Reason  string  `json:"reason"`
	Win32   *uint32 `json:"win32,omitempty"`
	HRESULT *uint32 `json:"hresult,omitempty"`
}

func New(stage, reason string) Diagnostic {
	return Sanitize(Diagnostic{Stage: stage, Reason: reason})
}

// FromError never formats arbitrary errors. Only this diagnostic type and an
// actual Windows syscall.Errno can supply metadata from an error chain.
func FromError(err error, stage, reason string) Diagnostic {
	var value Diagnostic
	if errors.As(err, &value) {
		return Sanitize(value)
	}
	var pointer *Diagnostic
	if errors.As(err, &pointer) && pointer != nil {
		return Sanitize(*pointer)
	}
	d := New(stage, reason)
	d.Win32 = win32FromError(err)
	return d
}

func Sanitize(d Diagnostic) Diagnostic {
	if !validStage(d.Stage) {
		d.Stage = "unknown"
	}
	if !validReason(d.Reason) {
		d.Reason = "unknown"
	}
	// Detach the metadata from caller-owned mutable pointers.
	if d.Win32 != nil {
		code := *d.Win32
		d.Win32 = &code
	}
	if d.HRESULT != nil {
		code := *d.HRESULT
		d.HRESULT = &code
	}
	return d
}

func (d Diagnostic) Error() string {
	d = Sanitize(d)
	s := d.Stage + "/" + d.Reason
	if d.Win32 != nil {
		s += " win32=" + strconv.FormatUint(uint64(*d.Win32), 10)
	}
	if d.HRESULT != nil {
		s += " hresult=0x" + strconv.FormatUint(uint64(*d.HRESULT), 16)
	}
	return s
}

// Even accidental serialization of an unsanitized value cannot copy input
// text, paths, candidate contents, or error messages into diagnostic fields.
func (d Diagnostic) MarshalJSON() ([]byte, error) {
	type wire Diagnostic
	return json.Marshal(wire(Sanitize(d)))
}

func validStage(stage string) bool {
	switch stage {
	case "diagnostic-storage", "unknown", "frontend-session", "tip-response", "frontend-wait", "tip-completion",
		"transport-connect", "transport-write", "transport-read", "transport-response",
		"broker-auth", "broker-request", "broker-select", "broker-queue", "broker-receipt", "broker-session", "broker-connection":
		return true
	}
	return false
}

func validReason(reason string) bool {
	switch reason {
	case "storage-close-pending", "storage-open-failed", "storage-write-failed", "storage-cleanup-failed", "unknown", "layout-mismatch", "stale-session", "invalid-response", "identity-mismatch",
		"snapshot-invalid", "lease-missing", "revision-mismatch", "operation-cancelled", "frontend-closed",
		"message-queue-unstable", "operation-pending", "operation-failed", "completion-rejected", "unsupported-host-edit",
		"cancellation-pending", "cancellation-failed", "broker-required", "pipe-name-invalid", "pipe-open-failed",
		"server-pid-query-failed", "server-image-query-failed", "connection-stopped", "request-encoding-failed",
		"request-too-large", "write-failed", "read-failed", "response-too-large", "frontend-not-authorized",
		"invalid-operation", "invalid-bind", "invalid-action-lease", "ambiguous-tip", "no-eligible-tip",
		"edit-pending", "request-identity-unavailable", "action-queued", "frontend-disconnected",
		"completion-unknown", "focus-revoked", "lease-revoked", "focus-changed", "stale-focus",
		"lease-identity-unavailable", "pending-action-mismatch", "invalid-poll", "previous-action-pending",
		"connection-closed", "sequence-mismatch":
		return true
	}
	return false
}
