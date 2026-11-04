//go:build windows && (amd64 || arm64)

package main

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"testing"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// These fixtures use fake targets/transports and the small in-memory engine.
// The message-pump cases additionally own an invisible STATIC window. No case
// activates a TIP, takes foreground focus or reads/writes a host document.
type autoUITestSession struct {
	mu                      sync.Mutex
	statusErr, editErr      error
	statuses, edits, closes int
	texts                   []string
}

func (s *autoUITestSession) Status() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.statuses++
	return s.statusErr
}
func (s *autoUITestSession) Edit(text, key string, extend bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.edits++
	s.texts = append(s.texts, text)
	return s.editErr
}
func (s *autoUITestSession) Close() error { s.mu.Lock(); defer s.mu.Unlock(); s.closes++; return nil }
func (s *autoUITestSession) counts() (int, int, int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.statuses, s.edits, s.closes
}
func (s *autoUITestSession) failStatus(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.statusErr = err
}

func autoUIFixture(t *testing.T, dial func(hostTarget) (frontendSession, error)) (*ui, *hostTarget) {
	t.Helper()
	a := previewUI(t)
	a.o.Host = true
	a.o.InstalledTSF = true
	a.initHost()
	a.follow = newFocusFollower(dial)
	current := &hostTarget{Window: 11, Focus: 12, Process: 13, Thread: 14}
	a.host.current = func() hostTarget { return *current }
	a.host.send = func(_ hostTarget, o tk.Output) error {
		text, key, extend, err := tsfEdit(o)
		if err != nil {
			return err
		}
		if a.tsf == nil {
			return errors.New("missing test session")
		}
		return a.tsf.Edit(text, key, extend)
	}
	t.Cleanup(a.stopAutoFocus)
	return a, current
}
func settleAutoUI(t *testing.T, a *ui, now time.Time, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		a.pollAutoFocus(now)
		if condition() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("automatic focus fixture did not settle")
}
func TestAutoFocusDiscoversWithoutButtonAndStatusKeepsComposition(t *testing.T) {
	s := &autoUITestSession{}
	a, _ := autoUIFixture(t, func(hostTarget) (frontendSession, error) { return s, nil })
	old := a.preview
	now := time.Now()
	settleAutoUI(t, a, now, func() bool { return a.tsf == s })
	if a.preview == old || !a.host.valid(a.host.ticket()) {
		t.Fatal("no fresh verified session")
	}
	previewAction(t, a.preview, "input", "a", "")
	stamp := a.preview.stamp()
	raw := a.preview.snapshot.State.RawInput
	a.pollAutoFocus(now.Add(400 * time.Millisecond))
	settleAutoUI(t, a, now.Add(400*time.Millisecond), func() bool { return !a.follow.pending })
	statuses, edits, _ := s.counts()
	if statuses != 1 || edits != 0 || a.preview.stamp() != stamp || a.preview.snapshot.State.RawInput != raw {
		t.Fatal("read-only poll changed composition, rebound, or edited")
	}
}
func TestAutoFocusSameWindowContextChangeCancelsCandidateBeforeEdit(t *testing.T) {
	first, second := &autoUITestSession{}, &autoUITestSession{}
	next := frontendSession(first)
	a, _ := autoUIFixture(t, func(hostTarget) (frontendSession, error) { return next, nil })
	now := time.Now()
	settleAutoUI(t, a, now, func() bool { return a.tsf == first })
	previewAction(t, a.preview, "input", "a", "")
	oldTicket := a.host.ticket()
	r := a.candidateRect(0)
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(1, x, y)
	first.failStatus(errors.New("context generation changed"))
	a.up(1, x, y)
	_, edits, _ := first.counts()
	if edits != 0 || a.tsf != nil || a.host.valid(oldTicket) || a.host.blocked || a.preview.snapshot.State.RawInput != "" {
		t.Fatal("stale context action was sent, retained, or mistaken for unknown mutation")
	}
	next = second
	settleAutoUI(t, a, now.Add(2*time.Second), func() bool { return a.tsf == second })
	a.up(1, x, y)
	_, edits, _ = second.counts()
	if edits != 0 || a.preview.snapshot.State.RawInput != "" {
		t.Fatal("old candidate migrated to new lease")
	}
}
func TestAutoFocusTargetSwitchCancelsOldDownAndRequiresNewGesture(t *testing.T) {
	first, second := &autoUITestSession{}, &autoUITestSession{}
	next := frontendSession(first)
	a, current := autoUIFixture(t, func(hostTarget) (frontendSession, error) { return next, nil })
	now := time.Now()
	settleAutoUI(t, a, now, func() bool { return a.tsf == first })
	previewAction(t, a.preview, "input", "a", "")
	r := a.candidateRect(0)
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(9, x, y)
	*current = hostTarget{21, 22, 23, 24}
	a.autoFocusChanged()
	next = second
	settleAutoUI(t, a, now.Add(2*time.Second), func() bool { return a.tsf == second })
	a.up(9, x, y)
	_, one, _ := first.counts()
	_, two, _ := second.counts()
	if one != 0 || two != 0 {
		t.Fatal("old UP was delivered after target switch")
	}
	previewAction(t, a.preview, "input", "a", "")
	a.down(10, x, y)
	a.up(10, x, y)
	a.up(10, x, y)
	_, two, _ = second.counts()
	if two != 1 {
		t.Fatal("new action did not commit exactly once")
	}
}
func TestAutoFocusUnknownSurvivesSwitchSuspendAndAutomaticDiscovery(t *testing.T) {
	first := &autoUITestSession{editErr: errors.New("written but receipt lost")}
	second := &autoUITestSession{}
	next := frontendSession(first)
	dials := 0
	a, current := autoUIFixture(t, func(hostTarget) (frontendSession, error) { dials++; return next, nil })
	now := time.Now()
	settleAutoUI(t, a, now, func() bool { return a.tsf == first })
	previewAction(t, a.preview, "input", "a", "")
	r := a.candidateRect(0)
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(1, x, y)
	a.up(1, x, y)
	_, edits, _ := first.counts()
	if edits != 1 || !a.host.blocked {
		t.Fatal("unknown edit did not latch review")
	}
	*current = hostTarget{31, 32, 33, 34}
	a.autoFocusChanged()
	a.suspendForMinimize()
	a.pollAutoFocus(now.Add(2 * time.Second))
	a.autoMinimized = false
	a.touchHelpOpen = true
	a.pollAutoFocus(now.Add(3 * time.Second))
	a.touchHelpOpen = false
	a.pollAutoFocus(now.Add(4 * time.Second))
	if !a.host.blocked || a.tsf != nil || dials != 1 {
		t.Fatal("automatic transition unlocked or reconnected unknown edit")
	}
	if err := a.host.bindAutomatic(*current); err == nil {
		t.Fatal("automatic bind cleared review")
	}
	next = second
	if err := a.bindHost(); err != nil {
		t.Fatal(err)
	} // Explicit user acknowledgement only.
	settleAutoUI(t, a, now.Add(5*time.Second), func() bool { return a.tsf == second })
	a.up(1, x, y)
	_, edits, _ = second.counts()
	if edits != 0 || a.host.blocked || a.preview.snapshot.State.RawInput != "" {
		t.Fatal("acknowledgement replayed or restored old composition")
	}
}

func TestAutoFocusSettingsModeChoiceSurvivesPausedSession(t *testing.T) {
	for _, locked := range []bool{false, true} {
		for _, mode := range []string{"full", "shorthand", "variable"} {
			t.Run(fmt.Sprintf("locked=%t/%s", locked, mode), func(t *testing.T) {
				first, second := &autoUITestSession{}, &autoUITestSession{}
				if locked {
					first.editErr = errors.New("written but receipt lost")
				}
				next := frontendSession(first)
				dials := 0
				a, _ := autoUIFixture(t, func(hostTarget) (frontendSession, error) { dials++; return next, nil })
				board, err := touchScreenBoard(a.s.Board)
				if err != nil {
					t.Fatal(err)
				}
				a.o.TouchUI = true
				a.top = a.touchHeaderLayout().height
				a.s = tk.NewState(board)
				a.s.Semantic, a.s.Original = true, true
				now := time.Now()
				settleAutoUI(t, a, now, func() bool { return a.tsf == first })
				previewAction(t, a.preview, "input", "a", "")
				old := a.preview
				candidate := a.candidateRect(0)
				x, y := (candidate.L+candidate.R)/2, (candidate.T+candidate.B)/2
				if locked {
					a.down(71, x, y)
					a.up(71, x, y)
					if !a.host.blocked {
						t.Fatal("fixture did not establish unknown-result lock")
					}
				}
				tapTouchControl(t, a, "settings")
				a.pollAutoFocus(now.Add(time.Second))
				if !a.touchSettingsOpen || !old.fault || a.tsf != nil || a.host.blocked != locked {
					t.Fatal("settings did not suspend the old session safely")
				}
				oldStamp := old.stamp()
				// Exercise actual settings gestures, including returning to the
				// default after another selection, without reviving the old session.
				for _, selected := range []string{"full", "shorthand", mode} {
					tapTouchSetting(t, a, selected)
					if a.touchMessage != "" || a.previewMode() != selected || !a.touchSettingsOpen || !old.fault || a.preview != old || old.stamp() != oldStamp || a.tsf != nil || a.host.blocked != locked {
						t.Fatalf("local mode selection failed or revived paused input: %s: %s", selected, a.touchMessage)
					}
					if locked && a.status != autoFocusReviewMessage {
						t.Fatal("local preference hid the unresolved edit warning")
					}
				}
				a.pollAutoFocus(now.Add(2 * time.Second))
				if dials != 1 || a.preview.snapshot.State.RawInput != "" {
					t.Fatal("settings selection reconnected or restored cancelled composition")
				}
				next = second
				tapTouchControl(t, a, "settings")
				if locked {
					a.pollAutoFocus(now.Add(3 * time.Second))
					if !a.host.blocked || a.tsf != nil || dials != 1 {
						t.Fatal("mode preference cleared unknown-result lock")
					}
					tapTouchControl(t, a, "reset") // Explicit review acknowledgement.
				}
				settleAutoUI(t, a, now.Add(4*time.Second), func() bool { return a.tsf == second })
				if a.preview == old || a.preview.mode != mode || a.preview.fault || a.preview.snapshot.State.RawInput != "" || a.host.blocked {
					t.Fatal("new clean connection did not apply the selected mode")
				}
				a.up(71, x, y)
				_, oldEdits, _ := first.counts()
				_, newEdits, _ := second.counts()
				wantOldEdits := 0
				if locked {
					wantOldEdits = 1
				}
				if oldEdits != wantOldEdits || newEdits != 0 {
					t.Fatal("mode settings edited or replayed a cancelled/unknown commit")
				}
				previewAction(t, a.preview, "input", "a", "")
				a.down(72, x, y)
				a.up(72, x, y)
				_, newEdits, _ = second.counts()
				if newEdits != 1 {
					t.Fatal("selected mode did not accept a fresh action after recovery")
				}
			})
		}
	}
}

func TestAutoFocusUnavailableDiscoveryIsBoundedAndDoesNotLatchUnknown(t *testing.T) {
	dials := 0
	a, _ := autoUIFixture(t, func(hostTarget) (frontendSession, error) { dials++; return nil, errors.New("profile unavailable") })
	now := time.Now()
	a.pollAutoFocus(now)
	settleAutoUI(t, a, now, func() bool { return !a.follow.pending })
	for i := 0; i < 10; i++ {
		a.pollAutoFocus(now.Add(900 * time.Millisecond))
	}
	if dials != 1 || a.host.blocked || a.tsf != nil {
		t.Fatal("unbounded bind retries or false unknown edit")
	}
	a.pollAutoFocus(now.Add(time.Second))
	settleAutoUI(t, a, now.Add(time.Second), func() bool { return !a.follow.pending })
	if dials != 2 {
		t.Fatal("non-mutating discovery never recovered")
	}
}
func TestAutoFocusSuspensionDiscardsPendingBinding(t *testing.T) {
	s := &autoUITestSession{}
	release := make(chan struct{})
	a, _ := autoUIFixture(t, func(hostTarget) (frontendSession, error) { <-release; return s, nil })
	now := time.Now()
	a.pollAutoFocus(now)
	a.touchHelpOpen = true
	a.pollAutoFocus(now)
	close(release)
	settleAutoUI(t, a, now, func() bool { return !a.follow.pending })
	if a.tsf != nil || a.host.target != (hostTarget{}) {
		t.Fatal("binding activated behind help")
	}
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		_, _, closed := s.counts()
		if closed > 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("discarded connection was not closed")
}

type autoUIDelayedSession struct {
	*autoUITestSession
	wait func()
}

func (s *autoUIDelayedSession) Status() error {
	err := s.autoUITestSession.Status()
	s.wait()
	return err
}

// This reuses the invisible, unshown message-only fixture pattern. All targets
// and transports remain fake, and cleanup runs before releasing the UI thread.
func autoUIMessageFixture(t *testing.T, first, next frontendSession) (*ui, uintptr) {
	t.Helper()
	runtime.LockOSThread()
	t.Cleanup(runtime.UnlockOSThread)
	a, h, _ := navigationHostFixture(t)
	a.o.Host, a.o.InstalledTSF = true, true
	a.follow = newFocusFollower(func(hostTarget) (frontendSession, error) { return next, nil })
	a.tsf = first
	a.host.send = func(_ hostTarget, o tk.Output) error {
		text, key, extend, err := tsfEdit(o)
		if err != nil {
			return err
		}
		if a.tsf == nil {
			return errors.New("missing test session")
		}
		return a.tsf.Edit(text, key, extend)
	}
	a.hostSink(a.host.ticket(), a.cancelGeneration)
	t.Cleanup(a.stopAutoFocus)
	return a, h
}

func removeAutoUIQuit() (uintptr, bool) {
	var m message
	ok, _, _ := U("PeekMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0x0012, 0x0012, 1)
	return m.W, ok != 0
}

func TestAutoFocusSlowStatusPumpsCancellationWithoutEditing(t *testing.T) {
	for _, kind := range []string{"minimize", "cancel", "quit"} {
		t.Run(kind, func(t *testing.T) {
			release, completed := make(chan struct{}), make(chan struct{})
			var releaseOnce sync.Once
			unblock := func() { releaseOnce.Do(func() { close(release) }) }
			defer unblock()
			first := &autoUIDelayedSession{autoUITestSession: &autoUITestSession{}}
			second := &autoUITestSession{}
			a, h := autoUIMessageFixture(t, first, second)
			if kind == "quit" {
				t.Cleanup(func() { removeAutoUIQuit() })
			}
			thread, _, _ := k32.NewProc("GetCurrentThreadId").Call()
			posted := make(chan error, 1)
			first.wait = func() {
				// This notification is queued only after the per-action Status
				// starts, so the initial UP message drain cannot consume it.
				ok, _, err := U("PostMessageW").Call(h, 0x0113, autoFocusTimer, 0)
				if ok != 0 {
					switch kind {
					case "minimize":
						ok, _, err = U("PostMessageW").Call(h, 0x0005, 1, 0)
					case "cancel":
						ok, _, err = U("PostMessageW").Call(h, 0x001F, 0, 0)
					case "quit":
						ok, _, err = U("PostThreadMessageW").Call(thread, 0x0012, 73, 0)
					}
				}
				if ok == 0 {
					posted <- fmt.Errorf("queue %s during Status: %v", kind, err)
				} else {
					posted <- nil
				}
				<-release
				close(completed)
			}
			previewAction(t, a.preview, "input", "a", "")
			r := a.candidateRect(0)
			x, y := (r.L+r.R)/2, (r.T+r.B)/2
			a.down(51, x, y)
			old := a.host.ticket()
			// A regression to blocking Status must fail promptly, without
			// waiting for the production five-second timeout or leaking work.
			watchdog := time.AfterFunc(1500*time.Millisecond, unblock)
			defer watchdog.Stop()
			started := time.Now()
			a.up(51, x, y)
			elapsed := time.Since(started)
			if !watchdog.Stop() || elapsed >= time.Second {
				t.Fatalf("%s waited for the slow Status instead of pumping messages: %s", kind, elapsed)
			}
			select {
			case err := <-posted:
				if err != nil {
					t.Fatal(err)
				}
			default:
				t.Fatal("action returned without reaching the controlled Status")
			}
			select {
			case <-completed:
				t.Fatal("Status finished before cancellation; responsiveness was not exercised")
			default:
			}
			statuses, edits, _ := first.counts()
			if statuses != 1 || edits != 0 || a.host.blocked || a.host.valid(old) || a.tsf != nil || a.hostBusy || len(a.previewTouches) != 0 || a.preview.snapshot.State.RawInput != "" {
				t.Fatal("read-only cancellation edited, retained old state, or latched unknown")
			}
			if kind == "quit" {
				if code, ok := removeAutoUIQuit(); !ok || code != 73 {
					t.Fatal("status wait swallowed or changed WM_QUIT")
				}
			}
			unblock()
			awaitFocusSignal(t, completed)
			if kind == "minimize" {
				if !a.autoMinimized {
					t.Fatal("queued minimize was not processed")
				}
				windowProc(h, 0x0005, 0, 0) // Restore state without showing the fixture.
			}
			// Continue in memory after the controlled message has been observed.
			// The quit case consumes its synthetic sentinel before this step.
			a.h = 0
			settleAutoUI(t, a, time.Now().Add(2*time.Second), func() bool { return a.tsf == second })
			a.up(51, x, y)
			_, edits, _ = second.counts()
			if edits != 0 || a.host.blocked || a.preview.snapshot.State.RawInput != "" {
				t.Fatal("normal recovery replayed the cancelled candidate")
			}
			previewAction(t, a.preview, "input", "a", "")
			a.down(52, x, y)
			a.up(52, x, y)
			_, edits, _ = second.counts()
			if edits != 1 {
				t.Fatal("new gesture did not recover after read-only cancellation")
			}
		})
	}
}

type autoUICommitHook struct {
	previewSessions
	afterCommit func()
}

func (s autoUICommitHook) Dispatch(e keyboardlab.Event) keyboardlab.Reply {
	reply := s.previewSessions.Dispatch(e)
	if response, err := reply.Decode(); err == nil && response.Commit != "" {
		s.afterCommit()
	}
	return reply
}

func TestAutoFocusPreSendCancellationFaultRecoversWithoutReview(t *testing.T) {
	first, second := &autoUITestSession{}, &autoUITestSession{}
	a, h := autoUIMessageFixture(t, first, second)
	queued := false
	a.preview.sessions = autoUICommitHook{previewSessions: a.preview.sessions, afterCommit: func() {
		if queued {
			return
		}
		queued = true
		// The engine has produced its one-shot commit, but hostSink has not
		// yet reached deliveryGate.send. Exercise that exact cancellation gap.
		if ok, _, err := U("PostMessageW").Call(h, 0x001F, 0, 0); ok == 0 {
			t.Fatalf("queue pre-send cancellation: %v", err)
		}
	}}
	previewAction(t, a.preview, "input", "a", "")
	old := a.preview
	r := a.candidateRect(0)
	x, y := (r.L+r.R)/2, (r.T+r.B)/2
	a.down(61, x, y)
	a.up(61, x, y)
	statuses, edits, _ := first.counts()
	if !queued || statuses != 1 || edits != 0 || !old.fault || a.host.blocked || a.tsf != nil || old.snapshot.Commit != "" {
		t.Fatal("pre-send cancellation was treated as an attempted or unknown edit")
	}
	a.h = 0
	settleAutoUI(t, a, time.Now().Add(2*time.Second), func() bool { return a.tsf == second })
	a.up(61, x, y)
	_, edits, _ = second.counts()
	if a.preview == old || edits != 0 || a.host.blocked || a.preview.snapshot.State.RawInput != "" {
		t.Fatal("automatic recovery revived the consumed old commit")
	}
	previewAction(t, a.preview, "input", "a", "")
	a.down(62, x, y)
	a.up(62, x, y)
	_, edits, _ = second.counts()
	if edits != 1 {
		t.Fatal("fresh input did not work after pre-send cancellation")
	}
}
