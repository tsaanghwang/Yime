//go:build windows

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"runtime"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/EasyIME/pime-go/input_methods/yime/toolhub"
)

const (
	wmAppCommand  = 0x0400 + 1
	wmAppCloseHub = 0x0400 + 2

	wsExControlparent  = 0x00010000
	wsExAppwindow      = 0x00040000
	wsOverlappedwindow = 0x00CF0000
	wsChild            = 0x40000000
	wsVisible          = 0x10000000

	swRestore    = 9
	swShowNormal = 1

	idButtonBase = 1000
)

var (
	moduser32   = syscall.NewLazyDLL("user32.dll")
	modkernel32 = syscall.NewLazyDLL("kernel32.dll")
	modcomctl32 = syscall.NewLazyDLL("comctl32.dll")

	procCreateWindowExW      = moduser32.NewProc("CreateWindowExW")
	procDefWindowProcW       = moduser32.NewProc("DefWindowProcW")
	procDispatchMessageW     = moduser32.NewProc("DispatchMessageW")
	procGetMessageW          = moduser32.NewProc("GetMessageW")
	procTranslateMessageW    = moduser32.NewProc("TranslateMessage")
	procIsDialogMessageW     = moduser32.NewProc("IsDialogMessageW")
	procPostQuitMessage      = moduser32.NewProc("PostQuitMessage")
	procRegisterClassExW     = moduser32.NewProc("RegisterClassExW")
	procPostMessageW         = moduser32.NewProc("PostMessageW")
	procShowWindow           = moduser32.NewProc("ShowWindow")
	procUpdateWindow         = moduser32.NewProc("UpdateWindow")
	procSetForegroundWindow  = moduser32.NewProc("SetForegroundWindow")
	procBringWindowToTop     = moduser32.NewProc("BringWindowToTop")
	procIsIconic             = moduser32.NewProc("IsIconic")
	procLoadIconW            = moduser32.NewProc("LoadIconW")
	procLoadCursorW          = moduser32.NewProc("LoadCursorW")
	procAdjustWindowRectEx   = moduser32.NewProc("AdjustWindowRectEx")
	procGetSystemMetrics     = moduser32.NewProc("GetSystemMetrics")
	procMessageBoxW          = moduser32.NewProc("MessageBoxW")
	procGetModuleHandleW     = modkernel32.NewProc("GetModuleHandleW")
	procInitCommonControlsEx = modcomctl32.NewProc("InitCommonControlsEx")

	wndProcCallback uintptr
)

type wndclassex struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   syscall.Handle
	Icon       syscall.Handle
	Cursor     syscall.Handle
	Background syscall.Handle
	MenuName   *uint16
	ClassName  *uint16
	IconSm     syscall.Handle
}

type winMsg struct {
	Hwnd    syscall.Handle
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      struct{ X, Y int32 }
}

type rect struct {
	Left, Top, Right, Bottom int32
}

type initCommonControlsEx struct {
	Size uint32
	ICC  uint32
}

type appState struct {
	manifest  toolhub.Manifest
	mainHWND  syscall.Handle
	clientW   int32
	clientH   int32
	buttonTop int32
}

func main() {
	manifestPath := flag.String("ManifestPath", "", "Path to pime_yime_tool_hub.json")
	flag.Parse()
	if strings.TrimSpace(*manifestPath) == "" {
		showError("缺少 ManifestPath 参数。")
		os.Exit(1)
	}
	data, err := os.ReadFile(*manifestPath)
	if err != nil {
		showError("无法读取工具清单：" + err.Error())
		os.Exit(1)
	}
	manifest := toolhub.Manifest{}
	if err := json.Unmarshal(data, &manifest); err != nil {
		showError("工具清单格式错误：" + err.Error())
		os.Exit(1)
	}
	if err := toolhub.Validate(manifest); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
	if err := runApp(&appState{manifest: manifest}); err != nil {
		showError(err.Error())
		os.Exit(1)
	}
}

func runApp(state *appState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	state.computeLayout()

	icc := initCommonControlsEx{Size: uint32(unsafe.Sizeof(initCommonControlsEx{})), ICC: 0x000000FF}
	procInitCommonControlsEx.Call(uintptr(unsafe.Pointer(&icc)))

	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeToolHub")
	cursor, _, _ := procLoadCursorW.Call(0, uintptr(32512))
	icon, _, _ := procLoadIconW.Call(instance, uintptr(32512))
	wndProcCallback = syscall.NewCallback(func(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
		return state.wndProc(hwnd, msg, wParam, lParam)
	})

	wndClass := wndclassex{
		Size:      uint32(unsafe.Sizeof(wndclassex{})),
		WndProc:   wndProcCallback,
		Instance:  syscall.Handle(instance),
		Icon:      syscall.Handle(icon),
		IconSm:    syscall.Handle(icon),
		Cursor:    syscall.Handle(cursor),
		ClassName: className,
	}
	if ret, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wndClass))); ret == 0 {
		return fmt.Errorf("RegisterClassEx failed")
	}

	title, _ := syscall.UTF16PtrFromString(state.manifest.Title)
	winW, winH := windowSizeForClient(state.clientW, state.clientH)
	screenWidth, _, _ := procGetSystemMetrics.Call(0)
	screenHeight, _, _ := procGetSystemMetrics.Call(1)
	x := (int32(screenWidth) - winW) / 2
	y := (int32(screenHeight) - winH) / 2

	hwnd, _, _ := procCreateWindowExW.Call(
		uintptr(wsExControlparent|wsExAppwindow),
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		uintptr(wsOverlappedwindow),
		uintptr(x), uintptr(y), uintptr(winW), uintptr(winH),
		0, 0, instance, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("CreateWindowEx failed")
	}
	state.mainHWND = syscall.Handle(hwnd)
	state.createControls()
	state.presentMainWindow()

	var message winMsg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		isDialog, _, _ := procIsDialogMessageW.Call(uintptr(state.mainHWND), uintptr(unsafe.Pointer(&message)))
		if isDialog != 0 {
			continue
		}
		procTranslateMessageW.Call(uintptr(unsafe.Pointer(&message)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&message)))
	}
	return nil
}

func (state *appState) computeLayout() {
	const (
		width      = int32(620)
		margin     = int32(16)
		titleH     = int32(26)
		summaryH   = int32(44)
		rowHeight  = int32(52)
		noteH      = int32(42)
		gap        = int32(8)
	)
	rowCount := (len(state.manifest.Tools) + 1) / 2
	if rowCount < 4 {
		rowCount = 4
	}
	state.clientW = width
	state.buttonTop = margin + titleH + gap + summaryH + gap
	state.clientH = state.buttonTop + int32(rowCount)*rowHeight + gap + noteH + margin
}

func (state *appState) createControls() {
	const margin = int32(16)
	createStatic(state.mainHWND, state.manifest.Title, rect{margin, 16, 580, 42}, 0)
	createStatic(state.mainHWND, state.manifest.Summary, rect{margin, 48, 596, 92}, 0)

	const (
		rowHeight = int32(52)
		colWidth  = int32(284)
		gap       = int32(12)
	)
	left := margin
	top := state.buttonTop
	for index, tool := range state.manifest.Tools {
		column := index % 2
		row := index / 2
		x := left + int32(column)*(colWidth+gap)
		y := top + int32(row)*rowHeight
		createButton(state.mainHWND, tool.Label, rect{x, y, x + colWidth, y + 40}, idButtonBase+index)
	}

	noteTop := state.clientH - 42 - margin
	createStatic(state.mainHWND, state.manifest.Note, rect{margin, noteTop, 596, noteTop + 42}, 0)
}

func (state *appState) wndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case 0x0111: // WM_COMMAND
		procPostMessageW.Call(uintptr(state.mainHWND), wmAppCommand, wParam, lParam)
		return 0
	case wmAppCommand:
		state.handleCommand(wParam)
		return 0
	case wmAppCloseHub:
		procShowWindow.Call(uintptr(hwnd), 0)
		procPostQuitMessage.Call(0)
		return 0
	case 0x0018: // WM_SHOWWINDOW
		if wParam != 0 && lParam == 0 {
			state.ensureRestored()
		}
		ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
		return ret
	case 0x0002: // WM_DESTROY
		procPostQuitMessage.Call(0)
		return 0
	}
	ret, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return ret
}

func (state *appState) handleCommand(wParam uintptr) {
	id := int(wParam & 0xffff)
	index := id - idButtonBase
	if index < 0 || index >= len(state.manifest.Tools) {
		return
	}
	entry := state.manifest.Tools[index]
	closeHub, err := toolhub.Invoke(entry)
	if err != nil {
		showError(err.Error())
		return
	}
	if closeHub {
		hwnd := state.mainHWND
		time.AfterFunc(800*time.Millisecond, func() {
			procPostMessageW.Call(uintptr(hwnd), wmAppCloseHub, 0, 0)
		})
	}
}

func (state *appState) presentMainWindow() {
	hwnd := uintptr(state.mainHWND)
	state.ensureRestored()
	procBringWindowToTop.Call(hwnd)
	procSetForegroundWindow.Call(hwnd)
	procShowWindow.Call(hwnd, swShowNormal)
	procUpdateWindow.Call(hwnd)
}

func (state *appState) ensureRestored() {
	hwnd := uintptr(state.mainHWND)
	iconic, _, _ := procIsIconic.Call(hwnd)
	if iconic != 0 {
		procShowWindow.Call(hwnd, swRestore)
	}
}

func createStatic(parent syscall.Handle, text string, box rect, id int) {
	createControl("STATIC", text, 0x50000000, box, parent, id)
}

func createButton(parent syscall.Handle, text string, box rect, id int) {
	createControl("BUTTON", text, 0x50010000, box, parent, id)
}

func createControl(className, text string, style int32, box rect, parent syscall.Handle, id int) syscall.Handle {
	classPtr, _ := syscall.UTF16PtrFromString(className)
	textPtr, _ := syscall.UTF16PtrFromString(text)
	width := box.Right - box.Left
	height := box.Bottom - box.Top
	hwnd, _, _ := procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(classPtr)),
		uintptr(unsafe.Pointer(textPtr)),
		uintptr(style),
		uintptr(box.Left), uintptr(box.Top), uintptr(width), uintptr(height),
		uintptr(parent), uintptr(id), 0, 0,
	)
	return syscall.Handle(hwnd)
}

func windowSizeForClient(clientW, clientH int32) (winW, winH int32) {
	r := rect{Left: 0, Top: 0, Right: clientW, Bottom: clientH}
	ret, _, _ := procAdjustWindowRectEx.Call(
		uintptr(unsafe.Pointer(&r)),
		uintptr(wsOverlappedwindow),
		0,
		0,
	)
	if ret == 0 {
		return clientW + 16, clientH + 39
	}
	return r.Right - r.Left, r.Bottom - r.Top
}

func showError(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("Yime 工具箱")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), 0x10)
}
