//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningconfig"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmanager"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	wsOverlappedWindow = 0x00CF0000
	wsVisible          = 0x10000000
	wsChild            = 0x40000000
	wsTabStop          = 0x00010000
	lvsReport          = 0x0001
	lvsSingleSel       = 0x0004
	lvsShowSelAlways   = 0x0008
	lvsExFullRowSelect = 0x0020
	lvsExGridLines     = 0x0001
	lvsExDoubleBuffer  = 0x00010000
	lvmFirst           = 0x1000
	lvmDeleteAllItems  = lvmFirst + 9
	lvmInsertItemW     = lvmFirst + 77
	lvmSetItemTextW    = lvmFirst + 116
	lvmInsertColumnW   = lvmFirst + 97
	lvmSetExtended     = lvmFirst + 54
	lvcfWidth          = 0x0002
	lvcfText           = 0x0004
	lvifText           = 0x0001
	idEnable           = 1001
	idDisable          = 1002
	idImport           = 1003
	idExport           = 1004
	idClear            = 1005
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")
	comdlg32 = syscall.NewLazyDLL("comdlg32.dll")

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
	procGetOpenFileNameW   = comdlg32.NewProc("GetOpenFileNameW")
	procGetSaveFileNameW   = comdlg32.NewProc("GetSaveFileNameW")
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
	Mask    int32
	Format  int32
	Width   int32
	Text    *uint16
	TextMax int32
	SubItem int32
	Image   int32
	Order   int32
}

type listItem struct {
	Mask                uint32
	Item, SubItem       int32
	State, StateMask    uint32
	Text                *uint16
	TextMax             int32
	Image               int32
	Param               uintptr
	Indent              int32
	GroupID             int32
	Columns             uint32
	ColumnFormat, Group *uint32
}

type openFilename struct {
	StructSize                   uint32
	Owner, Instance              syscall.Handle
	Filter, CustomFilter         *uint16
	MaxCustomFilter, FilterIndex uint32
	File                         *uint16
	MaxFile                      uint32
	FileTitle                    *uint16
	MaxFileTitle                 uint32
	InitialDir, Title            *uint16
	Flags                        uint32
	FileOffset, FileExtension    uint16
	DefaultExt                   *uint16
	CustomData                   uintptr
	Hook                         uintptr
	TemplateName                 *uint16
	Reserved                     uintptr
	Reserved2, FlagsEx           uint32
}

type runtimeStatus struct {
	IndexVersion string `json:"index_version"`
}

type app struct {
	installRoot  string
	stateRoot    string
	mainWindow   syscall.Handle
	listWindow   syscall.Handle
	statusWindow syscall.Handle
	records      []yimecore.LearnedRecord
}

func main() {
	installRoot := flag.String("InstallRoot", "", "YimeCore Trial package root")
	userDir := flag.String("UserDir", "", "YimeCore Trial state root")
	flag.String("IndexRoot", "", "YimeCore Trial index root (reserved for launch compatibility)")
	flag.String("Mode", "variable", "YimeCore Trial mode (reserved for launch compatibility)")
	experimental := flag.Bool("Experimental", false, "require isolated Trial mode")
	flag.Parse()
	if !*experimental || strings.TrimSpace(*installRoot) == "" || strings.TrimSpace(*userDir) == "" {
		showMessage("自学词语管理只接受完整的 Trial 参数。", 0x10)
		return
	}
	state := &app{installRoot: filepath.Clean(*installRoot), stateRoot: filepath.Clean(*userDir)}
	if err := state.run(); err != nil {
		showMessage(err.Error(), 0x10)
	}
}

func (a *app) run() error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if win32ui.ActivateExistingWindow("YimeCoreTrialLearningManager") {
		return nil
	}
	controls := commonControls{Size: uint32(unsafe.Sizeof(commonControls{})), ICC: 0xff}
	procInitCommonControls.Call(uintptr(unsafe.Pointer(&controls)))
	instance, _, _ := procGetModuleHandleW.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeCoreTrialLearningManager")
	title, _ := syscall.UTF16PtrFromString("Yime 试验版自学词语管理")
	cursor, _, _ := procLoadCursorW.Call(0, 32512)
	icon := win32ui.LoadYimeIcon(instance)
	windowProcedure = syscall.NewCallback(a.wndProc)
	class := windowClass{Size: uint32(unsafe.Sizeof(windowClass{})), Style: win32ui.ClassRedraw, WndProc: windowProcedure,
		Instance: syscall.Handle(instance), Icon: syscall.Handle(icon), IconSm: syscall.Handle(icon), Cursor: syscall.Handle(cursor),
		Background: win32ui.ColorWindowBackground, ClassName: className}
	if registered, _, _ := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&class))); registered == 0 {
		return errors.New("RegisterClassEx failed")
	}
	hwnd, _, _ := procCreateWindowExW.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), wsOverlappedWindow,
		150, 120, 760, 520, 0, 0, instance, 0)
	if hwnd == 0 {
		return errors.New("CreateWindowEx failed")
	}
	a.mainWindow = syscall.Handle(hwnd)
	a.createControls()
	win32ui.PresentMainWindowAfterLaunch(a.mainWindow)
	a.refreshWithRuntimeStop()
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
	labels := []struct {
		text            string
		id, left, width int
	}{{"启用", idEnable, 16, 96}, {"停用", idDisable, 120, 96}, {"导入", idImport, 224, 96}, {"导出", idExport, 328, 96}, {"清空", idClear, 432, 96}}
	for _, button := range labels {
		createControl("BUTTON", button.text, wsChild|wsVisible|wsTabStop, button.left, 14, button.width, 30, a.mainWindow, button.id)
	}
	a.listWindow = createControl("SysListView32", "", wsChild|wsVisible|lvsReport|lvsSingleSel|lvsShowSelAlways, 16, 58, 710, 374, a.mainWindow, 2001)
	procSendMessageW.Call(uintptr(a.listWindow), lvmSetExtended, 0, lvsExFullRowSelect|lvsExGridLines|lvsExDoubleBuffer)
	for index, column := range []struct {
		title string
		width int32
	}{{"词语", 300}, {"编码", 260}, {"次数", 120}} {
		text, _ := syscall.UTF16PtrFromString(column.title)
		spec := listColumn{Mask: lvcfText | lvcfWidth, Width: column.width, Text: text}
		procSendMessageW.Call(uintptr(a.listWindow), lvmInsertColumnW, uintptr(index), uintptr(unsafe.Pointer(&spec)))
	}
	a.statusWindow = createControl("STATIC", "正在读取自学词语...", wsChild|wsVisible, 16, 444, 710, 24, a.mainWindow, 2002)
}

func (a *app) wndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case 0x0111:
		a.handleCommand(int(wParam & 0xffff))
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

func (a *app) handleCommand(id int) {
	switch id {
	case idEnable, idDisable:
		enabled := id == idEnable
		if err := learningconfig.Save(filepath.Join(a.stateRoot, "learning.json"), enabled); err != nil {
			showMessage(err.Error(), 0x10)
			return
		}
		if err := a.restartRuntime(); err != nil {
			showMessage(err.Error(), 0x10)
			return
		}
		a.setStatus(map[bool]string{true: "自学习已启用。", false: "自学习已停用；现有数据已保留。"}[enabled])
	case idExport:
		path := chooseFile(a.mainWindow, true)
		if path == "" {
			return
		}
		a.runStopped(func(version string) error { return learningmanager.ExportStopped(a.stateRoot, version, path) })
	case idImport:
		path := chooseFile(a.mainWindow, false)
		if path == "" {
			return
		}
		a.runStopped(func(version string) error { return learningmanager.ImportStopped(a.stateRoot, version, path) })
	case idClear:
		if !confirm("确定清空当前 generation 的全部自学词语？此操作不能撤销。") {
			return
		}
		a.runStopped(func(version string) error { return learningmanager.ClearStopped(a.stateRoot, version) })
	}
}

func (a *app) refreshWithRuntimeStop() { a.runStopped(func(string) error { return nil }) }

func (a *app) runStopped(operation func(string) error) {
	a.setStatus("正在安全停止 Trial runtime...")
	version, err := a.indexVersion()
	if err == nil {
		err = a.stopRuntime()
	}
	if err == nil {
		err = operation(version)
	}
	var records []yimecore.LearnedRecord
	if err == nil {
		records, err = learningmanager.RecordsStopped(a.stateRoot, version)
	}
	restartErr := a.startRuntime()
	if err == nil {
		err = restartErr
	}
	if err != nil {
		a.setStatus("操作失败。")
		showMessage(err.Error(), 0x10)
		return
	}
	a.records = records
	a.renderRecords()
	a.setStatus(fmt.Sprintf("自学词语 %d 条；Trial runtime 已重新启动。", len(records)))
}

func (a *app) indexVersion() (string, error) {
	data, err := os.ReadFile(filepath.Join(a.stateRoot, "runtime-status.json"))
	if errors.Is(err, os.ErrNotExist) {
		return "installed-v1", nil
	}
	if err != nil {
		return "", err
	}
	var status runtimeStatus
	if err := json.Unmarshal(data, &status); err != nil {
		return "", err
	}
	if strings.TrimSpace(status.IndexVersion) == "" {
		return "installed-v1", nil
	}
	return status.IndexVersion, nil
}

func (a *app) runtimeArguments() []string {
	return []string{"-install-root", a.installRoot, "-state-root", a.stateRoot}
}
func (a *app) stopRuntime() error {
	arguments := append(a.runtimeArguments(), "-stop")
	command := exec.Command(filepath.Join(a.installRoot, "bin", "YimeCoreTrialRuntime.exe"), arguments...)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("停止 Trial runtime：%w：%s", err, strings.TrimSpace(string(output)))
	}
	return nil
}
func (a *app) startRuntime() error {
	return win32ui.StartDetachedGUIExecutable(filepath.Join(a.installRoot, "bin", "YimeCoreTrialRuntime.exe"), a.runtimeArguments()...)
}
func (a *app) restartRuntime() error {
	if err := a.stopRuntime(); err != nil {
		return err
	}
	return a.startRuntime()
}

func (a *app) renderRecords() {
	procSendMessageW.Call(uintptr(a.listWindow), lvmDeleteAllItems, 0, 0)
	for row, record := range a.records {
		values := []string{record.Text, record.Code, fmt.Sprint(record.Selections)}
		text, _ := syscall.UTF16PtrFromString(values[0])
		item := listItem{Mask: lvifText, Item: int32(row), Text: text}
		procSendMessageW.Call(uintptr(a.listWindow), lvmInsertItemW, 0, uintptr(unsafe.Pointer(&item)))
		for column := 1; column < len(values); column++ {
			value, _ := syscall.UTF16PtrFromString(values[column])
			item.SubItem, item.Text = int32(column), value
			procSendMessageW.Call(uintptr(a.listWindow), lvmSetItemTextW, uintptr(row), uintptr(unsafe.Pointer(&item)))
		}
	}
}
func (a *app) setStatus(text string) {
	pointer, _ := syscall.UTF16PtrFromString(text)
	procSetWindowTextW.Call(uintptr(a.statusWindow), uintptr(unsafe.Pointer(pointer)))
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

func chooseFile(owner syscall.Handle, save bool) string {
	buffer := make([]uint16, 32768)
	filter, _ := syscall.UTF16PtrFromString("Yime 自学备份 (*.json)\x00*.json\x00所有文件 (*.*)\x00*.*\x00")
	titleText := map[bool]string{true: "导出自学词语", false: "导入自学词语"}[save]
	title, _ := syscall.UTF16PtrFromString(titleText)
	extension, _ := syscall.UTF16PtrFromString("json")
	request := openFilename{StructSize: uint32(unsafe.Sizeof(openFilename{})), Owner: owner, Filter: filter, File: &buffer[0], MaxFile: uint32(len(buffer)), Title: title, DefaultExt: extension, Flags: 0x00080000 | 0x00000800}
	var result uintptr
	if save {
		result, _, _ = procGetSaveFileNameW.Call(uintptr(unsafe.Pointer(&request)))
	} else {
		request.Flags |= 0x00001000
		result, _, _ = procGetOpenFileNameW.Call(uintptr(unsafe.Pointer(&request)))
	}
	if result == 0 {
		return ""
	}
	return syscall.UTF16ToString(buffer)
}
func showMessage(text string, flags uintptr) {
	body, _ := syscall.UTF16PtrFromString(text)
	title, _ := syscall.UTF16PtrFromString("Yime 试验版自学词语管理")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), flags)
}
func confirm(text string) bool {
	body, _ := syscall.UTF16PtrFromString(text)
	title, _ := syscall.UTF16PtrFromString("Yime 试验版自学词语管理")
	result, _, _ := procMessageBoxW.Call(0, uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), 0x24)
	return result == 6
}
