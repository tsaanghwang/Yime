package main

import (
	"errors"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"reflect"
	"testing"
)

func TestPreviewMiddleDotsBufferedTriplesAndEditing(t *testing.T) {
	p := previewFixture(t)
	for i := 0; i < 6; i++ {
		previewAction(t, p, "symbol", "·", "")
	}
	if string(p.editor.text) != "" || !p.snapshot.SymbolChoice {
		t.Fatal("auto committed", p.snapshot)
	}
	if err := p.selectCandidate(p.candidate(1)); err != nil {
		t.Fatal(err)
	}
	if string(p.editor.text) != "⋯⋯" || p.snapshot.PendingMiddleDots != 0 {
		t.Fatal(p.editor.text, p.snapshot)
	}
	previewAction(t, p, "symbol", "·", "")
	previewAction(t, p, "symbol", "·", "")
	previewAction(t, p, "backspace", "", "")
	if string(p.editor.text) != "⋯⋯" || p.snapshot.PendingMiddleDots != 1 {
		t.Fatal(p.snapshot)
	}
	if err := p.navigate("Home", false, p.stamp()); err != nil {
		t.Fatal(err)
	}
	if string(p.editor.text) != "⋯⋯·" || p.editor.cursor != 0 || p.snapshot.PendingMiddleDots != 0 {
		t.Fatal(p.editor, p.snapshot)
	}
	previewAction(t, p, "symbol", "·", "")
	previewAction(t, p, "clear", "", "")
	if p.snapshot.PendingMiddleDots != 0 || string(p.editor.text) != "⋯⋯·" {
		t.Fatal(p.snapshot)
	}
	previewAction(t, p, "symbol", "·", "")
	if err := p.switchMode("full"); err != nil {
		t.Fatal(err)
	}
	if p.snapshot.PendingMiddleDots != 0 {
		t.Fatal("pending dots crossed session")
	}
}

func TestHostMiddleDotsDoNotErasePreviouslySentText(t *testing.T) {
	p := previewFixture(t)
	sent := []tk.Output{}
	p.emit = func(_ string, o tk.Output) error { sent = append(sent, o); return nil }
	for i := 0; i < 6; i++ {
		previewAction(t, p, "symbol", "·", "")
	}
	if len(sent) != 0 {
		t.Fatal("unselected dots reached host", sent)
	}
	if err := p.selectCandidate(p.candidate(1)); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(sent, []tk.Output{{Text: "⋯⋯"}}) {
		t.Fatal(sent)
	}
	previewAction(t, p, "symbol", "·", "")
	previewAction(t, p, "symbol", "·", "")
	previewAction(t, p, "backspace", "", "")
	if len(sent) != 1 {
		t.Fatal("pending backspace reached host", sent)
	}
	previewAction(t, p, "confirm", "", "Enter")
	if !reflect.DeepEqual(sent[1:], []tk.Output{{Text: "·"}, {Key: "Enter"}}) {
		t.Fatal(sent)
	}
	previewAction(t, p, "symbol", "·", "")
	p.emit = func(_ string, o tk.Output) error { sent = append(sent, o); return errors.New("send failed") }
	before := len(sent)
	if err := p.navigate("Home", false, p.stamp()); err == nil || !p.fault {
		t.Fatal("flush failure accepted")
	}
	if len(sent) != before+1 || sent[len(sent)-1].Text != "·" {
		t.Fatal("edit continued after failed flush", sent)
	}
}
