// Package keyboardlab implements isolated concept-keyboard sessions shared by
// the web prototype and the uninstalled desktop experiment. It never sends OS input.
package keyboardlab

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	maxSessions = 16
	maxEvents   = 4096
	maxInput    = 128
	InputPolicy = "concept-keyboard-modes-v2"
	// Resource policy pins encoding/dictionaries. Session policy additionally
	// prevents old web clients/servers from mixing symbol-buffer semantics.
	SessionPolicy = InputPolicy + "+ellipsis-choice-v1"
	inputPolicy   = InputPolicy
)

var modes = []string{"variable", "full", "shorthand"}

// Modes returns a new slice so callers cannot change the supported inventory.
func Modes() []string { return append([]string(nil), modes...) }

type engineFactory func(string) (engineapi.Engine, error)

// Service serializes session mutations and caches immutable replies. A caller
// must consume each event's Commit at most once, including cached retries.
type Service struct {
	layoutID  string
	newEngine engineFactory
	mu        sync.Mutex
	sessions  map[string]*labSession
	stopped   bool
}

// Reply carries the existing API status and immutable JSON snapshot. Body is a
// caller-owned copy, so in-process consumers cannot corrupt cached responses.
type Reply struct {
	Status int
	Body   []byte
}

func (r Reply) Decode() (Response, error) {
	var result Response
	err := json.Unmarshal(r.Body, &result)
	return result, err
}
func bytesReply(status int, body []byte) Reply {
	return Reply{Status: status, Body: append([]byte(nil), body...)}
}
func jsonReply(status int, value any) Reply {
	body, _ := json.Marshal(value)
	return bytesReply(status, body)
}
func errorReply(status int, message string) Reply {
	return jsonReply(status, map[string]any{"ok": false, "error": message})
}

// NewService creates isolated sessions from the supplied engine factory.
// Production entry points use OpenRuntime to validate all layout-bound data.
func NewService(layoutID string, factory func(string) (engineapi.Engine, error)) *Service {
	return &Service{layoutID: layoutID, newEngine: factory, sessions: make(map[string]*labSession)}
}

type labSession struct {
	mu                sync.Mutex
	id                string
	engine            *keyboardEngine
	revision          uint64
	state             engineapi.State
	cached            map[string]cachedResponse
	lastUsed          time.Time
	closed            bool
	pendingMiddleDots int
}
type cachedResponse struct {
	fingerprint [32]byte
	status      int
	body        []byte
}
type Event struct {
	SessionID       string `json:"sessionId"`
	EventID         string `json:"eventId"`
	BaseRevision    uint64 `json:"baseRevision"`
	Type            string `json:"type"`
	Code            string `json:"code,omitempty"`
	Delta           int    `json:"delta,omitempty"`
	CandidateID     string `json:"candidateId,omitempty"`
	InputMode       string `json:"inputMode,omitempty"`
	PunctuationMode string `json:"punctuationMode,omitempty"`
}
type Response struct {
	OK                bool            `json:"ok"`
	SessionID         string          `json:"sessionId,omitempty"`
	Revision          uint64          `json:"revision"`
	State             engineapi.State `json:"state"`
	Commit            string          `json:"commit,omitempty"`
	Error             string          `json:"error,omitempty"`
	Modes             keyboardModes   `json:"modes"`
	PendingMiddleDots int             `json:"pendingMiddleDots,omitempty"`
	SymbolChoice      bool            `json:"symbolChoice,omitempty"`
}

// Internal aliases preserve the web protocol's existing regression fixtures.
type eventRequest = Event
type response = Response

// Open creates a new independent session using exactly the requested layout.
func (a *Service) Open(mode, layoutID string) Reply {
	request := struct{ Mode, LayoutID string }{mode, layoutID}
	if request.LayoutID != a.layoutID {
		return errorReply(http.StatusConflict, "layout changed; reload the page")
	}
	if request.Mode != "variable" && request.Mode != "full" && request.Mode != "shorthand" {
		return errorReply(http.StatusBadRequest, "unknown input mode")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.stopped {
		return errorReply(http.StatusGone, "service closed")
	}
	for id, session := range a.sessions {
		session.mu.Lock()
		if session.closed || time.Since(session.lastUsed) > 30*time.Minute {
			delete(a.sessions, id)
		}
		session.mu.Unlock()
	}
	if len(a.sessions) >= maxSessions {
		return errorReply(http.StatusTooManyRequests, "session limit reached; close an existing session")
	}
	engine, err := a.newEngine(request.Mode)
	if err != nil {
		return errorReply(http.StatusInternalServerError, "engine session could not be created")
	}
	adapter := &keyboardEngine{base: engine}
	session := &labSession{id: randomID(), engine: adapter, state: adapter.Reset().State, cached: make(map[string]cachedResponse), lastUsed: time.Now()}
	a.sessions[session.id] = session
	return jsonReply(http.StatusOK, response{OK: true, SessionID: session.id, State: session.state, Modes: adapter.Modes()})
}

// Dispatch executes or retrieves one event without any host text side effect.
func (a *Service) Dispatch(request Event) Reply {
	if err := validateEvent(request); err != nil {
		return errorReply(http.StatusBadRequest, err.Error())
	}
	a.mu.Lock()
	if a.stopped {
		a.mu.Unlock()
		return errorReply(http.StatusGone, "service closed")
	}
	session := a.sessions[request.SessionID]
	if session != nil {
		session.mu.Lock()
	}
	a.mu.Unlock()
	if session == nil {
		return errorReply(http.StatusNotFound, "session not found")
	}
	defer session.mu.Unlock()
	session.lastUsed = time.Now()
	encoded, _ := json.Marshal(request)
	fingerprint := sha256.Sum256(encoded)
	if cached, exists := session.cached[request.EventID]; exists {
		if fingerprint != cached.fingerprint {
			return errorReply(http.StatusConflict, "event ID reused with different content")
		} else {
			return bytesReply(cached.status, cached.body)
		}

	}
	if session.closed {
		return errorReply(http.StatusGone, "session closed")
	}
	if len(session.cached) >= maxEvents && request.Type != "close" {
		return errorReply(http.StatusTooManyRequests, "session event limit reached; create a new session")
	}
	status := http.StatusOK
	result := session.snapshot(false, "")
	if request.BaseRevision != session.revision {
		status, result.Error = http.StatusConflict, "stale revision; synchronize before another event"
	} else {
		applied, err := session.apply(request)
		if err != nil {
			status, result.Error = http.StatusBadRequest, err.Error()
		} else {
			session.revision++
			session.state = applied.State
			result = session.snapshot(true, applied.Commit)
		}
	}
	body, _ := json.Marshal(result)
	session.cached[request.EventID] = cachedResponse{fingerprint, status, body}
	return bytesReply(status, body)
}

func (s *labSession) apply(r eventRequest) (engineapi.Result, error) {
	// Offer two explicit choices at three/six taps. No host text is rewritten
	// or committed until a current choice is selected.
	if r.Type == "symbol" && r.Code == "·" {
		if s.pendingMiddleDots >= 6 {
			return engineapi.Result{}, errors.New("请先选择省略号候选或取消")
		}
		s.pendingMiddleDots++
		return engineapi.Result{State: s.state}, nil
	}
	if r.Type == "backspace" && s.pendingMiddleDots > 0 {
		s.pendingMiddleDots--
		return engineapi.Result{State: s.state}, nil
	}
	if r.Type == "clear" || r.Type == "close" || r.Type == "setModes" {
		s.pendingMiddleDots = 0
	}
	if s.pendingMiddleDots >= 3 {
		if r.Type == "select" {
			return s.selectEllipsis(r.CandidateID)
		}
		if r.Type == "input" && len(r.Code) == 1 && r.Code[0] >= '1' && r.Code[0] <= '9' {
			index := int(r.Code[0] - '1')
			choices := s.ellipsisChoices()
			if index >= len(choices) {
				return engineapi.Result{State: s.state}, nil
			}
			return s.selectEllipsis(choices[index].ID)
		}
		if r.Type != "literal" {
			return engineapi.Result{}, errors.New("请先选择省略号候选或取消")
		}
	}
	if r.Type == "flushSymbols" {
		return s.flushMiddleDots(), nil
	}
	result, err := s.applyCore(r)
	if err == nil && (r.Type == "input" || r.Type == "symbol" || r.Type == "select") {
		// Keep incomplete dots in input order when another main text action
		// succeeds. Literal side-zone bypasses do not consume this buffer.
		result.Commit = s.flushMiddleDots().Commit + result.Commit
	}
	return result, err
}

func (s *labSession) ellipsisChoices() []engineapi.Candidate {
	groups := s.pendingMiddleDots / 3
	if groups == 0 {
		return nil
	}
	return []engineapi.Candidate{
		{ID: fmt.Sprintf("keyboard-lab:ellipsis:%d:2026", s.pendingMiddleDots), Text: strings.Repeat("…", groups)},
		{ID: fmt.Sprintf("keyboard-lab:ellipsis:%d:22ef", s.pendingMiddleDots), Text: strings.Repeat("⋯", groups)},
	}
}

func (s *labSession) selectEllipsis(id string) (engineapi.Result, error) {
	for _, c := range s.ellipsisChoices() {
		if c.ID == id {
			s.pendingMiddleDots %= 3
			return engineapi.Result{State: s.state, Commit: c.Text}, nil
		}
	}
	return engineapi.Result{}, errors.New("省略号候选已更新，请重新选择")
}

func (s *labSession) snapshot(ok bool, commit string) response {
	state := s.state
	choices := s.ellipsisChoices()
	if len(choices) > 0 {
		// Presentation overlay only; retain the engine's raw composition and
		// candidate/page ownership underneath the temporary symbol choices.
		state.Candidates = choices
		state.HasNext, state.HasPrevious, state.PageNumber = false, false, 0
	}
	return response{OK: ok, SessionID: s.id, Revision: s.revision, State: state, Commit: commit, Modes: s.engine.Modes(), PendingMiddleDots: s.pendingMiddleDots, SymbolChoice: len(choices) > 0}
}

func (s *labSession) flushMiddleDots() engineapi.Result {
	text := strings.Repeat("·", s.pendingMiddleDots)
	s.pendingMiddleDots = 0
	return engineapi.Result{State: s.state, Commit: text}
}

func (s *labSession) applyCore(r eventRequest) (engineapi.Result, error) {
	switch r.Type {
	case "input":
		return s.engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: r.Code})
	case "literal":
		return s.engine.DirectLiteral(r.Code), nil
	case "symbol":
		return s.engine.DirectSymbol(r.Code), nil
	case "setModes":
		return s.engine.SetModes(r.InputMode, r.PunctuationMode), nil
	case "backspace":
		return s.engine.Apply(engineapi.Event{Operation: engineapi.Backspace})
	case "clear":
		return s.engine.Apply(engineapi.Event{Operation: engineapi.Clear})
	case "close":
		s.closed = true
		return s.engine.Reset(), nil
	case "page":
		if r.Delta > 0 && s.state.HasNext {
			return s.engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
		}
		if r.Delta < 0 && s.state.HasPrevious {
			return s.engine.Apply(engineapi.Event{Operation: engineapi.PagePrevious})
		}
		return engineapi.Result{}, errors.New("candidate page boundary")
	case "select":
		for _, candidate := range s.state.Candidates {
			if candidate.ID == r.CandidateID {
				return s.engine.Select(r.CandidateID)
			}
		}
		return engineapi.Result{}, errors.New("candidate is not on the current page")
	}
	return engineapi.Result{}, errors.New("unknown event type")
}

func validateEvent(r eventRequest) error {
	if len(r.SessionID) != 48 || len(r.EventID) == 0 || len(r.EventID) > 128 {
		return errors.New("invalid session or event ID")
	}
	for _, b := range r.EventID {
		if b < 0x21 || b > 0x7e {
			return errors.New("event ID must be printable ASCII")
		}
	}
	if r.Type != "setModes" && (r.InputMode != "" || r.PunctuationMode != "") {
		return errors.New("mode fields require setModes")
	}
	switch r.Type {
	case "setModes":
		validMode := func(value string) bool { return value == "" || value == "chinese" || value == "english" }
		if r.Code == "" && r.Delta == 0 && r.CandidateID == "" && (r.InputMode != "" || r.PunctuationMode != "") && validMode(r.InputMode) && validMode(r.PunctuationMode) {
			return nil
		}
	case "symbol":
		valid := len(r.Code) == 1 && isASCIIPunctuation(r.Code[0])
		switch r.Code {
		case "·", "、", "—", "×", "√", "÷":
			valid = true
		}
		if valid && r.Delta == 0 && r.CandidateID == "" {
			return nil
		}
	case "literal":
		if len(r.Code) == 1 && (r.Code[0] >= 0x20 && r.Code[0] <= 0x7e || r.Code == "\n" || r.Code == "\t") && r.Delta == 0 && r.CandidateID == "" {
			return nil
		}
	case "input":
		if len(r.Code) == 1 && r.Code[0] >= 0x21 && r.Code[0] <= 0x7e && r.Delta == 0 && r.CandidateID == "" {
			return nil
		}
	case "backspace", "clear", "close", "flushSymbols":
		if r.Code == "" && r.Delta == 0 && r.CandidateID == "" {
			return nil
		}
	case "page":
		if r.Code == "" && (r.Delta == 1 || r.Delta == -1) && r.CandidateID == "" {
			return nil
		}
	case "select":
		if r.Code == "" && r.Delta == 0 && len(r.CandidateID) > 0 && len(r.CandidateID) <= 512 {
			return nil
		}
	}
	return errors.New("invalid event type or payload")
}

func randomID() string {
	var value [24]byte
	if _, err := rand.Read(value[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(value[:])
}

// Close waits for current mutations, rejects future calls and releases sessions.
// The owning Runtime calls this before unmapping any shared dictionary indexes.
func (a *Service) Close() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.stopped = true
	for _, s := range a.sessions {
		s.mu.Lock()
		s.closed = true
		s.mu.Unlock()
	}
	a.sessions = make(map[string]*labSession)
}
