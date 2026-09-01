package yimebroker

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

type EngineFactory func() (engineapi.Engine, error)
type ModeEngineFactory func(mode string) (engineapi.Engine, error)

type Config struct {
	MaxSessions          int
	MaxSessionsPerClient int
	OperationTimeout     time.Duration
}

type Dispatcher struct {
	factory     EngineFactory
	modeFactory ModeEngineFactory
	defaultMode string
	config      Config

	mu       sync.Mutex
	sessions map[string]*session
	// Slots remain occupied until an engine call actually returns, even after
	// its request deadline. This bounds non-cancellable third-party engines
	// that ignore timeouts instead of leaking an unbounded goroutine per retry.
	operationSlots chan struct{}
}

// NewModeDispatcher selects one immutable engine index when a session opens.
// Existing sessions retain their engine, so changing the toolbar mode never
// mutates an active composition.
func NewModeDispatcher(defaultMode string, factory ModeEngineFactory, config Config) (*Dispatcher, error) {
	if defaultMode != "full" && defaultMode != "variable" && defaultMode != "shorthand" {
		return nil, errors.New("default mode must be full, variable or shorthand")
	}
	if factory == nil {
		return nil, errors.New("mode engine factory is required")
	}
	dispatcher, err := NewDispatcher(func() (engineapi.Engine, error) { return factory(defaultMode) }, config)
	if err != nil {
		return nil, err
	}
	dispatcher.modeFactory = factory
	dispatcher.defaultMode = defaultMode
	return dispatcher, nil
}

type session struct {
	mu         sync.Mutex
	owner      string
	connection string
	engine     engineapi.Engine
	lastSeq    uint64
	closed     bool
}

type engineOutcome struct {
	result engineapi.Result
	err    error
	panic  any
}

type engineFactoryOutcome struct {
	engine engineapi.Engine
	err    error
	panic  any
}

func NewDispatcher(factory EngineFactory, config Config) (*Dispatcher, error) {
	if factory == nil {
		return nil, errors.New("engine factory is required")
	}
	if config.MaxSessions == 0 {
		config.MaxSessions = 64
	}
	if config.MaxSessionsPerClient == 0 {
		config.MaxSessionsPerClient = 4
	}
	if config.OperationTimeout == 0 {
		config.OperationTimeout = 50 * time.Millisecond
	}
	if config.MaxSessions < 1 || config.MaxSessionsPerClient < 1 || config.MaxSessionsPerClient > config.MaxSessions {
		return nil, errors.New("invalid session limits")
	}
	if config.OperationTimeout < time.Millisecond {
		return nil, errors.New("operation timeout must be at least 1ms")
	}
	return &Dispatcher{
		factory: factory, config: config, sessions: make(map[string]*session),
		operationSlots: make(chan struct{}, config.MaxSessions),
	}, nil
}

// HandleJSON includes strict wire decoding and response encoding in the E5-A
// replay path. Trusted client identity remains a separate argument.
func (d *Dispatcher) HandleJSON(ctx context.Context, client TrustedClient, data []byte) []byte {
	_, _, encoded, _ := d.handleJSON(ctx, client, data)
	return encoded
}

// handleJSON returns the decoded request and typed response alongside the wire
// encoding so transports can track connection-owned sessions without decoding
// either JSON document a second time.
func (d *Dispatcher) handleJSON(ctx context.Context, client TrustedClient, data []byte) (Request, Response, []byte, bool) {
	request, err := DecodeRequest(data)
	if err != nil {
		code := CodeInvalidRequest
		var versionProbe struct {
			Version int `json:"version"`
		}
		if len(data) <= MaxMessageBytes && json.Unmarshal(data, &versionProbe) == nil && versionProbe.Version != 0 && versionProbe.Version != ProtocolVersion {
			code = CodeUnsupportedVersion
		}
		response := errorResponse(0, "", code, err)
		encoded, _ := EncodeResponse(response)
		return Request{}, response, encoded, false
	}
	response := d.Dispatch(ctx, client, request)
	encoded, err := EncodeResponse(response)
	if err != nil {
		response = errorResponse(request.Sequence, request.SessionID, CodeEngine, err)
		encoded, _ = EncodeResponse(response)
	}
	return request, response, encoded, true
}

func (d *Dispatcher) Dispatch(ctx context.Context, client TrustedClient, request Request) (response Response) {
	defer func() { response.MutationID = request.MutationID }()
	if strings.TrimSpace(client.ID) == "" || len(client.ID) > 128 {
		return errorResponse(request.Sequence, request.SessionID, CodeInvalidClient, errors.New("trusted client ID is required and limited to 128 bytes"))
	}
	if request.Version != ProtocolVersion {
		return errorResponse(request.Sequence, request.SessionID, CodeUnsupportedVersion, fmt.Errorf("unsupported protocol version %d", request.Version))
	}
	if err := validateRequest(request); err != nil {
		return errorResponse(request.Sequence, request.SessionID, CodeInvalidRequest, err)
	}
	if request.Operation == OpenSession {
		return d.open(ctx, client, request)
	}
	return d.onSession(ctx, client, request)
}

func (d *Dispatcher) open(ctx context.Context, client TrustedClient, request Request) Response {
	d.mu.Lock()
	if len(d.sessions) >= d.config.MaxSessions || d.clientSessionCountLocked(client.ID) >= d.config.MaxSessionsPerClient {
		d.mu.Unlock()
		return errorResponse(request.Sequence, "", CodeSessionLimit, errors.New("session quota exceeded"))
	}
	id, err := d.newSessionIDLocked()
	if err != nil {
		d.mu.Unlock()
		return errorResponse(request.Sequence, "", CodeEngine, fmt.Errorf("create session ID: %w", err))
	}
	current := &session{owner: client.ID, connection: connectionOwner(client), lastSeq: request.Sequence}
	// Keep the session locked while its quota reservation is visible. Requests
	// that arrive on another connection from the same process cannot observe a
	// partially initialized engine.
	current.mu.Lock()
	d.sessions[id] = current // reservation participates in quota accounting
	d.mu.Unlock()
	defer current.mu.Unlock()
	if !d.acquireOperationSlot() {
		d.evict(id, current)
		return errorResponse(request.Sequence, id, CodeSessionLimit, errors.New("engine operation capacity exhausted"))
	}

	outcome, timedOut := runEngineFactoryWithDeadline(ctx, d.config.OperationTimeout, func() (engineapi.Engine, error) {
		defer d.releaseOperationSlot()
		var engine engineapi.Engine
		var factoryErr error
		if d.modeFactory != nil {
			mode := request.Mode
			if mode == "" {
				mode = d.defaultMode
			}
			engine, factoryErr = d.modeFactory(mode)
		} else {
			engine, factoryErr = d.factory()
		}
		if factoryErr == nil && engine != nil {
			if request.CandidateLimit != 0 {
				configurable, ok := engine.(interface{ SetCandidateLimit(int) error })
				if !ok {
					closeEngine(engine)
					return nil, errors.New("engine does not support candidate_limit")
				}
				if factoryErr = configurable.SetCandidateLimit(request.CandidateLimit); factoryErr != nil {
					closeEngine(engine)
					return nil, factoryErr
				}
			}
		}
		return engine, factoryErr
	})
	if timedOut {
		d.evict(id, current)
		return errorResponse(request.Sequence, id, CodeTimeout, errors.New("engine creation timed out"))
	}
	if outcome.panic != nil {
		d.evict(id, current)
		closeEngine(outcome.engine)
		return errorResponse(request.Sequence, id, CodeEnginePanic, fmt.Errorf("engine creation panic: %v", outcome.panic))
	}
	if outcome.err != nil || outcome.engine == nil {
		d.evict(id, current)
		closeEngine(outcome.engine)
		if outcome.err == nil {
			outcome.err = errors.New("engine factory returned nil")
		}
		return errorResponse(request.Sequence, id, CodeEngine, outcome.err)
	}
	current.engine = outcome.engine
	return Response{Version: ProtocolVersion, Sequence: request.Sequence, SessionID: id, EngineVersion: engineVersion(current.engine), Result: &engineapi.Result{}}
}

func (d *Dispatcher) newSessionIDLocked() (string, error) {
	for attempts := 0; attempts < 8; attempts++ {
		var entropy [16]byte
		if _, err := rand.Read(entropy[:]); err != nil {
			return "", err
		}
		id := fmt.Sprintf("s-%x", entropy)
		if d.sessions[id] == nil {
			return id, nil
		}
	}
	return "", errors.New("session ID collision limit reached")
}

func (d *Dispatcher) onSession(ctx context.Context, client TrustedClient, request Request) Response {
	d.mu.Lock()
	current := d.sessions[request.SessionID]
	d.mu.Unlock()
	if current == nil || current.owner != client.ID || current.connection != connectionOwner(client) {
		return errorResponse(request.Sequence, request.SessionID, CodeSessionNotFound, errors.New("session is unavailable for trusted client"))
	}

	current.mu.Lock()
	defer current.mu.Unlock()
	d.mu.Lock()
	active := d.sessions[request.SessionID] == current && !current.closed
	d.mu.Unlock()
	if !active {
		return errorResponse(request.Sequence, request.SessionID, CodeSessionNotFound, errors.New("session is closed"))
	}
	if request.Sequence != current.lastSeq+1 {
		return errorResponse(request.Sequence, request.SessionID, CodeSequence, fmt.Errorf("want sequence %d", current.lastSeq+1))
	}
	current.lastSeq = request.Sequence
	if request.Operation == CloseSession {
		d.evict(request.SessionID, current)
		closeEngine(current.engine)
		return Response{Version: ProtocolVersion, Sequence: request.Sequence, SessionID: request.SessionID, EngineVersion: engineVersion(current.engine), Result: &engineapi.Result{}}
	}

	if !d.acquireOperationSlot() {
		return errorResponse(request.Sequence, request.SessionID, CodeSessionLimit, errors.New("engine operation capacity exhausted"))
	}
	outcome, timedOut := runWithDeadline(ctx, d.config.OperationTimeout, func() (engineapi.Result, error) {
		defer d.releaseOperationSlot()
		switch request.Operation {
		case ApplyEvent:
			return current.engine.Apply(request.Event)
		case Select:
			if request.MutationID != "" {
				selector, ok := current.engine.(interface {
					SelectIdempotent(string, string) (engineapi.Result, error)
				})
				if !ok {
					return engineapi.Result{}, errors.New("engine does not support idempotent selection")
				}
				return selector.SelectIdempotent(request.CandidateID, durableMutationID(request.SessionID, request.MutationID))
			}
			return current.engine.Select(request.CandidateID)
		case Forget:
			forgetter, ok := current.engine.(engineapi.CandidateForgetter)
			if !ok {
				return engineapi.Result{}, errors.New("engine does not support candidate forgetting")
			}
			return forgetter.ForgetCandidate(request.CandidateID)
		case ResetSession:
			return current.engine.Reset(), nil
		default:
			return engineapi.Result{}, errors.New("unsupported session operation")
		}
	}, func() { closeEngine(current.engine) })
	if timedOut {
		d.evict(request.SessionID, current)
		return errorResponse(request.Sequence, request.SessionID, CodeTimeout, errors.New("engine operation timed out; session evicted"))
	}
	if outcome.panic != nil {
		d.evict(request.SessionID, current)
		closeEngine(current.engine)
		return errorResponse(request.Sequence, request.SessionID, CodeEnginePanic, fmt.Errorf("engine panic: %v; session evicted", outcome.panic))
	}
	if outcome.err != nil {
		return errorResponse(request.Sequence, request.SessionID, CodeEngine, outcome.err)
	}
	return Response{Version: ProtocolVersion, Sequence: request.Sequence, SessionID: request.SessionID, EngineVersion: engineVersion(current.engine), Result: &outcome.result}
}

func (d *Dispatcher) acquireOperationSlot() bool {
	select {
	case d.operationSlots <- struct{}{}:
		return true
	default:
		return false
	}
}

func (d *Dispatcher) releaseOperationSlot() {
	<-d.operationSlots
}

// durableMutationID prevents the pre-E6-C experimental text service from
// reusing its process-local selection sequence in multiple surface sessions.
// E6-C and other callers already supply globally stable IDs and retain their
// original cross-session idempotency semantics.
func durableMutationID(sessionID, mutationID string) string {
	if strings.HasPrefix(mutationID, "e6b2a-surface-") {
		return sessionID + ":" + mutationID
	}
	return mutationID
}

func runWithDeadline(ctx context.Context, timeout time.Duration, call func() (engineapi.Result, error), onLateCompletion func()) (engineOutcome, bool) {
	operationCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	completed := make(chan engineOutcome, 1)
	go func() {
		outcome := engineOutcome{}
		defer func() {
			outcome.panic = recover()
			completed <- outcome
		}()
		outcome.result, outcome.err = call()
	}()
	select {
	case outcome := <-completed:
		return outcome, false
	case <-operationCtx.Done():
		if onLateCompletion != nil {
			go func() {
				<-completed
				onLateCompletion()
			}()
		}
		return engineOutcome{err: operationCtx.Err()}, true
	}
}

func runEngineFactoryWithDeadline(ctx context.Context, timeout time.Duration, call func() (engineapi.Engine, error)) (engineFactoryOutcome, bool) {
	operationCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	completed := make(chan engineFactoryOutcome, 1)
	go func() {
		outcome := engineFactoryOutcome{}
		defer func() {
			outcome.panic = recover()
			completed <- outcome
		}()
		outcome.engine, outcome.err = call()
	}()
	select {
	case outcome := <-completed:
		return outcome, false
	case <-operationCtx.Done():
		go func() {
			outcome := <-completed
			closeEngine(outcome.engine)
		}()
		return engineFactoryOutcome{err: operationCtx.Err()}, true
	}
}

func closeEngine(engine engineapi.Engine) {
	if closer, ok := engine.(interface{ Close() error }); ok {
		_ = closer.Close()
	}
}

func engineVersion(engine engineapi.Engine) string {
	if versioned, ok := engine.(interface{ IndexVersion() string }); ok {
		return versioned.IndexVersion()
	}
	return ""
}

func (d *Dispatcher) evict(id string, target *session) {
	d.mu.Lock()
	if d.sessions[id] == target {
		delete(d.sessions, id)
		target.closed = true
	}
	d.mu.Unlock()
}

// CloseSession releases one session only when it still belongs to the
// authenticated transport client. It cleans up abandoned sessions when a
// connection ends without a protocol close request.
func (d *Dispatcher) CloseSession(client TrustedClient, id string) {
	d.mu.Lock()
	current := d.sessions[id]
	d.mu.Unlock()
	if current == nil || current.owner != client.ID || current.connection != connectionOwner(client) {
		return
	}
	current.mu.Lock()
	defer current.mu.Unlock()
	d.mu.Lock()
	if d.sessions[id] == current && current.owner == client.ID &&
		current.connection == connectionOwner(client) && !current.closed {
		delete(d.sessions, id)
		current.closed = true
		d.mu.Unlock()
		closeEngine(current.engine)
		return
	}
	d.mu.Unlock()
}

func connectionOwner(client TrustedClient) string {
	if client.ConnectionID != "" {
		return client.ConnectionID
	}
	// In-process experiment callers do not have a transport connection. Keep
	// their historical per-client behavior while real transports always assign
	// an opaque connection ID in ServeLines.
	return "direct:" + client.ID
}

func (d *Dispatcher) clientSessionCountLocked(clientID string) int {
	count := 0
	for _, current := range d.sessions {
		if current.owner == clientID {
			count++
		}
	}
	return count
}

func (d *Dispatcher) ActiveSessions() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.sessions)
}
