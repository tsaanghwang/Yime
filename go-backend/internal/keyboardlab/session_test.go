package keyboardlab

import (
	"bytes"
	"fmt"
	"strings"
	"testing"
)

func directState(t *testing.T, reply Reply, status int) Response {
	t.Helper()
	s, err := reply.Decode()
	if err != nil || reply.Status != status {
		t.Fatalf("reply %d: %s (%v)", reply.Status, reply.Body, err)
	}
	return s
}

func TestInProcessAndHTTPShareSessionPagingAndImmutableRetry(t *testing.T) {
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			a := testLab(t)
			s := directState(t, a.service.Open(mode, a.layoutID), 200)
			steps := []Event{{Type: "input", Code: "p"}, {Type: "page", Delta: 1}, {Type: "select"}}
			for i, e := range steps {
				e.SessionID, e.EventID, e.BaseRevision = s.SessionID, fmt.Sprintf("direct-%d", i), s.Revision
				if e.Type == "select" {
					e.CandidateID = s.State.Candidates[0].ID
				}
				direct := a.service.Dispatch(e)
				web := request(t, a, "/api/event", e)
				if direct.Status != web.Code || !bytes.Equal(direct.Body, web.Body.Bytes()) {
					t.Fatalf("in-process/HTTP divergence: %s / %s", direct.Body, web.Body.String())
				}
				s = directState(t, direct, 200)
				if e.Type == "page" && (s.State.PageNumber != 1 || len(s.State.Candidates) != 4) {
					t.Fatal("paging lost")
				}
				if e.Type == "select" && (s.Commit == "" || s.State.RawInput != "") {
					t.Fatal("selection lost")
				}
				// A desktop caller owns its bytes and decoded candidates. Neither can
				// change the cached response delivered to a later HTTP or direct retry.
				for n := range direct.Body {
					direct.Body[n] = 'x'
				}
				retry := a.service.Dispatch(e)
				if !bytes.Equal(retry.Body, web.Body.Bytes()) {
					t.Fatal("caller modified cached reply")
				}
			}
			a.service.Close()
			if got := a.service.Open(mode, a.layoutID); got.Status != 410 {
				t.Fatal("closed service reopened")
			}
			if got := a.service.Dispatch(Event{SessionID: s.SessionID, EventID: "closed", BaseRevision: s.Revision, Type: "clear"}); got.Status != 410 {
				t.Fatal("closed service accessed engine")
			}
		})
	}
}

func TestInProcessLimitRejectionPreservesRevisionAndAllowsRecovery(t *testing.T) {
	for _, mode := range modes {
		a := testLabWithRecords(t, "长码\t"+strings.Repeat("a", maxInput)+"\t100\n")
		s := directState(t, a.service.Open(mode, a.layoutID), 200)
		for i := 0; i < maxInput; i++ {
			s = directState(t, a.service.Dispatch(Event{SessionID: s.SessionID, EventID: fmt.Sprintf("fill-%d", i), BaseRevision: s.Revision, Type: "input", Code: "a"}), 200)
		}
		rejected := directState(t, a.service.Dispatch(Event{SessionID: s.SessionID, EventID: "overflow", BaseRevision: s.Revision, Type: "input", Code: "a"}), 400)
		if rejected.OK || rejected.Commit != "" || rejected.Revision != s.Revision || rejected.State.RawInput != s.State.RawInput {
			t.Fatal("rejection changed composition or commit")
		}
		for _, kind := range []string{"backspace", "clear"} {
			s = directState(t, a.service.Dispatch(Event{SessionID: s.SessionID, EventID: kind, BaseRevision: s.Revision, Type: kind}), 200)
			if kind == "backspace" && len(s.State.RawInput) != maxInput-1 {
				t.Fatal("backspace after rejection failed")
			}
		}
		if s.State.RawInput != "" || s.Commit != "" {
			t.Fatal("clear after rejection failed")
		}
	}
}
