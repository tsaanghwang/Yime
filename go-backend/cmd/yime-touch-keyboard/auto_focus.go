package main

import (
	"errors"
	"time"
)

type frontendSession interface {
	Status() error
	Edit(text, key string, extend bool) error
	Close() error
}

type focusProbe struct {
	generation uint64
	target     hostTarget
	client     frontendSession
	binding    bool
	err        error
}

// The window thread alone owns this state. Workers receive immutable inputs and
// return one observation; they cannot bind a target or change the input session.
type focusFollower struct {
	generation                  uint64
	pending, suspended, stopped bool
	lastAttempt                 time.Time
	results                     chan focusProbe
	done                        chan struct{}
	dial                        func(hostTarget) (frontendSession, error)
}

func newFocusFollower(dial func(hostTarget) (frontendSession, error)) *focusFollower {
	return &focusFollower{
		generation: 1,
		results:    make(chan focusProbe),
		done:       make(chan struct{}),
		dial:       dial,
	}
}

func (f *focusFollower) start(now time.Time, target hostTarget, existing frontendSession) bool {
	if f.pending || f.stopped || f.suspended {
		return false
	}
	f.pending, f.lastAttempt = true, now
	probe := focusProbe{generation: f.generation, target: target, client: existing, binding: existing == nil}
	dial, results, done := f.dial, f.results, f.done
	go func() {
		if probe.binding {
			if dial == nil {
				probe.err = errors.New("missing focus endpoint dialer")
			} else {
				probe.client, probe.err = dial(probe.target)
			}
		} else {
			probe.err = probe.client.Status()
		}
		select {
		case results <- probe:
		case <-done:
			// An existing session belongs to the window thread. Only an
			// unpublished connection created by this worker needs disposal.
			if probe.binding && probe.client != nil {
				_ = probe.client.Close()
			}
		}
	}()
	return true
}

func (f *focusFollower) take() (focusProbe, bool) {
	select {
	case result := <-f.results:
		f.pending = false
		return result, true
	default:
		return focusProbe{}, false
	}
}

func (f *focusFollower) matches(result focusProbe, current hostTarget) bool {
	return !f.stopped && !f.suspended && result.generation == f.generation && result.target == current
}

func (f *focusFollower) revoke() {
	f.lastAttempt = time.Time{}
	if f.generation == ^uint64(0) {
		f.stop()
		return
	}
	f.generation++
	// Keep pending until the outstanding worker is collected. Otherwise a
	// rapid A-B-A focus transition could create overlapping pipe exchanges.
}

func (f *focusFollower) stop() {
	if f.stopped {
		return
	}
	f.stopped = true
	close(f.done)
	f.revoke()
}
