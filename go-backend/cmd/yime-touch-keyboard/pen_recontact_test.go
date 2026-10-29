package main

import (
	"testing"
	"time"
)

func TestPenRecontactQuietTimeAndIdentity(t *testing.T) {
	now := time.Unix(100, 0)
	interval := 80 * time.Millisecond
	var p penRecontact
	if p.down(7, 1, "a", 0, now, interval) {
		t.Fatal("first press delayed")
	}
	p.up(7, 1, now.Add(20*time.Millisecond), true)
	if !p.down(7, 1, "a", 1, now.Add(32*time.Millisecond), interval) {
		t.Fatal("12ms recontact accepted")
	}
	p.up(7, 1, now.Add(52*time.Millisecond), false)
	if !p.down(7, 1, "a", 1, now.Add(120*time.Millisecond), interval) {
		t.Fatal("bounce chain did not extend quiet interval")
	}
	p.up(7, 1, now.Add(140*time.Millisecond), false)
	if p.down(7, 1, "a", 1, now.Add(220*time.Millisecond), interval) {
		t.Fatal("boundary80ms intentional press lost")
	}
	p.up(7, 2, now.Add(240*time.Millisecond), true)
	for _, tc := range []struct {
		id     uint32
		source uintptr
		key    string
		serial uint64
	}{{8, 1, "a", 2}, {7, 2, "a", 2}, {7, 1, "b", 2}, {7, 1, "a", 3}} {
		copy := p
		copy.contacts = nil
		if copy.down(tc.id, tc.source, tc.key, tc.serial, now.Add(241*time.Millisecond), interval) {
			t.Fatal("different contact/device/key/intervening action was filtered", tc)
		}
	}
}
func TestPenRecontactDefaultOffCancelledAndDuplicateDown(t *testing.T) {
	now := time.Unix(100, 0)
	var p penRecontact
	if p.down(1, 1, "a", 0, now, 0) || len(p.contacts) != 0 {
		t.Fatal("disabled filter retained contact")
	}
	p.down(1, 1, "a", 0, now, time.Second)
	if p.down(1, 1, "a", 0, now.Add(time.Millisecond), time.Second) {
		t.Fatal("duplicate DOWN changed active contact")
	}
	p.up(1, 0, now.Add(20*time.Millisecond), false)
	if p.down(1, 1, "a", 0, now.Add(21*time.Millisecond), time.Second) {
		t.Fatal("cancelled/nonaccepted press started cooldown")
	}
}
