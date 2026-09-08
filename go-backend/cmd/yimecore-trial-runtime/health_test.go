package main

import (
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

func TestSupervisorHealthExpiresAndClearsOldChild(t *testing.T) {
	h := &supervisorHealth{}
	now := time.Now()
	assertEmpty := func(at time.Time) {
		t.Helper()
		got := h.snapshotAt(at)
		if got.State != yimebroker.HealthStateStarting || got.BrokerPID != 0 || got.BrokerCreationFiletime != 0 {
			t.Fatalf("stale or partial child reported serving: %+v", got)
		}
	}
	assertEmpty(now)
	h.publish(101, 133000000000000000, now)
	for _, at := range []time.Time{now, now.Add(time.Second), now.Add(supervisorHealthMaxAge)} {
		got := h.snapshotAt(at)
		if got.State != yimebroker.HealthStateServing || got.BrokerPID != 101 || got.BrokerCreationFiletime != 133000000000000000 {
			t.Fatalf("fresh supervisor lost held identity: %+v", got)
		}
	}
	assertEmpty(now.Add(supervisorHealthMaxAge + time.Nanosecond))
	assertEmpty(now.Add(-time.Nanosecond))
	// Reads did not refresh the supervisor timestamp or resurrect the stale PID.
	assertEmpty(now.Add(3 * time.Second))
	h.publish(0, 0, now.Add(4*time.Second))
	assertEmpty(now.Add(4 * time.Second))
	h.publish(202, 133000000000000001, now.Add(5*time.Second))
	if got := h.snapshotAt(now.Add(5 * time.Second)); got.BrokerPID != 202 || got.BrokerCreationFiletime != 133000000000000001 {
		t.Fatalf("restart retained former identity: %+v", got)
	}
	for _, partial := range [][2]uint64{{0, 42}, {42, 0}} {
		h.publish(uint32(partial[0]), partial[1], now)
		assertEmpty(now)
	}
}

func TestRuntimeResolvedOptionsBindSeparateBrokerHealthPipe(t *testing.T) {
	base := `\\.\pipe\YimeBroker-health-runtime-test`
	health, err := yimebroker.HealthPipeName(base, yimebroker.HealthRoleBroker)
	if err != nil {
		t.Fatal(err)
	}
	config := options{installRoot: t.TempDir(), stateRoot: t.TempDir(), pipeName: base, healthPipe: health}
	args := brokerArguments(config)
	count := 0
	for i := 0; i+1 < len(args); i++ {
		if args[i] == "-health-pipe" {
			count++
			if args[i+1] != base+".health-v1" {
				t.Fatalf("unexpected health target: %q", args[i+1])
			}
		}
	}
	if count != 1 {
		t.Fatalf("expected one health endpoint argument, got %d", count)
	}
}
