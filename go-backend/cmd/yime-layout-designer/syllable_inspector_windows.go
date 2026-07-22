//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/syllableinspector"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	inspectorWindowStyle = 0x00CF0000
	inspectorBorder      = 0x00800000
	inspectorReadOnly    = 0x0800
	inspectorMultiline   = 0x0004
	inspectorAutoVScroll = 0x0040
	inspectorListNotify  = 0x0001
	inspectorENChange    = 0x0300
	inspectorSelChange   = 1

	idInspectorQuery    = 2101
	idInspectorCategory = 2102
	idInspectorList     = 2103
	idInspectorTrace    = 2104
	idInspectorCount    = 2105

	lbAddString    = 0x0180
	lbResetContent = 0x0184
	lbSetCurSel    = 0x0186
	lbGetCurSel    = 0x0188
)

type inspectorState struct {
	hwnd, query, category, list, trace, count syscall.Handle
	inventory                                 syllableinspector.Inventory
	filtered                                  []int
	layout                                    map[string]string
}

var (
	activeInspector   *inspectorState
	inspectorCallback uintptr
)

func showSyllableInspector(owner syscall.Handle, dataDir, sharedDir string, layout map[string]string) error {
	if activeInspector != nil && activeInspector.hwnd != 0 {
		showWindow.Call(uintptr(activeInspector.hwnd), swShow)
		return nil
	}
	inventory, err := syllableinspector.Load(dataDir)
	if err != nil && sharedDir != "" && sharedDir != dataDir {
		inventory, err = syllableinspector.Load(sharedDir)
	}
	if err != nil {
		return err
	}
	state := &inspectorState{inventory: inventory, layout: cloneStringMap(layout)}
	activeInspector = state
	instance, _, _ := getModuleHandle.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeSyllableInspector")
	if inspectorCallback == 0 {
		inspectorCallback = syscall.NewCallback(inspectorWndProc)
		cursor, _, _ := loadCursor.Call(0, 32512)
		icon := win32ui.LoadYimeIcon(instance)
		windowClass := wndClassEx{Size: uint32(unsafe.Sizeof(wndClassEx{})), WndProc: inspectorCallback, Instance: syscall.Handle(instance), Icon: syscall.Handle(icon), IconSm: syscall.Handle(icon), Cursor: syscall.Handle(cursor), Background: 16, ClassName: className}
		if atom, _, callErr := registerClassEx.Call(uintptr(unsafe.Pointer(&windowClass))); atom == 0 {
			activeInspector = nil
			return fmt.Errorf("注册音节分解观察器窗口: %v", callErr)
		}
	}
	title, _ := syscall.UTF16PtrFromString("Yime 音节分解观察器")
	hwnd, _, callErr := createWindowEx.Call(wsAppWindow, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), inspectorWindowStyle, 120, 80, 1160, 730, uintptr(owner), 0, instance, 0)
	if hwnd == 0 {
		activeInspector = nil
		return fmt.Errorf("创建音节分解观察器: %v", callErr)
	}
	state.hwnd = syscall.Handle(hwnd)
	state.createControls()
	state.refresh()
	showWindow.Call(hwnd, swShow)
	updateWindow.Call(hwnd)
	return nil
}

func cloneStringMap(source map[string]string) map[string]string {
	result := make(map[string]string, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}

func inspectorWndProc(hwnd syscall.Handle, message uint32, wParam, lParam uintptr) uintptr {
	if activeInspector != nil {
		switch message {
		case wmCommand:
			activeInspector.command(int(wParam&0xffff), int((wParam>>16)&0xffff))
			return 0
		case wmDestroy:
			activeInspector = nil
			return 0
		}
	}
	result, _, _ := defWindowProc.Call(uintptr(hwnd), uintptr(message), wParam, lParam)
	return result
}

func (state *inspectorState) createControls() {
	font, _, _ := getStockObject.Call(17)
	makeControl := func(class, text string, style uint32, x, y, width, height, id int) syscall.Handle {
		classPtr, _ := syscall.UTF16PtrFromString(class)
		textPtr, _ := syscall.UTF16PtrFromString(text)
		hwnd, _, _ := createWindowEx.Call(0, uintptr(unsafe.Pointer(classPtr)), uintptr(unsafe.Pointer(textPtr)), uintptr(wsChild|wsVisible|style), uintptr(x), uintptr(y), uintptr(width), uintptr(height), uintptr(state.hwnd), uintptr(id), 0, 0)
		sendMessage.Call(hwnd, wmSetFont, font, 1)
		return syscall.Handle(hwnd)
	}
	makeControl("STATIC", "搜索拼音、规则、Yinyuan ID 或音元名称：", 0, 20, 16, 280, 24, 0)
	state.query = makeControl("EDIT", "", wsTabstop|esAutoHScroll|inspectorBorder, 305, 12, 240, 28, idInspectorQuery)
	makeControl("STATIC", "类别：", 0, 565, 16, 50, 24, 0)
	state.category = makeControl("COMBOBOX", "", wsTabstop|wsVScroll|cbsDropdown, 615, 12, 245, 320, idInspectorCategory)
	comboAdd(state.category, "全部类别")
	for _, category := range state.inventory.Categories {
		comboAdd(state.category, category)
	}
	sendMessage.Call(uintptr(state.category), cbSetCurSel, 0, 0)
	state.count = makeControl("STATIC", "", 0, 875, 6, 245, 42, idInspectorCount)
	state.list = makeControl("LISTBOX", "", wsTabstop|wsVScroll|inspectorBorder|inspectorListNotify, 20, 52, 535, 590, idInspectorList)
	state.trace = makeControl("EDIT", "", wsTabstop|wsVScroll|inspectorBorder|inspectorReadOnly|inspectorMultiline|inspectorAutoVScroll, 575, 52, 545, 590, idInspectorTrace)
	makeControl("STATIC", "列表来自真实编码器的全量导出；观察器不在 Windows 端重新推断拼音规则。", 0, 20, 652, 1100, 24, 0)
}

func (state *inspectorState) command(id, notify int) {
	switch {
	case id == idInspectorQuery && notify == inspectorENChange:
		state.refresh()
	case id == idInspectorCategory && notify == inspectorSelChange:
		state.refresh()
	case id == idInspectorList && notify == inspectorSelChange:
		state.showSelected()
	}
}

func (state *inspectorState) refresh() {
	category := "全部类别"
	if selected := comboSel(state.category); selected > 0 && selected <= len(state.inventory.Categories) {
		category = state.inventory.Categories[selected-1]
	}
	state.filtered = state.inventory.Filter(getText(state.query), category)
	sendMessage.Call(uintptr(state.list), lbResetContent, 0, 0)
	for _, rowIndex := range state.filtered {
		text, _ := syscall.UTF16PtrFromString(state.inventory.Rows[rowIndex].Summary())
		sendMessage.Call(uintptr(state.list), lbAddString, 0, uintptr(unsafe.Pointer(text)))
	}
	setText(state.count, fmt.Sprintf("显示 %d / 全部 %d\r\n运行时 %d｜仅源侧 %d｜不一致 %d", len(state.filtered), len(state.inventory.Rows), state.inventory.RuntimeEntries, state.inventory.SourceOnly, state.inventory.Mismatches))
	if len(state.filtered) == 0 {
		setText(state.trace, "没有符合当前筛选条件的音节。")
		return
	}
	sendMessage.Call(uintptr(state.list), lbSetCurSel, 0, 0)
	state.showSelected()
}

func (state *inspectorState) showSelected() {
	selected, _, _ := sendMessage.Call(uintptr(state.list), lbGetCurSel, 0, 0)
	index := int(int32(selected))
	if index < 0 || index >= len(state.filtered) {
		return
	}
	setText(state.trace, state.inventory.Rows[state.filtered[index]].Trace(state.layout))
}
