package touchhostbridge

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

// Tiny explicit dictionaries exercise the real loader/index/YimeCore engine,
// not the complete shipped corpus or a real TSF text store.
func fixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	data := filepath.Join(root, "data")
	layout := filepath.Join(root, "prototypes/touch-terminal/data")
	for _, d := range []string{data, layout} {
		if e := os.MkdirAll(d, 0700); e != nil {
			t.Fatal(e)
		}
	}
	write := func(p string, b []byte) {
		t.Helper()
		if e := os.WriteFile(p, b, 0600); e != nil {
			t.Fatal(e)
		}
	}
	b, _ := json.Marshal(map[string]string{"layoutId": codemode.LayoutProjectionSHA256})
	write(filepath.Join(layout, "physical-layout.json"), b)
	hashes := map[string]string{}
	for _, mode := range keyboardlab.Modes() {
		name := "yime_" + mode + ".dict.yaml"
		body := []byte("---\nname: bridge_test\nversion: '1'\n...\n测试\ta\t100\n测验\ta\t90\n")
		for n := 0; n < 10; n++ {
			body = append(body, []byte(fmt.Sprintf("备选%d\ta\t%d\n", n, 80-n))...)
		}
		write(filepath.Join(data, name), body)
		sum := sha256.Sum256(body)
		hashes[name] = hex.EncodeToString(sum[:])
	}
	b, _ = json.Marshal(map[string]any{"schema_version": 1, "scope": "immutable_source_runtime_experiment", "limit": 0, "input_policy": keyboardlab.InputPolicy, "layout_projection_sha256": codemode.LayoutProjectionSHA256, "disabled_yinyuan_ids": []string{}, "dictionary_sha256": hashes})
	write(filepath.Join(data, "ascii_keyboard_manifest.json"), b)
	return root, data
}
func session(t *testing.T) *Session {
	t.Helper()
	r, d := fixture(t)
	s, e := Open(r, d, "variable", Focus{"own-test-host", 1})
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() {
		if e := s.Close(); e != nil {
			t.Error(e)
		}
	})
	return s
}
func dispatch(t *testing.T, s *Session, a Action) *Commit {
	t.Helper()
	a.Revision = s.Snapshot().Revision
	a.SessionID = s.Snapshot().SessionID
	c, e := s.Dispatch(s.Identity(), Focus{"own-test-host", 1}, a)
	if e != nil {
		t.Fatal(e)
	}
	return c
}
func commit(t *testing.T, s *Session) *Commit {
	t.Helper()
	dispatch(t, s, Action{Kind: "input", Code: "a"})
	st := s.Snapshot()
	if len(st.State.Candidates) == 0 {
		t.Fatal("no real engine candidates")
	}
	c := dispatch(t, s, Action{Kind: "select", CandidateID: st.State.Candidates[0].ID})
	if c == nil || c.Text != "测试" {
		t.Fatalf("commit %+v", c)
	}
	return c
}
func TestRealEngineCommitNeedsActualReceipt(t *testing.T) {
	s := session(t)
	c := commit(t, s)
	if s.Receipt().Outcome != Pending || s.Snapshot().Commit != "" {
		t.Fatal("queued edit mistaken for applied or text retained")
	}
	if _, e := s.Dispatch(s.Identity(), c.Focus, Action{SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Kind: "input", Code: "a"}); e == nil {
		t.Fatal("input during pending edit")
	}
	if e := s.Complete(c.ID, Pending); e == nil {
		t.Fatal("queued receipt accepted")
	}
	if e := s.Complete("other", Applied); e == nil {
		t.Fatal("foreign receipt")
	}
	if e := s.Complete(c.ID, Applied); e != nil {
		t.Fatal(e)
	}
	if e := s.Complete(c.ID, Applied); e == nil {
		t.Fatal("duplicate receipt")
	}
	if dispatch(t, s, Action{Kind: "input", Code: "a"}) != nil {
		t.Fatal("replay")
	}
}
func TestIdentityFocusAndCandidateRevision(t *testing.T) {
	s := session(t)
	i := s.Identity()
	a := Action{SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Kind: "input", Code: "a"}
	for _, bad := range []Identity{{"standard", i.DictionarySHA256, i.Mode, i.SessionPolicy}, {i.LayoutSHA256, "wrong", i.Mode, i.SessionPolicy}, {i.LayoutSHA256, i.DictionarySHA256, "full", i.SessionPolicy}} {
		if _, e := s.Dispatch(bad, Focus{"own-test-host", 1}, a); e == nil {
			t.Fatal("identity mismatch accepted")
		}
	}
	for _, f := range []Focus{{"other-host", 1}, {"own-test-host", 2}} {
		if _, e := s.Dispatch(i, f, a); e == nil {
			t.Fatal("focus mismatch accepted")
		}
	}
	dispatch(t, s, a)
	old := s.Snapshot()
	dispatch(t, s, Action{Kind: "backspace"})
	if _, e := s.Dispatch(i, Focus{"own-test-host", 1}, Action{SessionID: old.SessionID, Revision: old.Revision, Kind: "select", CandidateID: old.State.Candidates[0].ID}); e == nil {
		t.Fatal("stale candidate accepted")
	}
}
func TestUnknownFailureAndInvalidationNeverReplay(t *testing.T) {
	for _, outcome := range []Outcome{Failed, Unknown} {
		t.Run(string(outcome), func(t *testing.T) {
			s := session(t)
			c := commit(t, s)
			if e := s.Complete(c.ID, outcome); e != nil {
				t.Fatal(e)
			}
			if _, e := s.Dispatch(s.Identity(), c.Focus, Action{SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Kind: "input", Code: "a"}); e == nil {
				t.Fatal("terminal session reused")
			}
		})
	}
	s := session(t)
	c := commit(t, s)
	s.Invalidate()
	if s.Receipt().Outcome != Unknown {
		t.Fatal("pending edit not unknown")
	}
	if e := s.Complete(c.ID, Applied); e == nil {
		t.Fatal("late callback")
	}
}
func TestClearAndCloseDoNotCommit(t *testing.T) {
	s := session(t)
	dispatch(t, s, Action{Kind: "input", Code: "a"})
	if dispatch(t, s, Action{Kind: "clear"}) != nil || s.Snapshot().State.RawInput != "" {
		t.Fatal("clear committed")
	}
	_ = s.Close()
	if _, e := s.Dispatch(s.Identity(), Focus{"own-test-host", 1}, Action{SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Kind: "input", Code: "a"}); e == nil {
		t.Fatal("closed session reused")
	}
}
func TestSnapshotDoesNotExposeOwnedCandidateSlice(t *testing.T) {
	s := session(t)
	dispatch(t, s, Action{Kind: "input", Code: "a"})
	v := s.Snapshot()
	v.State.Candidates[0].ID = "forged"
	if s.Snapshot().State.Candidates[0].ID == "forged" {
		t.Fatal("alias")
	}
}
func TestLoaderRejectsWrongLayoutAndTamperedDictionary(t *testing.T) {
	r, d := fixture(t)
	p := filepath.Join(d, "yime_variable.dict.yaml")
	f, e := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0600)
	if e != nil {
		t.Fatal(e)
	}
	_, _ = f.WriteString("改\tb\t1\n")
	_ = f.Close()
	if s, e := Open(r, d, "variable", Focus{"own-test-host", 1}); e == nil {
		_ = s.Close()
		t.Fatal("tamper accepted")
	}
	r, d = fixture(t)
	_ = os.WriteFile(filepath.Join(r, "prototypes/touch-terminal/data/physical-layout.json"), []byte(`{"layoutId":"standard"}`), 0600)
	if s, e := Open(r, d, "variable", Focus{"own-test-host", 1}); e == nil {
		_ = s.Close()
		t.Fatal("standard layout accepted")
	}
}

func TestOldSessionActionCannotEnterNewActivation(t *testing.T) {
	old := session(t)
	next := session(t)
	action := Action{SessionID: old.Snapshot().SessionID, Revision: old.Snapshot().Revision, Kind: "input", Code: "a"}
	if _, err := next.Dispatch(next.Identity(), Focus{"own-test-host", 1}, action); err == nil {
		t.Fatal("old activation entered new session")
	}
	if next.Snapshot().State.RawInput != "" {
		t.Fatal("rejected action mutated session")
	}
}
func TestUnknownCandidateDoesNotCommit(t *testing.T) {
	s := session(t)
	dispatch(t, s, Action{Kind: "input", Code: "a"})
	st := s.Snapshot()
	if c, e := s.Dispatch(s.Identity(), Focus{"own-test-host", 1}, Action{SessionID: st.SessionID, Revision: st.Revision, Kind: "select", CandidateID: "not-present"}); e == nil || c != nil {
		t.Fatal("unknown candidate committed")
	}
	if s.Receipt().ID != "" {
		t.Fatal("receipt created for rejection")
	}
}

func TestOrdinaryPagingAndBackspace(t *testing.T) {
	s := session(t)
	dispatch(t, s, Action{Kind: "input", Code: "a"})
	first := s.Snapshot()
	if !first.State.HasNext {
		t.Fatal("fixture must have multiple pages")
	}
	if dispatch(t, s, Action{Kind: "page", Delta: 1}) != nil {
		t.Fatal("page committed")
	}
	if !s.Snapshot().State.HasPrevious {
		t.Fatal("page did not advance")
	}
	dispatch(t, s, Action{Kind: "page", Delta: -1})
	if s.Snapshot().State.Candidates[0].ID != first.State.Candidates[0].ID {
		t.Fatal("ordinary page round trip")
	}
	dispatch(t, s, Action{Kind: "backspace"})
	if s.Snapshot().State.RawInput != "" {
		t.Fatal("backspace did not clear code")
	}
}
func TestClosePendingPreservesUnknown(t *testing.T) {
	s := session(t)
	c := commit(t, s)
	if e := s.Close(); e != nil {
		t.Fatal(e)
	}
	if s.Receipt().Outcome != Unknown {
		t.Fatal("close claimed cancellation")
	}
	if e := s.Complete(c.ID, Applied); e == nil {
		t.Fatal("late completion accepted after close")
	}
}
func TestCompletionAndFocusLossSerialize(t *testing.T) {
	s := session(t)
	c := commit(t, s)
	var w sync.WaitGroup
	w.Add(2)
	go func() { defer w.Done(); _ = s.Complete(c.ID, Applied) }()
	go func() { defer w.Done(); s.Invalidate() }()
	w.Wait()
	if got := s.Receipt().Outcome; got != Applied && got != Unknown {
		t.Fatalf("invalid terminal result %q", got)
	}
	if _, e := s.Dispatch(s.Identity(), c.Focus, Action{SessionID: s.Snapshot().SessionID, Revision: s.Snapshot().Revision, Kind: "input", Code: "a"}); e == nil {
		t.Fatal("focus loss did not stop session")
	}
}
