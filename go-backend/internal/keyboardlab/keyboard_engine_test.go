package keyboardlab

import (
	"bytes"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

func pageEvent(t *testing.T, a *lab, s response, id string, delta int) response {
	t.Helper()
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: id, BaseRevision: s.Revision, Type: "page", Delta: delta})
	if w.Code != 200 {
		t.Fatalf("page: %d %s", w.Code, w.Body.String())
	}
	return decodeResponse(t, w)
}

func codingSymbols() []string {
	var symbols []string
	for _, c := range codemode.LayoutAlphabet {
		if isASCIIPunctuation(byte(c)) {
			symbols = append(symbols, string(c))
		}
	}
	return symbols
}

func nonCodingSymbol(t *testing.T) string {
	t.Helper()
	for c := byte('!'); c <= '~'; c++ {
		if isASCIIPunctuation(c) && !strings.ContainsRune(codemode.LayoutAlphabet, rune(c)) {
			return string(c)
		}
	}
	t.Fatal("fixture requires at least one non-coding ASCII symbol")
	return ""
}

func TestPrintableCharactersClassifiedAtServer(t *testing.T) {
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			a := testLab(t)
			s := openSession(t, a, mode)
			sequence := 0
			input := func(code string) {
				sequence++
				s = event(t, a, s, fmt.Sprint(sequence), "input", code)
			}
			for character := byte('!'); character <= '~'; character++ {
				code := string(character)
				if strings.Contains(codemode.LayoutAlphabet, code) {
					continue
				}
				input(code)
				if s.Commit != code || s.State.RawInput != "" {
					t.Fatalf("idle literal %q: %+v", code, s)
				}
				input("q") // no fixture matches; a literal must not lose this raw input
				input(code)
				if s.Commit != code || s.State.RawInput != "q" || len(s.State.Candidates) != 0 {
					t.Fatalf("unmatched literal %q: %+v", code, s)
				}
				sequence++
				s = event(t, a, s, fmt.Sprint(sequence), "clear", "")
				input("a")
				input(code)
				if character >= '2' && character <= '9' {
					if s.Commit != "" || s.State.RawInput != "a" {
						t.Fatalf("nonexistent ordinal %q was not no-op: %+v", code, s)
					}
					sequence++
					s = event(t, a, s, fmt.Sprint(sequence), "clear", "")
				} else {
					want := "小写" + code
					if character == '1' {
						want = "小写"
					}
					if s.Commit != want || s.State.RawInput != "" {
						t.Fatalf("pending literal %q: want %q, got %+v", code, want, s)
					}
				}
			}
		})
	}
}

func TestLiteralSymbolCandidatesKeepAllDictionaryCandidatesAndStablePages(t *testing.T) {
	for _, symbol := range codingSymbols() {
		for _, count := range []int{0, 1, 8, 9, 10, 18, 19, 27} {
			t.Run(fmt.Sprintf("%x/%d", symbol, count), func(t *testing.T) {
				var records strings.Builder
				var original []string
				for i := 0; i < count; i++ {
					text := fmt.Sprintf("符号候选%d", i)
					fmt.Fprintf(&records, "%s\t%s\t%d\n", text, symbol, 100-i)
					original = append(original, text)
				}
				a := testLabWithRecords(t, records.String())
				s := event(t, a, openSession(t, a, "variable"), "symbol", "input", symbol)
				firstPage := s.State
				last := s.State.Candidates[len(s.State.Candidates)-1]
				if last.Text != symbol || last.SourceID != literalSource || len(s.State.Candidates) != min(count+1, 9) {
					t.Fatalf("literal is not last on first page: %+v", s.State)
				}
				var actual []string
				seen := map[string]bool{}
				for page := 0; ; page++ {
					if s.State.PageNumber != page || len(s.State.Candidates) > 9 || s.State.HasPrevious != (page > 0) {
						t.Fatalf("page state: %+v", s.State)
					}
					for _, candidate := range s.State.Candidates {
						if seen[candidate.ID] {
							t.Fatalf("duplicate candidate %q", candidate.ID)
						}
						seen[candidate.ID] = true
						actual = append(actual, candidate.Text)
					}
					if !s.State.HasNext {
						break
					}
					s = pageEvent(t, a, s, fmt.Sprintf("next%d", page), 1)
				}
				position := min(count, 8)
				want := append([]string(nil), original[:position]...)
				want = append(want, symbol)
				want = append(want, original[position:]...)
				if !reflect.DeepEqual(actual, want) {
					t.Fatalf("candidate order changed: got %v want %v", actual, want)
				}
				for s.State.HasPrevious {
					s = pageEvent(t, a, s, fmt.Sprintf("previous%d", s.State.PageNumber), -1)
				}
				if !reflect.DeepEqual(firstPage, s.State) {
					t.Fatalf("page round trip changed stable IDs/state")
				}
				// The final ordinal on the first page submits the symbol, not an engine candidate.
				s = event(t, a, s, "literal-select", "input", fmt.Sprint(len(s.State.Candidates)))
				if s.Commit != symbol || s.State.RawInput != "" {
					t.Fatalf("literal selection: %+v", s)
				}
			})
		}
	}
}

func TestLiteralSymbolOverlayOnlyForExactlyOneCodeCharacter(t *testing.T) {
	for _, mode := range modes {
		a := testLab(t)
		for _, symbol := range codingSymbols() {
			s := event(t, a, openSession(t, a, mode), "symbol", "input", symbol)
			if len(s.State.Candidates) != 1 || s.State.Candidates[0].Text != symbol {
				t.Fatalf("single symbol missing: %+v", s)
			}
			s = event(t, a, s, "append", "input", "q")
			if s.State.RawInput != symbol+"q" || len(s.State.Candidates) != 0 {
				t.Fatalf("literal leaked into mixed code: %+v", s)
			}
			s = event(t, a, s, "erase", "backspace", "")
			if len(s.State.Candidates) != 1 || s.State.Candidates[0].Text != symbol {
				t.Fatalf("backspace did not restore literal: %+v", s)
			}
			s = event(t, a, s, "prefix", "input", "'")
			if len(s.State.Candidates) != 0 {
				t.Fatalf("literal leaked into symbol sequence: %+v", s)
			}
			event(t, a, s, "close", "close", "")
		}
	}
}

func TestOffsetCandidateSelectionAndLiteralRetriesAreAtomic(t *testing.T) {
	punct := nonCodingSymbol(t)
	var records strings.Builder
	for i := 0; i < 18; i++ {
		fmt.Fprintf(&records, "候选%d\t[\t%d\n", i, 100-i)
	}
	a := testLabWithRecords(t, records.String())
	for _, ordinal := range []string{"1", "9"} {
		s := event(t, a, openSession(t, a, "full"), "input", "input", "[")
		oldID := s.State.Candidates[8].ID
		s = pageEvent(t, a, s, "next", 1)
		if w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "old-page", BaseRevision: s.Revision, Type: "select", CandidateID: oldID}); w.Code != 400 {
			t.Fatalf("off-page literal selected: %d", w.Code)
		}
		want := s.State.Candidates[int(ordinal[0]-'1')].Text
		s = event(t, a, s, "choose", "input", ordinal)
		if s.Commit != want || s.State.RawInput != "" {
			t.Fatalf("offset candidate not selected: %+v", s)
		}
	}
	s := event(t, a, openSession(t, a, "full"), "raw", "input", "[")
	s = pageEvent(t, a, s, "next", 1)
	want := s.State.Candidates[0].Text + punct
	s = event(t, a, s, "punctuation", "input", punct)
	if s.Commit != want || s.State.RawInput != "" {
		t.Fatalf("offset visible first candidate plus punctuation: %+v", s)
	}
	s = event(t, a, s, "restart", "input", "[")
	s = pageEvent(t, a, s, "next-again", 1)
	s = event(t, a, s, "append-on-page", "input", "q")
	if s.State.RawInput != "[q" || s.State.PageNumber != 0 || len(s.State.Candidates) != 0 {
		t.Fatalf("append did not remove offset view: %+v", s)
	}
	s = event(t, a, s, "restore-symbol", "backspace", "")
	if s.State.PageNumber != 0 || s.State.Candidates[8].SourceID != literalSource {
		t.Fatalf("backspace did not restore first literal page: %+v", s)
	}
	want = s.State.Candidates[0].Text
	s = event(t, a, s, "select-after-restore", "input", "1")
	if s.Commit != want || s.State.RawInput != "" {
		t.Fatalf("stale offset owner after input reset: %+v", s)
	}
	for _, tc := range []struct{ raw, input, want string }{{"a", punct, "小写" + punct}, {"[", "9", "["}, {"q", "1", "1"}, {"a", "9", ""}} {
		s := event(t, a, openSession(t, a, "shorthand"), "raw", "input", tc.raw)
		req := eventRequest{SessionID: s.SessionID, EventID: "literal", BaseRevision: s.Revision, Type: "input", Code: tc.input}
		first, retry := request(t, a, "/api/event", req), request(t, a, "/api/event", req)
		if first.Code != 200 || !bytes.Equal(first.Body.Bytes(), retry.Body.Bytes()) {
			t.Fatalf("retry changed result: %s / %s", first.Body.String(), retry.Body.String())
		}
		result := decodeResponse(t, first)
		if result.Commit != tc.want || result.Revision != s.Revision+1 {
			t.Fatalf("atomic commit/revision: %+v", result)
		}
		// A subsequent event sees the once-applied result, not a second confirmation.
		result = event(t, a, result, "following", "input", "0")
		want := "0"
		if tc.input == "9" && tc.raw == "a" {
			want = "小写0"
		}
		if result.Commit != want {
			t.Fatalf("duplicate effect: %+v", result)
		}
	}
}

func TestCompositionLimitDoesNotBlockSelectionOrLiterals(t *testing.T) {
	punct := nonCodingSymbol(t)
	a := testLabWithRecords(t, "长码\t"+strings.Repeat("a", maxInput)+"\t100\n")
	for _, tc := range []struct{ code, input, want string }{
		{"q", "0", "0"}, {"q", "1", "1"}, {"q", punct, punct},
		{"a", "0", "长码0"}, {"a", "1", "长码"}, {"a", punct, "长码" + punct},
	} {
		code := tc.code
		s := openSession(t, a, "full")
		for i := 0; i < maxInput; i++ {
			s = event(t, a, s, fmt.Sprint(i), "input", code)
		}
		if len(s.State.RawInput) != maxInput {
			t.Fatal("fixture did not reach input limit")
		}
		w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "overflow", BaseRevision: s.Revision, Type: "input", Code: code})
		if w.Code != 400 {
			t.Fatal("coding input exceeded bound")
		}
		s = event(t, a, s, "literal-at-limit", "input", tc.input)
		if code == "q" {
			if s.Commit != tc.want || s.State.RawInput != strings.Repeat("q", maxInput) {
				t.Fatalf("unmatched raw lost: %+v", s)
			}
		} else if s.Commit != tc.want || s.State.RawInput != "" {
			t.Fatalf("literal confirmation blocked: %+v", s)
		}
	}
}
