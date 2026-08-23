package yimebroker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

type EngineFactory func() (engineapi.Engine, error)

type Config struct {
	MaxSessions          int
	MaxSessionsPerClient int
	OperationTimeout     time.Duration
}

type Dispatcher struct {
	factory EngineFactory
	config  Config

	mu       sync.Mutex
	sessions map[string]*session
	nextID   atomic.Uint64
}

type session struct {
	mu      sync.Mutex
	owner   string
	engine  engineapi.Engine
	lastSeq uint64
	closed  bool
}

type engineOutcome struct {
	result engineapi.Result
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
	return &Dispatcher{factory: factory, config: config, sessions: make(map[string]*session)}, nil
}

// HandleJSON includes strict wire decoding and response encoding in the E5-A
// replay path. Trusted client identity remains a separate argument.
func (d *Dispatcher) HandleJSON(ctx context.Context, client TrustedClient, data []byte) []byte {
	request, err := DecodeRequest(data)
	if err != nil {
		code := CodeInvalidRequest
		var versionProbe struct {
			Version int `json:"version"`
		}
		if len(data) <= MaxMessageBytes && json.Unmarshal(data, &versionProbe) == nil && versionProbe.Version != 0 && versionProbe.Version != ProtocolVersion {
			code = CodeUnsupportedVersion
		}
		encoded, _ := EncodeResponse(errorResponse(0, "", code, err))
		return encoded
	}
	response := d.Dispatch(ctx, client, request)
	encoded, err := EncodeResponse(response)
	if err != nil {
		encoded, _ = EncodeResponse(errorResponse(request.Sequence, request.SessionID, CodeEngine, err))
	}
	return encoded
}

func (d *Dispatcher) Dispatch(ctx context.Context, client TrustedClient, request Request) Response {
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
	id := fmt.Sprintf("s-%016x", d.nextID.Add(1))
	current := &session{owner: client.ID, lastSeq: request.Sequence}
	d.sessions[id] = current // reservation participates in quota accounting
	d.mu.Unlock()

	outcome, timedOut := runWithDeadline(ctx, d.config.OperationTimeout, func() (engineapi.Result, error) {
		engine, err := d.factory()
		if err == nil {
			current.engine = engine
		}
		return engineapi.Result{}, err
	}, func() { closeEngine(current.engine) })
	if timedOut {
		d.evict(id, current)
		return errorResponse(request.Sequence, id, CodeTimeout, errors.New("engine creation timed out"))
	}
	if outcome.panic != nil {
		d.evict(id, current)
		closeEngine(current.engine)
		return errorResponse(request.Sequence, id, CodeEnginePanic, fmt.Errorf("engine creation panic: %v", outcome.panic))
	}
	if outcome.err != nil || current.engine == nil {
		d.evict(id, current)
		closeEngine(current.engine)
		if outcome.err == nil {
			outcome.err = errors.New("engine factory returned nil")
		}
		return errorResponse(request.Sequence, id, CodeEngine, outcome.err)
	}
	return Response{Version: ProtocolVersion, Sequence: request.Sequence, SessionID: id, EngineVersion: engineVersion(current.engine), Result: &engineapi.Result{}}
}

func (d *Dispatcher) onSession(ctx context.Context, client TrustedClient, request Request) Response {
	d.mu.Lock()
	current := d.sessions[request.SessionID]
	d.mu.Unlock()
	if current == nil || current.owner != client.ID {
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

	outcome, timedOut := runWithDeadline(ctx, d.config.OperationTimeout, func() (engineapi.Result, error) {
		switch request.Operation {
		case ApplyEvent:
			return current.engine.Apply(request.Event)
		case Select:
			return current.engine.Select(request.CandidateID)
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
