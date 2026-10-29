//go:build windows && (amd64 || arm64)

package main

// Palettes affect drawing only. Source key colors, disabled actions, hit targets
// and input state remain unchanged; an omitted theme retains the original view.
type paintPalette struct {
	dark                                                    bool
	background, text, mutedText, panel, active, disabled    uintptr
	output, candidate, border, ruler, pressed, key, control uintptr
}

func (a *ui) palette() paintPalette {
	if a.o.Theme == "dark" {
		return paintPalette{
			dark:       true,
			background: color("#212020"), text: color("#ffffff"), mutedText: color("#b8b8b8"),
			panel: color("#313131"), active: color("#50634f"), disabled: color("#2b2b2b"),
			output: color("#292929"), candidate: color("#3b3a3a"), border: color("#626262"),
			ruler: color("#b9c8b7"), pressed: color("#50634f"),
			key: color("#3b3a3a"), control: color("#313131"),
		}
	}
	return paintPalette{
		background: 0xF2F4EF, text: 0x302C17, mutedText: 0x888888,
		panel: 0xE5EBE2, active: 0xB3DDC5, disabled: 0xDDDDDD,
		output: 0xFFFFFF, candidate: 0xFFFFFF, border: 0xA0A0A0,
		ruler: 0x306020, pressed: 0xA5CBB4,
	}
}

func (p paintPalette) keyColor(original string, control bool) uintptr {
	if !p.dark {
		return color(original)
	}
	if control {
		return p.control
	}
	return p.key
}
