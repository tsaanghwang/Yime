//go:build windows && (amd64 || arm64)

package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/keyboardlab"
	tk "github.com/tsaanghwang/Yime/go-backend/internal/touchkeyboard"
	"html"
	"image"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"
)

var u32 = syscall.NewLazyDLL("user32.dll")
var g32 = syscall.NewLazyDLL("gdi32.dll")
var k32 = syscall.NewLazyDLL("kernel32.dll")

func U(n string) *syscall.LazyProc { return u32.NewProc(n) }
func G(n string) *syscall.LazyProc { return g32.NewProc(n) }
func str(s string) *uint16         { p, _ := syscall.UTF16PtrFromString(s); return p }
func ptr(p *uint16) uintptr        { return uintptr(unsafe.Pointer(p)) }

type point struct{ X, Y int32 }
type rect struct{ L, T, R, B int32 }
type message struct {
	H       uintptr
	M       uint32
	W, L    uintptr
	Time    uint32
	P       point
	Private uint32
}
type wc struct {
	Size, Style                        uint32
	Proc                               uintptr
	Cls, Wnd                           int32
	Instance, Icon, Cursor, Background uintptr
	Menu, Name                         *uint16
	SmallIcon                          uintptr
}
type paint struct {
	DC              uintptr
	Erase           int32
	R               rect
	Restore, Update int32
	Reserved        [32]byte
}
type monitor struct {
	Size          uint32
	Monitor, Work rect
	Flags         uint32
	Device        [32]uint16
}
type guiInfo struct {
	Size, Flags                                        uint32
	Active, Focus, Capture, MenuOwner, MoveSize, Caret uintptr
	CaretRect                                          rect
}
type touch struct {
	X, Y                  int32
	Source                uintptr
	ID, Flags, Mask, Time uint32
	Extra                 uintptr
	CW, CH                uint32
}
type target struct{ Window, Focus uintptr }

// INPUT is a 40-byte union on Windows x64/ARM64. Keyboard fields occupy its
// first 24 bytes; do not use a shortened KEYBDINPUT struct as cbSize.
type input struct {
	Type uint32
	Pad  uint32
	Data [32]byte
}
type ui struct {
	h                uintptr
	s                *tk.State
	ppm              float64
	o                options
	status           string
	owners           map[uint32]target
	top, border      int
	hidden           bool
	font             uintptr
	monitorName      string
	lastTarget       target
	releasingCapture bool
	focusStarted     uint32
	touchReader      func(uintptr, uintptr) ([]touch, error)
	preview          *preview
	previewTouches   map[uint32]*previewGesture
	glyphFont        uintptr
	glyphs           map[string]string
	showGlyphs       bool
	host             *deliveryGate
	hostBusy         bool
	navSelecting     bool // Applies only to auxiliary navigation, never character keys.
	cancelGeneration uint64
}

var active *ui
var callback = syscall.NewCallback(windowProc)

const wmTouch = 0x0240
const drawTextNoPrefix = 0x0800

var focusCallback = syscall.NewCallback(func(hook, event, hwnd, object, child, thread, tick uintptr) uintptr {
	a := active
	if a != nil && a.host != nil {
		if a.host.target.Window != 0 && int32(uint32(tick)-a.focusStarted) >= 0 {
			a.loseHostFocus("焦点已变化；未确认组合已取消，请重新绑定目标")
		}
		return 0
	}
	if a != nil && a.lastTarget.Window != 0 && int32(uint32(tick)-a.focusStarted) >= 0 {
		a.cancel()
		a.lastTarget = target{}
		a.status = "Focus changed: gestures and one-shot modifiers cancelled."
		a.invalidate()
	}
	return 0
})

type toolButton struct {
	l, r          int32
	action, label string
}

var toolButtons = []toolButton{
	{8, 73, "smaller", "Ruler -1%"}, {78, 148, "larger", "Ruler +1%"},
	{155, 265, "layout", ""}, {275, 345, "hide", "Hide"},
	{355, 425, "close", "Close"}, {435, 515, "help", "Help / 帮助"},
}

func toolbarAction(x, y int32) string {
	if y < 28 || y >= 72 {
		return ""
	}
	for _, b := range toolButtons {
		if x >= b.l && x < b.r {
			return b.action
		}
	}
	return ""
}
func touchPromotedMouse(extra uintptr) bool {
	return uint32(extra)&0xffffff80 == 0xff515780
}
func clampWindow(current, work rect, width, height int32) rect {
	x := max(work.L, min(current.L, work.R-width))
	y := max(work.T, min(current.T, work.B-height))
	return rect{x, y, x + width, y + height}
}

const top = 110
const border = 10

func run(o options) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if p := U("SetProcessDpiAwarenessContext"); p.Find() == nil {
		p.Call(^uintptr(3))
	} // PER_MONITOR_AWARE_V2
	b, e := load(o)
	if e != nil {
		return e
	}
	if o.KeyView != "" && o.KeyView != "english" && o.KeyView != "original" {
		return errors.New("unknown key-view")
	}
	m := currentMonitor(0)
	ppm, e := tk.PixelsPerMM(int(m.Monitor.R-m.Monitor.L), o.ScreenMM)
	if e != nil {
		return e
	}
	ppm, e = tk.Calibrate(ppm, 100, o.ObservedMM)
	if e != nil {
		return e
	}
	a := &ui{s: tk.NewState(b), ppm: ppm, o: o, owners: map[uint32]target{}, top: top, border: border, status: "English text / Ctrl Alt shortcuts. Chinese composition is not connected in this milestone.", monitorName: syscall.UTF16ToString(m.Device[:])}
	a.s.Original = o.KeyView == "original"
	if o.Preview || o.Host {
		r, err := keyboardlab.OpenRuntime(o.Root, o.DataDir)
		if err != nil {
			return err
		}
		defer r.Close()
		a.preview, err = newPreview(r.Sessions, b.LayoutID, o.KeyView != "original")
		if err != nil {
			return err
		}
		a.s.Semantic = true
		a.s.Original = a.preview.original()
		a.top = 300
		a.previewTouches = map[uint32]*previewGesture{}
		a.status = "中文预览：输出仅在下方文本区；无系统输入。鼠标/模拟检查不代表手指或笔验收。"
		fontPath, err := filepath.Abs(filepath.Join(o.Root, "go-backend/input_methods/yime/data/fonts/YinYuan-Regular.ttf"))
		if err != nil {
			return err
		}
		if n, _, _ := G("AddFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0); n == 0 {
			return fmt.Errorf("无法加载进程私有 YinYuan 字体")
		}
		defer G("RemoveFontResourceExW").Call(ptr(str(fontPath)), 0x10, 0)
		a.glyphs, err = loadPreviewGlyphs(o.Root)
		if err != nil {
			return err
		}
		a.showGlyphs = true
		if o.Host {
			a.initHost()
		}
	}
	active = a
	defer func() { active = nil }()
	instance, _, _ := k32.NewProc("GetModuleHandleW").Call(0)
	c := wc{Proc: callback, Instance: instance, Name: str("YimeTouchKeyboardLab")}
	c.Size = uint32(unsafe.Sizeof(c))
	U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&c)))
	width := int(math.Ceil(b.Bounds.Width*tk.UnitMM*ppm)) + border*2
	height := int(math.Ceil(b.Bounds.Height*tk.UnitMM*ppm)) + a.top + border
	if width > int(m.Work.R-m.Work.L) || height > int(m.Work.B-m.Work.T) {
		return fmt.Errorf("%.2f x %.2f mm keyboard does not fit this monitor at 19.05mm/u; choose a numeric-zone profile or calibrate the monitor; no automatic shrinking", b.Bounds.Width*tk.UnitMM, b.Bounds.Height*tk.UnitMM)
	}
	title := "Yime desktop touch keyboard - English milestone"
	if o.Preview {
		title = "Yime 18u 中文受控预览（不向其他应用输入）"
	}
	if o.Host {
		title = "Yime 18u 中文宿主输入实验"
	}
	h, _, err := U("CreateWindowExW").Call(0x08000088, ptr(c.Name), ptr(str(title)), 0x80000000, uintptr(m.Work.L+(m.Work.R-m.Work.L-int32(width))/2), uintptr(m.Work.B-int32(height)-8), uintptr(width), uintptr(height), 0, 0, instance, 0)
	if h == 0 {
		return fmt.Errorf("CreateWindow: %w", err)
	}
	a.h = h
	defer func() {
		U("DestroyWindow").Call(h)
		if a.font != 0 {
			G("DeleteObject").Call(a.font)
		}
		if a.glyphFont != 0 {
			G("DeleteObject").Call(a.glyphFont)
		}
	}()
	if ok, _, err := U("RegisterTouchWindow").Call(h, 1); ok == 0 {
		return fmt.Errorf("RegisterTouchWindow: %w", err)
	}
	// Disable press-and-hold/right-click feedback on the keyboard surface only.
	U("SetPropW").Call(h, ptr(str("MicrosoftTabletPenServiceProperty")), 0x00010001)
	fontHeight := int32(-15)
	f, _, _ := G("CreateFontW").Call(uintptr(fontHeight), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("Segoe UI")))
	a.font = f
	if o.Preview || o.Host {
		glyphHeight := int32(-19)
		a.glyphFont, _, _ = G("CreateFontW").Call(uintptr(glyphHeight), 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, ptr(str("YinYuan")))
		if a.glyphFont == 0 {
			return fmt.Errorf("无法创建 YinYuan 私有字体")
		}
	}
	U("ShowWindow").Call(h, 4)
	U("UpdateWindow").Call(h)
	if o.Shot != "" {
		drain(100 * time.Millisecond)
		return a.screenshot(o.Shot)
	}
	// Out-of-context hooks observe transitions, including away-and-back between
	// DOWN and UP. They neither inject code into hosts nor change focus.
	var hooks []uintptr
	defer func() {
		for _, hook := range hooks {
			U("UnhookWinEvent").Call(hook)
		}
	}()
	for _, event := range []uintptr{3, 0x8005} {
		if o.Preview {
			break
		} // Controlled output has no external focus owner.
		hook, _, err := U("SetWinEventHook").Call(event, event, 0, focusCallback, 0, 0, 0)
		if hook == 0 {
			return fmt.Errorf("focus monitor unavailable: %v", err)
		}
		hooks = append(hooks, hook)
	}
	if o.Smoke {
		return a.smoke(instance)
	}
	if o.HostSmoke {
		return a.hostSmoke(instance)
	}
	if ok, _, _ := U("RegisterHotKey").Call(h, 1, 0x4003, 'K'); ok == 0 {
		a.status = "Ctrl+Alt+K unavailable; use Hide/Close on this window."
	} else {
		defer U("UnregisterHotKey").Call(h, 1)
	}
	fmt.Printf("Yime desktop keyboard: hwnd=%d, 1u=19.05mm, board=%.2fx%.2fmm, pixels/mm=%.5f (ruler verification required). Ctrl+Alt+K hides/shows.\n", h, b.Bounds.Width*tk.UnitMM, b.Bounds.Height*tk.UnitMM, ppm)
	var msg message
	for {
		v, _, _ := U("GetMessageW").Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(v) == -1 {
			return errors.New("GetMessage failed")
		}
		if v == 0 {
			break
		}
		U("TranslateMessage").Call(uintptr(unsafe.Pointer(&msg)))
		U("DispatchMessageW").Call(uintptr(unsafe.Pointer(&msg)))
	}
	return nil
}
func currentMonitor(hwnd uintptr) monitor {
	m := monitor{}
	m.Size = uint32(unsafe.Sizeof(m))
	h, _, _ := U("MonitorFromWindow").Call(hwnd, 1)
	U("GetMonitorInfoW").Call(h, uintptr(unsafe.Pointer(&m)))
	return m
}
func foreground() target {
	h, _, _ := U("GetForegroundWindow").Call()
	g := guiInfo{}
	g.Size = uint32(unsafe.Sizeof(g))
	if ok, _, _ := U("GetGUIThreadInfo").Call(0, uintptr(unsafe.Pointer(&g))); ok == 0 {
		return target{}
	}
	return target{h, g.Focus}
}
func valid(t target, own uintptr) bool {
	if t.Window == 0 || t.Focus == 0 || t.Window == own || foreground() != t {
		return false
	}
	v, _, _ := U("IsWindow").Call(t.Window)
	return v != 0
}
func (a *ui) invalidate() {
	if a.h != 0 {
		U("InvalidateRect").Call(a.h, 0, 0)
	}
}
func (a *ui) cancel() {
	a.cancelGeneration++
	a.s.Cancel()
	a.navSelecting = false
	a.owners = map[uint32]target{}
	a.previewTouches = map[uint32]*previewGesture{}
}
func (a *ui) down(id uint32, x, y int32) {
	if a.preview != nil {
		a.previewDown(id, x, y)
		return
	}
	if int(y) < a.top {
		a.toolbar(x, y)
		return
	}
	t := foreground()
	if !valid(t, a.h) {
		a.status = "Click a target application's text field first."
		a.invalidate()
		return
	}
	if a.lastTarget != t {
		a.cancel()
		a.lastTarget = t
		tick, _, _ := k32.NewProc("GetTickCount").Call()
		a.focusStarted = uint32(tick)
	}
	a.owners[id] = t
	a.s.Down(id, (float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
	a.invalidate()
}
func (a *ui) move(id uint32, x, y int32) {
	if p := a.previewTouches[id]; p != nil && !inside(p.area, x, y) {
		p.left = true
	}
	a.s.Move(id, (float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
}
func (a *ui) up(id uint32, x, y int32) {
	if a.preview != nil {
		a.previewUp(id, x, y)
		return
	}
	if owner, exists := a.owners[id]; exists && !valid(owner, a.h) {
		a.cancel()
		a.status = "Target focus changed: gesture and modifiers cancelled."
		a.invalidate()
		return
	}
	a.move(id, x, y)
	out := a.s.Up(id, (float64(x)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(y)-float64(a.top))/(tk.UnitMM*a.ppm))
	owner := a.owners[id]
	delete(a.owners, id)
	if out != nil {
		if !valid(owner, a.h) {
			a.status = "Target focus changed: input cancelled."
			a.cancel()
		} else if e := sendOutput(*out); e != nil {
			a.status = e.Error()
			a.cancel()
		} else {
			a.status = "Sent to the unchanged target focus. English literal text; Chinese bridge pending."
		}
	}
	a.invalidate()
}
func (a *ui) toolbar(x, y int32) {
	action := toolbarAction(x, y)
	if action == "" {
		return
	}
	a.cancel()
	switch action {
	case "smaller":
		a.ppm /= 1.01
		if !a.resize() {
			a.ppm *= 1.01
		}
	case "larger":
		a.ppm *= 1.01
		if !a.resize() {
			a.ppm /= 1.01
		}
	case "layout":
		if a.preview != nil {
			a.preview.toggleLayout()
			a.s.Original = a.preview.original()
		} else {
			a.s.Original = !a.s.Original
		}
	case "hide":
		if a.host != nil {
			a.loseHostFocus("键盘已隐藏；再次输入前请重新绑定")
		}
		a.hidden = true
		U("ShowWindow").Call(a.h, 0)
	case "close":
		U("DestroyWindow").Call(a.h)
	case "help":
		help := desktopHelp
		if a.preview != nil {
			help = previewHelp
		}
		if a.host != nil {
			a.loseHostFocus("帮助已打开；请重新绑定目标")
			help = hostHelp
		}
		U("MessageBoxW").Call(a.h, ptr(str(help)), ptr(str("Yime 桌面键盘使用帮助")), 0x00040040)
	}
	a.invalidate()
}
func (a *ui) resize() bool {
	m := currentMonitor(a.h)
	w := int(math.Ceil(a.s.Board.Bounds.Width*tk.UnitMM*a.ppm)) + 2*a.border
	h := int(math.Ceil(a.s.Board.Bounds.Height*tk.UnitMM*a.ppm)) + a.top + a.border
	if w > int(m.Work.R-m.Work.L) || h > int(m.Work.B-m.Work.T) {
		a.status = "Calibration exceeds monitor; keyboard is not fitted/scaled automatically."
		return false
	}
	current := rect{}
	U("GetWindowRect").Call(a.h, uintptr(unsafe.Pointer(&current)))
	position := clampWindow(current, m.Work, int32(w), int32(h))
	if ok, _, _ := U("SetWindowPos").Call(a.h, 0, uintptr(position.L), uintptr(position.T), uintptr(w), uintptr(h), 0x0014); ok == 0 {
		a.status = "Could not resize keyboard."
		return false
	}
	a.status = "Ruler calibration changed; measure the 100mm line. Unit pitch remains 19.05mm."
	return true
}
func windowProc(h uintptr, msg uint32, w, l uintptr) uintptr {
	a := active
	if a == nil || a.h != h {
		return def(h, msg, w, l)
	}
	switch msg {
	case 0x0002:
		if a.host != nil {
			a.loseHostFocus("键盘已关闭")
		}
		a.cancel()
		U("PostQuitMessage").Call(0)
		return 0
	case 0x0021:
		return 3 // WM_MOUSEACTIVATE / MA_NOACTIVATE
	case 0x024B:
		return 3 // WM_POINTERACTIVATE / PA_NOACTIVATE
	case 0x0020:
		cur, _, _ := U("LoadCursorW").Call(0, 32512)
		U("SetCursor").Call(cur)
		return 1
	case 0x0014:
		return 1
	case 0x0084:
		p := point{int32(int16(l & 0xffff)), int32(int16((l >> 16) & 0xffff))}
		U("ScreenToClient").Call(h, uintptr(unsafe.Pointer(&p)))
		if p.Y < 26 {
			return 2
		}
		return 1
	case 0x000F:
		a.paint()
		return 0
	case 0x007E, 0x02E0:
		if a.host != nil {
			a.loseHostFocus("显示环境已变化；请复核后重新绑定")
		}
		a.cancel()
		a.status = "Display changed. Recheck monitor width and ruler calibration before use."
		a.invalidate()
		return 0
	case 0x0312:
		if a.host != nil {
			a.loseHostFocus("键盘显示状态变化；请重新绑定")
		}
		a.cancel()
		a.hidden = !a.hidden
		v := uintptr(4)
		if a.hidden {
			v = 0
		}
		U("ShowWindow").Call(h, v)
		return 0
	case wmTouch:
		a.touch(w, l)
		return 0
	case 0x0201, 0x0200, 0x0202:
		extra, _, _ := U("GetMessageExtraInfo").Call()
		if touchPromotedMouse(extra) {
			return 0
		}
		x, y := int32(int16(l&0xffff)), int32(int16(l>>16))
		if msg == 0x0201 {
			a.down(0, x, y)
			U("SetCapture").Call(h)
		} else if msg == 0x0200 {
			a.move(0, x, y)
		} else {
			a.up(0, x, y)
			a.releasingCapture = true
			U("ReleaseCapture").Call()
			a.releasingCapture = false
		}
		return 0
	case 0x0215, 0x001F:
		// Releasing our mouse capture after a successful UP must preserve a
		// one-shot modifier. An unexpected capture loss still cancels it.
		if msg == 0x0215 && a.releasingCapture {
			return 0
		}
		a.cancel()
		a.invalidate()
		return 0
	}
	return def(h, msg, w, l)
}
func def(h uintptr, m uint32, w, l uintptr) uintptr {
	v, _, _ := U("DefWindowProcW").Call(h, uintptr(m), w, l)
	return v
}
func readNativeTouches(w, l uintptr) ([]touch, error) {
	defer U("CloseTouchInputHandle").Call(l)
	n := int(w & 0xffff)
	if n < 1 || n > 32 {
		return nil, errors.New("invalid touch frame")
	}
	v := make([]touch, n)
	if ok, _, err := U("GetTouchInputInfo").Call(l, uintptr(n), uintptr(unsafe.Pointer(&v[0])), unsafe.Sizeof(v[0])); ok == 0 {
		return nil, err
	}
	return v, nil
}
func (a *ui) touch(w, l uintptr) {
	reader := a.touchReader
	if reader == nil {
		reader = readNativeTouches
	}
	v, err := reader(w, l)
	if err != nil {
		a.cancel()
		return
	}
	// DOWNs precede UPs in a batched frame, so a simultaneous Shift+key frame
	// captures modifiers consistently. Every touch remains identified by dwID.
	// Windows does not sort contacts by dwID or semantic modifier order.
	for pass := 0; pass < 2; pass++ {
		for _, t := range v {
			if t.Flags&2 == 0 || t.Flags&0x80 != 0 {
				continue
			}
			p := point{t.X / 100, t.Y / 100}
			U("ScreenToClient").Call(a.h, uintptr(unsafe.Pointer(&p)))
			i := a.s.Hit((float64(p.X)-float64(a.border))/(tk.UnitMM*a.ppm), (float64(p.Y)-float64(a.top))/(tk.UnitMM*a.ppm))
			mod := false
			if i >= 0 {
				action := a.s.View(a.s.Board.Keys[i]).Action
				mod = action.Type == "shift" || action.Type == "unsupported" && (action.Label == "Ctrl" || action.Label == "Alt")
			}
			if mod == (pass == 0) {
				a.down(t.ID+1, p.X, p.Y)
			}
		}
	}

	for _, t := range v {
		p := point{t.X / 100, t.Y / 100}
		U("ScreenToClient").Call(a.h, uintptr(unsafe.Pointer(&p)))
		if t.Flags&1 != 0 {
			a.move(t.ID+1, p.X, p.Y)
		}
		if t.Flags&4 != 0 {
			a.up(t.ID+1, p.X, p.Y)
		}
	}
	a.invalidate()
}
func keyInput(vk, scan uint16, flags uint32) input {
	v := input{Type: 1}
	binary.LittleEndian.PutUint16(v.Data[:2], vk)
	binary.LittleEndian.PutUint16(v.Data[2:4], scan)
	binary.LittleEndian.PutUint32(v.Data[4:8], flags)
	return v
}

var virtualKeys = map[string]uint16{"Backspace": 8, "Tab": 9, "Enter": 13, "Escape": 27, "Space": 32, "PageUp": 33, "PageDown": 34, "End": 35, "Home": 36, "ArrowLeft": 37, "ArrowUp": 38, "ArrowRight": 39, "ArrowDown": 40, "Insert": 45, "Delete": 46}

func targetKeyboardLayout(t target) (uintptr, error) {
	thread, _, _ := U("GetWindowThreadProcessId").Call(t.Focus, 0)
	if thread == 0 {
		return 0, errors.New("target input thread unavailable")
	}
	layout, _, _ := U("GetKeyboardLayout").Call(thread)
	if layout == 0 {
		return 0, errors.New("target keyboard layout unavailable")
	}
	return layout, nil
}
func sendOutput(o tk.Output) error {
	if active != nil && active.preview != nil {
		return errors.New("controlled preview cannot send OS input")
	}
	destination := foreground()
	return sendOutputTo(o, destination)
}

// Only the host delivery adapter supplies a previously captured destination.
// The legacy English route captures it immediately above; P3 remains blocked.
func sendOutputTo(o tk.Output, destination target) error {
	if active != nil && active.preview != nil && active.host == nil {
		return errors.New("controlled preview cannot send OS input")
	}
	if !valid(destination, 0) {
		return errors.New("target focus unavailable")
	}
	// Do not disturb actual physical modifiers. In particular, never synthesize
	// releases for keys this process did not press.
	for _, v := range []uintptr{0x10, 0x11, 0x12, 0x5B, 0x5C} {
		s, _, _ := U("GetAsyncKeyState").Call(v)
		if s&0x8000 != 0 {
			return errors.New("Physical modifier is held; virtual input cancelled")
		}
	}
	var events []input
	appendVK := func(vk uint16, flags uint32) { events = append(events, keyInput(vk, 0, flags)) }
	modifiers := []uint16{}
	if o.Ctrl {
		modifiers = append(modifiers, 0x11)
	}
	if o.Alt {
		modifiers = append(modifiers, 0x12)
	}
	if o.Text != "" && !o.Ctrl && !o.Alt {
		for _, c := range utf16.Encode([]rune(o.Text)) {
			events = append(events, keyInput(0, c, 4), keyInput(0, c, 6))
		}
	} else {
		vk := virtualKeys[o.Key]
		if strings.HasPrefix(o.Key, "F") {
			n, _ := strconv.Atoi(o.Key[1:])
			if n >= 1 && n <= 12 {
				vk = uint16(111 + n)
			}
		}
		shift := o.Shift
		if o.Text != "" {
			if len([]rune(o.Text)) != 1 {
				return errors.New("shortcut requires one key")
			}
			c := []rune(o.Text)[0]
			layout, err := targetKeyboardLayout(destination)
			if err != nil {
				return err
			}
			v, _, _ := U("VkKeyScanExW").Call(uintptr(c), layout)
			if int16(v) == -1 {
				return errors.New("shortcut key unavailable in target keyboard layout")
			}
			vk = uint16(v) & 0xff
			shift = shift || v&0x100 != 0
			if v&0x600 != 0 {
				return errors.New("shortcut would require extra Ctrl/Alt in this Windows layout")
			}
		}
		if vk == 0 {
			return errors.New("unsupported editing key")
		}
		if shift {
			modifiers = append(modifiers, 0x10)
		}
		for _, m := range modifiers {
			appendVK(m, 0)
		}
		flags := uint32(0)
		if vk >= 33 && vk <= 46 {
			flags = 1
		}
		appendVK(vk, flags)
		appendVK(vk, flags|2)
		for i := len(modifiers) - 1; i >= 0; i-- {
			appendVK(modifiers[i], 2)
		}
	}
	if foreground() != destination {
		return errors.New("target focus changed before input")
	}
	return sendBatch(events, func(batch []input) (int, error) {
		n, _, err := U("SendInput").Call(uintptr(len(batch)), uintptr(unsafe.Pointer(&batch[0])), unsafe.Sizeof(batch[0]))
		return int(n), err
	})
}
func sendBatch(events []input, insert func([]input) (int, error)) error {
	if len(events) == 0 {
		return errors.New("empty input batch")
	}
	n, err := insert(events)
	if n != len(events) {
		// Release only our own modifiers if Windows inserted only a prefix.
		if releases := cleanupPrefix(events, n); len(releases) > 0 {
			_, _ = insert(releases)
		}

		return fmt.Errorf("SendInput inserted %d/%d events (target privileges or focus may prevent input): %v", n, len(events), err)
	}
	return nil
}

var tags = regexp.MustCompile(`<[^>]*>`)

func label(s string) string {
	if strings.HasPrefix(s, "<i ") {
		return "System"
	}
	return html.UnescapeString(tags.ReplaceAllString(s, ""))
}
func color(s string) uintptr {
	v, e := strconv.ParseUint(strings.TrimPrefix(s, "#"), 16, 32)
	if e != nil {
		return 0xEAF0EA
	}
	return uintptr((v>>16)&255 | (v & 0xff00) | ((v & 255) << 16))
}
func fill(dc uintptr, r rect, c uintptr) {
	b, _, _ := G("CreateSolidBrush").Call(c)
	U("FillRect").Call(dc, uintptr(unsafe.Pointer(&r)), b)
	G("DeleteObject").Call(b)
}
func text(dc uintptr, s string, r rect, flags uintptr) {
	v := utf16.Encode([]rune(s))
	if len(v) == 0 {
		return
	}
	U("DrawTextW").Call(dc, uintptr(unsafe.Pointer(&v[0])), uintptr(len(v)), uintptr(unsafe.Pointer(&r)), flags|drawTextNoPrefix)
}
func (a *ui) paint() {
	p := paint{}
	dc, _, _ := U("BeginPaint").Call(a.h, uintptr(unsafe.Pointer(&p)))
	if dc == 0 {
		return
	}
	defer U("EndPaint").Call(a.h, uintptr(unsafe.Pointer(&p)))
	r := rect{}
	U("GetClientRect").Call(a.h, uintptr(unsafe.Pointer(&r)))
	mem, _, _ := G("CreateCompatibleDC").Call(dc)
	bmp, _, _ := G("CreateCompatibleBitmap").Call(dc, uintptr(r.R), uintptr(r.B))
	old, _, _ := G("SelectObject").Call(mem, bmp)
	a.draw(mem, r)
	G("BitBlt").Call(dc, 0, 0, uintptr(r.R), uintptr(r.B), mem, 0, 0, 0x00CC0020)
	G("SelectObject").Call(mem, old)
	G("DeleteObject").Call(bmp)
	G("DeleteDC").Call(mem)
}
func (a *ui) draw(dc uintptr, r rect) {
	fill(dc, r, 0xF2F4EF)
	old, _, _ := G("SelectObject").Call(dc, a.font)
	defer G("SelectObject").Call(dc, old)
	G("SetBkMode").Call(dc, 1)
	G("SetTextColor").Call(dc, 0x302C17)
	title := "Yime desktop keyboard - ENGLISH TEXT"
	if a.preview != nil {
		title = "Yime 中文受控预览（不向其他应用输入）"
	}
	if a.host != nil {
		title = "Yime 中文宿主输入实验（先绑定目标）"
	}
	text(dc, fmt.Sprintf("%s | 1u = 19.05 mm | %.2f mm | Ctrl+Alt+K", title, a.s.Board.Bounds.Width*tk.UnitMM), rect{10, 3, r.R - 10, 25}, 0x24)
	for _, b := range toolButtons {
		title := b.label
		if b.action == "layout" {
			title = "Keys: " + map[bool]string{true: "original", false: "English"}[a.s.Original]
		}
		fill(dc, rect{b.l, 28, b.r, 72}, 0xE5EBE2)
		text(dc, title, rect{b.l, 29, b.r, 71}, 0x25)
	}
	// Ruler is in physical-coordinate pixels, independent of Windows DPI scale.
	x := int32(550)
	rr := x + int32(math.Round(100*a.ppm))
	fill(dc, rect{x, 62, rr, 64}, 0x306020)
	text(dc, "100 mm - measure this line", rect{x, 30, rr, 56}, 0x25)
	text(dc, a.status, rect{10, 80, r.R - 10, 104}, 0x24)
	if a.preview != nil {
		a.drawPreview(dc, r)
	}
	unit := tk.UnitMM * a.ppm
	for i, k := range a.s.Board.Keys {
		v := a.s.View(k)
		c := color(k.Color)
		if a.preview == nil && !nativeEnabled(v) {
			c = 0xE5E5E5
		}
		if a.s.Pressed(i) || modifierHeld(a.s, v.Action) {
			c = 0xA5CBB4
		}
		region, _, _ := G("CreateRectRgn").Call(0, 0, 0, 0)
		minx, miny, maxx, maxy := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
		for _, q := range k.Rectangles {
			l := float64(a.border) + (k.X+q.X)*unit
			t := float64(a.top) + (k.Y+q.Y)*unit
			right := l + q.Width*unit
			bottom := t + q.Height*unit
			minx = math.Min(minx, l)
			miny = math.Min(miny, t)
			maxx = math.Max(maxx, right)
			maxy = math.Max(maxy, bottom)
			part, _, _ := G("CreateRectRgn").Call(uintptr(int(l+1)), uintptr(int(t+1)), uintptr(int(right-1)), uintptr(int(bottom-1)))
			G("CombineRgn").Call(region, region, part, 2)
			G("DeleteObject").Call(part)
		}
		brush, _, _ := G("CreateSolidBrush").Call(c)
		G("FillRgn").Call(dc, region, brush)
		G("DeleteObject").Call(brush)
		outline, _, _ := G("CreateSolidBrush").Call(0xA0A0A0)
		G("FrameRgn").Call(dc, region, outline, 1, 1)
		G("DeleteObject").Call(outline)
		G("DeleteObject").Call(region)
		if v.Disabled {
			continue
		}
		// English legends use the same 12 normalized KLE positions as the browser.
		if a.preview != nil || nativeEnabled(v) {
			G("SetTextColor").Call(dc, 0x302C17)
		} else {
			G("SetTextColor").Call(dc, 0x888888)
		}
		if a.preview == nil && v.Action.Type == "toggle-language" {
			text(dc, "中文未接入", rect{int32(minx + 3), int32(miny + 3), int32(maxx - 3), int32(maxy - 3)}, 0x25)
			continue
		}
		for j, s := range v.Labels {
			s = label(s)
			if a.preview != nil && a.showGlyphs {
				if glyph, ok := a.glyphs[s]; ok {
					s = glyph
					G("SelectObject").Call(dc, a.glyphFont)
				} else {
					G("SelectObject").Call(dc, a.font)
				}
			}
			if s == "" {
				continue
			}
			col := j % 3
			row := j / 3
			l := minx + 4
			right := maxx - 4
			flags := uintptr(0x20)
			if col == 1 {
				flags |= 1
			} else if col == 2 {
				flags |= 2
			}
			y := miny + 5
			if row == 1 {
				y = miny + (maxy-miny)/2 - 9
			} else if row >= 2 {
				y = maxy - 23
			}
			text(dc, s, rect{int32(l), int32(y), int32(right), int32(y + 20)}, flags)
		}
	}
}
func modifierHeld(s *tk.State, a tk.Action) bool {
	if a.Type == "shift" {
		return s.Held("Shift")
	}
	return a.Type == "unsupported" && (a.Label == "Ctrl" || a.Label == "Alt") && s.Held(a.Label)
}
func drain(duration time.Duration) {
	until := time.Now().Add(duration)
	for time.Now().Before(until) {
		var m message
		for {
			v, _, _ := U("PeekMessageW").Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0, 1)
			if v == 0 {
				break
			}
			if m.M != 0x12 {
				U("TranslateMessage").Call(uintptr(unsafe.Pointer(&m)))
				U("DispatchMessageW").Call(uintptr(unsafe.Pointer(&m)))
			}
		}
		time.Sleep(time.Millisecond)
	}
}
func (a *ui) screenshot(path string) error {
	r := rect{}
	U("GetClientRect").Call(a.h, uintptr(unsafe.Pointer(&r)))
	dc, _, _ := U("GetDC").Call(a.h)
	defer U("ReleaseDC").Call(a.h, dc)
	mem, _, _ := G("CreateCompatibleDC").Call(dc)
	defer G("DeleteDC").Call(mem)
	bmp, _, _ := G("CreateCompatibleBitmap").Call(dc, uintptr(r.R), uintptr(r.B))
	defer G("DeleteObject").Call(bmp)
	old, _, _ := G("SelectObject").Call(mem, bmp)
	a.draw(mem, r)
	G("SelectObject").Call(mem, old)
	type info struct {
		Size                   uint32
		Width, Height          int32
		Planes, BitCount       uint16
		Compression, SizeImage uint32
		XPels, YPels           int32
		Colors, Important      uint32
		Color                  uint32
	}
	bi := info{Size: 40, Width: r.R, Height: -r.B, Planes: 1, BitCount: 32}
	raw := make([]byte, int(r.R*r.B*4))
	if n, _, e := G("GetDIBits").Call(dc, bmp, 0, uintptr(r.B), uintptr(unsafe.Pointer(&raw[0])), uintptr(unsafe.Pointer(&bi)), 0); n == 0 {
		return e
	}
	img := image.NewRGBA(image.Rect(0, 0, int(r.R), int(r.B)))
	for i := 0; i < len(raw); i += 4 {
		img.Pix[i], img.Pix[i+1], img.Pix[i+2], img.Pix[i+3] = raw[i+2], raw[i+1], raw[i], 255
	}
	f, e := os.Create(path)
	if e != nil {
		return e
	}
	defer f.Close()
	return png.Encode(f, img)
}
func (a *ui) smoke(instance uintptr) error {
	// This disposable native target belongs to this process. No existing document
	// or installed input method is opened, selected, reset, or accepted as tested.
	c := wc{Proc: syscall.NewCallback(func(h uintptr, m uint32, w, l uintptr) uintptr { return def(h, m, w, l) }), Instance: instance, Name: str("YimeTouchKeyboardTestTarget")}
	c.Size = uint32(unsafe.Sizeof(c))
	U("RegisterClassExW").Call(uintptr(unsafe.Pointer(&c)))
	h, _, e := U("CreateWindowExW").Call(0, ptr(c.Name), ptr(str("Disposable keyboard input target")), 0x10CF0000, 100, 100, 600, 220, 0, 0, instance, 0)
	if h == 0 {
		return e
	}
	defer U("DestroyWindow").Call(h)
	edit, _, e := U("CreateWindowExW").Call(0, ptr(str("EDIT")), 0, 0x50800084, 10, 10, 560, 150, h, 0, instance, 0)
	if edit == 0 {
		return e
	}
	U("SetForegroundWindow").Call(h)
	U("SetFocus").Call(edit)
	drain(100 * time.Millisecond)
	if foreground().Window != h || foreground().Focus != edit {
		return errors.New("isolated test target did not acquire foreground; no input sent")
	}
	for _, v := range []tk.Output{{Text: "a"}, {Text: "B"}, {Text: "!"}, {Key: "Backspace"}, {Text: "c"}, {Key: "ArrowLeft"}, {Text: "X"}, {Key: "End"}, {Key: "Enter"}, {Text: "z"}} {
		if e := sendOutput(v); e != nil {
			return e
		}
		drain(30 * time.Millisecond)
		if foreground().Window != h {
			return errors.New("keyboard changed the target foreground")
		}
	}
	buf := make([]uint16, 256)
	U("GetWindowTextW").Call(edit, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	got := syscall.UTF16ToString(buf)
	if got != "aBXc\r\nz" {
		return fmt.Errorf("isolated target text mismatch: %q", got)
	}
	before := foreground()
	a.down(800, 0, int32(a.top+10))
	a.up(800, 0, int32(a.top+10))
	if foreground() != before {
		return errors.New("empty keyboard hit changed target focus")
	}
	// Test the same DOWN/UP path used by touch, not only SendInput in isolation.
	for _, k := range a.s.Board.Keys {
		if k.English.Action.Type == "input" && k.English.Action.ASCII == "a" {
			x := int32(float64(a.border) + (k.X+.5)*tk.UnitMM*a.ppm)
			y := int32(float64(a.top) + (k.Y+.5)*tk.UnitMM*a.ppm)
			a.down(901, x, y)
			a.up(901, x, y)
			drain(40 * time.Millisecond)
			U("GetWindowTextW").Call(edit, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
			if syscall.UTF16ToString(buf) != "aBXc\r\nza" {
				return errors.New("native keyboard gesture did not reach target")
			}
			a.down(902, x, y)
			U("SetFocus").Call(h)
			a.up(902, x, y)
			drain(20 * time.Millisecond)
			U("SetFocus").Call(edit)
			U("GetWindowTextW").Call(edit, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
			if syscall.UTF16ToString(buf) != "aBXc\r\nza" {
				return errors.New("changed target focus was not cancelled")
			}
			break
		}
	}
	for _, k := range a.s.Board.Keys {
		if k.English.Action.ASCII != "a" {
			continue
		}
		x := int32(float64(a.border) + (k.X+.5)*tk.UnitMM*a.ppm)
		y := int32(float64(a.top) + (k.Y+.5)*tk.UnitMM*a.ppm)
		a.down(903, x, y)
		U("SetFocus").Call(h)
		U("SetFocus").Call(edit)
		drain(40 * time.Millisecond)
		a.up(903, x, y)
		drain(20 * time.Millisecond)
		U("GetWindowTextW").Call(edit, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
		if syscall.UTF16ToString(buf) != "aBXc\r\nza" {
			return errors.New("focus away-and-back did not cancel gesture")
		}
		break
	}
	// Exercise the actual mouse message path, including the synchronous
	// WM_CAPTURECHANGED caused by ReleaseCapture after Shift UP.
	for _, k := range a.s.Board.Keys {
		if k.English.Action.Type != "shift" {
			continue
		}
		x := int32(float64(a.border) + (k.X+.5)*tk.UnitMM*a.ppm)
		y := int32(float64(a.top) + (k.Y+.5)*tk.UnitMM*a.ppm)
		packed := uintptr(uint32(uint16(x)) | uint32(uint16(y))<<16)
		windowProc(a.h, 0x0201, 0, packed)
		windowProc(a.h, 0x0202, 0, packed)
		if !a.s.Shift {
			return errors.New("mouse capture release cleared one-shot Shift")
		}
		windowProc(a.h, 0x0215, 0, 0)
		if a.s.Shift {
			return errors.New("unexpected capture loss retained one-shot Shift")
		}
		break
	}
	for _, v := range []tk.Output{{Key: "Home", Ctrl: true}, {Key: "End", Shift: true}, {Text: "q"}} {
		if e := sendOutput(v); e != nil {
			return e
		}
		drain(30 * time.Millisecond)
	}
	U("GetWindowTextW").Call(edit, uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)))
	if syscall.UTF16ToString(buf) != "q\r\nza" {
		return fmt.Errorf("Ctrl/Shift editing mismatch: %q", syscall.UTF16ToString(buf))
	}
	fmt.Println("PASS: isolated native EDIT received Unicode text, uppercase, punctuation, Backspace, caret editing and Enter; Ctrl/Shift selection, native gesture routing, mouse Shift capture and observed focus away-and-back cancellation passed; target foreground/focus retained. Not physical touch or Notepad/Word acceptance.")
	return nil
}

func nativeEnabled(v tk.View) bool {
	if v.Disabled || v.Action.Type == "disabled" || v.Action.Type == "toggle-language" {
		return false
	}
	if v.Action.Type != "unsupported" {
		return true
	}
	if v.Action.Label == "Ctrl" || v.Action.Label == "Alt" {
		return true
	}
	if strings.HasPrefix(v.Action.Label, "F") {
		n, _ := strconv.Atoi(v.Action.Label[1:])
		return n >= 1 && n <= 12
	}
	return false
}

// Release only the keys this successful prefix actually pressed, including a
// Unicode packet whose key-up was not inserted. Never replay a text event.
func cleanupPrefix(events []input, n int) []input {
	if n < 0 || n > len(events) {
		return nil
	}
	var pending []input
	for _, e := range events[:n] {
		flags := binary.LittleEndian.Uint32(e.Data[4:8])
		if flags&2 == 0 {
			pending = append(pending, e)
		} else {
			for i := len(pending) - 1; i >= 0; i-- {
				if binary.LittleEndian.Uint32(pending[i].Data[:4]) == binary.LittleEndian.Uint32(e.Data[:4]) {
					pending = append(pending[:i], pending[i+1:]...)
					break
				}
			}
		}
	}
	var result []input
	for i := len(pending) - 1; i >= 0; i-- {
		e := pending[i]
		binary.LittleEndian.PutUint32(e.Data[4:8], binary.LittleEndian.Uint32(e.Data[4:8])|2)
		result = append(result, e)
	}
	return result
}
