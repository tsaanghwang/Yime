package main

import "testing"

func TestHealthFlagCannotClaimMainOrUnrelatedPipe(t *testing.T) {
	base := `\\.\pipe\YimeBroker-health-flags-test`
	for _, pair := range [][2]string{{base, base}, {base, base + ".other"}, {"", base + ".health-v1"}, {base, `\\remote\pipe\health`}, {base, base + ".runtime-health-v1"}} {
		if err := validateHealthPipe(pair[0], pair[1]); err == nil {
			t.Fatalf("unsafe endpoint override accepted: %q", pair)
		}
	}
	for _, pair := range [][2]string{{base, ""}, {"", ""}, {base, base + ".health-v1"}} {
		if err := validateHealthPipe(pair[0], pair[1]); err != nil {
			t.Fatalf("valid optional endpoint rejected: %q: %v", pair, err)
		}
	}
}
