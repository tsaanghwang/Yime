package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	maxSessions = 16
	maxEvents   = 4096
	maxInput    = 128
	maxBody     = 8192
	inputPolicy = "concept-keyboard-modes-v2"
)

type engineFactory func(string) (engineapi.Engine, error)
type lab struct {
	staticRoot, layoutID, origin, token string
	repositoryRoot                      string
	newEngine                           engineFactory
	builds                              map[string]yimecore.IndexBuildResult
	mu                                  sync.Mutex
	sessions                            map[string]*labSession
}
type labSession struct {
	mu       sync.Mutex
	id       string
	engine   *keyboardEngine
	revision uint64
	state    engineapi.State
	cached   map[string]cachedResponse
	lastUsed time.Time
	closed   bool
}
type cachedResponse struct {
	fingerprint [32]byte
	status      int
	body        []byte
}
type eventRequest struct {
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
type response struct {
	OK        bool            `json:"ok"`
	SessionID string          `json:"sessionId,omitempty"`
	Revision  uint64          `json:"revision"`
	State     engineapi.State `json:"state"`
	Commit    string          `json:"commit,omitempty"`
	Error     string          `json:"error,omitempty"`
	Modes     keyboardModes   `json:"modes"`
}

func newLab(staticRoot, layoutID, origin string, factory engineFactory) *lab {
	return &lab{staticRoot: staticRoot, layoutID: layoutID, origin: origin, token: randomID(), newEngine: factory, sessions: make(map[string]*labSession)}
}

func (a *lab) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	ip := net.ParseIP(host)
	if err != nil || ip == nil || !ip.IsLoopback() || "http://"+r.Host != a.origin {
		writeError(w, http.StatusForbidden, "loopback host required")
		return
	}
	if origin := r.Header.Get("Origin"); origin != "" && origin != a.origin {
		writeError(w, http.StatusForbidden, "cross-origin request rejected")
		return
	}
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" && site != "same-origin" && site != "none" {
		writeError(w, http.StatusForbidden, "cross-site request rejected")
		return
	}
	if r.URL.Path == "/api/info" && r.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, map[string]any{"version": 1, "inputPolicy": inputPolicy, "layoutId": a.layoutID, "token": a.token, "modes": modes, "scope": "isolated-yimecore-page-only", "indexes": a.builds})
		return
	}
	if strings.HasPrefix(r.URL.Path, "/api/") {
		if r.Method != http.MethodPost {
			writeError(w, http.StatusMethodNotAllowed, "POST required")
			return
		}
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Yime-Lab-Token")), []byte(a.token)) != 1 {
			writeError(w, http.StatusForbidden, "lab token required")
			return
		}
		contentType, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if contentType != "application/json" {
			writeError(w, http.StatusUnsupportedMediaType, "application/json required")
			return
		}
		switch r.URL.Path {
		case "/api/session":
			a.open(w, r)
		case "/api/event":
			a.event(w, r)
		default:
			writeError(w, http.StatusNotFound, "unknown API endpoint")
		}
		return
	}
	a.static(w, r)
}

func (a *lab) open(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Mode     string `json:"mode"`
		LayoutID string `json:"layoutId"`
	}
	if err := readJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if request.LayoutID != a.layoutID {
		writeError(w, http.StatusConflict, "layout changed; reload the page")
		return
	}
	if request.Mode != "variable" && request.Mode != "full" && request.Mode != "shorthand" {
		writeError(w, http.StatusBadRequest, "unknown input mode")
		return
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	for id, session := range a.sessions {
		session.mu.Lock()
		if session.closed || time.Since(session.lastUsed) > 30*time.Minute {
			delete(a.sessions, id)
		}
		session.mu.Unlock()
	}
	if len(a.sessions) >= maxSessions {
		writeError(w, http.StatusTooManyRequests, "session limit reached; close an existing session")
		return
	}
	engine, err := a.newEngine(request.Mode)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "engine session could not be created")
		return
	}
	adapter := &keyboardEngine{base: engine}
	session := &labSession{id: randomID(), engine: adapter, state: adapter.Reset().State, cached: make(map[string]cachedResponse), lastUsed: time.Now()}
	a.sessions[session.id] = session
	writeJSON(w, http.StatusOK, response{OK: true, SessionID: session.id, State: session.state, Modes: adapter.Modes()})
}

func (a *lab) event(w http.ResponseWriter, r *http.Request) {
	var request eventRequest
	if err := readJSON(w, r, &request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := validateEvent(request); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	a.mu.Lock()
	session := a.sessions[request.SessionID]
	if session != nil {
		session.mu.Lock()
	}
	a.mu.Unlock()
	if session == nil {
		writeError(w, http.StatusNotFound, "session not found")
		return
	}
	defer session.mu.Unlock()
	session.lastUsed = time.Now()
	encoded, _ := json.Marshal(request)
	fingerprint := sha256.Sum256(encoded)
	if cached, exists := session.cached[request.EventID]; exists {
		if fingerprint != cached.fingerprint {
			writeError(w, http.StatusConflict, "event ID reused with different content")
		} else {
			writeBytes(w, cached.status, cached.body)
		}
		return
	}
	if session.closed {
		writeError(w, http.StatusGone, "session closed")
		return
	}
	if len(session.cached) >= maxEvents && request.Type != "close" {
		writeError(w, http.StatusTooManyRequests, "session event limit reached; create a new session")
		return
	}
	status := http.StatusOK
	result := response{OK: false, SessionID: session.id, Revision: session.revision, State: session.state, Modes: session.engine.Modes()}
	if request.BaseRevision != session.revision {
		status, result.Error = http.StatusConflict, "stale revision; synchronize before another event"
	} else {
		applied, err := session.apply(request)
		if err != nil {
			status, result.Error = http.StatusBadRequest, err.Error()
		} else {
			session.revision++
			session.state = applied.State
			result = response{OK: true, SessionID: session.id, Revision: session.revision, State: session.state, Commit: applied.Commit, Modes: session.engine.Modes()}
		}
	}
	body, _ := json.Marshal(result)
	session.cached[request.EventID] = cachedResponse{fingerprint, status, body}
	writeBytes(w, status, body)
}

func (s *labSession) apply(r eventRequest) (engineapi.Result, error) {
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
	case "backspace", "clear", "close":
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

func (a *lab) static(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		writeError(w, http.StatusMethodNotAllowed, "GET or HEAD required")
		return
	}
	relative := strings.TrimPrefix(r.URL.Path, "/")
	if relative == "" {
		relative = "index.html"
	}
	if relative == "assets/YinYuan-Regular.ttf" {
		a.font(w, r)
		return
	}
	// This service exposes only the physical-model entrypoint. Historical demo
	// data and implementation files must not be mistaken for the live backend.
	switch relative {
	case "index.html", "app.mjs", "input.mjs", "keyboard-layout.mjs", "geometry.mjs", "style.css", "data/physical-layout.json", "README.md", "PROTOCOL.md", "HARDWARE.md":
	default:
		http.NotFound(w, r)
		return
	}
	root, err := filepath.EvalSymlinks(a.staticRoot)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	target, err := filepath.EvalSymlinks(filepath.Join(root, filepath.FromSlash(relative)))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		http.NotFound(w, r)
		return
	}
	switch strings.ToLower(filepath.Ext(target)) {
	case ".html", ".css", ".mjs", ".json", ".md":
	default:
		http.NotFound(w, r)
		return
	}
	info, err := os.Stat(target)
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(w, r)
		return
	}
	if strings.HasSuffix(target, ".mjs") {
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	}
	http.ServeFile(w, r, target)
}

func (a *lab) font(w http.ResponseWriter, r *http.Request) {
	if a.repositoryRoot == "" {
		http.NotFound(w, r)
		return
	}
	root, err := filepath.EvalSymlinks(a.repositoryRoot)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	// One known repository-owned file, not an exposed assets/fonts directory.
	target, err := filepath.EvalSymlinks(filepath.Join(root, "go-backend", "input_methods", "yime", "data", "fonts", "YinYuan-Regular.ttf"))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	rel, err := filepath.Rel(root, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		http.NotFound(w, r)
		return
	}
	info, err := os.Stat(target)
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "font/ttf")
	http.ServeFile(w, r, target)
}

func readJSON(w http.ResponseWriter, r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("invalid JSON request: %w", err)
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return errors.New("request must contain exactly one JSON object")
	}
	return nil
}
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{"ok": false, "error": message})
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	body, _ := json.Marshal(value)
	writeBytes(w, status, body)
}
func writeBytes(w http.ResponseWriter, status int, body []byte) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
