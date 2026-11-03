// Package touchhostbridge defines the first, host-neutral boundary between the
// dedicated concept-keyboard runtime and a future trusted TSF host adapter.
// It does not write host text, register an IME, or use SendInput. An Applied
// receipt is meaningful only when the host adapter observes edit completion.
package touchhostbridge

import (
	"encoding/json"
	"errors"
	"fmt"
	"sync"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
)

// Identity is derived from OpenRuntime's validated experimental layout and
// dictionary, never from the standard product's index or a caller label.
type Identity struct{ LayoutSHA256, DictionarySHA256, Mode, SessionPolicy string }

// Focus is an opaque trusted-host context and its activation epoch. It is not a
// HWND or authorization supplied by a remote client. The host must check it
// again at actual edit execution; comparing it here cannot prove OS focus.
type Focus struct {
	Context string
	Epoch   uint64
}
type Outcome string

const (
	Pending Outcome = "pending"
	Applied Outcome = "applied"
	Failed  Outcome = "failed"
	Unknown Outcome = "unknown"
)

// Commit is issued once. Its ID and focus must travel with the actual host edit.
// A transport must not retransmit it after a timeout, disconnect, or restart.
type Commit struct {
	ID       string
	Focus    Focus
	Identity Identity
	Text     string
	Edit     *HostEdit
}

// HostEdit is an operation on the current TSF selection. It contains no target
// window or document identity; the activated TIP owns and checks those values.
type HostEdit struct {
	Key   string `json:"key"`
	Shift bool   `json:"shift,omitempty"`
	Ctrl  bool   `json:"ctrl,omitempty"`
}
type Receipt struct {
	ID      string
	Outcome Outcome
}
type Action struct {
	SessionID                  string
	Revision                   uint64
	Kind, Code, CandidateID    string
	Delta                      int
	InputMode, PunctuationMode string
	Edit                       *HostEdit
}

// Session exclusively owns its runtime. It serializes mutations; callers must
// not turn Pending into Applied merely because an edit was queued (TF_S_ASYNC).
type Session struct {
	mu            sync.Mutex
	runtime       *keyboardlab.Runtime
	identity      Identity
	focus         Focus
	state         keyboardlab.Response
	sequence      uint64
	receipt       Receipt
	stopped       bool
	desktop       bool
	sharedRuntime bool
}

// Open validates all three experimental dictionaries using the existing loader,
// then opens one mode. Each Session is isolated from installed product state.
func Open(root, dataDir, mode string, focus Focus) (*Session, error) {
	return open(root, dataDir, mode, focus, false)
}

func OpenDesktop(root, dataDir, mode string, focus Focus) (*Session, error) {
	return open(root, dataDir, mode, focus, true)
}

func open(root, dataDir, mode string, focus Focus, desktop bool) (*Session, error) {
	if focus.Context == "" || focus.Epoch == 0 {
		return nil, errors.New("trusted focus context and nonzero epoch required")
	}
	r, err := keyboardlab.OpenRuntime(root, dataDir)
	if err != nil {
		return nil, err
	}
	s, err := OpenDesktopRuntime(r, mode, focus)
	if err != nil {
		_ = r.Close()
		return nil, err
	}
	s.desktop, s.sharedRuntime = desktop, false
	return s, nil
}

// OpenDesktopRuntime shares immutable mapped indexes across focused TIP
// sessions. The broker owns their lifetime; every composition stays separate.
func OpenDesktopRuntime(r *keyboardlab.Runtime, mode string, focus Focus) (*Session, error) {
	if r == nil || focus.Context == "" || focus.Epoch == 0 {
		return nil, errors.New("runtime and trusted focus required")
	}
	reply := r.Sessions.Open(mode, r.LayoutID)
	state, err := reply.Decode()
	if err != nil || reply.Status != 200 || !state.OK {
		return nil, errors.New("cannot open isolated mode session")
	}
	return &Session{runtime: r, identity: Identity{r.LayoutID, r.Builds[mode].SourceSHA256, mode, keyboardlab.SessionPolicy}, focus: focus, state: state, desktop: true, sharedRuntime: true}, nil
}
func (s *Session) Identity() Identity { s.mu.Lock(); defer s.mu.Unlock(); return s.identity }

// Snapshot returns a detached copy without ephemeral commit text. Revision is
// the token that a candidate press must retain until selection.
func (s *Session) Snapshot() keyboardlab.Response {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Reply's JSON round trip also detaches candidate/segment slices.
	return clone(s.state)
}
func clone(v keyboardlab.Response) keyboardlab.Response {
	// Reuse the public wire representation, not engine-owned slices.
	b, _ := json.Marshal(v)
	var out keyboardlab.Response
	_ = json.Unmarshal(b, &out)
	out.Commit = ""
	return out
}
func (s *Session) Receipt() Receipt { s.mu.Lock(); defer s.mu.Unlock(); return s.receipt }

// Dispatch returns at most one commit request and never applies it itself.
// All actions use a revision, not only select: delayed input cannot enter a new
// composition. Unknown/stale candidate IDs are also checked by keyboardlab.
func (s *Session) Dispatch(identity Identity, focus Focus, a Action) (*Commit, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopped {
		return nil, errors.New("session stopped; no replay")
	}
	if identity != s.identity || focus != s.focus {
		return nil, errors.New("identity or focus mismatch")
	}
	if s.receipt.Outcome == Pending {
		return nil, errors.New("host edit awaiting actual completion")
	}
	if a.SessionID != s.state.SessionID {
		return nil, errors.New("foreign session")
	}
	if a.Revision != s.state.Revision {
		return nil, errors.New("stale revision")
	}
	switch a.Kind {
	case "input", "backspace", "clear", "page", "select":
	case "literal", "symbol", "setModes", "flushSymbols":
		if !s.desktop {
			return nil, errors.New("unsupported first-phase action")
		}
	case "hostEdit":
		if !s.desktop || s.state.State.RawInput != "" || s.state.PendingMiddleDots != 0 || a.Edit == nil || a.Code != "" || a.CandidateID != "" || a.Delta != 0 || a.InputMode != "" || a.PunctuationMode != "" {
			return nil, errors.New("host editing requires empty composition and an edit action")
		}
		if err := ValidateHostEdit(*a.Edit); err != nil {
			return nil, err
		}
		s.sequence++
		id := fmt.Sprintf("%s/edit-%d", s.state.SessionID, s.sequence)
		reply := s.runtime.Sessions.Dispatch(keyboardlab.Event{SessionID: s.state.SessionID, EventID: id, BaseRevision: s.state.Revision, Type: "flushSymbols"})
		next, err := reply.Decode()
		if err != nil || reply.Status != 200 || !next.OK || next.Commit != "" || next.Revision != s.state.Revision+1 {
			s.stopped = true
			return nil, errors.New("host edit revision preparation failed; no replay")
		}
		s.state = next
		s.receipt = Receipt{id, Pending}
		edit := *a.Edit
		return &Commit{ID: id, Focus: s.focus, Identity: s.identity, Edit: &edit}, nil
	default:
		return nil, errors.New("unsupported first-phase action")
	}
	if a.Edit != nil {
		return nil, errors.New("edit fields require hostEdit")
	}
	s.sequence++
	id := fmt.Sprintf("bridge-%d", s.sequence)
	e := keyboardlab.Event{SessionID: s.state.SessionID, EventID: id, BaseRevision: a.Revision, Type: a.Kind, Code: a.Code, Delta: a.Delta, CandidateID: a.CandidateID, InputMode: a.InputMode, PunctuationMode: a.PunctuationMode}
	reply := s.runtime.Sessions.Dispatch(e)
	next, err := reply.Decode()
	if err != nil || next.SessionID != s.state.SessionID {
		s.stopped = true
		return nil, errors.New("invalid engine response; no replay")
	}
	if reply.Status != 200 || !next.OK {
		return nil, errors.New("engine rejected action")
	}
	if next.Revision != s.state.Revision+1 {
		s.stopped = true
		return nil, errors.New("invalid engine revision; no replay")
	}
	text := next.Commit
	next.Commit = ""
	s.state = next
	if text == "" {
		return nil, nil
	}
	commitID := s.state.SessionID + "/" + id
	s.receipt = Receipt{commitID, Pending}
	return &Commit{ID: commitID, Focus: s.focus, Identity: s.identity, Text: text}, nil
}

func ValidateHostEdit(e HostEdit) error {
	switch e.Key {
	case "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown":
		return nil
	case "Backspace", "Delete":
		return nil
	case "Enter", "Tab":
		if !e.Ctrl {
			return nil
		}
	case "SelectAll", "Copy", "Cut", "Paste":
		if !e.Ctrl && !e.Shift {
			return nil
		}
	}
	return errors.New("unsupported TSF edit operation")
}

// Complete is an in-process trusted-host adapter operation, never a public
// client RPC. It accepts only a single terminal receipt for the outstanding edit.
// Failed means the host confirmed failure, not permission to replay; Unknown
// includes timeouts and disconnects. Both stop this session permanently.
func (s *Session) Complete(id string, outcome Outcome) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.stopped || s.receipt.Outcome != Pending || s.receipt.ID != id {
		return errors.New("no matching pending edit")
	}
	if outcome != Applied && outcome != Failed && outcome != Unknown {
		return errors.New("terminal host outcome required")
	}
	s.receipt.Outcome = outcome
	if outcome != Applied {
		s.stopped = true
	}
	return nil
}

// Invalidate is called on focus loss, minimize, host destruction or disconnect.
// A pending edit becomes Unknown, never implicitly successful or retryable.
// A new activation requires a new Session and fresh composition.
func (s *Session) Invalidate() { s.mu.Lock(); defer s.mu.Unlock(); s.stop() }
func (s *Session) stop() {
	s.stopped = true
	if s.receipt.Outcome == Pending {
		s.receipt.Outcome = Unknown
	}
}
func (s *Session) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stop()
	if s.sharedRuntime {
		s.sequence++
		s.runtime.Sessions.Dispatch(keyboardlab.Event{SessionID: s.state.SessionID, EventID: fmt.Sprintf("bridge-close-%d", s.sequence), BaseRevision: s.state.Revision, Type: "close"})
		return nil
	}
	return s.runtime.Close()
}
