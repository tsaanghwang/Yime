package touchhostbridge

import (
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"testing"
)

func TestDesktopThreeModesAndEnglishLiteralKeepActualReceipt(t *testing.T) {
	root, data := fixture(t)
	runtime, e := keyboardlab.OpenRuntime(root, data)
	if e != nil {
		t.Fatal(e)
	}
	defer runtime.Close()
	for _, mode := range keyboardlab.Modes() {
		t.Run(mode, func(t *testing.T) {
			s, e := OpenDesktopRuntime(runtime, mode, Focus{"own-test-host", 1})
			if e != nil {
				t.Fatal(e)
			}
			defer s.Close()
			c := commit(t, s)
			if e = s.Complete(c.ID, Applied); e != nil {
				t.Fatal(e)
			}
			dispatch(t, s, Action{Kind: "setModes", InputMode: "english", PunctuationMode: "english"})
			c = dispatch(t, s, Action{Kind: "input", Code: "A"})
			if c == nil || c.Text != "A" || s.Snapshot().Commit != "" {
				t.Fatal("English commit bypassed completion")
			}
			if e = s.Complete(c.ID, Applied); e != nil {
				t.Fatal(e)
			}
			c = dispatch(t, s, Action{Kind: "literal", Code: "7"})
			if c == nil || c.Text != "7" {
				t.Fatal("literal route")
			}
			if e = s.Complete(c.ID, Applied); e != nil {
				t.Fatal(e)
			}
			before := s.Snapshot().Revision
			c = dispatch(t, s, Action{Kind: "hostEdit", Edit: &HostEdit{Key: "ArrowLeft", Shift: true}})
			if c == nil || c.Edit == nil || c.Text != "" || s.Snapshot().Revision != before+1 || s.Receipt().Outcome != Pending {
				t.Fatal("edit not prepared")
			}
			if _, e = s.Dispatch(s.Identity(), Focus{"own-test-host", 1}, Action{Kind: "input", SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Code: "b"}); e == nil {
				t.Fatal("overlapped edit")
			}
			if e = s.Complete(c.ID, Applied); e != nil {
				t.Fatal(e)
			}
			dispatch(t, s, Action{Kind: "setModes", InputMode: "chinese", PunctuationMode: "chinese"})
			dispatch(t, s, Action{Kind: "input", Code: "a"})
			if _, e = s.Dispatch(s.Identity(), Focus{"own-test-host", 1}, Action{Kind: "hostEdit", SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Edit: &HostEdit{Key: "Delete"}}); e == nil {
				t.Fatal("host edit during composition")
			}
		})
	}
}
