//go:build windows && (amd64 || arm64)

package main

import (
	"fmt"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"unsafe"
)

func TestTouchHelpNativeInputRoutesPreserveComposition(t *testing.T) {
	for _, route := range []string{"mouse", "finger", "pen"} {
		for _, paused := range []bool{false, true} {
			t.Run(route+map[bool]string{false: "-CN", true: "-EN-paused"}[paused], func(t *testing.T) {
				runtime.LockOSThread()
				defer runtime.UnlockOSThread()
				a, close := penCompatibilityFixture(t)
				defer close()
				b, err := touchScreenBoard(a.s.Board)
				if err != nil {
					t.Fatal(err)
				}
				a.s = tk.NewState(b)
				a.s.Semantic = true
				a.o.TouchUI = true
				a.top = a.touchHeaderLayout().height
				previewAction(t, a.preview, "toggle-language", "", "") // fixture starts EN
				a.preview.editor.insert("12")
				previewAction(t, a.preview, "input", "n", "")
				if paused {
					previewAction(t, a.preview, "toggle-language", "", "")
				}
				a.s.Original = a.preview.original()
				stamp := a.preview.stamp()
				tap := func(x, y int32) {
					switch route {
					case "mouse":
						windowProc(a.h, 0x0201, 0, uintptr(uint32(x)|uint32(y)<<16))
						windowProc(a.h, 0x0202, 0, uintptr(uint32(x)|uint32(y)<<16))
					case "finger":
						nativePenFrame(a, 71, 0x1a, x, y)
						nativePenFrame(a, 71, 0x14, x, y)
					case "pen":
						nativePenFrame(a, 72, 0x5a, x, y)
						promotedPenMouse(a, 0x0201, 0xff515702, x, y)
						nativePenFrame(a, 72, 0x54, x, y)
						promotedPenMouse(a, 0x0202, 0xff515782, x, y)
					}
				}
				x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "touch-ui" && v.Action.Key == "help" })
				tap(x, y)
				if !a.touchHelpOpen || a.touchSettingsOpen {
					t.Fatal("native route did not open internal help")
				}
				box := a.touchHelpPageRect(true)
				tap((box.L+box.R)/2, (box.T+box.B)/2)
				if a.touchHelpPage != 1 {
					t.Fatal("native route could not page help")
				}
				// Help text owns the covered key area, including non-button taps.
				tap(30, a.touchSettingsTop()+80)
				if a.preview.stamp() != stamp || a.preview.snapshot.State.RawInput != "n" || string(a.preview.editor.text) != "12" {
					t.Fatal("help changed/committed composition or typed through sheet")
				}
				if (a.preview.snapshot.Modes.Input == "english") != paused {
					t.Fatal("help changed language")
				}
				tap(x, y)
				if a.touchHelpOpen || a.preview.stamp() != stamp {
					t.Fatal("help did not return without mutating engine")
				}
			})
		}
	}
}
func TestTouchHelpRetainsAllInstructionsAndRejectsMovedOutTap(t *testing.T) {
	a := touchUIFixture(t)
	x, y := previewKeyPoint(t, a, func(_ tk.Key, v tk.View) bool { return v.Action.Type == "touch-ui" && v.Action.Key == "help" })
	a.down(1, x, y)
	a.move(1, -1, y)
	a.move(1, x, y)
	a.up(1, x, y)
	if a.touchHelpOpen {
		t.Fatal("moved-out help tap activated")
	}
	tapTouchControl(t, a, "help")
	a.up(51, x, y)
	if !a.touchHelpOpen {
		t.Fatal("duplicate UP toggled help twice")
	}
	for i := 0; i < 10; i++ {
		_ = a.applyTouchImmediate("help-next")
	}
	if a.touchHelpPage != len(touchHelpPages())-1 {
		t.Fatal("page not bounded")
	}
	tapTouchControl(t, a, "settings")
	if a.touchHelpOpen || !a.touchSettingsOpen {
		t.Fatal("settings/help sheets overlap")
	}
	content := strings.Join(touchHelpPages(), "\n")
	for _, line := range strings.Split(touchHelp, "\n")[1:] {
		if line != "" && !strings.Contains(content, line) {
			t.Fatal("help paragraph omitted")
		}
	}
	for _, ppm := range []float64{3, 4.82, 8.2} {
		a.ppm = ppm
		r := a.touchHelpPageRect(true)
		bottom := int32(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*ppm)) + int32(a.top+a.border)
		if r.B > bottom || r.T <= a.touchSettingsTop()+80 || r.R > a.previewWidth() {
			t.Fatal("help controls do not fit", ppm, r)
		}
	}
}

func TestTouchHelpHostStillInvalidatesBindingWithoutSending(t *testing.T) {
	a := touchUIFixture(t)
	a.preview.editor.insert("12")
	previewAction(t, a.preview, "input", "n", "")
	current := hostTarget{1, 2, 3, 4}
	sends := 0
	a.host = &deliveryGate{current: func() hostTarget { return current }, send: func(hostTarget, tk.Output) error { sends++; return nil }}
	if err := a.host.bind(current); err != nil {
		t.Fatal(err)
	}
	tapTouchControl(t, a, "help")
	if !a.touchHelpOpen || !a.preview.fault || a.host.target.Window != 0 || a.preview.snapshot.State.RawInput != "" || string(a.preview.editor.text) != "12" || sends != 0 {
		t.Fatal("host help retained binding, sent input or changed confirmed text")
	}
	tapTouchControl(t, a, "help")
	if a.touchHelpOpen || a.host.target.Window != 0 || sends != 0 {
		t.Fatal("return from help rebound host or emitted input")
	}
}

func TestTouchHelpTextFitsNativeFont(t *testing.T) {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	a := touchUIFixture(t)
	for _, ppm := range []float64{3, 4.82, 8.2} {
		a.ppm = ppm
		height := -int32(math.Round(tk.UnitMM * ppm * .2))
		font, _, _ := G("CreateFontW").Call(uintptr(height), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
		if font == 0 {
			t.Fatal("create help font")
		}
		dc, _, _ := G("CreateCompatibleDC").Call(0)
		previous, _, _ := G("SelectObject").Call(dc, font)
		_, _, heading := a.touchSettingMetrics()
		footer := a.touchHelpPageRect(false)
		for i, page := range touchHelpPages() {
			box := rect{20, a.touchSettingsTop() + heading + 8, a.previewWidth() - 20, footer.T - 12}
			measured := box
			U("DrawTextW").Call(dc, ptr(str(page)), ^uintptr(0), uintptr(unsafe.Pointer(&measured)), 0x10|0x400|drawTextNoPrefix)
			if measured.B > box.B {
				t.Errorf("page %d at ppm %.2f clips: text bottom %d, available %d", i, ppm, measured.B, box.B)
			}
		}
		G("SelectObject").Call(dc, previous)
		G("DeleteDC").Call(dc)
		G("DeleteObject").Call(font)
	}
	// Optional off-screen rendering uses only a disposable window owned by
	// this test process, never captures or drives any existing app.
	if dir := os.Getenv("YIME_TOUCH_HELP_RENDER_DIR"); dir != "" {
		previousDPI, _, _ := U("SetThreadDpiAwarenessContext").Call(^uintptr(3))
		defer U("SetThreadDpiAwarenessContext").Call(previousDPI)
		abs, err := filepath.Abs(dir)
		if err != nil {
			t.Fatal(err)
		}
		root, _ := filepath.Abs("../../../.generated")
		rel, err := filepath.Rel(root, abs)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			t.Fatal("render output must be inside workspace .generated")
		}
		if err = os.MkdirAll(abs, 0700); err != nil {
			t.Fatal(err)
		}
		a.ppm = 8.195331
		a.o.Theme = "dark"
		a.touchHelpOpen = true
		width := a.previewWidth()
		height := int32(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*a.ppm)) + int32(a.top+a.border)
		h, _, _ := U("CreateWindowExW").Call(0, ptr(str("STATIC")), 0, keyboardWindowStyle, 0, 0, uintptr(width), uintptr(height), 0, 0, 0, 0)
		if h == 0 {
			t.Fatal("create disposable render window")
		}
		a.h = h
		defer U("DestroyWindow").Call(h)
		client := rect{}
		U("GetClientRect").Call(h, uintptr(unsafe.Pointer(&client)))
		if client.R != width || client.B != height {
			t.Fatalf("offscreen render resized unexpectedly: want %dx%d, got %+v", width, height, client)
		}
		for _, v := range []struct {
			pixels int32
			target *uintptr
		}{{-15, &a.font}, {-31, &a.keyFont}, {-22, &a.touchFont}} {
			f, _, _ := G("CreateFontW").Call(uintptr(v.pixels), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
			*v.target = f
			defer G("DeleteObject").Call(f)
		}
		for i := range touchHelpPages() {
			a.touchHelpPage = i
			if err := a.screenshot(filepath.Join(abs, fmt.Sprintf("help-%d.png", i+1))); err != nil {
				t.Fatal(err)
			}
		}
	}
}
