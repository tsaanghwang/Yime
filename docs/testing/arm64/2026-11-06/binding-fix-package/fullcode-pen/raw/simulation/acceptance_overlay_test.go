//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"os"
	"runtime"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

// This additional acceptance test is supplied only by a process-local Go overlay.
// It uses the fixed package's complete isolated dictionaries and existing hidden
// own-window fixtures. It never connects to an installed TIP or external host.
func TestAcceptanceFullNiiiSyntheticRoutes20261106(t *testing.T) {
	root, data, report := os.Getenv("YIME_ACCEPTANCE_ROOT"), os.Getenv("YIME_ACCEPTANCE_LAB_DATA"), os.Getenv("YIME_ACCEPTANCE_REPORT")
	if root == "" || data == "" || report == "" {
		t.Fatal("explicit source, lab data and report paths required")
	}
	r, err := keyboardlab.OpenRuntime(root, data)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	rows := []map[string]any{}
	defer func() {
		value := map[string]any{
			"schema": "18u-fixed-fullcode-synthetic-routes-v1", "recordedUtc": time.Now().UTC().Format(time.RFC3339Nano),
			"sourceRoot": root, "dataDirectory": data, "layoutId": r.LayoutID, "indices": r.Builds,
			"routes": rows, "passed": !t.Failed(), "externalHostInputSent": false,
			"installedTIPConnected": false, "physicalFingerAcceptance": false, "physicalPenAcceptance": false,
			"scope": "synthetic own-window WM_TOUCH/pen-compatible mouse handling; real lab dictionary engine; memory editor",
		}
		raw, e := json.MarshalIndent(value, "", "  ")
		if e == nil {
			e = os.WriteFile(report, append(raw, '\n'), 0600)
		}
		if e != nil {
			t.Error(e)
		}
	}()
	for _, route := range []string{"synthetic-finger", "synthetic-native-pen-with-promoted-mouse", "synthetic-legacy-pen-mouse"} {
		t.Run(route, func(t *testing.T) {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()
			a, cleanup := penCompatibilityFixture(t)
			defer cleanup()
			p, err := newPreview(r.Sessions, r.LayoutID, true)
			if err != nil {
				t.Fatal(err)
			}
			a.preview = p
			board, err := touchScreenBoard(a.s.Board)
			if err != nil {
				t.Fatal(err)
			}
			a.s = tk.NewState(board)
			a.s.Semantic, a.s.Original = true, true
			a.o.Preview, a.o.TouchUI = true, true
			a.top = a.touchHeaderLayout().height
			if a.preview.emit != nil || a.installed != nil || a.host != nil || a.demo != nil {
				t.Fatal("external output must remain disconnected")
			}
			// Exercise the actual settings controls before the fixed key sequence.
			tapTouchControl(t, a, "settings")
			tapTouchSetting(t, a, "full")
			tapTouchControl(t, a, "settings")
			if a.preview.mode != "full" || a.preview.snapshot.Modes.Input != "chinese" || a.s.Shift {
				t.Fatal("full Chinese base layer not selected")
			}
			id := uint32(100)
			tap := func(x, y int32) {
				id++
				before := string(a.preview.editor.text)
				if route == "synthetic-legacy-pen-mouse" {
					promotedPenMouse(a, 0x0201, 0xff515702, x, y)
				} else {
					down := uint32(0x1a)
					if route == "synthetic-native-pen-with-promoted-mouse" {
						down = 0x5a
					}
					nativePenFrame(a, id, down, x, y)
					if route == "synthetic-native-pen-with-promoted-mouse" {
						promotedPenMouse(a, 0x0201, 0xff515702, x, y)
					}
				}
				if string(a.preview.editor.text) != before {
					t.Fatal("DOWN committed text")
				}
				if route == "synthetic-legacy-pen-mouse" {
					promotedPenMouse(a, 0x0202, 0xff515702, x, y)
				} else {
					up := uint32(0x14)
					if route == "synthetic-native-pen-with-promoted-mouse" {
						up = 0x54
					}
					nativePenFrame(a, id, up, x, y)
					if route == "synthetic-native-pen-with-promoted-mouse" {
						promotedPenMouse(a, 0x0202, 0xff515782, x, y)
					}
				}
				// A repeated terminal UP must never duplicate code or candidate output.
				text, raw := string(a.preview.editor.text), a.preview.snapshot.State.RawInput
				if route == "synthetic-legacy-pen-mouse" {
					promotedPenMouse(a, 0x0202, 0xff515702, x, y)
				} else {
					up := uint32(0x14)
					if route == "synthetic-native-pen-with-promoted-mouse" {
						up = 0x54
					}
					nativePenFrame(a, id, up, x, y)
				}
				if string(a.preview.editor.text) != text || a.preview.snapshot.State.RawInput != raw {
					t.Fatal("repeated UP changed state")
				}
			}
			progress := []string{}
			for i, key := range []struct{ id, ascii, raw string }{{"R06K12", "n", "n"}, {"R05K14", "i", "ni"}, {"R05K14", "i", "nii"}, {"R05K14", "i", "niii"}} {
				x, y := previewKeyPoint(t, a, func(k tk.Key, v tk.View) bool {
					return k.ID == key.id && v.Action.Type == "input" && v.Action.ASCII == key.ascii
				})
				tap(x, y)
				if a.preview.snapshot.State.RawInput != key.raw || string(a.preview.editor.text) != "" {
					t.Fatalf("key %d: raw=%q output=%q", i, a.preview.snapshot.State.RawInput, string(a.preview.editor.text))
				}
				progress = append(progress, a.preview.snapshot.State.RawInput)
			}
			candidateIndex := -1
			for i, c := range a.preview.snapshot.State.Candidates {
				if c.Text == "你" {
					candidateIndex = i
					break
				}
			}
			if candidateIndex < 0 {
				t.Fatalf("niii lacks visible 你 candidate: %+v", a.preview.snapshot.State.Candidates)
			}
			old := a.preview.candidate(candidateIndex)
			area := a.candidateRect(candidateIndex)
			tap((area.L+area.R)/2, (area.T+area.B)/2)
			if string(a.preview.editor.text) != "你" || a.preview.snapshot.State.RawInput != "" || len(a.preview.snapshot.State.Candidates) != 0 || a.preview.snapshot.Commit != "" {
				t.Fatalf("commit not consumed once/cleared: output=%q state=%+v", string(a.preview.editor.text), a.preview.snapshot.State)
			}
			if err := a.preview.selectCandidate(old); err == nil {
				t.Fatal("stale candidate replay accepted")
			}
			if string(a.preview.editor.text) != "你" {
				t.Fatal("stale replay duplicated output")
			}
			rows = append(rows, map[string]any{"route": route, "mode": "full", "keyIds": []string{"N08", "M03", "M03", "M03"}, "physicalIds": []string{"R06K12", "R05K14", "R05K14", "R05K14"}, "rawProgress": progress, "candidate": "你", "candidateIndex": candidateIndex, "output": string(a.preview.editor.text), "rawAfterCommit": a.preview.snapshot.State.RawInput, "candidateCountAfterCommit": len(a.preview.snapshot.State.Candidates), "downDidNotCommit": true, "duplicateUpRejected": true, "staleCandidateReplayRejected": true, "passed": true})
			t.Logf("%s: N08 M03 M03 M03 => niii => 你 exactly once; composition cleared; repeated UP and stale candidate rejected", route)
		})
	}
}
