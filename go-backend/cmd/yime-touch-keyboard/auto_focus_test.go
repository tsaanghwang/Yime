package main

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type focusTestSession struct {
	statuses, edits, closes atomic.Int32
	status                  func() error
	closed                  chan struct{}
	closeOnce               sync.Once
}

func (s *focusTestSession) Status() error {
	s.statuses.Add(1)
	if s.status != nil {
		return s.status()
	}
	return nil
}

func (s *focusTestSession) Edit(string, string, bool) error {
	s.edits.Add(1)
	return nil
}

func (s *focusTestSession) Close() error {
	s.closes.Add(1)
	if s.closed != nil {
		s.closeOnce.Do(func() { close(s.closed) })
	}
	return nil
}

func awaitFocusSignal(t *testing.T, signal <-chan struct{}) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatal("focus worker did not reach the expected checkpoint")
	}
}

func takeFocusProbe(t *testing.T, f *focusFollower) focusProbe {
	t.Helper()
	deadline := time.NewTimer(2 * time.Second)
	defer deadline.Stop()
	tick := time.NewTicker(time.Millisecond)
	defer tick.Stop()
	for {
		if result, ok := f.take(); ok {
			return result
		}
		select {
		case <-tick.C:
		case <-deadline.C:
			t.Fatal("focus worker result unavailable")
		}
	}
}

func TestFocusFollowerRejectsLateABABinding(t *testing.T) {
	target := hostTarget{1, 2, 3, 4}
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	releaseWorker := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseWorker()
	var calls atomic.Int32
	f := newFocusFollower(func(got hostTarget) (frontendSession, error) {
		if calls.Add(1) == 1 {
			close(entered)
		}
		<-release
		return &focusTestSession{}, nil
	})
	defer f.stop()
	if f.generation != 1 || cap(f.results) != 0 {
		t.Fatal("initial generation or unbuffered ownership handoff changed")
	}
	now := time.Unix(100, 0)
	if !f.start(now, target, nil) || f.lastAttempt != now {
		t.Fatal("initial discovery did not start")
	}
	awaitFocusSignal(t, entered)
	if _, ok := f.take(); ok || !f.pending {
		t.Fatal("empty take changed pending work")
	}
	f.revoke() // A -> B.
	f.revoke() // B -> A, with exactly the same HWND/PID/TID tuple.
	if !f.pending || !f.lastAttempt.IsZero() || f.start(now, target, nil) {
		t.Fatal("revocation released the single-worker gate")
	}
	releaseWorker()
	result := takeFocusProbe(t, f)
	if f.pending || result.err != nil || !result.binding || result.generation != 1 || f.matches(result, target) {
		t.Fatal("late original target was accepted after A-B-A")
	}
	_ = result.client.Close() // The reducer caller owns a delivered stale client.
	if !f.start(now.Add(time.Second), target, nil) {
		t.Fatal("fresh worker did not start after collecting the old one")
	}
	fresh := takeFocusProbe(t, f)
	defer fresh.client.Close()
	if !f.matches(fresh, target) || calls.Load() != 2 {
		t.Fatal("fresh generation did not recover independently")
	}
	if f.matches(fresh, hostTarget{1, 5, 3, 4}) {
		t.Fatal("different focus window accepted")
	}
}

func TestFocusFollowerStatusFailureIsReadOnlyAndSingleWorker(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	releaseWorker := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseWorker()
	want := errors.New("context changed")
	session := &focusTestSession{status: func() error { close(entered); <-release; return want }}
	var dials atomic.Int32
	f := newFocusFollower(func(hostTarget) (frontendSession, error) {
		dials.Add(1)
		return nil, errors.New("unexpected bind")
	})
	defer f.stop()
	target := hostTarget{1, 2, 3, 4}
	now := time.Unix(100, 0)
	if !f.start(now, target, session) {
		t.Fatal("status worker not started")
	}
	awaitFocusSignal(t, entered)
	if f.start(now.Add(time.Second), target, nil) || f.lastAttempt != now {
		t.Fatal("overlapping worker or rejected attempt modified state")
	}
	f.revoke()
	if !f.pending || f.generation != 2 {
		t.Fatal("only the window thread should change reducer state")
	}
	releaseWorker()
	result := takeFocusProbe(t, f)
	if result.binding || result.client != session || !errors.Is(result.err, want) || f.matches(result, target) {
		t.Fatal("stale status failure was rebound or accepted")
	}
	if dials.Load() != 0 || session.statuses.Load() != 1 || session.edits.Load() != 0 || session.closes.Load() != 0 {
		t.Fatal("read-only status worker mutated or disposed its existing session")
	}
	_ = session.Close()
}

func TestFocusFollowerStopDisposesUnpublishedBinding(t *testing.T) {
	entered, release := make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	releaseWorker := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseWorker()
	session := &focusTestSession{closed: make(chan struct{})}
	f := newFocusFollower(func(hostTarget) (frontendSession, error) {
		close(entered)
		<-release
		return session, nil
	})
	defer f.stop()
	target := hostTarget{1, 2, 3, 4}
	if !f.start(time.Now(), target, nil) {
		t.Fatal("binding not started")
	}
	awaitFocusSignal(t, entered)
	f.stop()
	f.stop()
	releaseWorker()
	awaitFocusSignal(t, session.closed)
	if session.closes.Load() != 1 || session.edits.Load() != 0 || !f.stopped || !f.pending {
		t.Fatal("stop did not preserve reducer ownership and dispose the new client once")
	}
	if f.start(time.Now(), target, nil) || f.matches(focusProbe{generation: f.generation, target: target}, target) {
		t.Fatal("stopped follower became active")
	}
}

func TestFocusFollowerStopLeavesExistingSessionWithOwner(t *testing.T) {
	entered, release, returned := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var releaseOnce sync.Once
	releaseWorker := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseWorker()
	session := &focusTestSession{status: func() error {
		close(entered)
		<-release
		close(returned)
		return nil
	}}
	f := newFocusFollower(nil)
	defer f.stop()
	if !f.start(time.Now(), hostTarget{1, 2, 3, 4}, session) {
		t.Fatal("status not started")
	}
	awaitFocusSignal(t, entered)
	f.stop()
	releaseWorker()
	awaitFocusSignal(t, returned)
	if session.closes.Load() != 0 || session.edits.Load() != 0 {
		t.Fatal("worker touched an owner-held session after stop")
	}
	_ = session.Close()
}

func TestFocusFollowerSuspensionAndOverflowNeverReactivate(t *testing.T) {
	f := newFocusFollower(nil)
	defer f.stop()
	target := hostTarget{1, 2, 3, 4}
	f.suspended = true
	if f.start(time.Now(), target, nil) || f.matches(focusProbe{generation: 1, target: target}, target) {
		t.Fatal("suspended follower accepted discovery")
	}
	f.revoke()
	if !f.suspended || f.pending || f.stopped {
		t.Fatal("revocation resumed a suspended follower")
	}
	f.generation = ^uint64(0)
	f.revoke()
	if !f.stopped || f.generation != ^uint64(0) {
		t.Fatal("generation wrapped instead of stopping")
	}
	awaitFocusSignal(t, f.done)
	f.suspended = false
	f.revoke()
	if f.start(time.Now(), target, nil) || !f.stopped {
		t.Fatal("revocation or resume reactivated an exhausted follower")
	}
}
