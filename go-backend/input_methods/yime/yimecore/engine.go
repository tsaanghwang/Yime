package yimecore

import (
	"errors"
	"fmt"
	"sort"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
)

const defaultCandidateLimit = 9

// Engine is the E0 Go session implementation. It intentionally implements
// only deterministic code input and indexed candidate lookup.
type Engine struct {
	index             lookupIndex
	userLexiconBase   lookupIndex
	userLexiconPath   string
	userLexiconFile   lexiconFileSignature
	limit             int
	rawInput          string
	candidates        []engineapi.Candidate
	sentence          *engineapi.Candidate
	exactCache        map[string][]record
	sentenceInput     string
	sentenceStates    [][]sentencePath
	userModel         *UserModel
	previousCommit    string
	pageNumber        int
	hasNextPage       bool
	activeSegment     *engineapi.Segment
	focusedSentence   *engineapi.Candidate
	publishedSentence *engineapi.Candidate
	segmentChoices    map[segmentSpan]record
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

func NewBundleEngineWithUserModel(index *BundleIndex, candidateLimit int, model *UserModel) (*Engine, error) {
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

func (e *Engine) SetCandidateLimit(candidateLimit int) error {
	if candidateLimit < 5 || candidateLimit > 9 {
		return fmt.Errorf("candidate limit must be between 5 and 9")
	}
	if e.rawInput != "" {
		return errors.New("candidate limit cannot change during composition")
	}
	e.limit = candidateLimit
	return nil
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
		if e.rawInput == "" {
			if err := e.reloadUserLexiconIfChanged(); err != nil {
				return engineapi.Result{}, err
			}
		}
		if e.activeSegment != nil || len(e.segmentChoices) > 0 {
			e.activeSegment = nil
			e.focusedSentence = nil
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
		var sentence *engineapi.Candidate
		if e.focusedSentence != nil && e.focusedSentence.ID == event.CandidateID {
			copy := cloneCandidate(*e.focusedSentence)
			sentence = &copy
			for i := range copy.Segments {
				segment := copy.Segments[i]
				if segment.Start == event.SegmentStart && segment.End == event.SegmentEnd {
					focused = &segment
					break
				}
			}
		}
		if focused == nil && e.sentence != nil && e.sentence.ID == event.CandidateID {
			copy := cloneCandidate(*e.sentence)
			sentence = &copy
			for i := range copy.Segments {
				segment := copy.Segments[i]
				if segment.Start == event.SegmentStart && segment.End == event.SegmentEnd {
					focused = &segment
					break
				}
			}
		}
		for _, candidate := range e.candidates {
			if focused != nil {
				break
			}
			if candidate.ID != event.CandidateID {
				continue
			}
			for i := range candidate.Segments {
				segment := candidate.Segments[i]
				if segment.Start == event.SegmentStart && segment.End == event.SegmentEnd {
					focused = &segment
					copy := cloneCandidate(candidate)
					sentence = &copy
					break
				}
			}
		}
		if focused == nil && sentence != nil {
			if len(sentence.Segments) == 0 && event.SegmentStart == 0 &&
				event.SegmentEnd == len(e.rawInput) && sentence.Text != "" {
				focused = &engineapi.Segment{
					Start: 0, End: len(e.rawInput), Text: sentence.Text,
					Code: sentence.Code, SourceID: sentence.SourceID,
				}
			}
		}
		if focused == nil || focused.End > len(e.rawInput) {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.sentence = sentence
		e.seedLearnedSentenceChoices(sentence)
		e.activeSegment = focused
		e.focusedSentence = sentence
		e.pageNumber = 0
	case engineapi.ExpandSegment:
		if event.Code != "" || event.CandidateID == "" || event.SegmentStart < 0 || event.SegmentEnd <= event.SegmentStart {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		var sentence *engineapi.Candidate
		for _, candidate := range []*engineapi.Candidate{e.focusedSentence, e.sentence} {
			if candidate != nil && candidate.ID == event.CandidateID {
				copy := cloneCandidate(*candidate)
				sentence = &copy
				break
			}
		}
		if sentence == nil {
			for _, candidate := range e.candidates {
				if candidate.ID == event.CandidateID {
					copy := cloneCandidate(candidate)
					sentence = &copy
					break
				}
			}
		}
		var expanded *engineapi.Candidate
		var first *engineapi.Segment
		var ok bool
		if sentence != nil && len(sentence.Segments) == 0 {
			expanded, first, ok = e.expandExactWholeSentence(sentence, event.SegmentStart, event.SegmentEnd)
		} else if sentence != nil {
			for _, segment := range sentence.Segments {
				if segment.Start == event.SegmentStart && segment.End == event.SegmentEnd {
					expanded, first, ok = e.resegmentConstruction(sentence, segment)
					if !ok {
						expanded, first, ok = e.expandSentenceSegment(sentence, segment)
					}
					break
				}
			}
		}
		if !ok || expanded == nil || first == nil {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		e.sentence = expanded
		e.activeSegment = first
		e.focusedSentence = expanded
		e.pageNumber = 0
	default:
		return engineapi.Result{}, engineapi.ErrInvalidEvent
	}
	e.refresh()
	return engineapi.Result{State: e.snapshot()}, nil
}

func (e *Engine) seedLearnedSentenceChoices(sentence *engineapi.Candidate) {
	if sentence == nil || sentence.SourceID != "user-model" || len(sentence.Segments) < 2 ||
		len(e.segmentChoices) > 0 {
		return
	}
	choices := make(map[segmentSpan]record, len(sentence.Segments))
	for _, segment := range sentence.Segments {
		var selected *record
		for _, match := range e.exactMatches(segment.Code) {
			if match.text == segment.Text {
				copy := match
				selected = &copy
				break
			}
		}
		if selected == nil {
			return
		}
		choices[segmentSpan{start: segment.Start, end: segment.End}] = *selected
	}
	e.segmentChoices = choices
}

// Select commits a candidate from the current snapshot and clears the input.
func (e *Engine) Select(candidateID string) (engineapi.Result, error) {
	return e.selectCandidate(candidateID, "")
}

// SelectIdempotent commits at most one learning mutation for mutationID.
func (e *Engine) SelectIdempotent(candidateID, mutationID string) (engineapi.Result, error) {
	if mutationID == "" {
		return engineapi.Result{}, errors.New("mutation ID is required")
	}
	return e.selectCandidate(candidateID, mutationID)
}

func (e *Engine) selectCandidate(candidateID, mutationID string) (engineapi.Result, error) {
	if e.publishedSentence != nil && e.publishedSentence.ID == candidateID {
		return e.commitCandidate(*e.publishedSentence, mutationID)
	}
	if e.activeSegment != nil && e.focusedSentence != nil && e.focusedSentence.ID == candidateID {
		return e.commitCandidate(*e.focusedSentence, mutationID)
	}
	if e.activeSegment == nil && e.sentence != nil && e.sentence.ID == candidateID {
		return e.commitCandidate(*e.sentence, mutationID)
	}
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
				e.focusedSentence = nil
				return engineapi.Result{State: e.snapshot()}, nil
			}
			return e.commitCandidate(candidate, mutationID)
		}
	}
	return engineapi.Result{}, engineapi.ErrUnknownCandidate
}

// ForgetCandidate removes learned preference for a candidate in the current
// snapshot without committing or clearing the composition.
func (e *Engine) ForgetCandidate(candidateID string) (engineapi.Result, error) {
	var target *engineapi.Candidate
	if e.sentence != nil && e.sentence.ID == candidateID {
		copy := cloneCandidate(*e.sentence)
		target = &copy
	}
	if target == nil {
		for index := range e.candidates {
			if e.candidates[index].ID == candidateID {
				copy := cloneCandidate(e.candidates[index])
				target = &copy
				break
			}
		}
	}
	if target == nil {
		return engineapi.Result{}, engineapi.ErrUnknownCandidate
	}
	if _, err := e.userModel.ForgetWithError(target.Code, target.Text); err != nil {
		return engineapi.Result{}, fmt.Errorf("persist candidate forget: %w", err)
	}
	e.pageNumber = 0
	e.refresh()
	return engineapi.Result{State: e.snapshot()}, nil
}

func (e *Engine) commitCandidate(candidate engineapi.Candidate, mutationID string) (engineapi.Result, error) {
	observations := make([]UserObservation, 0, len(candidate.Segments)+1)
	if len(candidate.Segments) > 1 {
		previousText := e.previousCommit
		for _, segment := range candidate.Segments {
			observations = append(observations, UserObservation{
				Code: segment.Code, Text: segment.Text, PreviousText: previousText,
			})
			previousText = segment.Text
		}
	}
	observations = append(observations, UserObservation{
		Code: candidate.Code, Text: candidate.Text, PreviousText: e.previousCommit,
	})
	if err := e.userModel.observeBatchIdempotent(observations, mutationID); err != nil {
		return engineapi.Result{}, fmt.Errorf("persist user selection: %w", err)
	}
	e.previousCommit = candidate.Text
	e.rawInput = ""
	e.pageNumber = 0
	e.hasNextPage = false
	e.candidates = nil
	e.sentence = nil
	e.clearSegmentEdits()
	e.resetSentenceComposer()
	return engineapi.Result{State: e.snapshot(), Commit: candidate.Text}, nil
}

// Reset clears the session without producing a commit.
func (e *Engine) Reset() engineapi.Result {
	e.rawInput = ""
	e.candidates = nil
	e.sentence = nil
	e.pageNumber = 0
	e.hasNextPage = false
	e.clearSegmentEdits()
	e.resetSentenceComposer()
	return engineapi.Result{State: e.snapshot()}
}

func (e *Engine) refresh() {
	if e.rawInput == "" {
		e.candidates = nil
		e.sentence = nil
		e.pageNumber = 0
		e.hasNextPage = false
		return
	}
	if e.activeSegment != nil {
		e.refreshSegmentCandidates()
		return
	}
	fetchLimit := (e.pageNumber+1)*e.limit + 1
	exactRecords, restrictToSingleCharacter := e.firstSyllableExactRecords(e.rawInput, fetchLimit)
	lexicalExactCandidates := make([]engineapi.Candidate, 0, fetchLimit)
	seenExact := make(map[string]struct{}, len(exactRecords))
	for _, item := range exactRecords {
		candidate := engineapi.Candidate{
			ID: item.code + "\x1f" + item.text, Text: item.text, Code: item.code,
			SourceID: item.source, Weight: item.weight, Exact: true,
		}
		e.scoreCandidate(&candidate)
		lexicalExactCandidates = append(lexicalExactCandidates, candidate)
		seenExact[candidate.ID] = struct{}{}
	}
	for _, identity := range e.userModel.learnedCandidates(e.rawInput, fetchLimit) {
		if restrictToSingleCharacter && !isSingleCharacter(identity.text) {
			continue
		}
		candidate := engineapi.Candidate{
			ID: identity.code + "\x1f" + identity.text, Text: identity.text,
			Code: identity.code, SourceID: "user-model", Exact: true,
		}
		if _, exists := seenExact[candidate.ID]; exists {
			continue
		}
		e.scoreCandidate(&candidate)
		lexicalExactCandidates = append(lexicalExactCandidates, candidate)
	}
	rankCandidates(lexicalExactCandidates)
	e.sentence = e.bestSentence(lexicalExactCandidates, fetchLimit)
	pool := append([]engineapi.Candidate(nil), lexicalExactCandidates...)
	if len(pool) == 0 && (e.sentence == nil || !e.sentence.Exact) {
		records := e.sentencePrefixRecords(e.rawInput, fetchLimit)
		pool = make([]engineapi.Candidate, 0, len(records))
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
			pool = append(pool, candidate)
		}
	}
	rankCandidates(pool)
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
	segmentInput := e.rawInput[segment.Start:segment.End]
	records := e.index.exact(segmentInput, fetchLimit)
	if segment.End == len(e.rawInput) && segment.Code != segmentInput {
		records = e.index.lookup(segmentInput, fetchLimit)
	}
	pool := make([]engineapi.Candidate, 0, len(records))
	for _, item := range records {
		candidate := engineapi.Candidate{
			ID: item.code + "\x1f" + item.text, Text: item.text, Code: item.code,
			SourceID: item.source, Weight: item.weight, Exact: item.code == segmentInput,
		}
		e.scoreCandidate(&candidate)
		pool = append(pool, candidate)
	}
	rankCandidates(pool)
	for index := range pool {
		if pool[index].Text == segment.Text && pool[index].Code == segment.Code {
			selected := pool[index]
			copy(pool[1:index+1], pool[:index])
			pool[0] = selected
			break
		}
	}
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
	e.scoreCandidateWithContext(candidate, 0)
}

func (e *Engine) scoreCandidateWithContext(candidate *engineapi.Candidate, sentenceContext int64) {
	candidate.Score.Static = candidate.Weight
	candidate.Score.Context = saturatingAdd(sentenceContext,
		e.userModel.contextBoost(e.previousCommit, candidate.Code, candidate.Text))
	candidate.Score.User = e.userModel.candidateBoost(candidate.Code, candidate.Text)
	candidate.Score.Total = saturatingAdd(candidate.Score.Static, candidate.Score.Context)
	candidate.Score.Total = saturatingAdd(candidate.Score.Total, candidate.Score.User)
}

// ClearContext drops only the session's previous-commit context. It does not
// clear composition state or learned counts.
func (e *Engine) ClearContext() { e.previousCommit = "" }

func rankCandidates(candidates []engineapi.Candidate) {
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].Exact != candidates[j].Exact {
			return candidates[i].Exact
		}
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

func rankGeneratedCandidates(candidates []engineapi.Candidate) {
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].Exact != candidates[j].Exact {
			return candidates[i].Exact
		}
		if len(candidates[i].Segments) > 1 && len(candidates[j].Segments) > 1 {
			if priority := compareWordFirstSegments(candidates[i].Segments, candidates[j].Segments); priority != 0 {
				return priority > 0
			}
		}
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
	if e.sentence != nil {
		sentence := cloneCandidate(*e.sentence)
		result.Sentence = &sentence
	} else if e.focusedSentence != nil {
		sentence := cloneCandidate(*e.focusedSentence)
		result.Sentence = &sentence
	}
	if result.Sentence != nil {
		sentence := cloneCandidate(*result.Sentence)
		e.publishedSentence = &sentence
	} else {
		e.publishedSentence = nil
	}
	return result
}

func (e *Engine) clearSegmentEdits() {
	e.activeSegment = nil
	e.focusedSentence = nil
	e.segmentChoices = nil
}

func cloneCandidates(source []engineapi.Candidate) []engineapi.Candidate {
	result := append([]engineapi.Candidate(nil), source...)
	for i := range result {
		result[i] = cloneCandidate(result[i])
	}
	return result
}

func cloneCandidate(source engineapi.Candidate) engineapi.Candidate {
	source.Segments = append([]engineapi.Segment(nil), source.Segments...)
	return source
}
