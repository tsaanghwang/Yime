package main

import (
	"errors"
	"fmt"
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

func TestDiagnosticRejectsForeignTargetOnEveryRebind(t *testing.T) {
	fixture := hostTarget{1, 2, 3, 4}
	foreign := hostTarget{5, 6, 7, 8}
	current := fixture
	calls := 0
	g := &deliveryGate{current: func() hostTarget { return current }, send: func(hostTarget, tk.Output) error { calls++; return nil }}
	g.restrictTarget(fixture)
	for i := 0; i < 2; i++ {
		current = fixture
		if err := g.bind(current); err != nil {
			t.Fatal(err)
		}
		old := g.ticket()
		current = foreign // e.g. another application becomes foreground in drain.
		if err := g.bind(current); err == nil {
			t.Fatal("diagnostic authorized foreign target")
		}
		if err := g.deliver(old, "probe", tk.Output{Text: "must not send"}); err == nil || calls != 0 {
			t.Fatal("diagnostic emitted against foreign foreground")
		}
		g.invalidate("prepare another recovery bind")
	}
}

func TestHostEnterPreservesShiftAndConfirmationPolicy(t *testing.T) {
	for _, zone := range []string{"main", "left", "right"} {
		for _, shift := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/shift=%t", zone, shift), func(t *testing.T) {
				p := previewFixture(t)
				previewAction(t, p, "input", "a", "")
				if zone == "main" {
					previewAction(t, p, "toggle-language", "", "")
				}
				raw := p.snapshot.State.RawInput
				var outputs []tk.Output
				p.emit = func(_ string, o tk.Output) error { outputs = append(outputs, o); return nil }
				action := tk.Action{Type: "literal", ASCII: "\n"}
				if zone == "main" {
					action = tk.Action{Type: "confirm", Key: "Enter"}
				}
				out := tk.Output{Action: action, Zone: zone, Shift: shift}
				if zone == "main" {
					stale := p.stamp()
					stale.revision--
					if err := p.apply(out, stale); err == nil || len(outputs) != 0 {
						t.Fatal("stale Enter sent")
					}
				}
				if err := p.apply(out, p.stamp()); err != nil {
					t.Fatal(err)
				}
				if len(outputs) != 1 || outputs[0].Key != "Enter" || outputs[0].Text != "" || outputs[0].Shift != shift || p.snapshot.State.RawInput != raw {
					t.Fatalf("Enter lost modifiers or consumed composition: %+v", outputs)
				}
			})
		}
	}
	p := previewFixture(t)
	previewAction(t, p, "input", "a", "")
	var outputs []tk.Output
	p.emit = func(_ string, o tk.Output) error { outputs = append(outputs, o); return nil }
	if err := p.apply(tk.Output{Action: tk.Action{Type: "confirm", Key: "Enter"}, Shift: true}, p.stamp()); err != nil {
		t.Fatal(err)
	}
	if len(outputs) != 1 || outputs[0].Text != "中文𠀀" || outputs[0].Key != "" || outputs[0].Shift {
		t.Fatalf("Chinese Shift+Enter stopped confirming candidate: %+v", outputs)
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
