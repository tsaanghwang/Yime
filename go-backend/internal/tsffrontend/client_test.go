package tsffrontend

import (
	"encoding/json"
	"errors"
	"strings"
	"sync"
	"testing"
)

type fakeTransport struct {
	calls    int
	closed   bool
	mutate   func(map[string]any)
	writeErr bool
	requests []map[string]any
}

func TestBindReasonSurvivesWithoutReplayOrArbitraryText(t *testing.T) {
	for _, reason := range []string{"focus-owner-mismatch", "no-focused-document", "no-top-context", "focus-changed", "key-focus-missing", "profile-inactive", "context-read-only", "context-loading", "generation-exhausted", "native-host-required", "native-peer-required", "private-document-text"} {
		tr := &fakeTransport{mutate: func(r map[string]any) { r["ok"] = false; r["outcome"] = "bind-rejected"; r["reason"] = reason }}
		_, err := Bind(tr, 42, 43)
		if err == nil || !tr.closed || tr.calls != 1 {
			t.Fatal("bind failure retried or accepted")
		}
		if strings.Contains(err.Error(), reason) != (reason != "private-document-text") {
			t.Fatal("reason not safely preserved", err)
		}
	}
	tr := &fakeTransport{}
	if _, err := Bind(tr, 42, 0); err == nil || tr.calls != 0 || !tr.closed {
		t.Fatal("missing focus sent")
	}
}

func (f *fakeTransport) Close() error { f.closed = true; return nil }
func (f *fakeTransport) Exchange(b []byte) ([]byte, error) {
	f.calls++
	if f.writeErr {
		return nil, errors.New("lost reply")
	}
	var q map[string]any
	_ = json.Unmarshal(b, &q)
	f.requests = append(f.requests, q)
	outcome := "applied"
	if q["operation"] == "bind" {
		outcome = "bound"
	} else if q["operation"] == "status" {
		outcome = "ready"
	}
	r := map[string]any{"version": 2, "sequence": q["sequence"], "ok": true, "outcome": outcome, "retryAllowed": false, "activationId": "activation-1", "generation": uint64(7)}
	if f.mutate != nil {
		f.mutate(r)
	}
	return json.Marshal(r)
}
func TestCommitRequiresAppliedAndNeverReplays(t *testing.T) {
	for _, outcome := range []string{"pending", "unknown", "failed", "queued"} {
		t.Run(outcome, func(t *testing.T) {
			tr := &fakeTransport{}
			c, e := Bind(tr, 42, 43)
			if e != nil {
				t.Fatal(e)
			}
			tr.mutate = func(r map[string]any) { r["outcome"] = outcome }
			if c.Edit("你", "", false) == nil {
				t.Fatal("accepted unconfirmed edit")
			}
			n := tr.calls
			if c.Edit("你", "", false) == nil || tr.calls != n || !tr.closed {
				t.Fatal("replayed stopped edit")
			}
		})
	}
}
func TestTransportLossStopsSession(t *testing.T) {
	tr := &fakeTransport{}
	c, _ := Bind(tr, 42, 43)
	tr.writeErr = true
	if c.Edit("a", "", false) == nil {
		t.Fatal("accepted lost reply")
	}
	if !tr.closed {
		t.Fatal("not closed")
	}
}
func TestIdentityAndReplyShape(t *testing.T) {
	for _, field := range []string{"sequence", "version", "retryAllowed", "ok", "missing"} {
		t.Run(field, func(t *testing.T) {
			tr := &fakeTransport{mutate: func(r map[string]any) {
				switch field {
				case "sequence", "version":
					r[field] = 99
				case "retryAllowed":
					r[field] = true
				case "ok":
					r[field] = false
				default:
					delete(r, "retryAllowed")
				}
			}}
			if _, e := Bind(tr, 42, 43); e == nil || !tr.closed {
				t.Fatal("accepted malformed bind")
			}
		})
	}
}
func TestTextAndEditingContracts(t *testing.T) {
	tr := &fakeTransport{}
	c, e := Bind(tr, 42, 43)
	if e != nil {
		t.Fatal(e)
	}
	for _, key := range []string{"Enter", "Tab", "Backspace", "Delete", "ArrowLeft", "ArrowRight", "Home", "End", "SelectAll"} {
		if e = c.Edit("", key, false); e != nil {
			t.Fatal(key, e)
		}
	}
	if e = c.Edit("你😀", "", false); e != nil {
		t.Fatal(e)
	}
	before := tr.calls
	for _, key := range []string{"F1", "Escape", "Ctrl+V"} {
		if c.Edit("", key, false) == nil {
			t.Fatal("unsupported key")
		}
	}
	if c.Edit("x", "", true) == nil || c.Edit("", "Delete", true) == nil || tr.calls != before {
		t.Fatal("invalid edit sent")
	}
}
func TestReplyRejectsDuplicateAndNull(t *testing.T) {
	for _, raw := range []string{
		`{"version":2,"sequence":1,"ok":true,"outcome":"bound","retryAllowed":null,"activationId":"a","generation":1}`,
		`{"version":2,"sequence":1,"ok":false,"ok":true,"outcome":"bound","retryAllowed":false,"activationId":"a","generation":1}`,
		`{"version":2,"sequence":1,"ok":true,"outcome":"bound","retryAllowed":false,"activationId":"a","activationId":"b","generation":1}`,
		`{"version":2,"sequence":1,"ok":true,"outcome":"bound","retryAllowed":false,"activationId":"a","generation":null}`,
	} {
		if validReplyObject([]byte(raw)) {
			t.Fatal("ambiguous receipt accepted")
		}
	}
}

func TestStatusIsReadOnlyAndPinsBoundIdentity(t *testing.T) {
	tr := &fakeTransport{}
	c, err := Bind(tr, 42, 43)
	if err != nil {
		t.Fatal(err)
	}
	if err = c.Status(); err != nil {
		t.Fatal(err)
	}
	if err = c.Edit("新", "", false); err != nil {
		t.Fatal(err)
	}
	for i, q := range tr.requests {
		if q["version"] != float64(2) || q["sequence"] != float64(i+1) {
			t.Fatalf("wrong wire identity: %+v", q)
		}
		if i == 0 {
			if len(q) != 5 || q["operation"] != "bind" || q["activationId"] != nil || q["generation"] != nil {
				t.Fatalf("bind did not establish a new identity: %+v", q)
			}
			continue
		}
		if q["activationId"] != "activation-1" || q["generation"] != float64(7) {
			t.Fatalf("bound identity not echoed: %+v", q)
		}
	}
	q := tr.requests[1]
	if q["operation"] != "status" || len(q) != 5 || q["text"] != nil || q["key"] != nil || q["extend"] != nil {
		t.Fatalf("status included an edit: %+v", q)
	}
	if tr.requests[2]["operation"] != "edit" || len(tr.requests[2]) != 8 {
		t.Fatal("wrong edit shape")
	}
}

func TestStatusAndEditRejectNewIdentityWithoutAdoptingIt(t *testing.T) {
	for _, operation := range []string{"status", "edit"} {
		for _, field := range []string{"activationId", "generation"} {
			t.Run(operation+"/"+field, func(t *testing.T) {
				tr := &fakeTransport{}
				c, err := Bind(tr, 42, 43)
				if err != nil {
					t.Fatal(err)
				}
				tr.mutate = func(r map[string]any) {
					if field == "activationId" {
						r[field] = "new-activation"
					} else {
						r[field] = uint64(8)
					}
				}
				if operation == "status" {
					err = c.Status()
				} else {
					err = c.Edit("旧", "", false)
				}
				if err == nil || !tr.closed || c.activationID != "activation-1" || c.generation != 7 {
					t.Fatal("adopted an unbound identity", err)
				}
				calls := tr.calls
				if c.Status() == nil || c.Edit("旧", "", false) == nil || tr.calls != calls {
					t.Fatal("stale client retried or edited")
				}
			})
		}
	}
}

func TestStatusUnavailableAndTransportLossAreNotEditOutcomes(t *testing.T) {
	for _, failure := range []string{"context-changed", "lease-inactive", "stale-generation", "private-document-text", "transport"} {
		t.Run(failure, func(t *testing.T) {
			tr := &fakeTransport{}
			c, err := Bind(tr, 42, 43)
			if err != nil {
				t.Fatal(err)
			}
			tr.mutate = func(r map[string]any) { r["outcome"], r["reason"] = "unavailable", failure }
			tr.writeErr = failure == "transport"
			err = c.Status()
			if err == nil || !tr.closed || strings.Contains(err.Error(), "edit result unknown") {
				t.Fatal("status incorrectly treated as a document mutation", err)
			}
			if failure == "private-document-text" && strings.Contains(err.Error(), failure) {
				t.Fatal("untrusted status reason disclosed")
			}
			if c.Edit("新", "", false) == nil || tr.calls != 2 {
				t.Fatal("unavailable status allowed later edits")
			}
		})
	}
}

func TestV2IdentityAndStrictReplyShape(t *testing.T) {
	for _, failure := range []string{"missing-activation", "missing-generation", "empty-activation", "long-activation", "nul-activation", "zero-generation", "negative-generation", "fraction-generation", "string-generation", "v1", "extra", "missing-ok"} {
		t.Run(failure, func(t *testing.T) {
			tr := &fakeTransport{mutate: func(r map[string]any) {
				switch failure {
				case "missing-activation":
					delete(r, "activationId")
				case "missing-generation":
					delete(r, "generation")
				case "empty-activation":
					r["activationId"] = ""
				case "long-activation":
					r["activationId"] = strings.Repeat("a", 129)
				case "nul-activation":
					r["activationId"] = "a\x00b"
				case "zero-generation":
					r["generation"] = 0
				case "negative-generation":
					r["generation"] = -1
				case "fraction-generation":
					r["generation"] = 1.5
				case "string-generation":
					r["generation"] = "7"
				case "v1":
					r["version"] = 1
				case "extra":
					r["target"] = "forged"
				case "missing-ok":
					delete(r, "ok")
				}
			}}
			if _, err := Bind(tr, 42, 43); err == nil || tr.calls != 1 || !tr.closed {
				t.Fatal("malformed v2 bind accepted or retried", err)
			}
		})
	}
}

func TestLostEditReceiptCannotBeRecoveredByStatus(t *testing.T) {
	tr := &fakeTransport{}
	c, err := Bind(tr, 42, 43)
	if err != nil {
		t.Fatal(err)
	}
	tr.writeErr = true
	if err = c.Edit("已写但回包丢失", "", false); err == nil || !strings.Contains(err.Error(), "result unknown") {
		t.Fatal("edit transport loss was not unknown", err)
	}
	tr.writeErr = false
	if c.Status() == nil || c.Edit("已写但回包丢失", "", false) == nil || tr.calls != 2 {
		t.Fatal("status recovered a failed edit session or replayed it")
	}
	if err = c.Close(); err != nil || tr.calls != 2 {
		t.Fatal("close sent another request after unknown result", err)
	}
}

func TestStatusDoesNotAcceptAnEditReceipt(t *testing.T) {
	tr := &fakeTransport{}
	c, err := Bind(tr, 42, 43)
	if err != nil {
		t.Fatal(err)
	}
	tr.mutate = func(r map[string]any) { r["outcome"] = "applied" }
	if c.Status() == nil || !tr.closed || tr.calls != 2 {
		t.Fatal("status accepted a receipt for a different operation")
	}
	if c.Edit("新", "", false) == nil || tr.calls != 2 {
		t.Fatal("invalid status receipt left editing enabled")
	}
}

func TestStatusAndEditSerializeOneSequence(t *testing.T) {
	tr := &fakeTransport{}
	c, err := Bind(tr, 42, 43)
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 20)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(edit bool) {
			defer wg.Done()
			if edit {
				errs <- c.Edit("新", "", false)
			} else {
				errs <- c.Status()
			}
		}(i%2 == 0)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if len(tr.requests) != 21 {
		t.Fatal("missing request")
	}
	for i, q := range tr.requests {
		if q["sequence"] != float64(i+1) {
			t.Fatal("concurrent status broke edit sequence")
		}
	}
}
