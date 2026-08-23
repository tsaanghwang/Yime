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
	previousCommit string
	pageNumber     int
	hasNextPage    bool
	activeSegment  *engineapi.Segment
	segmentChoices map[segmentSpan]record
}

type segmentSpan struct {
	start int
	end   int
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

// NewBundleEngine constructs a session over an immutable core index and an
// explicitly selected set of reviewed E4 overlay indexes.
func NewBundleEngine(index *BundleIndex, candidateLimit int) (*Engine, error) {
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
		if event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		code, err := normalizeCode(event.Code)
		if err != nil || len(code) != len(event.Code) {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		if e.activeSegment != nil || len(e.segmentChoices) > 0 {
			e.clearSegmentEdits()
			e.resetSentenceComposer()
		}
		e.rawInput += code
		e.pageNumber = 0
	case engineapi.Backspace:
		if event.Code != "" || event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		if e.activeSegment != nil || len(e.segmentChoices) > 0 {
			e.clearSegmentEdits()
			e.resetSentenceComposer()
		}
		if len(e.rawInput) > 0 {
			e.rawInput = e.rawInput[:len(e.rawInput)-1]
		}
		e.pageNumber = 0
	case engineapi.Clear:
		if event.Code != "" || event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.rawInput = ""
		e.pageNumber = 0
		e.clearSegmentEdits()
		e.resetSentenceComposer()
	case engineapi.PageNext:
		if event.Code != "" || event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		if e.rawInput != "" && e.hasNextPage {
			e.pageNumber++
		}
	case engineapi.PagePrevious:
		if event.Code != "" || event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		if e.pageNumber > 0 {
			e.pageNumber--
		}
	case engineapi.FocusSegment:
		if event.Code != "" || event.CandidateID == "" || event.SegmentStart < 0 || event.SegmentEnd <= event.SegmentStart {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		var focused *engineapi.Segment
		for _, candidate := range e.candidates {
			if candidate.ID != event.CandidateID {
				continue
			}
			for i := range candidate.Segments {
				segment := candidate.Segments[i]
				if segment.Start == event.SegmentStart && segment.End == event.SegmentEnd {
					focused = &segment
					break
				}
			}
		}
		if focused == nil || focused.End > len(e.rawInput) {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.activeSegment = focused
		e.pageNumber = 0
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
			if e.activeSegment != nil {
				span := segmentSpan{start: e.activeSegment.Start, end: e.activeSegment.End}
				if e.segmentChoices == nil {
					e.segmentChoices = make(map[segmentSpan]record)
				}
				e.segmentChoices[span] = record{
					text: candidate.Text, code: candidate.Code, weight: candidate.Weight, source: candidate.SourceID,
				}
				e.activeSegment = nil
				e.pageNumber = 0
				e.hasNextPage = false
				e.resetSentenceComposer()
				e.refresh()
				return engineapi.Result{State: e.snapshot()}, nil
			}
			e.userModel.observeWithContext(candidate.Code, candidate.Text, e.previousCommit)
			e.previousCommit = candidate.Text
			e.rawInput = ""
			e.pageNumber = 0
			e.hasNextPage = false
			e.candidates = nil
			e.clearSegmentEdits()
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
	e.pageNumber = 0
	e.hasNextPage = false
	e.clearSegmentEdits()
	e.resetSentenceComposer()
	return engineapi.Result{State: e.snapshot()}
}

func (e *Engine) refresh() {
	if e.rawInput == "" {
		e.candidates = nil
		e.pageNumber = 0
		e.hasNextPage = false
		return
	}
	if e.activeSegment != nil {
		e.refreshSegmentCandidates()
		return
	}
	fetchLimit := (e.pageNumber+1)*e.limit + 1
	records := e.index.lookup(e.rawInput, fetchLimit)
	exactCandidates := make([]engineapi.Candidate, 0, fetchLimit)
	prefixCandidates := make([]engineapi.Candidate, 0, fetchLimit)
	seen := make(map[string]struct{}, fetchLimit)
	for _, item := range records {
		candidate := engineapi.Candidate{
			ID:       item.code + "\x1f" + item.text,
			Text:     item.text,
			Code:     item.code,
			SourceID: item.source,
			Weight:   item.weight,
			Exact:    item.code == e.rawInput,
		}
		e.scoreCandidate(&candidate)
		seen[candidate.Text+"\x1f"+candidate.Code] = struct{}{}
		if candidate.Exact {
			exactCandidates = append(exactCandidates, candidate)
		} else {
			prefixCandidates = append(prefixCandidates, candidate)
		}
	}
	for _, candidate := range e.composeSentences(e.rawInput, fetchLimit) {
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
	pool := make([]engineapi.Candidate, 0, fetchLimit)
	for _, group := range [][]engineapi.Candidate{exactCandidates, prefixCandidates} {
		for _, candidate := range group {
			pool = append(pool, candidate)
			if len(pool) == fetchLimit {
				break
			}
		}
		if len(pool) == fetchLimit {
			break
		}
	}
	start := e.pageNumber * e.limit
	if start >= len(pool) {
		if e.pageNumber > 0 {
			e.pageNumber--
			e.refresh()
			return
		}
		e.candidates = nil
		e.hasNextPage = false
		return
	}
	end := start + e.limit
	if end > len(pool) {
		end = len(pool)
	}
	e.candidates = append(e.candidates[:0], pool[start:end]...)
	e.hasNextPage = len(pool) > end
}

func (e *Engine) refreshSegmentCandidates() {
	segment := e.activeSegment
	if segment == nil || segment.Start < 0 || segment.End > len(e.rawInput) || segment.End <= segment.Start {
		e.activeSegment = nil
		e.candidates = nil
		e.hasNextPage = false
		return
	}
	fetchLimit := (e.pageNumber+1)*e.limit + 1
	records := e.index.exact(e.rawInput[segment.Start:segment.End], fetchLimit)
	pool := make([]engineapi.Candidate, 0, len(records))
	for _, item := range records {
		candidate := engineapi.Candidate{
			ID: item.code + "\x1f" + item.text, Text: item.text, Code: item.code,
			SourceID: item.source, Weight: item.weight, Exact: true,
		}
		e.scoreCandidate(&candidate)
		pool = append(pool, candidate)
	}
	rankCandidates(pool)
	start := e.pageNumber * e.limit
	if start >= len(pool) {
		if e.pageNumber > 0 {
			e.pageNumber--
			e.refreshSegmentCandidates()
			return
		}
		e.candidates = nil
		e.hasNextPage = false
		return
	}
	end := start + e.limit
	if end > len(pool) {
		end = len(pool)
	}
	e.candidates = append(e.candidates[:0], pool[start:end]...)
	e.hasNextPage = len(pool) > end
}

func (e *Engine) scoreCandidate(candidate *engineapi.Candidate) {
	candidate.Score.Static = candidate.Weight
	candidate.Score.Context = e.userModel.contextBoost(e.previousCommit, candidate.Code, candidate.Text)
	candidate.Score.User = e.userModel.candidateBoost(candidate.Code, candidate.Text)
	candidate.Score.Total = saturatingAdd(candidate.Score.Static, candidate.Score.Context)
	candidate.Score.Total = saturatingAdd(candidate.Score.Total, candidate.Score.User)
}

// ClearContext drops only the session's previous-commit context. It does not
// clear composition state or learned counts.
func (e *Engine) ClearContext() { e.previousCommit = "" }

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
	result := engineapi.State{
		RawInput: e.rawInput, PageNumber: e.pageNumber,
		HasPrevious: e.pageNumber > 0, HasNext: e.hasNextPage,
	}
	if e.activeSegment != nil {
		active := *e.activeSegment
		result.ActiveSegment = &active
	}
	if len(e.candidates) > 0 {
		result.Candidates = cloneCandidates(e.candidates)
	}
	return result
}

func (e *Engine) clearSegmentEdits() {
	e.activeSegment = nil
	e.segmentChoices = nil
}

func cloneCandidates(source []engineapi.Candidate) []engineapi.Candidate {
	result := append([]engineapi.Candidate(nil), source...)
	for i := range result {
		result[i].Segments = append([]engineapi.Segment(nil), result[i].Segments...)
	}
	return result
}
