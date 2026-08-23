package yimecore

import (
	"fmt"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const defaultCandidateLimit = 9

// Engine is the E0 Go session implementation. It intentionally implements
// only deterministic code input and indexed candidate lookup.
type Engine struct {
	index      *Index
	limit      int
	rawInput   string
	candidates []engineapi.Candidate
}

var _ engineapi.Engine = (*Engine)(nil)

// NewEngine constructs an isolated engine session.
func NewEngine(index *Index, candidateLimit int) (*Engine, error) {
	if index == nil {
		return nil, fmt.Errorf("index is required")
	}
	if candidateLimit == 0 {
		candidateLimit = defaultCandidateLimit
	}
	if candidateLimit < 1 || candidateLimit > 9 {
		return nil, fmt.Errorf("candidate limit must be between 1 and 9")
	}
	return &Engine{index: index, limit: candidateLimit}, nil
}

// Apply advances the session by one host-neutral event.
func (e *Engine) Apply(event engineapi.Event) (engineapi.Result, error) {
	switch event.Operation {
	case engineapi.AppendCode:
		code, err := normalizeCode(event.Code)
		if err != nil || len(code) != len(event.Code) {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.rawInput += code
	case engineapi.Backspace:
		if event.Code != "" {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		if len(e.rawInput) > 0 {
			e.rawInput = e.rawInput[:len(e.rawInput)-1]
		}
	case engineapi.Clear:
		if event.Code != "" {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.rawInput = ""
	default:
		return engineapi.Result{}, engineapi.ErrInvalidEvent
	}
	e.refresh()
	return engineapi.Result{State: e.snapshot()}, nil
}

// Select commits a candidate from the current snapshot and clears the input.
func (e *Engine) Select(candidateID string) (engineapi.Result, error) {
	for _, candidate := range e.candidates {
		if candidate.ID == candidateID {
			e.rawInput = ""
			e.candidates = nil
			return engineapi.Result{State: e.snapshot(), Commit: candidate.Text}, nil
		}
	}
	return engineapi.Result{}, engineapi.ErrUnknownCandidate
}

// Reset clears the session without producing a commit.
func (e *Engine) Reset() engineapi.Result {
	e.rawInput = ""
	e.candidates = nil
	return engineapi.Result{State: e.snapshot()}
}

func (e *Engine) refresh() {
	if e.rawInput == "" {
		e.candidates = nil
		return
	}
	records := e.index.lookup(e.rawInput, e.limit)
	candidates := make([]engineapi.Candidate, 0, len(records))
	for _, item := range records {
		candidates = append(candidates, engineapi.Candidate{
			ID:     item.code + "\x1f" + item.text,
			Text:   item.text,
			Code:   item.code,
			Weight: item.weight,
			Exact:  item.code == e.rawInput,
		})
	}
	e.candidates = candidates
}

func (e *Engine) snapshot() engineapi.State {
	result := engineapi.State{RawInput: e.rawInput}
	if len(e.candidates) > 0 {
		result.Candidates = append([]engineapi.Candidate(nil), e.candidates...)
	}
	return result
}
