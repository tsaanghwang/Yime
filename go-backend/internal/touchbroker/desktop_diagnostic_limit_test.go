package touchbroker

import (
	"context"
	"testing"
	"time"
)

func TestDesktopDiagnosticServerBudgetDoesNotResetOnReconnectOrClockRollback(t *testing.T) {
	var budget diagnosticBudget
	now := time.Date(2026, 11, 5, 0, 0, 0, 0, time.UTC)
	for i := 0; i < desktopDiagnosticLimit; i++ {
		if !budget.allow(now) {
			t.Fatal("budget rejected permitted event", i)
		}
	}
	for _, at := range []time.Time{now, now.Add(-time.Hour), now.Add(time.Minute - time.Nanosecond)} {
		if budget.allow(at) {
			t.Fatal("budget renewed before its interval")
		}
	}
	if !budget.allow(now.Add(time.Minute)) || budget.used != 1 {
		t.Fatal("budget did not renew at its boundary")
	}
}

type blockedDiagnosticWriter struct {
	entered  chan struct{}
	release  chan struct{}
	returned chan struct{}
}

func (w *blockedDiagnosticWriter) Write(p []byte) (int, error) {
	close(w.entered)
	<-w.release
	close(w.returned)
	return len(p), nil
}

func TestDesktopDiagnosticStalledSinkHasBoundedQueueAndNonblockingClose(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	out := &blockedDiagnosticWriter{make(chan struct{}), make(chan struct{}), make(chan struct{})}
	sink := newDesktopDiagnosticSink(ctx, out)
	defer close(out.release)
	sink.Write([]byte("{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\"}\n"))
	select {
	case <-out.entered:
	case <-time.After(3 * time.Second):
		t.Fatal("writer did not reach controlled barrier")
	}
	done := make(chan struct{})
	go func() {
		for i := 0; i < 1000; i++ {
			sink.Write([]byte("{}\n"))
		}
		cancel()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("diagnostic callback or shutdown blocked on stderr")
	}
	if len(sink.queue) > desktopDiagnosticLimit || sink.budget.used != desktopDiagnosticLimit {
		t.Fatal("unbounded diagnostic queue or event rate")
	}
	before := len(sink.queue)
	sink.Write([]byte("{}\n"))
	if len(sink.queue) != before {
		t.Fatal("closed sink accepted new events")
	}
}
