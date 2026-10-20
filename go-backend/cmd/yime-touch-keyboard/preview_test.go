package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// Explicit small fixtures exercise the real engine. They are never shipped as
// dictionaries or represented as canonical pronunciation/complete-corpus data.
func previewFixture(t *testing.T) *preview {
	t.Helper()
	dir := t.TempDir()
	source := filepath.Join(dir, "fixture.dict.yaml")
	var data strings.Builder
	data.WriteString("---\nname: explicit_desktop_test_fixture\nversion: '1'\n...\n中文𠀀\ta\t100\n大写\tA\t100\n")
	for i := 0; i < 15; i++ {
		fmt.Fprintf(&data, "测试%d\tp\t%d\n", i, 100-i)
	}
	if err := os.WriteFile(source, []byte(data.String()), 0600); err != nil {
		t.Fatal(err)
	}
	indices := map[string]*yimecore.FileIndex{}
	for _, mode := range keyboardlab.Modes() {
		path := filepath.Join(dir, mode+".yidx")
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
	s := keyboardlab.NewService("fixture", func(mode string) (engineapi.Engine, error) { return yimecore.NewFileEngine(indices[mode], 9) })
	t.Cleanup(s.Close)
	p, err := newPreview(s, "fixture", true)
	if err != nil {
		t.Fatal(err)
	}
	return p
}
func previewAction(t *testing.T, p *preview, kind, code, key string) {
	t.Helper()
	if err := p.apply(tk.Output{Action: tk.Action{Type: kind, ASCII: code, Key: key}}, p.stamp()); err != nil {
		t.Fatal(err)
	}
}
func TestPreviewThreeModesSelectionEditCancelAndStaleCandidates(t *testing.T) {
	p := previewFixture(t)
	for _, mode := range keyboardlab.Modes() {
		if err := p.switchMode(mode); err != nil {
			t.Fatal(err)
		}
		p.editor = previewEditor{}
		previewAction(t, p, "input", "a", "")
		if p.snapshot.State.RawInput != "a" || p.snapshot.State.Candidates[0].Text != "中文𠀀" {
			t.Fatal(p.snapshot)
		}
		c := p.candidate(0)
		if err := p.selectCandidate(c); err != nil {
			t.Fatal(err)
		}
		if err := p.selectCandidate(c); err == nil {
			t.Fatal("duplicate candidate was accepted")
		}
		if string(p.editor.text) != "中文𠀀" || p.snapshot.Commit != "" {
			t.Fatal("commit not consumed exactly once")
		}
		previewAction(t, p, "backspace", "", "")
		if string(p.editor.text) != "中文" {
			t.Fatal("supplementary scalar split")
		}
		previewAction(t, p, "local", "", "Home")
		if err := p.apply(tk.Output{Action: tk.Action{Type: "local", Key: "ArrowRight"}, Shift: true}, p.stamp()); err != nil {
			t.Fatal(err)
		}
		previewAction(t, p, "local", "", "Delete")
		if string(p.editor.text) != "文" {
			t.Fatal("local selection deletion")
		}
		previewAction(t, p, "input", "a", "")
		previewAction(t, p, "backspace", "", "")
		if p.snapshot.State.RawInput != "" || string(p.editor.text) != "文" {
			t.Fatal("composition backspace touched output")
		}
		previewAction(t, p, "input", "p", "")
		old := p.candidate(0)
		stamp := p.stamp()
		if err := p.page(1); err != nil {
			t.Fatal(err)
		}
		if err := p.selectCandidate(old); err == nil {
			t.Fatal("old page accepted")
		}
		if err := p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "1"}}, stamp); err == nil {
			t.Fatal("old digit selected new page")
		}
		previewAction(t, p, "clear", "", "")
		if p.snapshot.State.RawInput != "" || string(p.editor.text) != "文" {
			t.Fatal("cancel committed")
		}
	}
}
func TestPreviewLanguageLayoutAndLiteralBypass(t *testing.T) {
	p := previewFixture(t)
	previewAction(t, p, "input", "a", "")
	p.toggleLayout()
	if !p.original() || !p.englishView {
		t.Fatal("CN changed EN preference")
	}
	previewAction(t, p, "toggle-language", "", "")
	if p.original() || p.snapshot.Modes.Punctuation != "english" || p.snapshot.State.RawInput != "a" {
		t.Fatal(p.snapshot)
	}
	p.toggleLayout()
	previewAction(t, p, "toggle-language", "", "")
	previewAction(t, p, "toggle-language", "", "")
	if !p.original() {
		t.Fatal("English preference lost")
	}
	previewAction(t, p, "input", "A", "")
	previewAction(t, p, "confirm", "", "Enter")
	if string(p.editor.text) != "A\n" || p.snapshot.State.RawInput != "a" {
		t.Fatal("paused composition consumed")
	}
	previewAction(t, p, "toggle-language", "", "")
	previewAction(t, p, "literal", "7", "")
	previewAction(t, p, "literal", "\n", "")
	if string(p.editor.text) != "A\n7\n" || p.snapshot.State.RawInput != "a" {
		t.Fatal("side bypass selected")
	}
	for _, s := range []string{"·", "、", "—", "×", "√", "÷"} {
		previewAction(t, p, "symbol", s, "")
	}
	if p.snapshot.State.RawInput != "a" {
		t.Fatal("symbols destroyed composition")
	}
	if p.literalEntries {
		t.Fatal("literal switch enabled by default")
	}
	p.literalEntries = true
	if err := p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "!", LiteralEntry: true}}, p.stamp()); err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(string(p.editor.text), "！") || p.snapshot.State.RawInput != "a" {
		t.Fatal("reserved literal entrance not isolated")
	}
}
func TestPreviewModeSwitchRetiresOldSessionAndPreservesOutput(t *testing.T) {
	p := previewFixture(t)
	previewAction(t, p, "literal", "x", "")
	previewAction(t, p, "input", "a", "")
	old := p.candidate(0)
	if err := p.switchMode("full"); err != nil {
		t.Fatal(err)
	}
	if err := p.selectCandidate(old); err == nil {
		t.Fatal("retired session accepted")
	}
	if p.snapshot.State.RawInput != "" || string(p.editor.text) != "x" {
		t.Fatal("switch silently committed")
	}
	r := p.sessions.Dispatch(keyboardlab.Event{SessionID: old.stamp.session, EventID: "late", BaseRevision: old.stamp.revision, Type: "clear"})
	if r.Status != 410 && r.Status != 404 { // Open may already have pruned the closed session.
		t.Fatal("old engine still live")
	}
}

type replaySessions struct {
	previewSessions
	reply keyboardlab.Reply
}

func (s replaySessions) Dispatch(e keyboardlab.Event) keyboardlab.Reply { return s.reply }
func TestPreviewRefusesReplayedCommitAndRecoversCompositionLimit(t *testing.T) {
	p := previewFixture(t)
	for i := 0; i < 128; i++ {
		previewAction(t, p, "input", "a", "")
	}
	if err := p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "a"}}, p.stamp()); err == nil || p.fault {
		t.Fatal("limit should be a recoverable rejection")
	}
	previewAction(t, p, "clear", "", "")
	previewAction(t, p, "literal", "x", "")
	p.sessions = replaySessions{p.sessions, keyboardlab.Reply{Status: 200, Body: []byte(fmt.Sprintf(`{"ok":true,"sessionId":%q,"revision":%d,"commit":"duplicate","modes":{"input":"chinese","punctuation":"chinese"}}`, p.snapshot.SessionID, p.snapshot.Revision))}}
	if err := p.apply(tk.Output{Action: tk.Action{Type: "literal", ASCII: "y"}}, p.stamp()); err == nil || !p.fault {
		t.Fatal("replayed response accepted")
	}
	if string(p.editor.text) != "x" {
		t.Fatal("commit duplicated")
	}
}
