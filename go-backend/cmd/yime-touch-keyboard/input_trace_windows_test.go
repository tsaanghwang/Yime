//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
)

func TestInputTraceRejectsNonPreviewBeforeAnyRuntime(t *testing.T) {
	for _, o := range []options{{}, {Preview: true, Host: true}, {Preview: true, EnglishOnly: true}, {Preview: true, CheckPackage: true}, {Preview: true, Shot: "test.png"}} {
		o.InputTrace = filepath.Join(t.TempDir(), "unused.jsonl")
		if err := execute(o); err == nil || !strings.Contains(err.Error(), "interactive --preview only") {
			t.Fatal("trace option reached a non-preview runtime", err)
		}
		if _, err := os.Stat(o.InputTrace); !os.IsNotExist(err) {
			t.Fatal("invalid mode created trace evidence")
		}
	}
}

func TestInputTracePreservesEvidenceAndOmitsContent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "input.jsonl")
	trace, err := openInputTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	a := previewUI(t)
	a.inputTrace = trace
	a.preview.editor.insert("PRIVATE_DOCUMENT_SENTINEL")
	previewAction(t, a.preview, "input", "a", "")
	a.s.Shift = true
	a.traceInput("sample", 0, 0, 0)
	if err := trace.file.Close(); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "PRIVATE_DOCUMENT_SENTINEL") || strings.Contains(string(raw), "\"rawInput\"") {
		t.Fatal("diagnostics logged document content")
	}
	var row map[string]any
	if err := json.Unmarshal(raw, &row); err != nil {
		t.Fatal(err)
	}
	if row["shiftLatch"] != true || row["rawLength"] != float64(1) || row["localOutputLength"] != float64(len("PRIVATE_DOCUMENT_SENTINEL")) {
		t.Fatal("diagnostic state missing", row)
	}
	if _, err := openInputTrace(path); err == nil {
		t.Fatal("old trace overwritten")
	}
	again, _ := os.ReadFile(path)
	if string(again) != string(raw) {
		t.Fatal("old evidence changed")
	}
}

func TestPenCompatibleMouseShiftSurvivesNativeReleaseCapture(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a := previewUI(t)
	previewAction(t, a.preview, "toggle-language", "", "")
	a.s.Original = a.preview.original()
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create native capture fixture")
	}
	index := int32(-4)
	old, _, _ := U("SetWindowLongPtrW").Call(h, uintptr(index), callback)
	if old == 0 {
		U("DestroyWindow").Call(h)
		t.Fatal("subclass fixture")
	}
	previous := active
	a.h, active = h, a
	defer func() {
		U("SetWindowLongPtrW").Call(h, uintptr(index), old)
		U("DestroyWindow").Call(h)
		active = previous
	}()
	tap := func(x, y int32) {
		l := uintptr(uint32(x) | uint32(y)<<16)
		U("SendMessageW").Call(h, 0x0201, 0, l)
		if captured, _, _ := U("GetCapture").Call(); captured != h {
			t.Fatal("fixture did not get native capture")
		}
		U("SendMessageW").Call(h, 0x0202, 0, l)
	}
	sx, sy := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "shift" })
	ax, ay := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "input" && v.Action.ASCII == "a" })
	tap(sx, sy)
	if !a.s.Shift {
		t.Fatal("normal native release cleared one-shot Shift")
	}
	tap(ax, ay)
	tap(ax, ay)
	if string(a.preview.editor.text) != "Aa" || a.s.Shift {
		t.Fatal("pen-compatible mouse route did not preserve one-shot Shift", string(a.preview.editor.text))
	}
}
