//go:build windows

package main

import (
	"errors"
	"flag"
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/professionallexicon"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wsOverlappedWindow = 0x00CF0000
	wsVisible          = 0x10000000
	wsChild            = 0x40000000
	wsTabStop          = 0x00010000
	lvsReport          = 0x0001
	lvsSingleSel       = 0x0004
	lvmFirst           = 0x1000
	lvmInsertItemW     = lvmFirst + 77
	lvmSetItemTextW    = lvmFirst + 116
	lvmInsertColumnW   = lvmFirst + 97
	lvmSetExtended     = lvmFirst + 54
	lvmSetItemState    = lvmFirst + 43
	lvmGetItemState    = lvmFirst + 44
	lvsExGridLines     = 0x0001
	lvsExCheckboxes    = 0x0004
	lvsExFullRowSelect = 0x0020
	lvsExDoubleBuffer  = 0x00010000
	lvcfWidth          = 0x0002
	lvcfText           = 0x0004
	lvifText           = 0x0001
	lvifState          = 0x0008
	lvisStateImageMask = 0xF000
	idEnable           = 1001
	idDisable          = 1002
	idApply            = 1003
)

var (
	user32                 = syscall.NewLazyDLL("user32.dll")
	kernel32               = syscall.NewLazyDLL("kernel32.dll")
	comctl32               = syscall.NewLazyDLL("comctl32.dll")
	procCreateWindowExW    = user32.NewProc("CreateWindowExW")
	procDefWindowProcW     = user32.NewProc("DefWindowProcW")
	procDispatchMessageW   = user32.NewProc("DispatchMessageW")
	procGetMessageW        = user32.NewProc("GetMessageW")
	procTranslateMessage   = user32.NewProc("TranslateMessage")
	procPostQuitMessage    = user32.NewProc("PostQuitMessage")
	procRegisterClassExW   = user32.NewProc("RegisterClassExW")
	procLoadCursorW        = user32.NewProc("LoadCursorW")
	procSetWindowTextW     = user32.NewProc("SetWindowTextW")
	procMessageBoxW        = user32.NewProc("MessageBoxW")
	procSendMessageW       = user32.NewProc("SendMessageW")
	procGetModuleHandleW   = kernel32.NewProc("GetModuleHandleW")
	procInitCommonControls = comctl32.NewProc("InitCommonControlsEx")
	windowProcedure        uintptr
)

type windowClass struct {
	Size, Style                        uint32
	WndProc                            uintptr
	ClsExtra, WndExtra                 int32
	Instance, Icon, Cursor, Background syscall.Handle
	MenuName, ClassName                *uint16
	IconSm                             syscall.Handle
}

type message struct {
	Hwnd           syscall.Handle
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Point          struct{ X, Y int32 }
}

type commonControls struct{ Size, ICC uint32 }

type listColumn struct {
	Mask, Format, Width            int32
	Text                           *uint16
	TextMax, SubItem, Image, Order int32
}

type listItem struct {
	Mask                uint32
	Item, SubItem       int32
	State, StateMask    uint32
	Text                *uint16
	TextMax, Image      int32
	Param               uintptr
	Indent, GroupID     int32
	Columns             uint32
	ColumnFormat, Group *uint32
}

type app struct {
	installRoot                          string
	stateRoot                            string
	catalog                              professionallexicon.Catalog
	state                                professionallexicon.State
	mainWindow, listWindow, statusWindow syscall.Handle
}

func main() {
	installRoot := flag.String("InstallRoot", "", "YimeCore Trial package root")
	userDir := flag.String("UserDir", "", "YimeCore Trial state root")
	flag.String("IndexRoot", "", "YimeCore Trial index root (reserved for launch compatibility)")
	flag.String("Mode", "variable", "YimeCore Trial mode (reserved for launch compatibility)")
	experimental := flag.Bool("Experimental", false, "require isolated Trial mode")
	flag.Parse()
	if !*experimental || strings.TrimSpace(*installRoot) == "" || strings.TrimSpace(*userDir) == "" {
		showMessage("专业词库加载只接受完整的 Trial 参数。", 0x10)
		return
	}
	state := &app{installRoot: filepath.Clean(*installRoot), stateRoot: filepath.Clean(*userDir)}
	var err error
	state.catalog, err = professionallexicon.LoadCatalog(filepath.Join(state.installRoot, "professional-lexicons"))
	if err == nil {
		state.state, err = professionallexicon.LoadState(filepath.Join(state.stateRoot, "professional-lexicons.json"))
	}
	if err != nil {
		showMessage(err.Error(), 0x10)
		return
	}
	if err := state.run(); err != nil {
		showMessage(err.Error(), 0x10)
	}
}

func (a *app) run() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if win32ui.ActivateExistingWindow("YimeCoreTrialProfessionalLexicon") {
		return nil
	}
	controls := commonControls{Size: uint32(unsafe.Sizeof(commonControls{})), ICC: 0xff}
	procInitCommonControls.Call(uintptr(unsafe.Pointer(&controls)))
	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeCoreTrialProfessionalLexicon")
	title, _ := syscall.UTF16PtrFromString("Yime 试验版专业词库加载")
	cursor, _, _ := procLoadCursorW.Call(0, 32512)
	icon := win32ui.LoadYimeIcon(instance)
	windowProcedure = syscall.NewCallback(a.wndProc)
	class := windowClass{Size: uint32(unsafe.Sizeof(windowClass{})), Style: win32ui.ClassRedraw, WndProc: windowProcedure,
		Instance: syscall.Handle(instance), Icon: syscall.Handle(icon), IconSm: syscall.Handle(icon), Cursor: syscall.Handle(cursor),
		Background: win32ui.ColorWindowBackground, ClassName: className}
	if result, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&class))); result == 0 {
		return errors.New("RegisterClassEx failed")
	}
	hwnd, _, _ := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), wsOverlappedWindow,
		180, 140, 760, 500, 0, 0, instance, 0)
	if hwnd == 0 {
		return errors.New("CreateWindowEx failed")
	}
	a.mainWindow = syscall.Handle(hwnd)
	a.createControls()
	win32ui.PresentMainWindowAfterLaunch(a.mainWindow)
	var current message
	for {
		result, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&current)), 0, 0, 0)
		if int32(result) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&current)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&current)))
	}
	return nil
}

func (a *app) createControls() {
	createControl("BUTTON", "总开关：启用", wsChild|wsVisible|wsTabStop, 16, 14, 132, 30, a.mainWindow, idEnable)
	createControl("BUTTON", "总开关：停用", wsChild|wsVisible|wsTabStop, 156, 14, 132, 30, a.mainWindow, idDisable)
	createControl("BUTTON", "应用选择", wsChild|wsVisible|wsTabStop, 596, 14, 128, 30, a.mainWindow, idApply)
	a.listWindow = createControl("SysListView32", "", wsChild|wsVisible|lvsReport|lvsSingleSel, 16, 58, 708, 348, a.mainWindow, 2001)
	procSendMessageW.Call(uintptr(a.listWindow), lvmSetExtended, 0, lvsExGridLines|lvsExCheckboxes|lvsExFullRowSelect|lvsExDoubleBuffer)
	for index, column := range []struct {
		title string
		width int32
	}{{"专业词库", 220}, {"包 ID", 200}, {"来源 / 审查依据", 260}} {
		text, _ := syscall.UTF16PtrFromString(column.title)
		spec := listColumn{Mask: lvcfText | lvcfWidth, Width: column.width, Text: text}
		procSendMessageW.Call(uintptr(a.listWindow), lvmInsertColumnW, uintptr(index), uintptr(unsafe.Pointer(&spec)))
	}
	selected := map[string]bool{}
	for _, id := range a.state.Selected {
		selected[id] = true
	}
	for row, pack := range a.catalog.Packs {
		values := []string{pack.Name, pack.ID, pack.Provenance}
		text, _ := syscall.UTF16PtrFromString(values[0])
		item := listItem{Mask: lvifText, Item: int32(row), Text: text}
		procSendMessageW.Call(uintptr(a.listWindow), lvmInsertItemW, 0, uintptr(unsafe.Pointer(&item)))
		for column := 1; column < len(values); column++ {
			value, _ := syscall.UTF16PtrFromString(values[column])
			item.SubItem, item.Text = int32(column), value
			procSendMessageW.Call(uintptr(a.listWindow), lvmSetItemTextW, uintptr(row), uintptr(unsafe.Pointer(&item)))
		}
		setChecked(a.listWindow, row, selected[pack.ID])
	}
	a.statusWindow = createControl("STATIC", "", wsChild|wsVisible, 16, 420, 708, 24, a.mainWindow, 2002)
	a.updateStatus("就绪。")
}

func (a *app) wndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case 0x0111:
		switch int(wParam & 0xffff) {
		case idEnable:
			a.state.Enabled = true
			a.updateStatus("总开关已设为启用；点击“应用选择”生效。")
		case idDisable:
			a.state.Enabled = false
			a.updateStatus("总开关已设为停用；已安装文件和选择会保留。")
		case idApply:
			a.apply()
		}
		return 0
	case win32ui.WmDeferredPresent:
		win32ui.PresentMainWindow(a.mainWindow)
		return 0
	case 0x0002:
		procPostQuitMessage.Call(0)
		return 0
	}
	result, _, _ := procDefWindowProcW.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return result
}

func (a *app) apply() {
	a.state.Selected = nil
	for row, pack := range a.catalog.Packs {
		if isChecked(a.listWindow, row) {
			a.state.Selected = append(a.state.Selected, pack.ID)
		}
	}
	path := filepath.Join(a.stateRoot, "professional-lexicons.json")
	if err := professionallexicon.SaveState(path, a.state); err != nil {
		showMessage(err.Error(), 0x10)
		return
	}
	if err := a.restartRuntime(); err != nil {
		showMessage(err.Error(), 0x10)
		return
	}
	a.updateStatus(fmt.Sprintf("已应用：总开关 %s，选择 %d 个已审查词库。", map[bool]string{true: "开启", false: "关闭"}[a.state.Enabled], len(a.state.Selected)))
}

func (a *app) restartRuntime() error {
	runtimePath := filepath.Join(a.installRoot, "bin", "YimeCoreTrialRuntime.exe")
	arguments := []string{"-install-root", a.installRoot, "-state-root", a.stateRoot}
	stop := exec.Command(runtimePath, append(arguments, "-stop")...)
	if output, err := stop.CombinedOutput(); err != nil {
		return fmt.Errorf("停止 Trial runtime：%w：%s", err, strings.TrimSpace(string(output)))
	}
	return win32ui.StartDetachedGUIExecutable(runtimePath, arguments...)
}

func (a *app) updateStatus(message string) {
	if len(a.catalog.Packs) == 0 {
		message = "当前安装包没有经清单批准的专业词库；不会创建或下载虚构分类。"
	}
	pointer, _ := syscall.UTF16PtrFromString(message)
	procSetWindowTextW.Call(uintptr(a.statusWindow), uintptr(unsafe.Pointer(pointer)))
}

func setChecked(hwnd syscall.Handle, row int, checked bool) {
	state := uint32(1 << 12)
	if checked {
		state = 2 << 12
	}
	item := listItem{Mask: lvifState, StateMask: lvisStateImageMask, State: state}
	procSendMessageW.Call(uintptr(hwnd), lvmSetItemState, uintptr(row), uintptr(unsafe.Pointer(&item)))
}
func isChecked(hwnd syscall.Handle, row int) bool {
	state, _, _ := procSendMessageW.Call(uintptr(hwnd), lvmGetItemState, uintptr(row), lvisStateImageMask)
	return (state >> 12) == 2
}
func createControl(className, text string, style uintptr, x, y, width, height int, parent syscall.Handle, id int) syscall.Handle {
	classPointer, _ := syscall.UTF16PtrFromString(className)
	textPointer, _ := syscall.UTF16PtrFromString(text)
	hwnd, _, _ := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(classPointer)), uintptr(unsafe.Pointer(textPointer)), style,
		uintptr(x), uintptr(y), uintptr(width), uintptr(height), uintptr(parent), uintptr(id), 0, 0)
	control := syscall.Handle(hwnd)
	win32ui.ApplyDefaultGUIFont(control)
	return control
}
func showMessage(text string, flags uintptr) {
	body, _ := syscall.UTF16PtrFromString(text)
	title, _ := syscall.UTF16PtrFromString("Yime 试验版专业词库加载")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), flags)
}
