//go:build windows && (amd64 || arm64)

package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/installed18uhost"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"os"
	"time"
)

// Fixed synthetic actions use the same GUI controller and authenticated UI
// pipe as touch input. The separate registered host reads its actual TSF text
// after every checkpoint. This is software integration evidence, not finger
// or pen acceptance and not a command channel for arbitrary text/documents.
func (a *ui) installedSmoke() error {
	input := make(chan bool, 1)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			var q struct {
				Proceed bool `json:"proceed"`
			}
			if json.Unmarshal(scanner.Bytes(), &q) != nil {
				input <- false
				return
			}
			input <- q.Proceed
		}
		close(input)
	}()
	wait := func() error {
		deadline := time.NewTimer(20 * time.Second)
		defer deadline.Stop()
		tick := time.NewTicker(5 * time.Millisecond)
		defer tick.Stop()
		for {
			select {
			case yes, ok := <-input:
				if !ok || !yes {
					return errors.New("registered host did not confirm checkpoint")
				}
				return nil
			case <-deadline.C:
				return errors.New("registered host checkpoint deadline")
			case <-tick.C:
				if !pumpHostMessages() {
					return errors.New("keyboard closed")
				}
			}
		}
	}
	checkpoint := func(name, mode, text, code string, away bool) error {
		if e := json.NewEncoder(os.Stdout).Encode(map[string]any{"stage": "checkpoint", "name": name, "mode": mode, "expected": text, "code": code, "focusAway": away}); e != nil {
			return e
		}
		return wait()
	}
	if e := checkpoint("ready", "", "KEEP|", "", false); e != nil {
		return e
	}
	expected := "KEEP|"
	for _, mode := range []string{"full", "variable", "shorthand"} {
		// The host pumps its STA after restoring focus; let the TIP advertise the
		// new generation. No failed input action is retried.
		until := time.Now().Add(400 * time.Millisecond)
		for time.Now().Before(until) {
			if !pumpHostMessages() {
				return errors.New("closed")
			}
			time.Sleep(5 * time.Millisecond)
		}
		a.preview.mode = mode
		if e := a.bindInstalled(); e != nil {
			return fmt.Errorf("%s bind: %w", mode, e)
		}
		code, e := installed18uhost.CanonicalNiMode(a.o.Root, mode)
		if e != nil {
			return e
		}
		apply := func(kind, ascii, key string, shift bool) error {
			return a.preview.apply(tk.Output{Action: tk.Action{Type: kind, ASCII: ascii, Key: key}, Shift: shift}, a.preview.stamp())
		}
		compose := func() error {
			for _, ch := range code {
				if e := apply("input", string(ch), "", false); e != nil {
					return e
				}
			}
			return nil
		}
		if e = compose(); e != nil {
			return e
		}
		if e = checkpoint("preedit", mode, expected+code, code, false); e != nil {
			return e
		}
		selected := false
		for page := 0; page < 128 && !selected; page++ {
			for i, c := range a.preview.snapshot.State.Candidates {
				if c.Text == "你" {
					e = a.preview.selectCandidate(a.preview.candidate(i))
					selected = e == nil
					break
				}
			}
			if selected || e != nil {
				break
			}
			if !a.preview.snapshot.State.HasNext {
				break
			}
			e = a.preview.page(1)
			if e != nil {
				break
			}
		}
		if e != nil {
			return e
		}
		if !selected {
			return errors.New("canonical 你 absent from visible candidate pages")
		}
		expected += "你"
		if e = checkpoint("candidate", mode, expected, code, false); e != nil {
			return e
		}
		if e = apply("toggle-language", "", "", false); e != nil {
			return e
		}
		if e = apply("input", "x", "", false); e != nil {
			return e
		}
		expected += "x"
		if e = apply("literal", "7", "", false); e != nil {
			return e
		}
		expected += "7"
		if e = checkpoint("english-literal", mode, expected, code, false); e != nil {
			return e
		}
		if e = apply("backspace", "", "Backspace", false); e != nil {
			return e
		}
		expected = expected[:len(expected)-1]
		if e = apply("local", "", "ArrowLeft", true); e != nil {
			return e
		}
		if e = apply("literal", "Z", "", false); e != nil {
			return e
		}
		expected = expected[:len(expected)-1] + "Z"
		if e = checkpoint("host-edit", mode, expected, code, false); e != nil {
			return e
		}
		if e = apply("toggle-language", "", "", false); e != nil {
			return e
		}
		if e = compose(); e != nil {
			return e
		}
		if e = apply("clear", "", "", false); e != nil {
			return e
		}
		if e = checkpoint("cancel", mode, expected, code, false); e != nil {
			return e
		}
		if e = compose(); e != nil {
			return e
		}
		if e = checkpoint("focus-cancel", mode, expected, code, true); e != nil {
			return e
		}
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"stage": "result", "ok": true, "sendInput": false, "registeredHostReadbacks": true, "modes": []string{"full", "variable", "shorthand"}, "physicalAcceptance": false})
}
