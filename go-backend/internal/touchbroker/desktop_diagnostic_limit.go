package touchbroker

import (
	"context"
	"errors"
	"io"
	"sync"
	"time"
)

const desktopDiagnosticLimit = 64

var errDiagnosticDropped = errors.New("diagnostic discarded")

// Fixed storage and a fixed event budget, independent of adapter lifetimes and
// reconnects. Clock rollback never replenishes the budget early.
type diagnosticBudget struct {
	mu    sync.Mutex
	since time.Time
	used  int
}

func (b *diagnosticBudget) allow(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.since.IsZero() || now.Sub(b.since) >= time.Minute {
		b.since, b.used = now, 0
	}
	if b.used >= desktopDiagnosticLimit {
		return false
	}
	b.used++
	return true
}

// A stalled stderr reader cannot retain a connection callback. One worker and
// at most 64 bounded lines are owned by the Broker; shutdown does not join an
// uninterruptible writer. This is best-effort transport, not a save receipt.
type desktopDiagnosticSink struct {
	ctx    context.Context
	queue  chan []byte
	budget diagnosticBudget
}

func newDesktopDiagnosticSink(ctx context.Context, out io.Writer) *desktopDiagnosticSink {
	s := &desktopDiagnosticSink{ctx: ctx, queue: make(chan []byte, desktopDiagnosticLimit)}
	go func() {
		defer func() { _ = recover() }()
		for {
			select {
			case <-ctx.Done():
				return
			case line := <-s.queue:
				if ctx.Err() != nil {
					return
				}
				if n, err := out.Write(line); err != nil || n != len(line) {
					return
				}
			}
		}
	}()
	return s
}

func (s *desktopDiagnosticSink) Write(line []byte) (int, error) {
	if len(line) > 256 || s.ctx.Err() != nil || !s.budget.allow(time.Now()) {
		return len(line), nil
	}
	copyLine := append([]byte(nil), line...)
	select {
	case s.queue <- copyLine:
	default:
	}
	return len(line), nil
}
