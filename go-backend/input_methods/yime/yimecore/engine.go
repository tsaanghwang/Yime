package yimecore

import (
	"fmt"
	"sort"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const defaultCandidateLimit = 9

// Engine is the E0 Go session implementation. It intentionally implements
// only deterministic code input and indexed candidate lookup.
type Engine struct {
	index          lookupIndex
	limit          int
	rawInput       string
	candidates     []engineapi.Candidate
	exactCache     map[string][]record
	sentenceInput  string
	sentenceStates [][]sentencePath
	userModel      *UserModel
}

type lookupIndex interface {
	lookup(prefix string, limit int) []record
	exact(code string, limit int) []record
	maximumCodeBytes() int
	identity() string
}

var _ engineapi.Engine = (*Engine)(nil)

// NewEngine constructs an isolated engine session.
func NewEngine(index *Index, candidateLimit int) (*Engine, error) {
	return newEngine(index, candidateLimit)
}

// NewFileEngine constructs a session over a validated compact E1 index.
func NewFileEngine(index *FileIndex, candidateLimit int) (*Engine, error) {
	return newEngine(index, candidateLimit)
}

// NewFileEngineWithUserModel enables E3 selection learning without changing
// or coupling the immutable static index to the user data file.
func NewFileEngineWithUserModel(index *FileIndex, candidateLimit int, model *UserModel) (*Engine, error) {
	engine, err := newEngine(index, candidateLimit)
	if err != nil {
		return nil, err
	}
	if model == nil {
		return nil, fmt.Errorf("user model is required")
	}
	engine.userModel = model
	return engine, nil
}

// NewEngineWithUserModel is the in-memory-index counterpart used by focused
// deterministic learning tests.
func NewEngineWithUserModel(index *Index, candidateLimit int, model *UserModel) (*Engine, error) {
	engine, err := newEngine(index, candidateLimit)
	if err != nil {
		return nil, err
	}
	if model == nil {
		return nil, fmt.Errorf("user model is required")
	}
	engine.userModel = model
	return engine, nil
}

func newEngine(index lookupIndex, candidateLimit int) (*Engine, error) {
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
		e.resetSentenceComposer()
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
			e.userModel.observe(candidate.Code, candidate.Text)
			e.rawInput = ""
			e.candidates = nil
			e.resetSentenceComposer()
			return engineapi.Result{State: e.snapshot(), Commit: candidate.Text}, nil
		}
	}
	return engineapi.Result{}, engineapi.ErrUnknownCandidate
}

// Reset clears the session without producing a commit.
func (e *Engine) Reset() engineapi.Result {
	e.rawInput = ""
	e.candidates = nil
	e.resetSentenceComposer()
	return engineapi.Result{State: e.snapshot()}
}

func (e *Engine) refresh() {
	if e.rawInput == "" {
		e.candidates = nil
		return
	}
	records := e.index.lookup(e.rawInput, e.limit)
	exactCandidates := make([]engineapi.Candidate, 0, e.limit)
	prefixCandidates := make([]engineapi.Candidate, 0, e.limit)
	seen := make(map[string]struct{}, e.limit)
	for _, item := range records {
		candidate := engineapi.Candidate{
			ID:     item.code + "\x1f" + item.text,
			Text:   item.text,
			Code:   item.code,
			Weight: item.weight,
			Exact:  item.code == e.rawInput,
		}
		e.scoreCandidate(&candidate)
		seen[candidate.Text+"\x1f"+candidate.Code] = struct{}{}
		if candidate.Exact {
			exactCandidates = append(exactCandidates, candidate)
		} else {
			prefixCandidates = append(prefixCandidates, candidate)
		}
	}
	for _, candidate := range e.composeSentences(e.rawInput, e.limit) {
		key := candidate.Text + "\x1f" + candidate.Code
		if _, exists := seen[key]; exists {
			continue
		}
		e.scoreCandidate(&candidate)
		exactCandidates = append(exactCandidates, candidate)
		seen[key] = struct{}{}
	}
	rankCandidates(exactCandidates)
	rankCandidates(prefixCandidates)
	candidates := make([]engineapi.Candidate, 0, e.limit)
	for _, group := range [][]engineapi.Candidate{exactCandidates, prefixCandidates} {
		for _, candidate := range group {
			candidates = append(candidates, candidate)
			if len(candidates) == e.limit {
				e.candidates = candidates
				return
			}
		}
	}
	e.candidates = candidates
}

func (e *Engine) scoreCandidate(candidate *engineapi.Candidate) {
	candidate.Score.Static = candidate.Weight
	candidate.Score.User = e.userModel.candidateBoost(candidate.Code, candidate.Text)
	candidate.Score.Total = saturatingAdd(candidate.Score.Static, candidate.Score.Context)
	candidate.Score.Total = saturatingAdd(candidate.Score.Total, candidate.Score.User)
}

func rankCandidates(candidates []engineapi.Candidate) {
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].Score.Total != candidates[j].Score.Total {
			return candidates[i].Score.Total > candidates[j].Score.Total
		}
		if candidates[i].Weight != candidates[j].Weight {
			return candidates[i].Weight > candidates[j].Weight
		}
		if candidates[i].Text != candidates[j].Text {
			return candidates[i].Text < candidates[j].Text
		}
		return candidates[i].ID < candidates[j].ID
	})
}

func (e *Engine) snapshot() engineapi.State {
	result := engineapi.State{RawInput: e.rawInput}
	if len(e.candidates) > 0 {
		result.Candidates = cloneCandidates(e.candidates)
	}
	return result
}

func cloneCandidates(source []engineapi.Candidate) []engineapi.Candidate {
	result := append([]engineapi.Candidate(nil), source...)
	for i := range result {
		result[i].Segments = append([]engineapi.Segment(nil), result[i].Segments...)
	}
	return result
}
