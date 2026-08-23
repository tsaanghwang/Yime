// Package engineapi defines the host-neutral contract used by candidate
// engines during the YimeCore replacement experiment.
package engineapi

import "errors"

// Operation identifies a host-neutral input state transition.
type Operation uint8

const (
	AppendCode Operation = iota + 1
	Backspace
	Clear
	PageNext
	PagePrevious
)

var (
	ErrInvalidEvent     = errors.New("invalid engine event")
	ErrUnknownCandidate = errors.New("candidate is not present in the current snapshot")
)

// Event carries an operation into an engine session. Code is required only
// for AppendCode. Candidate selection deliberately uses stable candidate IDs
// through Engine.Select instead of host window ordinals.
type Event struct {
	Operation Operation `json:"operation"`
	Code      string    `json:"code,omitempty"`
}

// Candidate is a host-neutral candidate returned by an engine. ID must stay
// stable for the lifetime of the current input state. Labels such as Shift+1
// are a text-service concern and never enter this contract.
type Candidate struct {
	ID       string    `json:"id"`
	Text     string    `json:"text"`
	Code     string    `json:"code"`
	SourceID string    `json:"source_id,omitempty"`
	Weight   int64     `json:"weight"`
	Exact    bool      `json:"exact"`
	Segments []Segment `json:"segments,omitempty"`
	Score    Score     `json:"score"`
}

// Score keeps the experiment's ranking inputs auditable. Static comes from
// the immutable index, Context is reserved for E3 contextual ranking, and
// User comes only from the independent user model.
type Score struct {
	Static  int64 `json:"static"`
	Context int64 `json:"context"`
	User    int64 `json:"user"`
	Total   int64 `json:"total"`
}

// Segment explains one position-preserving dictionary edge used to build a
// generated sentence. Start and End are byte offsets in the raw ASCII input.
type Segment struct {
	Start    int    `json:"start"`
	End      int    `json:"end"`
	Text     string `json:"text"`
	Code     string `json:"code"`
	SourceID string `json:"source_id"`
}

// State is a point-in-time engine snapshot.
type State struct {
	RawInput    string      `json:"raw_input"`
	Candidates  []Candidate `json:"candidates,omitempty"`
	PageNumber  int         `json:"page_number,omitempty"`
	HasPrevious bool        `json:"has_previous,omitempty"`
	HasNext     bool        `json:"has_next,omitempty"`
}

// Result combines the durable state after a transition with an ephemeral
// commit. A non-empty Commit is consumed by the text-service adapter.
type Result struct {
	State  State  `json:"state"`
	Commit string `json:"commit,omitempty"`
}

// Engine is intentionally independent from PIME requests, Rime sessions,
// Windows handles, IPC messages and physical candidate labels.
//
// Implementations are session-scoped. Callers must serialize Apply, Select
// and Reset calls for one Engine instance.
type Engine interface {
	Apply(Event) (Result, error)
	Select(candidateID string) (Result, error)
	Reset() Result
}
