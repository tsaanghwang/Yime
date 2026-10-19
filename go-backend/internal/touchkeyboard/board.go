// Package touchkeyboard contains the desktop lab's geometry and input state.
// It has no installed-product, registry, global hook, or dictionary dependency.
package touchkeyboard

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
)

const UnitMM = 19.05 // Common full-size MX centre-to-centre pitch, not cap width.
type Rect struct{ X, Y, Width, Height float64 }
type Action struct {
	Type  string `json:"type"`
	ASCII string `json:"ascii"`
	Key   string `json:"key"`
	Label string `json:"label"`
}
type View struct {
	Labels      []string `json:"labels"`
	Action      Action   `json:"action"`
	ShiftAction Action   `json:"shiftAction"`
	Disabled    bool     `json:"disabled"`
}
type Key struct {
	ID                  string `json:"id"`
	X, Y, Width, Height float64
	Rectangles          []Rect   `json:"rectangles"`
	Zone                string   `json:"zone"`
	Color               string   `json:"color"`
	Labels              []string `json:"labels"`
	Action              Action   `json:"action"`
	ShiftAction         Action   `json:"shiftAction"`
	EditAction          Action   `json:"editAction"`
	English             View     `json:"english"`
}
type Board struct {
	FormatVersion int                             `json:"formatVersion"`
	LayoutID      string                          `json:"layoutId"`
	Keys          []Key                           `json:"keys"`
	Bounds        struct{ Width, Height float64 } `json:"bounds"`
}

// MainGeometry is a reviewed replacement of physical geometry only. All main
// IDs must occur exactly once; actions/ASCII projections cannot be overridden.
type Placement struct {
	X, Y, Width, Height float64
	Rectangles          []Rect
}
type Profile struct {
	NumericZones  string               `json:"numericZones"` // both, left, right, none
	RemoveGutters bool                 `json:"removeGutters"`
	MainWidthU    float64              `json:"mainWidthU,omitempty"`
	MainGeometry  map[string]Placement `json:"mainGeometry,omitempty"`
}

func Load(path string) (Board, error) {
	var b Board
	raw, e := os.ReadFile(path)
	if e != nil {
		return b, e
	}
	e = json.Unmarshal(raw, &b)
	if e != nil {
		return b, e
	}
	if b.FormatVersion != 4 || len(b.Keys) != 134 || b.LayoutID == "" {
		return b, errors.New("current generated CN/EN134 board required")
	}
	return b, nil
}
func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
func (k Key) Contains(x, y float64) bool {
	for _, r := range k.Rectangles {
		if x >= k.X+r.X && x < k.X+r.X+r.Width && y >= k.Y+r.Y && y < k.Y+r.Y+r.Height {
			return true
		}
	}
	return false
}
func extent(keys []Key, zone string) (float64, float64) {
	lo, hi := math.Inf(1), math.Inf(-1)
	for _, k := range keys {
		if k.Zone != zone {
			continue
		}
		for _, v := range k.Rectangles {
			lo = math.Min(lo, k.X+v.X)
			hi = math.Max(hi, k.X+v.X+v.Width)
		}
	}
	return lo, hi
}
func Arrange(source Board, p Profile) (Board, error) {
	b := source
	b.Keys = nil
	if p.NumericZones == "" {
		p.NumericZones = "both"
	}
	if p.NumericZones != "both" && p.NumericZones != "left" && p.NumericZones != "right" && p.NumericZones != "none" {
		return b, errors.New("unknown numericZones")
	}
	mainLo, _ := extent(source.Keys, "main")
	main := []Key{}
	for _, original := range source.Keys {
		if original.Zone != "main" {
			continue
		}
		k := original
		k.Rectangles = append([]Rect(nil), k.Rectangles...)
		k.X -= mainLo
		if len(p.MainGeometry) > 0 {
			v, ok := p.MainGeometry[k.ID]
			if !ok {
				return b, fmt.Errorf("mainGeometry lacks %s", k.ID)
			}
			k.X, k.Y, k.Width, k.Height = v.X, v.Y, v.Width, v.Height
			k.Rectangles = append([]Rect(nil), v.Rectangles...)
		} else if p.RemoveGutters {
			// The one common empty central band in the reviewed KLE is [12.25,12.5).
			// Preserve every key's width and pitch; this is a translation, not scaling.
			for _, v := range k.Rectangles {
				l := original.X + v.X
				rr := l + v.Width
				if l < 12.5 && rr > 12.25 {
					return b, errors.New("key intersects reviewed centre gutter")
				}
			}
			if original.X >= 12.5 {
				k.X -= .25
			}
		}
		main = append(main, k)
	}
	if len(p.MainGeometry) > 0 && len(p.MainGeometry) != len(main) {
		return b, errors.New("mainGeometry must contain exactly the main key inventory")
	}
	if e := validate(main); e != nil {
		return b, e
	}
	lo, hi := extent(main, "main")
	mainWidth := hi - lo
	if p.MainWidthU != 0 && (!finite(p.MainWidthU) || math.Abs(mainWidth-p.MainWidthU) > .00001) {
		return b, fmt.Errorf("mainWidthU %.2f needs reviewed mainGeometry (current %.2fu); uniform key scaling is forbidden", p.MainWidthU, mainWidth)
	}
	gap := .25
	if p.RemoveGutters {
		gap = 0
	}
	left := p.NumericZones == "both" || p.NumericZones == "left"
	right := p.NumericZones == "both" || p.NumericZones == "right"
	offset := 0.
	if left {
		offset = 3 + gap
	}
	for _, k := range main {
		k.X += offset - lo
		b.Keys = append(b.Keys, k)
	}
	for _, k := range source.Keys {
		if k.Zone == "left" && left {
			b.Keys = append(b.Keys, k)
		}
		if k.Zone == "right" && right {
			k.X = k.X - 21.75 + offset + mainWidth + gap
			b.Keys = append(b.Keys, k)
		}
	}
	b.Bounds.Width = offset + mainWidth
	if right {
		b.Bounds.Width += gap + 3
	}
	if e := validate(b.Keys); e != nil {
		return b, e
	}
	b.Bounds.Height = 0
	for _, k := range b.Keys {
		for _, v := range k.Rectangles {
			b.Bounds.Height = math.Max(b.Bounds.Height, k.Y+v.Y+v.Height)
		}
	}
	return b, nil
}
func validate(keys []Key) error {
	seen := map[string]bool{}
	for i, k := range keys {
		if k.ID == "" || seen[k.ID] || !finite(k.X) || !finite(k.Y) {
			return errors.New("invalid/duplicate key identity or position")
		}
		seen[k.ID] = true
		if len(k.Rectangles) == 0 {
			return errors.New("key geometry requires rectangles")
		}
		for _, v := range k.Rectangles {
			if !finite(v.X) || !finite(v.Y) || !finite(v.Width) || !finite(v.Height) || v.Width <= 0 || v.Height <= 0 || k.X+v.X < 0 || k.Y+v.Y < 0 {
				return errors.New("invalid physical key rectangle")
			}
			for _, other := range keys[:i] {
				for _, w := range other.Rectangles {
					if k.X+v.X < other.X+w.X+w.Width-1e-8 && k.X+v.X+v.Width > other.X+w.X+1e-8 && k.Y+v.Y < other.Y+w.Y+w.Height-1e-8 && k.Y+v.Y+v.Height > other.Y+w.Y+1e-8 {
						return fmt.Errorf("overlapping keys %s/%s", k.ID, other.ID)
					}
				}
			}
		}
	}
	return nil
}
func PixelsPerMM(screenWidthPx int, screenWidthMM float64) (float64, error) {
	if screenWidthPx <= 0 || !finite(screenWidthMM) || screenWidthMM < 100 || screenWidthMM > 3000 {
		return 0, errors.New("provide measured/estimated monitor width in mm")
	}
	return float64(screenWidthPx) / screenWidthMM, nil
}
func Calibrate(pxPerMM, referenceMM, observedMM float64) (float64, error) {
	if !finite(pxPerMM) || !finite(referenceMM) || !finite(observedMM) || pxPerMM <= 0 || referenceMM <= 0 || observedMM <= 0 {
		return 0, errors.New("invalid ruler calibration")
	}
	return pxPerMM * referenceMM / observedMM, nil
}
