//go:build windows && (amd64 || arm64)

package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"testing"
)

func TestInstalledAllGesturesRequireExactRevision(t *testing.T) {
	p := previewFixture(t)
	p.installed = true
	old := p.stamp()
	previewAction(t, p, "input", "a", "")
	before := p.snapshot.Revision
	err := p.apply(tk.Output{Action: tk.Action{Type: "input", ASCII: "p"}}, old)
	if err == nil || p.snapshot.Revision != before || p.snapshot.State.RawInput != "a" {
		t.Fatal("stale coding touch entered newer composition")
	}
}
func TestInstalledEditingMapsTextOperationsOnly(t *testing.T) {
	for _, x := range []struct{ text, key string }{{"a", "SelectAll"}, {"c", "Copy"}, {"x", "Cut"}, {"v", "Paste"}} {
		e, err := installedHostEdit(tk.Output{Text: x.text, Ctrl: true})
		if err != nil || e.Key != x.key || e.Ctrl {
			t.Fatal(x, e, err)
		}
	}
	if _, e := installedHostEdit(tk.Output{Key: "Delete", Ctrl: true}); e != nil {
		t.Fatal(e)
	}
	for _, o := range []tk.Output{{Text: "x", Alt: true}, {Text: "z", Ctrl: true}, {Key: "F1"}} {
		if _, e := installedHostEdit(o); e == nil {
			t.Fatal("unsupported application command treated as TSF edit")
		}
	}
}
