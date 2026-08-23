package main

import (
	"testing"
	"time"
)

func TestSummarizeAndLatencyGate(t *testing.T) {
	values := []time.Duration{time.Millisecond, 2 * time.Millisecond, 3 * time.Millisecond, 4 * time.Millisecond, 5 * time.Millisecond}
	got := summarize(values)
	if got.Samples != 5 || got.P50NS != int64(3*time.Millisecond) || got.P95NS != int64(5*time.Millisecond) || got.MaxNS != int64(5*time.Millisecond) {
		t.Fatalf("summary = %+v", got)
	}
	if !latencyPassed(got) {
		t.Fatalf("expected latency gate to pass: %+v", got)
	}
	got.MaxNS = int64(maximumSingle + time.Nanosecond)
	if latencyPassed(got) {
		t.Fatal("maximum latency gate did not reject an outlier")
	}
}
