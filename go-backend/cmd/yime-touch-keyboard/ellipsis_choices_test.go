package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"testing"
)

func TestEllipsisChoicesStayExplicitInEnglishAndPreserveChinese(t *testing.T) {
	p := previewFixture(t)
	previewAction(t, p, "input", "a", "")
	previewAction(t, p, "toggle-language", "", "")
	for i := 0; i < 3; i++ {
		previewAction(t, p, "symbol", "·", "")
	}
	if !p.candidatesEnabled() || !p.snapshot.SymbolChoice || string(p.editor.text) != "" || p.snapshot.State.RawInput != "a" {
		t.Fatal(p.snapshot)
	}
	if p.candidateLabel(0) != "1  …\nU+2026" || p.candidateLabel(1) != "2  ⋯\nU+22EF" {
		t.Fatal("missing codepoint labels")
	}
	old := p.candidate(0)
	previewAction(t, p, "symbol", "·", "")
	if err := p.selectCandidate(old); err == nil {
		t.Fatal("stale touch selected")
	}
	if err := p.navigate("Home", false, p.stamp()); err == nil || p.fault {
		t.Fatal("unselected choice flushed or terminal fault")
	}
	if err := p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "b"}}, p.stamp()); err == nil {
		t.Fatal("implicit commit")
	}
	if err := p.selectCandidate(p.candidate(1)); err != nil {
		t.Fatal(err)
	}
	if string(p.editor.text) != "⋯" || p.snapshot.PendingMiddleDots != 1 || p.snapshot.State.RawInput != "a" || p.candidatesEnabled() {
		t.Fatal(p.snapshot, p.editor)
	}
	previewAction(t, p, "clear", "", "")
	for i := 0; i < 3; i++ {
		previewAction(t, p, "symbol", "·", "")
	}
	previewAction(t, p, "confirm", "", "Enter")
	if string(p.editor.text) != "⋯…" || p.snapshot.SymbolChoice || p.snapshot.PendingMiddleDots != 0 {
		t.Fatal(p.snapshot, p.editor)
	}
}
