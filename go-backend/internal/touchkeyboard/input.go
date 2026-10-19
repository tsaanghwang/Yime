package touchkeyboard

type Output struct {
	Text, Key        string
	Shift, Ctrl, Alt bool
}
type press struct {
	index                        int
	action                       Action
	shift, ctrl, alt, used, left bool
}

// State captures a character layer at DOWN and emits only on an inside UP.
// Modifiers are virtual until an atomic SendInput batch; no global key is held.
type State struct {
	Board            Board
	Original         bool
	Shift, Ctrl, Alt bool
	Number           map[string]bool
	presses          map[uint32]*press
}

func NewState(b Board) *State {
	return &State{Board: b, Number: map[string]bool{"left": true, "right": true}, presses: map[uint32]*press{}}
}
func (s *State) View(k Key) View {
	if s.Original {
		return View{Labels: k.Labels, Action: k.Action, ShiftAction: k.ShiftAction}
	}
	return k.English
}
func modifier(a Action) string {
	if a.Type == "shift" {
		return "Shift"
	}
	if a.Type == "unsupported" && (a.Label == "Ctrl" || a.Label == "Alt") {
		return a.Label
	}
	return ""
}
func (s *State) Held(name string) bool {
	v := name == "Shift" && s.Shift || name == "Ctrl" && s.Ctrl || name == "Alt" && s.Alt
	for _, p := range s.presses {
		if !p.left && modifier(p.action) == name {
			v = true
		}
	}
	return v
}
func (s *State) Hit(x, y float64) int {
	for i, k := range s.Board.Keys {
		if k.Contains(x, y) {
			return i
		}
	}
	return -1
}
func (s *State) Down(id uint32, x, y float64) {
	if _, ok := s.presses[id]; ok {
		return
	}
	i := s.Hit(x, y)
	if i < 0 {
		return
	}
	k := s.Board.Keys[i]
	v := s.View(k)
	if v.Disabled || v.Action.Type == "disabled" {
		return
	}
	a := v.Action
	sh, ct, al := s.Held("Shift"), s.Held("Ctrl"), s.Held("Alt")
	if modifier(a) == "" {
		if sh && v.ShiftAction.Type != "" {
			a = v.ShiftAction
		}
		if k.Zone != "main" && !s.Number[k.Zone] && k.EditAction.Type != "" {
			a = k.EditAction
		}
		for _, p := range s.presses {
			if modifier(p.action) != "" {
				p.used = true
			}
		}
	}
	s.presses[id] = &press{index: i, action: a, shift: sh, ctrl: ct, alt: al}
}
func (s *State) Move(id uint32, x, y float64) {
	if p := s.presses[id]; p != nil && !s.Board.Keys[p.index].Contains(x, y) {
		p.left = true
	}
}
func (s *State) Cancel() {
	s.presses = map[uint32]*press{}
	s.Shift = false
	s.Ctrl = false
	s.Alt = false
}
func (s *State) Pressed(index int) bool {
	for _, p := range s.presses {
		if p.index == index && !p.left {
			return true
		}
	}
	return false
}
func (s *State) Up(id uint32, x, y float64) *Output {
	p := s.presses[id]
	if p == nil {
		return nil
	}
	delete(s.presses, id)
	if p.left || !s.Board.Keys[p.index].Contains(x, y) {
		return nil
	}
	switch modifier(p.action) {
	case "Shift":
		if !p.used {
			s.Shift = !s.Shift
		}
		return nil
	case "Ctrl":
		if !p.used {
			s.Ctrl = !s.Ctrl
		}
		return nil
	case "Alt":
		if !p.used {
			s.Alt = !s.Alt
		}
		return nil
	}
	a := p.action
	k := s.Board.Keys[p.index]
	switch a.Type {
	case "toggle-layout":
		s.Original = !s.Original
		s.Cancel()
		return nil
	case "toggle-number":
		s.Number[k.Zone] = !s.Number[k.Zone]
		return nil
	case "toggle-language":
		return nil // Chinese engine bridge is a separate milestone.
	case "input", "literal", "symbol":
		s.Shift = false
		s.Ctrl = false
		s.Alt = false
		return s.output(Output{Text: a.ASCII, Shift: p.shift, Ctrl: p.ctrl, Alt: p.alt})
	case "clear":
		return s.output(Output{Key: "Escape", Shift: p.shift, Ctrl: p.ctrl, Alt: p.alt})
	case "backspace":
		return s.output(Output{Key: "Backspace", Ctrl: p.ctrl, Alt: p.alt})
	case "confirm":
		return s.output(Output{Key: a.Key, Shift: p.shift, Ctrl: p.ctrl, Alt: p.alt})
	case "local":
		return s.output(Output{Key: a.Key, Shift: p.shift, Ctrl: p.ctrl, Alt: p.alt})
	case "unsupported":
		if len(a.Label) >= 2 && a.Label[0] == 'F' {
			return s.output(Output{Key: a.Label, Shift: p.shift, Ctrl: p.ctrl, Alt: p.alt})
		}
	}
	return nil
}

func (s *State) output(o Output) *Output { s.Shift = false; s.Ctrl = false; s.Alt = false; return &o }
