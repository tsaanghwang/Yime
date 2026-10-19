package touchkeyboard

import (
	"math"
	"path/filepath"
	"testing"
)

func board(t *testing.T) Board {
	t.Helper()
	b, e := Load(filepath.Join("..", "..", "..", "prototypes", "touch-terminal", "data", "physical-layout.json"))
	if e != nil {
		t.Fatal(e)
	}
	return b
}
func TestFullSizeAndIndependentZones(t *testing.T) {
	b := board(t)
	for _, v := range []struct {
		z string
		g bool
		w float64
		n int
	}{{"both", false, 24.75, 134}, {"none", true, 18, 100}, {"left", true, 21, 117}, {"right", true, 21, 117}, {"both", true, 24, 134}} {
		got, e := Arrange(b, Profile{NumericZones: v.z, RemoveGutters: v.g})
		if e != nil {
			t.Fatal(e)
		}
		if math.Abs(got.Bounds.Width-v.w) > 1e-8 || len(got.Keys) != v.n {
			t.Fatalf("%+v got %.2f/%d", v, got.Bounds.Width, len(got.Keys))
		}
		for _, k := range got.Keys {
			for _, old := range b.Keys {
				if k.ID == old.ID && (k.Width != old.Width || k.Action != old.Action || k.ShiftAction != old.ShiftAction) {
					t.Fatal("region interface changed a key's size or encoding")
				}
			}
		}
	}
	if UnitMM*24.75 != 471.4875 {
		t.Fatal("physical pitch changed")
	}
}
func TestReserved17URequiresReviewedGeometry(t *testing.T) {
	b := board(t)
	if _, e := Arrange(b, Profile{NumericZones: "none", RemoveGutters: true, MainWidthU: 17}); e == nil {
		t.Fatal("must not shrink keys to claim 17u")
	}
	if _, e := Arrange(b, Profile{MainGeometry: map[string]Placement{"bad": {X: 0}}}); e == nil {
		t.Fatal("incomplete main geometry accepted")
	}
}
func TestRulerCalibrationUsesPhysicalPixelsNotDPI(t *testing.T) {
	p, e := PixelsPerMM(2560, 597.73)
	if e != nil {
		t.Fatal(e)
	}
	corrected, e := Calibrate(p, 100, 80)
	if e != nil || math.Abs(corrected/p-1.25) > 1e-9 {
		t.Fatal("ruler correction failed")
	}
	for _, v := range []float64{0, -1, math.NaN(), math.Inf(1)} {
		if _, e := PixelsPerMM(2560, v); e == nil {
			t.Fatal("invalid physical width")
		}
		if _, e := Calibrate(p, 100, v); e == nil {
			t.Fatal("invalid ruler measurement")
		}
	}
}
func coord(s *State, kind, text string) (float64, float64) {
	for _, k := range s.Board.Keys {
		v := s.View(k)
		if v.Action.Type == kind && (text == "" || v.Action.ASCII == text) {
			r := k.Rectangles[0]
			return k.X + r.X + r.Width/2, k.Y + r.Y + r.Height/2
		}
	}
	panic("fixture key not found")
}
func TestHeldShiftCapturedAtDownAndReleasedBeforeLetter(t *testing.T) {
	s := NewState(board(t))
	x, y := coord(s, "shift", "")
	a, b := coord(s, "input", "a")
	s.Down(1, x, y)
	s.Down(2, a, b)
	if o := s.Up(1, x, y); o != nil {
		t.Fatal(o)
	}
	out := s.Up(2, a, b)
	if out == nil || out.Text != "A" || s.Held("Shift") {
		t.Fatalf("lost captured layer: %#v", out)
	}
}
func TestOneShotShiftCancellationAndDisabledKeys(t *testing.T) {
	s := NewState(board(t))
	x, y := coord(s, "shift", "")
	s.Down(1, x, y)
	s.Up(1, x, y)
	a, b := coord(s, "input", "a")
	s.Down(2, a, b)
	o := s.Up(2, a, b)
	if o == nil || o.Text != "A" {
		t.Fatal(o)
	}
	s.Down(3, a, b)
	s.Move(3, -1, -1)
	s.Move(3, a, b)
	if s.Up(3, a, b) != nil {
		t.Fatal("returning after drag-out must stay cancelled")
	}
	for _, k := range s.Board.Keys {
		if k.English.Disabled {
			s.Down(8, k.X+.5, k.Y+.5)
			if s.Up(8, k.X+.5, k.Y+.5) != nil {
				t.Fatal("disabled English key emitted input")
			}
		}
	}
	s.Cancel()
	if s.Held("Shift") {
		t.Fatal("cancel did not clear virtual modifiers")
	}
}
func TestISONotchNeverHitsAndNumericEditFiveIsNoop(t *testing.T) {
	s := NewState(board(t))
	for _, k := range s.Board.Keys {
		if len(k.Rectangles) > 1 {
			for dx := .05; dx < k.Width; dx += .1 {
				for dy := .05; dy < k.Height; dy += .1 {
					inside := k.Contains(k.X+dx, k.Y+dy)
					if !inside {
						s.Down(4, k.X+dx, k.Y+dy)
						if o := s.Up(4, k.X+dx, k.Y+dy); o != nil {
							t.Fatal("ISO hole emitted action")
						}
					}
				}
			}
		}
		if k.Zone == "left" && k.Action.ASCII == "5" {
			s.Number["left"] = false
			s.Down(9, k.X+.5, k.Y+.5)
			if s.Up(9, k.X+.5, k.Y+.5) != nil {
				t.Fatal("numeric edit 5 must remain no-op")
			}
		}
	}
}
