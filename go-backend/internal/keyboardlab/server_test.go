package keyboardlab

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const testOrigin = "http://127.0.0.1:8765"

// These sessions use the production compact-index loader and engine, with
// test-only dictionary records chosen to distinguish case, digits and paging.
func testLab(t *testing.T) *lab {
	return testLabWithRecords(t, "")
}

func testLabWithRecords(t *testing.T, extra string) *lab {
	t.Helper()
	root := t.TempDir()
	var dictionary strings.Builder
	dictionary.WriteString("---\nname: keyboard_lab_test\nversion: '1'\n...\n小写\ta\t100\n大写\tA\t100\n数字\t1\t100\n连输\ta1\t100\n")
	for i := 0; i < 13; i++ {
		fmt.Fprintf(&dictionary, "测试%d\tp\t%d\n", i, 100-i)
	}
	dictionary.WriteString(extra)
	source := filepath.Join(root, "test.dict.yaml")
	if err := os.WriteFile(source, []byte(dictionary.String()), 0600); err != nil {
		t.Fatal(err)
	}
	indices := make(map[string]*yimecore.FileIndex)
	for _, mode := range modes {
		path := filepath.Join(root, mode+".yidx")
		if _, err := yimecore.BuildIndexFile(mode, source, path); err != nil {
			t.Fatal(err)
		}
		index, err := yimecore.OpenFileIndex(path)
		if err != nil {
			t.Fatal(err)
		}
		indices[mode] = index
		t.Cleanup(func() { _ = index.Close() })
	}
	return newLab(root, "test-layout", testOrigin, func(mode string) (engineapi.Engine, error) { return yimecore.NewFileEngine(indices[mode], 9) })
}

func request(t *testing.T, a *lab, path string, value any) *httptest.ResponseRecorder {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	r := httptest.NewRequest(http.MethodPost, testOrigin+path, bytes.NewReader(data))
	r.RemoteAddr = "127.0.0.1:50000"
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Yime-Lab-Token", a.token)
	r.Header.Set("Origin", testOrigin)
	w := httptest.NewRecorder()
	a.ServeHTTP(w, r)
	return w
}

func decodeResponse(t *testing.T, w *httptest.ResponseRecorder) response {
	t.Helper()
	var result response
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func openSession(t *testing.T, a *lab, mode string) response {
	t.Helper()
	w := request(t, a, "/api/session", map[string]string{"mode": mode, "layoutId": a.layoutID})
	if w.Code != 200 {
		t.Fatalf("open: %d %s", w.Code, w.Body.String())
	}
	return decodeResponse(t, w)
}

func event(t *testing.T, a *lab, state response, id, kind, code string) response {
	t.Helper()
	w := request(t, a, "/api/event", eventRequest{SessionID: state.SessionID, EventID: id, BaseRevision: state.Revision, Type: kind, Code: code})
	if w.Code != 200 {
		t.Fatalf("event %s: %d %s", id, w.Code, w.Body.String())
	}
	return decodeResponse(t, w)
}

func TestRealEngineThreeModesCaseDigitsAndSessionIsolation(t *testing.T) {
	a := testLab(t)
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			left, right := openSession(t, a, mode), openSession(t, a, mode)
			left = event(t, a, left, "uppercase", "input", "A")
			if left.State.RawInput != "A" || left.State.Candidates[0].Text != "大写" {
				t.Fatalf("case lost: %+v", left.State)
			}
			right = event(t, a, right, "digit", "input", "1")
			if right.State.RawInput != "" || right.Commit != "1" || len(right.State.Candidates) != 0 {
				t.Fatalf("idle digit did not commit or sessions shared: %+v", right)
			}
			left = event(t, a, left, "reset", "clear", "")
			left = event(t, a, left, "lowercase", "input", "a")
			left = event(t, a, left, "digit-after-candidate", "input", "1")
			if left.State.RawInput != "" || left.Commit != "小写" {
				t.Fatalf("digit while candidates visible did not select: %+v", left)
			}
			left = event(t, a, left, "retype", "input", "a")
			left = event(t, a, left, "erase", "backspace", "")
			if left.State.RawInput != "" {
				t.Fatalf("backspace: %+v", left)
			}
		})
	}
}

func TestSelectIsCurrentPageStableIDAndRetryCommitsOnce(t *testing.T) {
	a := testLab(t)
	s := event(t, a, openSession(t, a, "full"), "input", "input", "p")
	if len(s.State.Candidates) != 9 || !s.State.HasNext {
		t.Fatalf("first page: %+v", s.State)
	}
	firstID := s.State.Candidates[0].ID
	paging := eventRequest{SessionID: s.SessionID, EventID: "page", BaseRevision: s.Revision, Type: "page", Delta: 1}
	w := request(t, a, "/api/event", paging)
	if w.Code != 200 {
		t.Fatalf("page: %s", w.Body.String())
	}
	s = decodeResponse(t, w)
	if len(s.State.Candidates) != 4 || s.State.PageNumber != 1 || !s.State.HasPrevious || s.State.HasNext {
		t.Fatalf("last page: %+v", s.State)
	}
	bad := eventRequest{SessionID: s.SessionID, EventID: "old-page", BaseRevision: s.Revision, Type: "select", CandidateID: firstID}
	if w := request(t, a, "/api/event", bad); w.Code != 400 {
		t.Fatalf("old-page selected: %d", w.Code)
	}
	want := s.State.Candidates[0].Text
	selectEvent := eventRequest{SessionID: s.SessionID, EventID: "commit", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[0].ID}
	first := request(t, a, "/api/event", selectEvent)
	second := request(t, a, "/api/event", selectEvent)
	if first.Code != 200 || !bytes.Equal(first.Body.Bytes(), second.Body.Bytes()) {
		t.Fatalf("retry not identical: %s / %s", first.Body.String(), second.Body.String())
	}
	committed := decodeResponse(t, first)
	if committed.Commit != want || committed.State.RawInput != "" || committed.Revision != s.Revision+1 {
		t.Fatalf("commit: %+v", committed)
	}
	selectEvent.CandidateID = firstID
	if w := request(t, a, "/api/event", selectEvent); w.Code != 409 {
		t.Fatalf("event ID conflict accepted: %d", w.Code)
	}
	if w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "stale", BaseRevision: s.Revision, Type: "input", Code: "a"}); w.Code != 409 {
		t.Fatalf("stale mutation accepted: %d", w.Code)
	}
}

func TestConcurrentEventsCannotShareARevision(t *testing.T) {
	a := testLab(t)
	s := openSession(t, a, "variable")
	var group sync.WaitGroup
	statuses := make(chan int, 2)
	for _, id := range []string{"one", "two"} {
		group.Add(1)
		go func(id string) {
			defer group.Done()
			w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: id, Type: "input", Code: "a"})
			statuses <- w.Code
		}(id)
	}
	group.Wait()
	close(statuses)
	counts := map[int]int{}
	for code := range statuses {
		counts[code]++
	}
	if counts[200] != 1 || counts[409] != 1 {
		t.Fatalf("concurrent mutations: %v", counts)
	}
}

func TestCompositionLimitRejectionAllowsBackspaceAndClear(t *testing.T) {
	a := testLabWithRecords(t, "长码\t"+strings.Repeat("a", 128)+"\t100\n")
	s := openSession(t, a, "full")
	for i := 0; i < 128; i++ {
		s = event(t, a, s, fmt.Sprintf("fill-%d", i), "input", "a")
	}
	w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "overflow", BaseRevision: s.Revision, Type: "input", Code: "a"})
	rejected := decodeResponse(t, w)
	if w.Code != 400 || rejected.OK || rejected.Error != "composition limit reached" || rejected.Commit != "" || rejected.SessionID != s.SessionID || rejected.Revision != s.Revision || rejected.State.RawInput != s.State.RawInput || rejected.Modes != s.Modes {
		t.Fatalf("unexpected limit response: %d %+v", w.Code, rejected)
	}
	s = event(t, a, rejected, "shorten", "backspace", "")
	if len(s.State.RawInput) != 127 {
		t.Fatalf("cannot shorten after rejection: %+v", s)
	}
	s = event(t, a, s, "cancel", "clear", "")
	if s.State.RawInput != "" || s.Commit != "" {
		t.Fatalf("cannot cancel after rejection: %+v", s)
	}
}

func TestCloseReclaimsCapacityAndPreventsFurtherMutation(t *testing.T) {
	a := testLab(t)
	first := openSession(t, a, "variable")
	for i := 1; i < maxSessions; i++ {
		openSession(t, a, "full")
	}
	if w := request(t, a, "/api/session", map[string]string{"mode": "full", "layoutId": a.layoutID}); w.Code != 429 {
		t.Fatalf("session cap: %d", w.Code)
	}
	closed := event(t, a, first, "close", "close", "")
	if w := request(t, a, "/api/event", eventRequest{SessionID: first.SessionID, EventID: "after-close", BaseRevision: closed.Revision, Type: "input", Code: "a"}); w.Code != 410 {
		t.Fatalf("closed session accepted: %d", w.Code)
	}
	openSession(t, a, "shorthand")
}

func TestLoopbackOriginTokenAndPayloadBoundaries(t *testing.T) {
	a := testLab(t)
	for _, tc := range []struct {
		name, host, remote, origin, token, body string
		status                                  int
	}{
		{"foreign-host", "attacker.invalid:8765", "127.0.0.1:1", testOrigin, a.token, `{}`, 403},
		{"nonlocal-peer", "127.0.0.1:8765", "192.0.2.1:1", testOrigin, a.token, `{}`, 403},
		{"foreign-origin", "127.0.0.1:8765", "127.0.0.1:1", "https://attacker.invalid", a.token, `{}`, 403},
		{"no-token", "127.0.0.1:8765", "127.0.0.1:1", testOrigin, "", `{}`, 403},
		{"unknown-field", "127.0.0.1:8765", "127.0.0.1:1", testOrigin, a.token, `{"mode":"full","layoutId":"test-layout","unexpected":true}`, 400},
		{"two-json-values", "127.0.0.1:8765", "127.0.0.1:1", testOrigin, a.token, `{"mode":"full","layoutId":"test-layout"}{}`, 400},
		{"oversized", "127.0.0.1:8765", "127.0.0.1:1", testOrigin, a.token, `{"mode":"` + strings.Repeat("x", maxBody) + `"}`, 400},
		{"old-layout", "127.0.0.1:8765", "127.0.0.1:1", testOrigin, a.token, `{"mode":"full","layoutId":"old"}`, 409},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodPost, testOrigin+"/api/session", strings.NewReader(tc.body))
			r.Host, r.RemoteAddr = tc.host, tc.remote
			r.Header.Set("Origin", tc.origin)
			r.Header.Set("Content-Type", "application/json")
			r.Header.Set("X-Yime-Lab-Token", tc.token)
			w := httptest.NewRecorder()
			a.ServeHTTP(w, r)
			if w.Code != tc.status {
				t.Fatalf("status %d: %s", w.Code, w.Body.String())
			}
		})
	}
	s := openSession(t, a, "full")
	for _, code := range []string{"你好", "aa", " ", "\n"} {
		if w := request(t, a, "/api/event", eventRequest{SessionID: s.SessionID, EventID: "invalid", Type: "input", Code: code}); w.Code != 400 {
			t.Fatalf("invalid code accepted %q", code)
		}
	}
}

func TestStaticFilesCannotEscapePrototypeOrListDirectories(t *testing.T) {
	a := testLab(t)
	for name, body := range map[string]string{"index.html": "<h1>model</h1>", "app.mjs": "export {};", "private.py": "secret"} {
		if err := os.WriteFile(filepath.Join(a.staticRoot, name), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Mkdir(filepath.Join(a.staticRoot, "subdir"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(a.staticRoot, "data"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(a.staticRoot, "data", "demo.json"), []byte(`{"historical":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		path string
		want int
	}{{"/", 200}, {"/app.mjs", 200}, {"/private.py", 404}, {"/data/demo.json", 404}, {"/subdir/", 404}, {"/../AGENTS.md", 404}, {"/%2e%2e/AGENTS.md", 404}} {
		r := httptest.NewRequest(http.MethodGet, testOrigin+tc.path, nil)
		r.RemoteAddr = "127.0.0.1:1"
		w := httptest.NewRecorder()
		a.ServeHTTP(w, r)
		if w.Code != tc.want {
			t.Fatalf("%s: %d", tc.path, w.Code)
		}
	}
}
