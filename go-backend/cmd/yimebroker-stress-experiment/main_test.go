package main

import (
	"testing"
	"time"
)

func TestSummarizeAndLatencyGate(t *testing.T) {
	values := []time.Duration{time.Millisecond, 2 * time.Millisecond, 3 * time.Millisecond, 4 * time.Millisecond, 5 * time.Millisecond}
	histogram := newLatencyHistogram()
	for _, value := range values {
		histogram.add(value)
	}
	got := histogram.summary()
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

func TestLatencyHistogramMergeUsesBoundedStorage(t *testing.T) {
	left := newLatencyHistogram()
	right := newLatencyHistogram()
	for index := 0; index < 100000; index++ {
		left.add(time.Duration(index%1000) * time.Microsecond)
		right.add(time.Duration(index%2000) * time.Microsecond)
	}
	left.merge(right)
	if left.Samples != 200000 || len(left.Buckets) != latencyBucketCount {
		t.Fatalf("merged histogram = samples %d, buckets %d", left.Samples, len(left.Buckets))
	}
	if got := left.summary(); got.P99NS <= 0 || got.MaxNS != int64(1999*time.Microsecond) {
		t.Fatalf("merged summary = %+v", got)
	}
}
