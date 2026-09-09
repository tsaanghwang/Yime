//go:build windows

package yime

// MaintenanceReadiness proves a native session can answer its current schema.
// It sends no keys, consumes no commit, and does not read composition/user text.
// The caller owns this dedicated client and must close it after observing ready.
func (ime *IME) MaintenanceReadiness() (bool, string) {
	b, ok := ime.backend.(*nativeBackend)
	if !ok || b == nil || !b.EnsureSession() {
		return false, ""
	}
	schema, ok := GetCurrentSchema(b.sessionID)
	if !ok || schema == "" || schema == ".default" {
		return false, ""
	}
	return true, schema
}
