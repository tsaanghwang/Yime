package yime

import "testing"

func TestMaintenanceReadinessRejectsUninitializedBackend(t *testing.T) {
	ime := &IME{}
	if ready, schema := ime.MaintenanceReadiness(); ready || schema != "" {
		t.Fatalf("uninitialized backend ready: %v %q", ready, schema)
	}
}
