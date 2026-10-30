package keyboardlab

import (
	"bytes"
	"fmt"
	"net/http"
	"reflect"
	"strings"
	"testing"
)

func TestEllipsisChoiceBothCodepointsModesAndCounts(t *testing.T) {
	for _, mode := range Modes() {
		for _, language := range []string{"chinese", "english"} {
			for _, count := range []int{3, 6} {
				for option, char := range []string{"…", "⋯"} {
					t.Run(fmt.Sprintf("%s/%s/%d/%d", mode, language, count, option), func(t *testing.T) {
						a := testLab(t)
						s := event(t, a, openSession(t, a, mode), "compose", "input", "p")
						s = setModes(t, a, s, "language", language, language)
						before := s.State
						for i := 0; i < count; i++ {
							s = event(t, a, s, fmt.Sprint("dot", i), "symbol", "·")
							if s.Commit != "" {
								t.Fatal("auto commit", s)
							}
						}
						if !s.SymbolChoice || len(s.State.Candidates) != 2 || s.State.HasNext || s.State.HasPrevious || s.State.RawInput != "p" {
							t.Fatal(s)
						}
						r := eventRequest{SessionID: s.SessionID, EventID: "pick", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[option].ID}
						first, retry := request(t, a, "/api/event", r), request(t, a, "/api/event", r)
						if first.Code != http.StatusOK || !bytes.Equal(first.Body.Bytes(), retry.Body.Bytes()) {
							t.Fatal(first.Body, retry.Body)
						}
						s = decodeResponse(t, first)
						if s.Commit != strings.Repeat(char, count/3) || s.SymbolChoice || s.PendingMiddleDots != 0 || !reflect.DeepEqual(s.State, before) {
							t.Fatal(s)
						}
					})
				}
			}
		}
	}
}

func TestEllipsisChoicesRejectStaleOrImplicitCommits(t *testing.T) {
	a := testLab(t)
	s := openSession(t, a, "variable")
	for i := 0; i < 3; i++ {
		s = event(t, a, s, fmt.Sprint("dot", i), "symbol", "·")
	}
	oldID := s.State.Candidates[0].ID
	s = event(t, a, s, "fourth", "symbol", "·")
	for i, r := range []eventRequest{{Type: "select", CandidateID: oldID}, {Type: "input", Code: "a"}, {Type: "symbol", Code: "!"}, {Type: "flushSymbols"}} {
		r.SessionID = s.SessionID
		r.BaseRevision = s.Revision
		r.EventID = fmt.Sprint("reject", i)
		w := request(t, a, "/api/event", r)
		observed := decodeResponse(t, w)
		if w.Code != 400 || observed.Commit != "" || !observed.SymbolChoice || observed.PendingMiddleDots != 4 || observed.Revision != s.Revision {
			t.Fatal(w.Body)
		}
	}
	s = event(t, a, s, "side", "literal", "7")
	if s.Commit != "7" || !s.SymbolChoice || s.PendingMiddleDots != 4 {
		t.Fatal(s)
	}
	// Explicit ordinal chooses only complete triples, retaining the fourth tap.
	s = event(t, a, s, "ordinal", "input", "2")
	if s.Commit != "⋯" || s.PendingMiddleDots != 1 || s.SymbolChoice {
		t.Fatal(s)
	}
	s = event(t, a, s, "clear", "clear", "")
	for i := 0; i < 6; i++ {
		s = event(t, a, s, fmt.Sprint("six", i), "symbol", "·")
	}
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, BaseRevision: s.Revision, EventID: "seventh", Type: "symbol", Code: "·"})
	if w.Code != 400 || decodeResponse(t, w).PendingMiddleDots != 6 {
		t.Fatal(w.Body)
	}
	s = event(t, a, s, "unavailable", "input", "9")
	if s.Commit != "" || s.PendingMiddleDots != 6 {
		t.Fatal(s)
	}
	s = event(t, a, s, "back", "backspace", "")
	if !s.SymbolChoice || s.PendingMiddleDots != 5 || s.State.Candidates[0].Text != "…" {
		t.Fatal(s)
	}
	s = setModes(t, a, s, "switch", "english", "english")
	if s.Commit != "" || s.SymbolChoice || s.PendingMiddleDots != 0 {
		t.Fatal(s)
	}
}

func TestEllipsisSelectionRestoresUnderlyingCandidatePage(t *testing.T) {
	a := testLab(t)
	s := event(t, a, openSession(t, a, "variable"), "compose-page", "input", "p")
	s = pageEvent(t, a, s, "page-next", 1)
	before := s.State
	if before.PageNumber != 1 || len(before.Candidates) < 2 {
		t.Fatal(before)
	}
	for i := 0; i < 3; i++ {
		s = event(t, a, s, fmt.Sprint("page-dot", i), "symbol", "·")
	}
	if !s.SymbolChoice || s.State.PageNumber != 0 || s.State.HasPrevious || s.State.HasNext {
		t.Fatal(s)
	}
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "page-symbol-select", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[0].ID})
	s = decodeResponse(t, w)
	if s.Commit != "…" || !reflect.DeepEqual(s.State, before) {
		t.Fatal("underlying page not restored", s)
	}
	w = request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "page-word-select", BaseRevision: s.Revision, Type: "select", CandidateID: before.Candidates[1].ID})
	s = decodeResponse(t, w)
	if !s.OK || s.Commit != before.Candidates[1].Text || s.State.RawInput != "" {
		t.Fatal(s)
	}
}
