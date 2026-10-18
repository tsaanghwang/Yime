package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func setModes(t *testing.T, a *lab, s response, id, input, punctuation string) response {
	t.Helper()
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: id, BaseRevision: s.Revision, Type: "setModes", InputMode: input, PunctuationMode: punctuation})
	if w.Code != 200 {
		t.Fatalf("setModes: %d %s", w.Code, w.Body.String())
	}
	return decodeResponse(t, w)
}

func TestIndependentModesAndLiteralBypassPreservePausedComposition(t *testing.T) {
	for _, mode := range modes {
		a := testLab(t)
		s := openSession(t, a, mode)
		if s.Modes != (keyboardModes{"chinese", "english"}) {
			t.Fatalf("defaults: %+v", s.Modes)
		}
		s = event(t, a, s, "compose", "input", "p")
		s = pageEvent(t, a, s, "next", 1)
		before := s.State
		s = setModes(t, a, s, "input-mode", "english", "")
		if !reflect.DeepEqual(s.State, before) || s.Commit != "" || s.Modes.Punctuation != "english" {
			t.Fatalf("switch changed composition: %+v", s)
		}
		for i, c := range "aAzZ019!" {
			s = event(t, a, s, fmt.Sprintf("english%d", i), "input", string(c))
			if s.Commit != string(c) || !reflect.DeepEqual(s.State, before) {
				t.Fatalf("English input changed case or composition: %+v", s)
			}
		}
		s = setModes(t, a, s, "punct-mode", "", "chinese")
		s = event(t, a, s, "chinese-punctuation", "input", "!")
		if s.Commit != "！" || s.Modes.Input != "english" || !reflect.DeepEqual(s.State, before) {
			t.Fatalf("modes coupled: %+v", s)
		}
		for i, code := range []string{"1", "0", ".", "/", "*", "+", "-", "=", "'", "\"", " ", "\n", "\t"} {
			s = event(t, a, s, fmt.Sprintf("bypass%d", i), "literal", code)
			if s.Commit != code || !reflect.DeepEqual(s.State, before) {
				t.Fatalf("literal bypass translated, selected or cleared: %+v", s)
			}
		}
		s = setModes(t, a, s, "resume", "chinese", "")
		if s.Modes.Punctuation != "chinese" || !reflect.DeepEqual(s.State, before) {
			t.Fatalf("resume changed state: %+v", s)
		}
		want := s.State.Candidates[0].Text
		s = event(t, a, s, "select", "input", "1")
		if s.Commit != want || s.State.RawInput != "" {
			t.Fatalf("resumed selection: %+v", s)
		}
	}
}

func TestAllCarrierSymbolsStayASCIIAndExposeLiteralInBothPunctuationModes(t *testing.T) {
	if len(codemode.LayoutAlphabet) != 75 || len(codingSymbols()) != 23 {
		t.Fatalf("expected 75 independent carriers with 23 symbols, got %d/%d", len(codemode.LayoutAlphabet), len(codingSymbols()))
	}
	wantChinese := map[string]string{",": "，", ".": "。", ";": "；", ":": "：", "?": "？", "!": "！", "(": "（", ")": "）", "[": "【", "]": "】", "<": "《", ">": "》", "{": "『", "}": "』", "/": "、", "\\": "、", "^": "……", "_": "——", "'": "‘", "\"": "“"}
	for _, punctuation := range []string{"english", "chinese"} {
		a := testLab(t)
		for _, symbol := range codingSymbols() {
			s := setModes(t, a, openSession(t, a, "variable"), "modes", "", punctuation)
			s = event(t, a, s, "code", "input", symbol)
			want := symbol
			if punctuation == "chinese" {
				if value, ok := wantChinese[symbol]; ok {
					want = value
				}
			}
			last := s.State.Candidates[len(s.State.Candidates)-1]
			if s.State.RawInput != symbol || last.Code != symbol || last.Text != want || s.Commit != "" {
				t.Fatalf("%s %q code/transformed candidate: %+v", punctuation, symbol, s)
			}
			s = event(t, a, s, "choose", "input", fmt.Sprint(len(s.State.Candidates)))
			if s.Commit != want || s.State.RawInput != "" {
				t.Fatalf("literal commit: %+v", s)
			}
			event(t, a, s, "close", "close", "")
		}
	}
}

func TestPunctuationSwitchOnlyChangesLiteralDisplayAndQuoteCommitAdvancesOnce(t *testing.T) {
	a := testLab(t)
	s := event(t, a, openSession(t, a, "full"), "quote", "input", "'")
	original := s.State
	s = setModes(t, a, s, "zh", "", "chinese")
	if s.State.RawInput != "'" || s.State.Candidates[0].ID != original.Candidates[0].ID || s.State.Candidates[0].Code != "'" || s.State.Candidates[0].Text != "‘" || original.Candidates[0].Text != "'" {
		t.Fatalf("mode mutated ID/raw/previous snapshot: %+v", s)
	}
	s = setModes(t, a, s, "en", "", "english")
	s = setModes(t, a, s, "zh-again", "", "chinese")
	if s.State.Candidates[0].Text != "‘" {
		t.Fatal("render toggled quote state")
	}
	selectQuote := eventRequest{SessionID: s.SessionID, EventID: "commit-quote", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[0].ID}
	first, retry := request(t, a, "/api/event", selectQuote), request(t, a, "/api/event", selectQuote)
	if first.Code != 200 || !bytes.Equal(first.Body.Bytes(), retry.Body.Bytes()) {
		t.Fatal("quote retry was not cached")
	}
	s = decodeResponse(t, first)
	if s.Commit != "‘" {
		t.Fatalf("opening quote: %+v", s)
	}
	s = event(t, a, s, "quote-again", "input", "'")
	if s.State.Candidates[0].Text != "’" {
		t.Fatal("next candidate did not show closing quote")
	}
	s = event(t, a, s, "side-quote", "literal", "'")
	if s.State.Candidates[0].Text != "’" || s.Commit != "'" {
		t.Fatal("side bypass advanced pair")
	}
	s = event(t, a, s, "cancel", "clear", "")
	s = event(t, a, s, "quote-after-cancel", "input", "'")
	if s.State.Candidates[0].Text != "’" {
		t.Fatal("cancellation advanced pair")
	}
	s = event(t, a, s, "closing", "input", "1")
	if s.Commit != "’" {
		t.Fatal("closing quote did not commit")
	}
	s = setModes(t, a, s, "english", "english", "")
	for i, want := range []string{"“", "”"} {
		s = event(t, a, s, fmt.Sprintf("double%d", i), "input", "\"")
		if s.Commit != want {
			t.Fatalf("double quote %d: %+v", i, s)
		}
	}
}

func TestModeRequestsAreValidatedAndIdempotent(t *testing.T) {
	a := testLab(t)
	s := openSession(t, a, "variable")
	r := httptest.NewRequest(http.MethodGet, testOrigin+"/api/info", nil)
	r.RemoteAddr = "127.0.0.1:1"
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	var info map[string]any
	if json.Unmarshal(w.Body.Bytes(), &info) != nil || info["inputPolicy"] != "concept-keyboard-modes-v2" {
		t.Fatalf("protocol policy missing: %s", w.Body.String())
	}
	for i, bad := range []eventRequest{
		{Type: "setModes"}, {Type: "setModes", InputMode: "caps"}, {Type: "setModes", PunctuationMode: "fullwidth"}, {Type: "setModes", InputMode: "english", Code: "x"},
		{Type: "input", Code: "x", InputMode: "english"}, {Type: "literal", Code: "aa"}, {Type: "literal", Code: "\x00"}, {Type: "literal", Code: "\r"}, {Type: "literal", Code: "汉"},
	} {
		bad.SessionID, bad.EventID, bad.BaseRevision = s.SessionID, fmt.Sprintf("bad%d", i), s.Revision
		if got := request(t, a, "/api/event", bad); got.Code != 400 {
			t.Fatalf("bad request accepted: %+v", bad)
		}
	}
	change := eventRequest{SessionID: s.SessionID, EventID: "mode", BaseRevision: s.Revision, Type: "setModes", InputMode: "english", PunctuationMode: "chinese"}
	first, retry := request(t, a, "/api/event", change), request(t, a, "/api/event", change)
	if first.Code != 200 || !bytes.Equal(first.Body.Bytes(), retry.Body.Bytes()) {
		t.Fatal("mode retry changed response")
	}
	s = decodeResponse(t, first)
	if s.Modes != (keyboardModes{"english", "chinese"}) || s.Revision != 1 || s.Commit != "" {
		t.Fatalf("mode result: %+v", s)
	}
	change.PunctuationMode = "english"
	if got := request(t, a, "/api/event", change); got.Code != 409 {
		t.Fatal("mode mutation conflict ignored")
	}
	change.EventID = "stale"
	if got := request(t, a, "/api/event", change); got.Code != 409 {
		t.Fatal("stale mode mutation accepted")
	}
}
