package keyboardlab

import (
	"bytes"
	"fmt"
	"net/http"
	"reflect"
	"testing"
)

func TestMiddleDotTriplesPreserveCompositionAndRetry(t *testing.T) {
	for _, mode := range Modes() {
		t.Run(mode, func(t *testing.T) {
			a := testLab(t)
			s := event(t, a, openSession(t, a, mode), "compose", "input", "p")
			before := s.State
			for i := 1; i <= 6; i++ {
				r := eventRequest{SessionID: s.SessionID, EventID: fmt.Sprint("dot", i), BaseRevision: s.Revision, Type: "symbol", Code: "·"}
				first, retry := request(t, a, "/api/event", r), request(t, a, "/api/event", r)
				if first.Code != http.StatusOK || !bytes.Equal(first.Body.Bytes(), retry.Body.Bytes()) {
					t.Fatalf("tap/retry %d: %s / %s", i, first.Body, retry.Body)
				}
				s = decodeResponse(t, first)
				if s.Commit != "" || s.PendingMiddleDots != i || s.State.RawInput != before.RawInput || s.SymbolChoice != (i >= 3) {
					t.Fatalf("tap%d state/commit: %+v", i, s)
				}
			}
			if len(s.State.Candidates) != 2 || s.State.Candidates[0].Text != "……" || s.State.Candidates[1].Text != "⋯⋯" {
				t.Fatal(s)
			}
			w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "choose", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[1].ID})
			s = decodeResponse(t, w)
			if !s.OK || s.Commit != "⋯⋯" || s.PendingMiddleDots != 0 || s.SymbolChoice || !reflect.DeepEqual(s.State, before) {
				t.Fatal(s)
			}
		})
	}
}

func TestMiddleDotBufferEditingBoundariesAndLiteralIsolation(t *testing.T) {
	a := testLab(t)
	s := event(t, a, openSession(t, a, "variable"), "compose", "input", "p")
	s = event(t, a, s, "dot1", "symbol", "·")
	s = event(t, a, s, "dot2", "symbol", "·")
	s = event(t, a, s, "back", "backspace", "")
	if s.PendingMiddleDots != 1 || s.State.RawInput != "p" || s.Commit != "" {
		t.Fatal(s)
	}
	s = event(t, a, s, "side", "literal", "7")
	if s.Commit != "7" || s.PendingMiddleDots != 1 || s.State.RawInput != "p" {
		t.Fatal(s)
	}
	s = event(t, a, s, "main", "symbol", "!")
	if s.Commit != "·!" || s.PendingMiddleDots != 0 || s.State.RawInput != "p" {
		t.Fatal(s)
	}
	s = event(t, a, s, "dot3", "symbol", "·")
	s = event(t, a, s, "clear", "clear", "")
	if s.PendingMiddleDots != 0 || s.State.RawInput != "" || s.Commit != "" {
		t.Fatal(s)
	}
	s = event(t, a, s, "dot4", "symbol", "·")
	s = setModes(t, a, s, "en", "english", "english")
	if s.PendingMiddleDots != 0 || s.Commit != "" {
		t.Fatal(s)
	}
	s = event(t, a, s, "dot5", "symbol", "·")
	s = event(t, a, s, "en-text", "input", "a")
	if s.Commit != "·a" || s.PendingMiddleDots != 0 {
		t.Fatal(s)
	}
	s = event(t, a, s, "dot6", "symbol", "·")
	s = event(t, a, s, "flush", "flushSymbols", "")
	if s.Commit != "·" || s.PendingMiddleDots != 0 {
		t.Fatal(s)
	}
	s = event(t, a, s, "dot7", "symbol", "·")
	s = event(t, a, s, "close", "close", "")
	if s.Commit != "" || s.PendingMiddleDots != 0 {
		t.Fatal(s)
	}
}

func TestRejectedDotMutationAndCandidateConfirmation(t *testing.T) {
	a := testLab(t)
	s := event(t, a, openSession(t, a, "variable"), "compose", "input", "p")
	s = event(t, a, s, "dot", "symbol", "·")
	// A client cannot inject the newly produced Unicode symbol as an entrance.
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "invalid", BaseRevision: s.Revision, Type: "symbol", Code: "⋯"})
	if w.Code != http.StatusBadRequest {
		t.Fatal(w.Code)
	}
	w = request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "stale", BaseRevision: s.Revision - 1, Type: "symbol", Code: "·"})
	if w.Code != http.StatusConflict || decodeResponse(t, w).PendingMiddleDots != 1 {
		t.Fatal(w.Body)
	}
	id, text := s.State.Candidates[0].ID, s.State.Candidates[0].Text
	w = request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "select", BaseRevision: s.Revision, Type: "select", CandidateID: id})
	s = decodeResponse(t, w)
	if !s.OK || s.Commit != "·"+text || s.PendingMiddleDots != 0 || s.State.RawInput != "" {
		t.Fatal(s)
	}
}
