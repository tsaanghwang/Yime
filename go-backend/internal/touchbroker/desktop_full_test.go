package touchbroker

import (
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	bridge "github.com/tsaanghwang/Yime/go-backend/internal/touchhostbridge"
	"os"
	"path/filepath"
	"testing"
)

func TestDesktopFullResourcesThreeModes(t *testing.T) {
	data := os.Getenv("YIME_18U_FULL_DATA")
	if data == "" {
		t.Skip("explicit locked full 18u data not configured")
	}
	root, e := filepath.Abs("../../..")
	if e != nil {
		t.Fatal(e)
	}
	runtime, e := keyboardlab.OpenRuntime(root, data)
	if e != nil {
		t.Fatal(e)
	}
	defer runtime.Close()
	for _, mode := range keyboardlab.Modes() {
		t.Run(mode, func(t *testing.T) {
			if runtime.LayoutID != LayoutSHA || runtime.Builds[mode].SourceSHA256 != DesktopDictionaryHashes[mode] {
				t.Fatal("full data identity mismatch")
			}
			focus := bridge.Focus{Context: "synthetic-full-desktop", Epoch: 1}
			s, e := bridge.OpenDesktopRuntime(runtime, mode, focus)
			if e != nil {
				t.Fatal(e)
			}
			defer s.Close()
			act := func(a bridge.Action) *bridge.Commit {
				t.Helper()
				snap := s.Snapshot()
				a.SessionID = snap.SessionID
				a.Revision = snap.Revision
				c, e := s.Dispatch(s.Identity(), focus, a)
				if e != nil {
					t.Fatal(e)
				}
				return c
			}
			code, e := installed18uhost.CanonicalNiMode(root, mode)
			if e != nil {
				t.Fatal(e)
			}
			for _, ch := range code {
				if act(bridge.Action{Kind: "input", Code: string(ch)}) != nil {
					t.Fatal("code unexpectedly committed")
				}
			}
			id := ""
			for page := 0; page < 128 && id == ""; page++ {
				snap := s.Snapshot()
				for _, c := range snap.State.Candidates {
					if c.Text == "你" {
						id = c.ID
						break
					}
				}
				if id != "" || !snap.State.HasNext {
					break
				}
				act(bridge.Action{Kind: "page", Delta: 1})
			}
			if id == "" {
				t.Fatal("canonical 你 missing")
			}
			c := act(bridge.Action{Kind: "select", CandidateID: id})
			if c == nil || c.Text != "你" || s.Receipt().Outcome != bridge.Pending {
				t.Fatal("real dictionary selection not pending")
			}
			if e = s.Complete(c.ID, bridge.Applied); e != nil {
				t.Fatal(e)
			}
			act(bridge.Action{Kind: "setModes", InputMode: "english", PunctuationMode: "english"})
			c = act(bridge.Action{Kind: "input", Code: "A"})
			if c == nil || c.Text != "A" {
				t.Fatal("English mode failed")
			}
			if e = s.Complete(c.ID, bridge.Applied); e != nil {
				t.Fatal(e)
			}
			t.Logf("mode=%s canonicalKeys=%d fullDictionaryHash=%s", mode, len(code), runtime.Builds[mode].SourceSHA256)
		})
	}
}
