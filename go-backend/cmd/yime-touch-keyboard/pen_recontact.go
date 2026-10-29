package main

import "time"

type penContact struct {
	key        string
	source     uintptr
	id         uint32
	serial     uint64
	suppressed bool
}

// An opt-in preview experiment, not a global keyboard debounce. Only native
// pen character contacts are offered here; fingers, mouse, modifiers and
// controls never enter this filter. Quiet time extends across a bounce chain.
type penRecontact struct {
	contacts map[uint32]penContact
	last     penContact
	lastUp   time.Time
}

func (p *penRecontact) down(id uint32, source uintptr, key string, serial uint64, now time.Time, interval time.Duration) bool {
	if old, ok := p.contacts[id]; ok {
		return old.suppressed
	}
	if key == "" || interval <= 0 {
		return false
	}
	gap := now.Sub(p.lastUp)
	blocked := p.last.key == key && p.last.source == source && p.last.id == id && p.last.serial == serial && gap >= 0 && gap < interval
	if p.contacts == nil {
		p.contacts = make(map[uint32]penContact)
	}
	p.contacts[id] = penContact{key: key, source: source, id: id, serial: serial, suppressed: blocked}
	return blocked
}
func (p *penRecontact) blocked(id uint32) bool { return p.contacts[id].suppressed }
func (p *penRecontact) up(id uint32, serial uint64, now time.Time, accepted bool) {
	c, ok := p.contacts[id]
	delete(p.contacts, id)
	if !ok {
		return
	}
	if accepted || c.suppressed && serial == c.serial {
		c.serial = serial
		p.last, p.lastUp = c, now
	}
}
