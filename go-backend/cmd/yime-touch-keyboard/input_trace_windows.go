//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
	"unicode/utf8"
	"unsafe"
)

// Opt-in diagnostics for this preview window only. Never record host text,
// composition content, or global input, and never replace earlier evidence.
type inputTrace struct {
	file          *os.File
	encoder       *json.Encoder
	start         time.Time
	sequence      uint64
	messageSerial uint64
	messageID     uint64
	epoch         uint64
	minimized     bool
	err           error
}

func openInputTrace(path string) (*inputTrace, error) {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return nil, fmt.Errorf("create new preview input trace: %w", err)
	}
	return &inputTrace{file: f, encoder: json.NewEncoder(f), start: time.Now()}, nil
}

func (t *inputTrace) write(row map[string]any) {
	if t == nil || t.err != nil {
		return
	}
	t.sequence++
	row["schemaVersion"] = 2
	row["diagnosticVersion"] = "pr87-routing-v1"
	row["messageID"] = t.messageID
	row["epoch"] = t.epoch
	row["sequence"] = t.sequence
	row["recordedAtUTC"] = time.Now().UTC().Format(time.RFC3339Nano)
	row["elapsedMS"] = float64(time.Since(t.start)) / float64(time.Millisecond)
	t.err = t.encoder.Encode(row)
}

func tracedInputMessage(msg uint32, pressed bool) bool {
	switch msg {
	case 0x0201, 0x0202, wmTouch, 0x001F, 0x0215, 0x0005, 0x0312,
		0x0246, 0x0247, 0x0249, 0x024A, 0x024C: // Pointer down/up/enter/leave/capture.
		return true
	case 0x0200, 0x0245: // Mouse/pointer movement only while a gesture is pending.
		return pressed
	}
	return false
}

func (a *ui) traceInput(stage string, msg uint32, w, l uintptr) {
	if a.inputTrace == nil || a.inputTrace.err != nil {
		return
	}
	extra, _, _ := U("GetMessageExtraInfo").Call()
	row := map[string]any{
		"stage": stage, "message": fmt.Sprintf("0x%04x", msg),
		"wParam": fmt.Sprintf("0x%x", w), "lParam": fmt.Sprintf("0x%x", l),
		"extra":      fmt.Sprintf("0x%x", extra),
		"shiftLatch": a.s.Shift, "shiftHeld": a.s.Held("Shift"),
		"ctrlLatch": a.s.Ctrl, "altLatch": a.s.Alt,
		"cancelGeneration": a.cancelGeneration,
		"pendingGestures":  len(a.previewTouches), "selectionLatch": a.navSelecting,
		"nativePenOwnsMouse": a.nativePenOwnsMouse,
	}
	var pressed []string
	for i, k := range a.s.Board.Keys {
		if a.s.Pressed(i) {
			pressed = append(pressed, k.ID)
		}
	}
	row["pressedKeys"] = pressed
	if stream, ok := a.soundStream.(interface{ diagnostics() map[string]any }); ok {
		row["audio"] = stream.diagnostics()
	}
	row["soundUnavailable"] = a.soundUnavailable
	row["soundSuspended"] = a.soundSuspended
	if a.preview != nil {
		row["inputLanguage"] = a.preview.snapshot.Modes.Input
		row["rawLength"] = utf8.RuneCountInString(a.preview.snapshot.State.RawInput)
		row["localOutputLength"] = len(a.preview.editor.text)
		row["previewFault"] = a.preview.fault
	}
	if msg >= 0x0245 && msg <= 0x024C {
		var kind uint32
		if ok, _, _ := U("GetPointerType").Call(w&0xffff, uintptr(unsafe.Pointer(&kind))); ok != 0 {
			row["pointerType"] = kind
			row["pointerTypeRead"] = "ok"
		} else {
			row["pointerTypeRead"] = "failed"
		}
	}
	a.inputTrace.write(row)
}

// Diagnostic-only state. These helpers never dispatch input or change UI state.
// Reasons and action names are code-owned enums; never pass an error string or text.
func (a *ui) traceDecision(stage, reason string, id uint32, action string) {
	if a.inputTrace == nil || a.inputTrace.err != nil {
		return
	}
	row := map[string]any{"stage": stage, "reason": reason, "action": action,
		"pendingGestures": len(a.previewTouches), "cancelGeneration": a.cancelGeneration,
		"nativePenOwnsMouse": a.nativePenOwnsMouse}
	if stage == "touch-route" {
		row["nativeContactID"] = id
		row["gestureID"] = id + 1
	} else if stage != "page-hit" && stage != "lifecycle" && stage != "touch-read" {
		row["gestureID"] = id // 0 is the legacy mouse route.
	}
	if a.preview != nil {
		row["page"] = a.preview.snapshot.State.PageNumber
		row["hasPrevious"] = a.preview.snapshot.State.HasPrevious
		row["hasNext"] = a.preview.snapshot.State.HasNext
		row["rawLength"] = utf8.RuneCountInString(a.preview.snapshot.State.RawInput)
		row["localOutputLength"] = len(a.preview.editor.text)
	}
	a.inputTrace.write(row)
}

func (a *ui) traceLifecycle(reason string) {
	if a.inputTrace == nil || a.inputTrace.err != nil {
		return
	}
	t := a.inputTrace
	if reason == "minimized" {
		if t.minimized {
			return
		}
		t.minimized = true
	} else if reason == "size-visible" {
		if t.minimized {
			reason = "restored-reprepare-required"
			t.epoch++
			t.minimized = false
		}
	}
	a.traceDecision("lifecycle", reason, 0, "")
}

func (a *ui) tracePage(id uint32, delta int) error {
	if a.inputTrace == nil || a.inputTrace.err != nil {
		return a.preview.page(delta)
	}
	before := a.preview.snapshot.State.PageNumber
	available := a.preview.snapshot.State.HasNext
	if delta < 0 {
		available = a.preview.snapshot.State.HasPrevious
	}
	a.inputTrace.write(map[string]any{"stage": "page-request", "gestureID": id, "delta": delta,
		"pageBefore": before, "available": available})
	err := a.preview.page(delta)
	after := a.preview.snapshot.State.PageNumber
	reason := "unchanged"
	if err != nil {
		reason = "dispatch-error"
	} else if !available {
		reason = "boundary-unavailable"
	} else if before != after {
		reason = "page-changed"
	}
	a.inputTrace.write(map[string]any{"stage": "page-result", "gestureID": id, "delta": delta,
		"pageBefore": before, "pageAfter": after, "availableBefore": available,
		"hasPrevious": a.preview.snapshot.State.HasPrevious, "hasNext": a.preview.snapshot.State.HasNext,
		"reason": reason})
	return err
}

func (a *ui) traceMouseRoute(msg uint32, reason string) {
	if a.inputTrace == nil || a.inputTrace.err != nil || !tracedInputMessage(msg, len(a.previewTouches) != 0) {
		return
	}
	a.traceDecision("mouse-route", reason, 0, "")
}
