package tsffrontend

import (
	"encoding/json"
	"errors"
	"testing"
)

type fakeTransport struct {
	calls    int
	closed   bool
	mutate   func(map[string]any)
	writeErr bool
}

func (f *fakeTransport) Close() error { f.closed = true; return nil }
func (f *fakeTransport) Exchange(b []byte) ([]byte, error) {
	f.calls++
	if f.writeErr {
		return nil, errors.New("lost reply")
	}
	var q map[string]any
	_ = json.Unmarshal(b, &q)
	outcome := "applied"
	if q["operation"] == "bind" {
		outcome = "bound"
	}
	r := map[string]any{"version": 1, "sequence": q["sequence"], "ok": true, "outcome": outcome, "retryAllowed": false}
	if f.mutate != nil {
		f.mutate(r)
	}
	return json.Marshal(r)
}
func TestCommitRequiresAppliedAndNeverReplays(t *testing.T) {
	for _, outcome := range []string{"pending", "unknown", "failed", "queued"} {
		t.Run(outcome, func(t *testing.T) {
			tr := &fakeTransport{}
			c, e := Bind(tr, 42)
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
	c, _ := Bind(tr, 42)
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
			if _, e := Bind(tr, 42); e == nil || !tr.closed {
				t.Fatal("accepted malformed bind")
			}
		})
	}
}
func TestTextAndEditingContracts(t *testing.T) {
	tr := &fakeTransport{}
	c, e := Bind(tr, 42)
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
		`{"version":1,"sequence":1,"ok":true,"outcome":"bound","retryAllowed":null}`,
		`{"version":1,"sequence":1,"ok":false,"ok":true,"outcome":"bound","retryAllowed":false}`,
	} {
		if validReplyObject([]byte(raw)) {
			t.Fatal("ambiguous receipt accepted")
		}
	}
}
