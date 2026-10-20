package keyboardlab

import (
	"errors"
	"fmt"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

const labPageSize = 9
const literalSource = "keyboard-lab:literal"

// keyboardEngine is the experiment's host adapter, not a dictionary or a
// change to YimeCore/Rime. It classifies printable keyboard characters and
// inserts one literal candidate into the view for a single coding symbol.
// The underlying engine still owns all dictionary candidates and their IDs.
type keyboardEngine struct {
	base             engineapi.Engine
	baseState        engineapi.State
	state            engineapi.State
	owners           map[string]int // visible dictionary candidate ID -> engine page
	modes            keyboardModes
	closeSingleQuote bool
	closeDoubleQuote bool
}

type keyboardModes struct {
	Input       string `json:"input"`
	Punctuation string `json:"punctuation"`
}

func (e *keyboardEngine) Modes() keyboardModes {
	if e.modes.Input == "" {
		e.modes.Input = "chinese"
	}
	if e.modes.Punctuation == "" {
		e.modes.Punctuation = "english"
	}
	return e.modes
}

// SetModes changes interpretation, never the underlying ASCII composition.
// A paused Chinese composition remains visible while English input is active.
func (e *keyboardEngine) SetModes(input, punctuation string) engineapi.Result {
	e.Modes()
	if input != "" {
		e.modes.Input = input
	}
	if punctuation != "" {
		e.modes.Punctuation = punctuation
	}
	e.refreshLiteralDisplay()
	return engineapi.Result{State: e.state}
}

// DirectLiteral is the side numeric area's bypass, also used for explicit
// Space/Enter text insertion in English mode. It cannot select, translate,
// append code, reset composition, or advance punctuation-pair state.
func (e *keyboardEngine) DirectLiteral(text string) engineapi.Result {
	return engineapi.Result{State: e.state, Commit: text}
}

// DirectSymbol is a reviewed main-key literal entrance, preserving composition.
func (e *keyboardEngine) DirectSymbol(text string) engineapi.Result {
	commit := e.punctuation(text, true)
	e.refreshLiteralDisplay()
	return engineapi.Result{State: e.state, Commit: commit}
}

func (e *keyboardEngine) Reset() engineapi.Result {
	result := e.base.Reset()
	e.baseState, e.state, e.owners = result.State, result.State, nil
	return result
}

func isCodingSymbol(raw string) bool {
	return len(raw) == 1 && isASCIIPunctuation(raw[0]) && strings.Contains(codemode.LayoutAlphabet, raw)
}

func isASCIIPunctuation(c byte) bool {
	return c >= '!' && c <= '/' || c >= ':' && c <= '@' || c >= '[' && c <= '`' || c >= '{' && c <= '~'
}

func (e *keyboardEngine) Apply(event engineapi.Event) (engineapi.Result, error) {
	switch event.Operation {
	case engineapi.AppendCode:
		if len(event.Code) != 1 || event.Code[0] < '!' || event.Code[0] > '~' || event.CandidateID != "" || event.SegmentStart != 0 || event.SegmentEnd != 0 {
			return engineapi.Result{}, engineapi.ErrInvalidEvent
		}
		character := event.Code[0]
		if e.Modes().Input == "english" {
			commit := e.punctuation(event.Code, true)
			e.refreshLiteralDisplay()
			return engineapi.Result{State: e.state, Commit: commit}, nil
		}
		if character >= '1' && character <= '9' && len(e.state.Candidates) > 0 {
			ordinal := int(character - '1')
			if ordinal >= len(e.state.Candidates) {
				return engineapi.Result{State: e.state}, nil
			}
			return e.Select(e.state.Candidates[ordinal].ID)
		}
		if !strings.Contains(codemode.LayoutAlphabet, event.Code) {
			return e.literal(event.Code)
		}
		if len(e.state.RawInput) >= maxInput {
			return engineapi.Result{}, errors.New("composition limit reached")
		}
	case engineapi.PageNext, engineapi.PagePrevious:
		if isCodingSymbol(e.state.RawInput) {
			page := e.state.PageNumber
			if event.Operation == engineapi.PageNext && e.state.HasNext {
				page++
			} else if event.Operation == engineapi.PagePrevious && e.state.HasPrevious {
				page--
			}
			return e.literalPage(page)
		}
	}
	result, err := e.base.Apply(event)
	if err != nil {
		return engineapi.Result{}, err
	}
	e.baseState, e.state, e.owners = result.State, result.State, nil
	if isCodingSymbol(result.State.RawInput) {
		return e.literalPage(0)
	}
	return result, nil
}

// literal is one externally atomic event: confirm the visible first candidate
// (when one exists), then append the literal to the same response commit. With
// unmatched input there is nothing to confirm: retain it and commit only the
// newly typed literal. Never silently submit or discard unmatched raw ASCII.
func (e *keyboardEngine) literal(text string) (engineapi.Result, error) {
	if len(e.state.Candidates) == 0 {
		return engineapi.Result{State: e.state, Commit: e.punctuation(text, true)}, nil
	}
	result, err := e.Select(e.state.Candidates[0].ID)
	if err != nil {
		return engineapi.Result{}, err
	}
	result.Commit += e.punctuation(text, true)
	return result, nil
}

func (e *keyboardEngine) Select(id string) (engineapi.Result, error) {
	var selected *engineapi.Candidate
	for index := range e.state.Candidates {
		if e.state.Candidates[index].ID == id {
			selected = &e.state.Candidates[index]
			break
		}
	}
	if selected == nil {
		return engineapi.Result{}, engineapi.ErrUnknownCandidate
	}
	if selected.SourceID == literalSource && selected.ID == literalID(e.state.RawInput) {
		text := e.punctuation(e.state.RawInput, true)
		result := e.Reset()
		result.Commit = text
		return result, nil
	}
	if page, exists := e.owners[id]; exists {
		if _, err := e.enginePage(page); err != nil {
			return engineapi.Result{}, err
		}
	}
	result, err := e.base.Select(id)
	if err == nil {
		e.baseState, e.state, e.owners = result.State, result.State, nil
	}
	return result, err
}

func literalID(raw string) string { return fmt.Sprintf("%s:%x", literalSource, raw) }

// This is an explicit experimental punctuation table, not a full-width mode.
// Unknown ASCII symbols stay unchanged. Pair state advances only on a commit,
// never on displaying, paging, switching modes, cancelling, or replaying one.
var chinesePunctuation = map[string]string{
	",": "，", ".": "。", ";": "；", ":": "：", "?": "？", "!": "！",
	"(": "（", ")": "）", "[": "【", "]": "】", "<": "《", ">": "》",
	"{": "『", "}": "』", "/": "、", "\\": "、", "^": "……", "_": "——",
}

func (e *keyboardEngine) punctuation(text string, commit bool) string {
	if e.Modes().Punctuation != "chinese" {
		return text
	}
	if text == "'" || text == "\"" {
		closing, opening, ending := &e.closeSingleQuote, "‘", "’"
		if text == "\"" {
			closing, opening, ending = &e.closeDoubleQuote, "“", "”"
		}
		result := opening
		if *closing {
			result = ending
		}
		if commit {
			*closing = !*closing
		}
		return result
	}
	if value, exists := chinesePunctuation[text]; exists {
		return value
	}
	return text
}

func (e *keyboardEngine) refreshLiteralDisplay() {
	// Copy before editing: prior response snapshots must remain immutable.
	e.state.Candidates = append([]engineapi.Candidate(nil), e.state.Candidates...)
	for index := range e.state.Candidates {
		candidate := &e.state.Candidates[index]
		if candidate.SourceID == literalSource {
			candidate.Text = e.punctuation(candidate.Code, false)
		}
	}
}

// enginePage moves only through native YimeCore pages. At most two adjacent
// pages are needed for a literal-augmented view; no full result set is loaded.
func (e *keyboardEngine) enginePage(page int) (engineapi.State, error) {
	for e.baseState.PageNumber != page {
		op := engineapi.PageNext
		if e.baseState.PageNumber > page {
			op = engineapi.PagePrevious
		} else if !e.baseState.HasNext {
			return engineapi.State{}, errors.New("dictionary page boundary")
		}
		before := e.baseState.PageNumber
		result, err := e.base.Apply(engineapi.Event{Operation: op})
		if err != nil {
			return engineapi.State{}, err
		}
		e.baseState = result.State
		if before == e.baseState.PageNumber {
			return engineapi.State{}, errors.New("dictionary page did not advance")
		}
	}
	return e.baseState, nil
}

func (e *keyboardEngine) literalPage(page int) (engineapi.Result, error) {
	var state engineapi.State
	owners := map[string]int{}
	if page == 0 {
		base, err := e.enginePage(0)
		if err != nil {
			return engineapi.Result{}, err
		}
		state = base
		count := min(len(base.Candidates), labPageSize-1)
		state.Candidates = append([]engineapi.Candidate(nil), base.Candidates[:count]...)
		for _, candidate := range state.Candidates {
			owners[candidate.ID] = 0
		}
		state.Candidates = append(state.Candidates, engineapi.Candidate{
			ID: literalID(base.RawInput), Text: e.punctuation(base.RawInput, false), Code: base.RawInput,
			SourceID: literalSource, Exact: true,
			Annotations: engineapi.CandidateAnnotations{KeySequence: base.RawInput},
		})
		state.HasNext = len(base.Candidates) > count
	} else {
		previous, err := e.enginePage(page - 1)
		if err != nil {
			return engineapi.Result{}, err
		}
		if len(previous.Candidates) != labPageSize {
			return engineapi.Result{}, errors.New("literal candidate page boundary")
		}
		state = previous
		carry := previous.Candidates[labPageSize-1]
		state.Candidates = []engineapi.Candidate{carry}
		owners[carry.ID] = page - 1
		state.HasNext = false
		if previous.HasNext {
			current, err := e.enginePage(page)
			if err != nil {
				return engineapi.Result{}, err
			}
			count := min(len(current.Candidates), labPageSize-1)
			state.Candidates = append(state.Candidates, current.Candidates[:count]...)
			for _, candidate := range current.Candidates[:count] {
				owners[candidate.ID] = page
			}
			state.HasNext = len(current.Candidates) > count
		}
	}
	state.PageNumber, state.HasPrevious = page, page > 0
	e.state, e.owners = state, owners
	return engineapi.Result{State: state}, nil
}
