//go:build windows

package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/win32ui"
)

const (
	wmDestroy = 0x0002
	wmCommand = 0x0111
	wmSetFont = 0x0030

	wsChild       = 0x40000000
	wsVisible     = 0x10000000
	wsTabstop     = 0x00010000
	wsVScroll     = 0x00200000
	wsAppWindow   = 0x00040000
	wsFixedWindow = 0x00CA0000
	bsMultiline   = 0x00002000
	cbsDropdown   = 0x0003
	esAutoHScroll = 0x0080

	cbAddString    = 0x0143
	cbGetCurSel    = 0x0147
	cbSetCurSel    = 0x014E
	cbResetContent = 0x014B
	cbErr          = -1

	mbIconError    = 0x10
	mbIconQuestion = 0x20
	mbIconInfo     = 0x40
	mbYesNo        = 0x4
	idYes          = 6
	swHide         = 0
	swShow         = 5

	idLayer         = 100
	idYinyuan       = 101
	idAssign        = 102
	idReset         = 103
	idPreview       = 104
	idApply         = 105
	idTrialEdit     = 106
	idTrial         = 107
	idStatus        = 108
	idProfileName   = 109
	idProfileList   = 110
	idProfileNew    = 111
	idProfileSave   = 112
	idProfileLoad   = 113
	idProfileDelete = 114
	idKeyBase       = 1000

	uiWindowTitle = "Yime \u97f3\u5143\u952e\u76d8\u5e03\u5c40\u8bbe\u8ba1\u5668"
	uiInstruction = "\u64cd\u4f5c\uff1a\u5148\u70b9\u952e\u4f4d\uff0c\u518d\u9009\u62e9 Yinyuan ID\uff0c\u7136\u540e\u70b9\u51fb\u5206\u914d\uff1b\u5df2\u5360\u7528\u952e\u4f1a\u81ea\u52a8\u4ea4\u6362\u3002"
	uiAssign      = "\u5206\u914d / \u4ea4\u6362"
	uiReset       = "\u6062\u590d\u6b63\u5f0f\u5e03\u5c40"
	uiPreview     = "\u6821\u9a8c / \u9884\u89c8"
	uiApply       = "\u786e\u8ba4\u5e94\u7528\u5e03\u5c40"
	uiTrialLabel  = "\u62fc\u97f3\u8bd5\u7b97\uff1a"
	uiTrialButton = "\u8bd5\u7b97\u4e09\u6a21\u5f0f\u7f16\u7801"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")

	createWindowEx     = user32.NewProc("CreateWindowExW")
	defWindowProc      = user32.NewProc("DefWindowProcW")
	dispatchMessage    = user32.NewProc("DispatchMessageW")
	getMessage         = user32.NewProc("GetMessageW")
	translateMessage   = user32.NewProc("TranslateMessage")
	isDialogMessage    = user32.NewProc("IsDialogMessageW")
	postQuitMessage    = user32.NewProc("PostQuitMessage")
	registerClassEx    = user32.NewProc("RegisterClassExW")
	sendMessage        = user32.NewProc("SendMessageW")
	setWindowText      = user32.NewProc("SetWindowTextW")
	getWindowTextLen   = user32.NewProc("GetWindowTextLengthW")
	getWindowText      = user32.NewProc("GetWindowTextW")
	messageBox         = user32.NewProc("MessageBoxW")
	setProcessDPIAware = user32.NewProc("SetProcessDPIAware")
	showWindow         = user32.NewProc("ShowWindow")
	updateWindow       = user32.NewProc("UpdateWindow")
	enableWindow       = user32.NewProc("EnableWindow")
	loadCursor         = user32.NewProc("LoadCursorW")
	getModuleHandle    = kernel32.NewProc("GetModuleHandleW")
	getConsoleWindow   = kernel32.NewProc("GetConsoleWindow")
	getStockObject     = gdi32.NewProc("GetStockObject")
	initCommonControl  = comctl32.NewProc("InitCommonControlsEx")

	guiCallback uintptr
	activeGUI   *guiState
)

type wndClassEx struct {
	Size, Style         uint32
	WndProc             uintptr
	ClsExtra, WndExtra  int32
	Instance, Icon      syscall.Handle
	Cursor, Background  syscall.Handle
	MenuName, ClassName *uint16
	IconSm              syscall.Handle
}

type winMessage struct {
	Hwnd           syscall.Handle
	Message        uint32
	WParam, LParam uintptr
	Time           uint32
	Pt             struct{ X, Y int32 }
}

type commonControls struct{ Size, ICC uint32 }
type keySpec struct{ base, shift string }

var keyboardRows = [][]keySpec{
	makeKeyRow("`1234567890-=", "~!@#$%^&*()_+"),
	makeKeyRow("qwertyuiop[]\\", "QWERTYUIOP{}|"),
	makeKeyRow("asdfghjkl;'", `ASDFGHJKL:"`),
	makeKeyRow("zxcvbnm,./", "ZXCVBNM<>?"),
}

type guiState struct {
	dataDir, draftPath       string
	sharedDir, userDir       string
	userMode                 bool
	source, draft            layoutdesigner.Profile
	sourceDigest             string
	hwnd                     syscall.Handle
	layerCombo, idCombo      syscall.Handle
	status, trialEdit        syscall.Handle
	profileName, profileList syscall.Handle
	applyButton              syscall.Handle
	keyButtons               []syscall.Handle
	keySpecs                 []keySpec
	ids                      []string
	stored                   []layoutdesigner.StoredProfile
	layer, selected          int
}

func makeKeyRow(base, shift string) []keySpec {
	a, b := []rune(base), []rune(shift)
	result := make([]keySpec, 0, len(a))
	for i, r := range a {
		result = append(result, keySpec{base: string(r), shift: string(b[i])})
	}
	return result
}

func runGraphical(args []string) error {
	setProcessDPIAware.Call()
	if console, _, _ := getConsoleWindow.Call(); console != 0 {
		showWindow.Call(console, swHide)
	}
	flags := flag.NewFlagSet("yime-layout-designer-gui", flag.ContinueOnError)
	sharedFlag := flags.String("SharedDir", "", "Yime shared Rime data directory")
	userFlag := flags.String("UserDir", "", "Yime user Rime data directory")
	if err := flags.Parse(args); err != nil {
		return err
	}
	userMode := strings.TrimSpace(*sharedFlag) != "" || strings.TrimSpace(*userFlag) != ""
	var dataDir string
	var err error
	if userMode {
		if strings.TrimSpace(*sharedFlag) == "" || strings.TrimSpace(*userFlag) == "" {
			return fmt.Errorf("SharedDir 和 UserDir 必须同时指定")
		}
		dataDir, err = layoutdesigner.EffectiveDataDir(*sharedFlag, *userFlag)
	} else {
		dataDir, err = resolveDataDir("")
	}
	if err != nil {
		return err
	}
	source, err := layoutdesigner.LoadProfile(filepath.Join(dataDir, layoutdesigner.ProfileFileName))
	if err != nil {
		return err
	}
	digest, _ := source.Digest()
	local := os.Getenv("LOCALAPPDATA")
	if local == "" {
		local = os.TempDir()
	}
	draftPath := filepath.Join(local, "Yime", "layout-designer-draft.json")
	if userMode {
		draftPath = filepath.Join(layoutdesigner.UserLayoutDirectory(*userFlag), "auto-draft.json")
	}
	draft := cloneGUIProfile(source)
	draft.BasedOnDigest = digest
	if saved, loadErr := layoutdesigner.LoadProfile(draftPath); loadErr == nil && saved.BasedOnDigest == digest {
		draft = saved
	}
	state := &guiState{
		dataDir: dataDir, draftPath: draftPath, source: source, draft: draft,
		sharedDir: *sharedFlag, userDir: *userFlag, userMode: userMode,
		sourceDigest: digest, selected: -1,
	}
	return runGUIWindow(state)
}

func cloneGUIProfile(p layoutdesigner.Profile) layoutdesigner.Profile {
	result := p
	result.Projection = map[string]string{}
	for id, key := range p.Projection {
		result.Projection[id] = key
	}
	return result
}

func runGUIWindow(state *guiState) error {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	if win32ui.ActivateExistingWindow("YimeLayoutDesigner") {
		return nil
	}
	activeGUI = state
	icc := commonControls{Size: uint32(unsafe.Sizeof(commonControls{})), ICC: 0xFFFF}
	initCommonControl.Call(uintptr(unsafe.Pointer(&icc)))
	instance, _, _ := getModuleHandle.Call(0)
	className, _ := syscall.UTF16PtrFromString("YimeLayoutDesigner")
	cursor, _, _ := loadCursor.Call(0, 32512)
	icon := win32ui.LoadYimeIcon(instance)
	guiCallback = syscall.NewCallback(guiWndProc)
	wc := wndClassEx{
		Size: uint32(unsafe.Sizeof(wndClassEx{})), WndProc: guiCallback,
		Instance: syscall.Handle(instance), Icon: syscall.Handle(icon), Cursor: syscall.Handle(cursor),
		Background: 16, ClassName: className, IconSm: syscall.Handle(icon),
	}
	if atom, _, callErr := registerClassEx.Call(uintptr(unsafe.Pointer(&wc))); atom == 0 {
		return fmt.Errorf("register window class: %v", callErr)
	}
	title, _ := syscall.UTF16PtrFromString(uiWindowTitle)
	hwnd, _, callErr := createWindowEx.Call(
		wsAppWindow, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(title)), wsFixedWindow,
		80, 60, 1190, 720, 0, 0, instance, 0,
	)
	if hwnd == 0 {
		return fmt.Errorf("create window: %v", callErr)
	}
	state.hwnd = syscall.Handle(hwnd)
	state.createControls()
	state.refresh()
	showWindow.Call(hwnd, swShow)
	updateWindow.Call(hwnd)
	var msg winMessage
	for {
		ret, _, _ := getMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		if handled, _, _ := isDialogMessage.Call(hwnd, uintptr(unsafe.Pointer(&msg))); handled == 0 {
			translateMessage.Call(uintptr(unsafe.Pointer(&msg)))
			dispatchMessage.Call(uintptr(unsafe.Pointer(&msg)))
		}
	}
	return nil
}

func guiWndProc(hwnd syscall.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	if activeGUI != nil {
		switch msg {
		case wmCommand:
			activeGUI.command(int(wParam&0xffff), int((wParam>>16)&0xffff))
			return 0
		case wmDestroy:
			postQuitMessage.Call(0)
			return 0
		}
	}
	ret, _, _ := defWindowProc.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
	return ret
}

func (s *guiState) createControls() {
	font, _, _ := getStockObject.Call(17)
	makeControl := func(class, text string, style uint32, x, y, w, h, id int) syscall.Handle {
		classPtr, _ := syscall.UTF16PtrFromString(class)
		textPtr, _ := syscall.UTF16PtrFromString(text)
		hwnd, _, _ := createWindowEx.Call(
			0, uintptr(unsafe.Pointer(classPtr)), uintptr(unsafe.Pointer(textPtr)), uintptr(wsChild|wsVisible|style),
			uintptr(x), uintptr(y), uintptr(w), uintptr(h), uintptr(s.hwnd), uintptr(id), 0, 0,
		)
		sendMessage.Call(hwnd, wmSetFont, font, 1)
		return syscall.Handle(hwnd)
	}

	makeControl("STATIC", "\u663e\u793a\u5c42\uff1a", 0, 18, 16, 64, 24, 0)
	s.layerCombo = makeControl("COMBOBOX", "", wsTabstop|wsVScroll|cbsDropdown, 80, 12, 130, 200, idLayer)
	comboAdd(s.layerCombo, "Base")
	comboAdd(s.layerCombo, "Shift")
	sendMessage.Call(uintptr(s.layerCombo), cbSetCurSel, 0, 0)
	makeControl("STATIC", uiInstruction, 0, 230, 16, 760, 24, 0)

	y := 58
	indents := []int{0, 20, 38, 58}
	for rowIndex, row := range keyboardRows {
		for _, spec := range row {
			index := len(s.keySpecs)
			x := 18 + indents[rowIndex] + (index-rowStart(rowIndex))*82
			button := makeControl("BUTTON", "", wsTabstop|bsMultiline, x, y, 78, 54, idKeyBase+index)
			s.keyButtons = append(s.keyButtons, button)
			s.keySpecs = append(s.keySpecs, spec)
		}
		y += 59
	}

	makeControl("STATIC", "\u97f3\u5143 ID：", 0, 20, 322, 92, 24, 0)
	s.idCombo = makeControl("COMBOBOX", "", wsTabstop|wsVScroll|cbsDropdown, 112, 316, 245, 420, idYinyuan)
	s.ids = layoutdesigner.ExpectedIDs()
	sort.Strings(s.ids)
	for _, id := range s.ids {
		comboAdd(s.idCombo, fmt.Sprintf("%s  %s", id, layoutdesigner.DescribeID(id)))
	}
	makeControl("BUTTON", uiAssign, wsTabstop, 382, 315, 120, 32, idAssign)
	makeControl("BUTTON", uiReset, wsTabstop, 512, 315, 125, 32, idReset)
	makeControl("BUTTON", uiPreview, wsTabstop, 647, 315, 130, 32, idPreview)
	s.applyButton = makeControl("BUTTON", uiApply, wsTabstop, 787, 315, 140, 32, idApply)

	makeControl("STATIC", uiTrialLabel, 0, 20, 370, 92, 24, 0)
	s.trialEdit = makeControl("EDIT", "zhong1 guo2", wsTabstop|esAutoHScroll, 122, 365, 245, 28, idTrialEdit)
	makeControl("BUTTON", uiTrialButton, wsTabstop, 382, 364, 150, 30, idTrial)
	makeControl("STATIC", "方案名称：", 0, 550, 370, 82, 24, 0)
	s.profileName = makeControl("EDIT", s.draft.Name, wsTabstop|esAutoHScroll, 635, 365, 210, 28, idProfileName)
	makeControl("BUTTON", "保存方案", wsTabstop, 855, 364, 100, 30, idProfileSave)
	makeControl("BUTTON", "新建副本", wsTabstop, 965, 364, 100, 30, idProfileNew)
	makeControl("STATIC", "已存方案：", 0, 20, 416, 92, 24, 0)
	s.profileList = makeControl("COMBOBOX", "", wsTabstop|wsVScroll|cbsDropdown, 112, 410, 245, 240, idProfileList)
	makeControl("BUTTON", "载入", wsTabstop, 382, 409, 100, 30, idProfileLoad)
	makeControl("BUTTON", "删除", wsTabstop, 492, 409, 100, 30, idProfileDelete)
	s.reloadStoredProfiles()
	s.status = makeControl("STATIC", "", 0, 20, 460, 1125, 170, idStatus)
}

func rowStart(row int) int {
	total := 0
	for i := 0; i < row; i++ {
		total += len(keyboardRows[i])
	}
	return total
}

func (s *guiState) refresh() {
	for i, button := range s.keyButtons {
		token := s.keySpecs[i].base
		if s.layer == 1 {
			token = s.keySpecs[i].shift
		}
		id := idAtKey(s.draft, token)
		label := token + "\r\n--"
		if id != "" {
			label = token + "\r\n" + id + " " + layoutdesigner.DescribeID(id)
		}
		setText(button, label)
	}
	plan, err := layoutdesigner.Preview(s.dataDir, s.draft)
	if err != nil {
		s.setStatus("Layout error: " + err.Error())
		enableWindow.Call(uintptr(s.applyButton), 0)
		return
	}
	enableWindow.Call(uintptr(s.applyButton), 1)
	status := fmt.Sprintf(
		"Canonical: %s\r\nDraft: %s\r\nChanged IDs (%d): %s\r\nData: %s",
		plan.SourceDigest[:12], plan.TargetDigest[:12], len(plan.ChangedIDs), strings.Join(plan.ChangedIDs, " "), s.dataDir,
	)
	if s.userMode {
		status += "\r\n用户覆盖目录: " + s.userDir
	}
	s.setStatus(status)
}

func (s *guiState) command(id, notify int) {
	switch {
	case id == idLayer && notify == 1:
		if selected := comboSel(s.layerCombo); selected >= 0 {
			s.layer, s.selected = selected, -1
			s.refresh()
		}
	case id >= idKeyBase && id < idKeyBase+len(s.keyButtons):
		s.selected = id - idKeyBase
		token := s.selectedToken()
		assigned := idAtKey(s.draft, token)
		sendMessage.Call(uintptr(s.idCombo), cbSetCurSel, ^uintptr(0), 0)
		for i, item := range s.ids {
			if item == assigned {
				sendMessage.Call(uintptr(s.idCombo), cbSetCurSel, uintptr(i), 0)
				break
			}
		}
		s.setStatus(fmt.Sprintf("Selected key %q on %s layer. Current: %s %s", token, []string{"Base", "Shift"}[s.layer], assigned, layoutdesigner.DescribeID(assigned)))
	case id == idAssign:
		s.assign()
	case id == idReset:
		s.reset()
	case id == idPreview:
		s.preview()
	case id == idApply:
		s.apply()
	case id == idTrial:
		s.trial()
	case id == idProfileNew:
		s.newProfile()
	case id == idProfileSave:
		s.saveProfile()
	case id == idProfileLoad:
		s.loadProfile()
	case id == idProfileDelete:
		s.deleteProfile()
	}
}

func (s *guiState) selectedToken() string {
	if s.selected < 0 || s.selected >= len(s.keySpecs) {
		return ""
	}
	if s.layer == 1 {
		return s.keySpecs[s.selected].shift
	}
	return s.keySpecs[s.selected].base
}

func (s *guiState) assign() {
	token := s.selectedToken()
	if token == "" {
		showMessage(s.hwnd, "\u8bf7\u5148\u70b9\u51fb\u4e00\u4e2a\u952e\u4f4d\u3002", mbIconInfo)
		return
	}
	selected := comboSel(s.idCombo)
	if selected < 0 || selected >= len(s.ids) {
		showMessage(s.hwnd, "\u8bf7\u9009\u62e9\u4e00\u4e2a Yinyuan ID\u3002", mbIconInfo)
		return
	}
	if err := s.draft.Assign(s.ids[selected], token); err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	_ = os.MkdirAll(filepath.Dir(s.draftPath), 0755)
	if err := layoutdesigner.WriteProfileAtomic(s.draftPath, s.draft); err != nil {
		showMessage(s.hwnd, "Save auto-draft: "+err.Error(), mbIconError)
	}
	s.refresh()
}

func (s *guiState) reset() {
	if showMessage(s.hwnd, "放弃当前草案并恢复官方布局？\r\n只有再次点击“确认应用布局”后才会切换。", mbYesNo|mbIconQuestion) != idYes {
		return
	}
	resetSource := s.source
	if s.userMode {
		if official, err := layoutdesigner.LoadProfile(filepath.Join(s.sharedDir, layoutdesigner.ProfileFileName)); err == nil {
			resetSource = official
		}
	}
	s.draft = cloneGUIProfile(resetSource)
	s.draft.BasedOnDigest = s.sourceDigest
	setText(s.profileName, s.draft.Name)
	_ = os.Remove(s.draftPath)
	s.selected = -1
	s.refresh()
}

func (s *guiState) preview() {
	plan, err := layoutdesigner.Preview(s.dataDir, s.draft)
	if err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	showMessage(s.hwnd, fmt.Sprintf(
		"Layout is valid.\r\n\r\nCanonical: %s\r\nDraft: %s\r\nChanged IDs: %s\r\nPinyin: %d\r\nDictionary records: %d",
		plan.SourceDigest[:12], plan.TargetDigest[:12], strings.Join(plan.ChangedIDs, " "), plan.PinyinEntries, plan.DictionaryEntries,
	), mbIconInfo)
}

func (s *guiState) trial() {
	record, err := layoutdesigner.TrialPinyin(s.dataDir, s.draft, getText(s.trialEdit))
	if err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	s.setStatus(fmt.Sprintf("Pinyin trial\r\nFull: %s\r\nVariable: %s\r\nShorthand: %s", record.Full, record.Variable, record.Shorthand))
}

func (s *guiState) apply() {
	if name := strings.TrimSpace(getText(s.profileName)); name != "" {
		s.draft.Name = name
	}
	plan, err := layoutdesigner.Preview(s.dataDir, s.draft)
	if err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	if len(plan.ChangedIDs) == 0 {
		showMessage(s.hwnd, "\u8349\u6848\u4e0e\u6b63\u5f0f\u5e03\u5c40\u76f8\u540c\uff0c\u65e0\u9700\u5e94\u7528\u3002", mbIconInfo)
		return
	}
	question := fmt.Sprintf("重建 %d 条词典记录和三套输入方案？\r\n学习记录会按字词迁移到新编码。\r\n\r\n应用布局 %s？", plan.DictionaryEntries, plan.TargetDigest[:12])
	if showMessage(s.hwnd, question, mbYesNo|mbIconQuestion) != idYes {
		return
	}
	enableWindow.Call(uintptr(s.applyButton), 0)
	s.setStatus("正在重建码表、词典和三套方案，请勿关闭窗口……")
	updateWindow.Call(uintptr(s.hwnd))
	var applied layoutdesigner.Plan
	var migrationCount int
	if s.userMode {
		result, applyErr := layoutdesigner.ApplyUser(s.sharedDir, s.userDir, s.draft)
		applied, migrationCount, err = result.Plan, len(result.Migrations), applyErr
	} else {
		applied, err = layoutdesigner.Apply(s.dataDir, s.draft)
	}
	enableWindow.Call(uintptr(s.applyButton), 1)
	if err != nil {
		showMessage(s.hwnd, "应用失败；原布局文件保持不变或已经回滚：\r\n"+err.Error(), mbIconError)
		s.refresh()
		return
	}
	if s.userMode {
		s.dataDir, _ = layoutdesigner.EffectiveDataDir(s.sharedDir, s.userDir)
	}
	s.source, _ = layoutdesigner.LoadProfile(filepath.Join(s.dataDir, layoutdesigner.ProfileFileName))
	s.sourceDigest, _ = s.source.Digest()
	s.draft = cloneGUIProfile(s.source)
	s.draft.BasedOnDigest = s.sourceDigest
	_ = os.Remove(s.draftPath)
	s.refresh()
	if s.userMode {
		showMessage(s.hwnd, fmt.Sprintf("布局 %s 已应用。\r\n已迁移 %d 个学习词库；输入法会在下一次输入时安全刷新。", applied.TargetDigest[:12], migrationCount), mbIconInfo)
	} else {
		showMessage(s.hwnd, fmt.Sprintf("Layout %s was generated.\r\nBuild and deploy Yime next.", applied.TargetDigest[:12]), mbIconInfo)
	}
}

func (s *guiState) setStatus(text string) { setText(s.status, text) }

func (s *guiState) reloadStoredProfiles() {
	if !s.userMode || s.profileList == 0 {
		return
	}
	s.stored, _ = layoutdesigner.ListStoredProfiles(s.userDir)
	sendMessage.Call(uintptr(s.profileList), cbResetContent, 0, 0)
	for _, item := range s.stored {
		comboAdd(s.profileList, item.Profile.Name)
	}
	if len(s.stored) > 0 {
		sendMessage.Call(uintptr(s.profileList), cbSetCurSel, 0, 0)
	}
}

func (s *guiState) newProfile() {
	if !s.userMode {
		showMessage(s.hwnd, "方案库仅在从输入法工具中心打开时可用。", mbIconInfo)
		return
	}
	s.draft = cloneGUIProfile(s.source)
	s.draft.BasedOnDigest = s.sourceDigest
	s.draft.Name = "新布局 " + time.Now().Format("2006-01-02 150405")
	setText(s.profileName, s.draft.Name)
	s.selected = -1
	s.refresh()
}

func (s *guiState) saveProfile() {
	if !s.userMode {
		showMessage(s.hwnd, "方案库仅在从输入法工具中心打开时可用。", mbIconInfo)
		return
	}
	s.draft.Name = strings.TrimSpace(getText(s.profileName))
	s.draft.BasedOnDigest = s.sourceDigest
	path, err := layoutdesigner.SaveStoredProfile(s.userDir, s.draft)
	if err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	s.reloadStoredProfiles()
	showMessage(s.hwnd, "方案已保存：\r\n"+path, mbIconInfo)
}

func (s *guiState) loadProfile() {
	selected := comboSel(s.profileList)
	if selected < 0 || selected >= len(s.stored) {
		showMessage(s.hwnd, "请先选择一个已存方案。", mbIconInfo)
		return
	}
	s.draft = cloneGUIProfile(s.stored[selected].Profile)
	s.draft.BasedOnDigest = s.sourceDigest
	setText(s.profileName, s.draft.Name)
	s.selected = -1
	s.refresh()
}

func (s *guiState) deleteProfile() {
	selected := comboSel(s.profileList)
	if selected < 0 || selected >= len(s.stored) {
		showMessage(s.hwnd, "请先选择一个已存方案。", mbIconInfo)
		return
	}
	item := s.stored[selected]
	if showMessage(s.hwnd, "删除已存方案“"+item.Profile.Name+"”？\r\n不会改变当前正在使用的布局。", mbYesNo|mbIconQuestion) != idYes {
		return
	}
	if err := layoutdesigner.DeleteStoredProfile(item.Path, s.userDir); err != nil {
		showMessage(s.hwnd, err.Error(), mbIconError)
		return
	}
	s.reloadStoredProfiles()
}

func idAtKey(p layoutdesigner.Profile, key string) string {
	for id, current := range p.Projection {
		if current == key {
			return id
		}
	}
	return ""
}

func comboAdd(hwnd syscall.Handle, text string) {
	ptr, _ := syscall.UTF16PtrFromString(text)
	sendMessage.Call(uintptr(hwnd), cbAddString, 0, uintptr(unsafe.Pointer(ptr)))
}

func comboSel(hwnd syscall.Handle) int {
	value, _, _ := sendMessage.Call(uintptr(hwnd), cbGetCurSel, 0, 0)
	if int32(value) == cbErr {
		return -1
	}
	return int(value)
}

func setText(hwnd syscall.Handle, text string) {
	ptr, _ := syscall.UTF16PtrFromString(text)
	setWindowText.Call(uintptr(hwnd), uintptr(unsafe.Pointer(ptr)))
}

func getText(hwnd syscall.Handle) string {
	length, _, _ := getWindowTextLen.Call(uintptr(hwnd))
	buffer := make([]uint16, length+1)
	getWindowText.Call(uintptr(hwnd), uintptr(unsafe.Pointer(&buffer[0])), length+1)
	return syscall.UTF16ToString(buffer)
}

func showMessage(hwnd syscall.Handle, text string, flags uintptr) int {
	body, _ := syscall.UTF16PtrFromString(text)
	title, _ := syscall.UTF16PtrFromString(uiWindowTitle)
	result, _, _ := messageBox.Call(uintptr(hwnd), uintptr(unsafe.Pointer(body)), uintptr(unsafe.Pointer(title)), flags)
	return int(result)
}
