//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/binary"
	"testing"
	"unsafe"
)

func TestWin32StructSizes(t *testing.T) {
	if unsafe.Sizeof(input{}) != 40 || unsafe.Sizeof(touch{}) != 48 || unsafe.Sizeof(guiInfo{}) != 72 || unsafe.Sizeof(message{}) != 48 {
		t.Fatal("Windows ABI size mismatch")
	}
}
func TestPartialSendReleasesOnlyInsertedKeysWithoutRepeatingText(t *testing.T) {
	events := []input{keyInput(17, 0, 0), keyInput(18, 0, 0), keyInput(65, 0, 0), keyInput(65, 0, 2), keyInput(18, 0, 2), keyInput(17, 0, 2)}
	for n := 0; n <= len(events); n++ {
		r := cleanupPrefix(events, n)
		want := []int{0, 1, 2, 3, 2, 1, 0}[n]
		if len(r) != want {
			t.Fatalf("prefix %d got %d", n, len(r))
		}
		for _, e := range r {
			if binary.LittleEndian.Uint32(e.Data[4:8])&2 == 0 {
				t.Fatal("replayed key-down")
			}
		}
	}
	r := cleanupPrefix([]input{keyInput(0, 'a', 4), keyInput(0, 'a', 6)}, 1)
	if len(r) != 1 || binary.LittleEndian.Uint32(r[0].Data[4:8]) != 6 {
		t.Fatal("unfinished Unicode packet not released")
	}
}

func TestToolbarMatchesPaintedButtonsAndClampsCalibration(t *testing.T) {
	for _, p := range []point{{390, 90}, {390, 75}, {0, 40}, {74, 40}, {270, 40}, {440, 20}} {
		if toolbarAction(p.X, p.Y) != "" {
			t.Fatalf("unpainted toolbar hit: %+v", p)
		}
	}
	if toolbarAction(390, 40) != "close" || toolbarAction(450, 40) != "help" {
		t.Fatal("painted toolbar inaccessible")
	}
	got := clampWindow(rect{100, 700, 500, 1000}, rect{0, 0, 1000, 1000}, 500, 400)
	if got != (rect{100, 600, 600, 1000}) {
		t.Fatalf("bottom row off-screen: %+v", got)
	}
}
func TestPenMouseAllowedAndOnlyTouchDuplicatesSuppressed(t *testing.T) {
	if touchPromotedMouse(0xff515700) || touchPromotedMouse(0) || !touchPromotedMouse(0xff515780) || !touchPromotedMouse(0xff51578a) {
		t.Fatal("pen/touch signature classification")
	}
}
func TestNativeTouchMessageRoutesToReader(t *testing.T) {
	h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, 0, 0, 0, 1, 1, 0, 0, 0, 0)
	if h == 0 {
		t.Fatal("create own hidden fixture")
	}
	defer U("DestroyWindow").Call(h)
	previous := active
	defer func() { active = previous }()
	calls := 0
	active = &ui{h: h, touchReader: func(w, l uintptr) ([]touch, error) {
		calls++
		if w != 2 || l != 99 {
			t.Fatal("touch frame arguments lost")
		}
		return nil, nil
	}}
	windowProc(h, 0x0240, 2, 99)
	if calls != 1 {
		t.Fatal("WM_TOUCH did not reach native input reader")
	}
}
func TestAmpersandDrawsPixelsAsLiteralText(t *testing.T) {
	dc, _, _ := G("CreateCompatibleDC").Call(0)
	if dc == 0 {
		t.Fatal("create memory DC")
	}
	defer G("DeleteDC").Call(dc)
	bitmap, _, _ := G("CreateCompatibleBitmap").Call(dc, 64, 32)
	if bitmap == 0 {
		t.Fatal("create own bitmap")
	}
	old, _, _ := G("SelectObject").Call(dc, bitmap)
	defer func() { G("SelectObject").Call(dc, old); G("DeleteObject").Call(bitmap) }()
	fill(dc, rect{0, 0, 64, 32}, 0xffffff)
	G("SetTextColor").Call(dc, 0)
	G("SetBkMode").Call(dc, 1)
	text(dc, "&", rect{0, 0, 64, 32}, 0x20)
	ink := 0
	for y := uintptr(0); y < 32; y++ {
		for x := uintptr(0); x < 64; x++ {
			v, _, _ := G("GetPixel").Call(dc, x, y)
			if v == 0 {
				ink++
			}
		}
	}
	if ink == 0 {
		t.Fatal("ampersand swallowed by mnemonic processing")
	}
}
