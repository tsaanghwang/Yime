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
	file     *os.File
	encoder  *json.Encoder
	start    time.Time
	sequence uint64
	err      error
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
	case 0x0200:
		return pressed
	}
	return false
}

func (a *ui) traceInput(stage string, msg uint32, w, l uintptr) {
	if a.inputTrace == nil {
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
	if a.preview != nil {
		row["inputLanguage"] = a.preview.snapshot.Modes.Input
		row["rawLength"] = utf8.RuneCountInString(a.preview.snapshot.State.RawInput)
		row["localOutputLength"] = len(a.preview.editor.text)
		row["previewFault"] = a.preview.fault
	}
	if msg >= 0x0246 && msg <= 0x024C {
		var kind uint32
		if ok, _, _ := U("GetPointerType").Call(w&0xffff, uintptr(unsafe.Pointer(&kind))); ok != 0 {
			row["pointerType"] = kind
		}
	}
	a.inputTrace.write(row)
}
