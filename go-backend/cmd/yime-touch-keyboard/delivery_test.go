package main

import (
	"errors"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"testing"
)

func TestDeliveryBindsIdentityEpochAndConsumesOnce(t *testing.T) {
	a := hostTarget{1, 2, 3, 4}
	current := a
	calls := 0
	g := &deliveryGate{current: func() hostTarget { return current }, send: func(hostTarget, tk.Output) error { calls++; return nil }}
	if err := g.bind(a); err != nil {
		t.Fatal(err)
	}
	first := g.ticket()
	if err := g.deliver(first, "commit-1", tk.Output{Text: "你好"}); err != nil {
		t.Fatal(err)
	}
	if err := g.deliver(first, "commit-1", tk.Output{Text: "你好"}); err == nil || calls != 1 {
		t.Fatal("duplicate delivery")
	}
	current.Process++
	if err := g.deliver(first, "recycled-hwnd", tk.Output{Text: "bad"}); err == nil || calls != 1 {
		t.Fatal("recycled HWND accepted")
	}
	current = a
	g.invalidate("observed focus away and back")
	if err := g.bind(a); err != nil {
		t.Fatal(err)
	}
	if err := g.deliver(first, "late", tk.Output{Text: "bad"}); err == nil || calls != 1 {
		t.Fatal("late old-epoch commit")
	}
	if err := g.deliver(g.ticket(), "fresh", tk.Output{Text: "新"}); err != nil || calls != 2 {
		t.Fatal("explicit fresh binding failed")
	}
}
func TestDeliveryFailureAndFocusDuringSendBlockUntilExplicitBind(t *testing.T) {
	for _, kind := range []string{"zero", "partial", "focus"} {
		t.Run(kind, func(t *testing.T) {
			a := hostTarget{1, 2, 3, 4}
			current := a
			calls := 0
			var g *deliveryGate
			g = &deliveryGate{current: func() hostTarget { return current }, send: func(hostTarget, tk.Output) error {
				calls++
				if kind == "focus" {
					g.invalidate("focus during send")
					return nil
				}
				return errors.New(kind)
			}}
			if err := g.bind(a); err != nil {
				t.Fatal(err)
			}
			ticket := g.ticket()
			if err := g.deliver(ticket, "one", tk.Output{Text: "文"}); err == nil || !g.blocked {
				t.Fatal("uncertain result accepted")
			}
			if err := g.deliver(ticket, "two", tk.Output{Text: "文"}); err == nil || calls != 1 {
				t.Fatal("continued after uncertainty")
			}
			g.send = func(hostTarget, tk.Output) error { calls++; return nil }
			if err := g.bind(a); err != nil {
				t.Fatal(err)
			}
			if err := g.deliver(ticket, "one", tk.Output{Text: "文"}); err == nil {
				t.Fatal("replayed old ticket after recovery")
			}
			if err := g.deliver(g.ticket(), "three", tk.Output{Text: "新"}); err != nil || calls != 2 {
				t.Fatal("fresh action failed")
			}
		})
	}
}
func TestHostControllerEmitsCommitsNotCompositionAndStopsOnFailure(t *testing.T) {
	p := previewFixture(t)
	var output []tk.Output
	ids := map[string]bool{}
	p.emit = func(id string, o tk.Output) error {
		if ids[id] {
			t.Fatal("reused output identity")
		}
		ids[id] = true
		output = append(output, o)
		return nil
	}
	previewAction(t, p, "input", "a", "")
	if len(output) != 0 {
		t.Fatal("raw composition sent")
	}
	previewAction(t, p, "confirm", "", "Space")
	if len(output) != 1 || output[0].Text != "中文𠀀" || len(p.editor.text) != 0 {
		t.Fatal("host and preview sinks mixed")
	}
	previewAction(t, p, "backspace", "", "")
	if output[1].Key != "Backspace" {
		t.Fatal("editing did not reach host")
	}
	previewAction(t, p, "input", "a", "")
	previewAction(t, p, "clear", "", "")
	if len(output) != 2 {
		t.Fatal("cancel sent Escape or raw ASCII to host")
	}
	p.emit = func(string, tk.Output) error { return errors.New("partial") }
	if err := p.apply(tk.Output{Action: tk.Action{Type: "literal", ASCII: "x"}}, p.stamp()); err == nil || !p.fault {
		t.Fatal("failed host commit did not stop session")
	}
	p.emit = func(string, tk.Output) error { t.Fatal("replayed after fault"); return nil }
	if err := p.apply(tk.Output{Action: tk.Action{Type: "literal", ASCII: "x"}}, p.stamp()); err == nil {
		t.Fatal("fault accepted new action")
	}
}
