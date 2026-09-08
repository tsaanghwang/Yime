package main

import (
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

const supervisorHealthMaxAge = 2 * time.Second

// Only the supervisor loop refreshes this snapshot. The health handler cannot
// keep a stuck supervisor looking live by refreshing its own timestamp.
type supervisorHealth struct {
	mu       sync.RWMutex
	updated  time.Time
	snapshot yimebroker.HealthSnapshot
}

func (h *supervisorHealth) publish(pid uint32, creation uint64, now time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.updated = now
	h.snapshot = yimebroker.HealthSnapshot{State: yimebroker.HealthStateStarting}
	if pid != 0 && creation != 0 {
		h.snapshot = yimebroker.HealthSnapshot{State: yimebroker.HealthStateServing, BrokerPID: pid, BrokerCreationFiletime: creation}
	}
}

func (h *supervisorHealth) observe(broker *runtimeProcess) {
	pid, creation, err := broker.healthIdentity()
	if err != nil {
		h.publish(0, 0, time.Now())
		return
	}
	h.publish(pid, creation, time.Now())
}

func (h *supervisorHealth) snapshotAt(now time.Time) yimebroker.HealthSnapshot {
	h.mu.RLock()
	defer h.mu.RUnlock()
	age := now.Sub(h.updated)
	if h.updated.IsZero() || age < 0 || age > supervisorHealthMaxAge {
		return yimebroker.HealthSnapshot{State: yimebroker.HealthStateStarting}
	}
	return h.snapshot
}

func (h *supervisorHealth) snapshotNow() yimebroker.HealthSnapshot {
	return h.snapshotAt(time.Now())
}
