package touchbroker

import "io"

// writeRejectionDiagnostic is best-effort only. No request fields or arbitrary
// error text enter this fixed vocabulary. Writer/Error panics and write failures
// must not replace the existing protocol response. A missing line is not proof
// that no rejection occurred. Synchronous stderr diagnostics may affect timing.
func writeRejectionDiagnostic(w io.Writer, stage string, cause error) {
	defer func() { _ = recover() }()
	label := "broker-rejected"
	switch stage {
	case "request":
		label = "broker-request-rejected"
	case "dispatch":
		label = "broker-dispatch-rejected"
	}
	reason := "unclassified"
	if cause != nil {
		switch cause.Error() {
		case "connection owner mismatch":
			reason = "connection-owner-mismatch"
		case "protocol/product/sequence mismatch":
			reason = "protocol-product-sequence-mismatch"
		case "invalid TIP focus lease":
			reason = "invalid-focus-lease"
		case "invalid open":
			reason = "invalid-open"
		case "dedicated runtime unavailable":
			reason = "runtime-unavailable"
		case "loaded resource identity mismatch":
			reason = "loaded-resource-identity-mismatch"
		case "session identity or lease mismatch":
			reason = "session-identity-or-lease-mismatch"
		case "session stopped; no replay":
			reason = "session-stopped"
		case "invalid action":
			reason = "invalid-action"
		case "action rejected":
			reason = "action-rejected"
		case "invalid completion":
			reason = "invalid-completion"
		case "completion rejected":
			reason = "completion-rejected"
		case "invalid termination":
			reason = "invalid-termination"
		case "unsupported dedicated operation":
			reason = "unsupported-operation"
		case "identity or focus mismatch":
			reason = "identity-or-focus-mismatch"
		case "host edit awaiting actual completion":
			reason = "host-edit-awaiting-completion"
		case "foreign session":
			reason = "foreign-session"
		case "stale revision":
			reason = "stale-revision"
		case "unsupported first-phase action":
			reason = "unsupported-first-phase-action"
		case "invalid engine response; no replay":
			reason = "invalid-engine-response"
		case "engine rejected action":
			reason = "engine-rejected-action"
		case "invalid engine revision; no replay":
			reason = "invalid-engine-revision"
		}
	}
	// Both strings above are code-owned constants; no escaping of user data is
	// necessary because none is included. One bounded write, never a retry.
	_, _ = w.Write([]byte("{\"stage\":\"" + label + "\",\"reason\":\"" + reason + "\"}\n"))
}
