//go:build windows && (amd64 || arm64)

package main

import (
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"time"
)

func (a *ui) penTime() time.Time {
	if a.penClock != nil {
		return a.penClock()
	}
	return time.Now()
}
func (a *ui) penCharacterAt(x, y int32) string {
	if a.o.PenRecontactMS == 0 || a.preview == nil || !a.o.Preview || !a.o.TouchUI || a.host != nil || a.touchHelpOpen || a.touchSettingsOpen || a.navSelecting || a.s.Held("Ctrl") || a.s.Held("Alt") {
		return ""
	}
	i := a.s.Hit((float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
	if i < 0 {
		return ""
	}
	k := a.s.Board.Keys[i]
	v := a.s.View(k)
	if k.Zone != "main" || v.Disabled || v.Action.Type != "input" {
		return ""
	}
	return k.ID
}
func (a *ui) penContactDown(t touch, p point, now time.Time) bool {
	if t.Flags&0x40 == 0 {
		return false
	}
	key := a.penCharacterAt(p.X, p.Y)
	blocked := a.penRecontact.down(t.ID, t.Source, key, a.acceptedInputSerial, now, time.Duration(a.o.PenRecontactMS)*time.Millisecond)
	if key != "" && a.inputTrace != nil {
		a.inputTrace.write(map[string]any{"stage": "pen-filter", "id": t.ID, "keyID": key, "intervalMS": a.o.PenRecontactMS, "suppressed": blocked})
	}
	return blocked
}
