// 音元拼音输入法 Go 实现（基于 Rime 引擎）
// 对齐 python/input_methods/rime/rime_ime.py
package yime

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/EasyIME/pime-go/pime"
)

const (
	APP         = "PIME"
	APP_VERSION = "0.01"

	ID_MODE_ICON                      = 1
	ID_ASCII_MODE                     = 2
	ID_FULL_SHAPE                     = 3
	ID_ASCII_PUNCT                    = 4
	ID_TRADITIONALIZATION             = 5
	ID_YIME_VARIABLE                  = 20
	ID_YIME_FULL                      = 21
	ID_YIME_SHORTHAND                 = 22
	ID_DEPLOY                         = 10
	ID_SYNC                           = 11
	ID_SYNC_DIR                       = 12
	ID_SHARED_DIR                     = 13
	ID_USER_DIR                       = 14
	ID_LOG_DIR                        = 16
	ID_USER_LEXICON_ADD               = 30
	ID_USER_LEXICON_DELETE            = 31
	ID_USER_LEXICON_EDIT              = 32
	ID_USER_LEXICON_APPLY             = 33
	ID_USER_LEXICON_IMPORT            = 34
	ID_USER_LEXICON_EXPORT            = 35
	ID_REVERSE_LOOKUP_DEFAULT         = 40
	ID_REVERSE_LOOKUP_FULL            = 41
	ID_REVERSE_LOOKUP_HIDDEN          = 42
	ID_REVERSE_LOOKUP_STANDARD_PINYIN = 43
	ID_REVERSE_LOOKUP_YIME_PINYIN     = 44
	ID_REVERSE_LOOKUP_KEY_SEQUENCE    = 45
	ID_HELP_VIEW                      = 60
	ID_HELP_TRIAL_FEEDBACK            = 61
	ID_HELP_COPY_TRIAL_TEMPLATE       = 62
	ID_CANDIDATE_PAGE_SIZE_5          = 70
	ID_CANDIDATE_PAGE_SIZE_6          = 71
	ID_CANDIDATE_PAGE_SIZE_7          = 72
	ID_CANDIDATE_PAGE_SIZE_8          = 73
	ID_CANDIDATE_PAGE_SIZE_9          = 74
	ID_CANDIDATE_LAYOUT_TOGGLE        = 75
)

const (
	defaultCandidatePageSize   = 5
	minCandidatePageSize       = 5
	maxCandidatePageSize       = 9
	horizontalCandidatesPerRow = 10
	verticalCandidatesPerRow   = 1
	yimeCandidateSelectKeys    = "1234567890"
	userLexiconSourceFileName  = "yime_user_phrases.txt"
	rimeUserLexiconFileName    = "custom_phrase.txt"
	defaultUserLexiconWeight   = "1000000"
)

type Style struct {
	DisplayTrayIcon    bool
	CandidateFormat    string
	CandidatePerRow    int
	CandidateUseCursor bool
	FontFace           string
	FontPoint          int
	InlinePreedit      string
	SoftCursor         bool
}

type candidateItem struct {
	Text    string
	Comment string
}

type rimeState struct {
	CommitString    string
	Composition     string
	CursorPos       int
	SelStart        int
	SelEnd          int
	Candidates      []candidateItem
	CandidateCursor int
	SelectKeys      string
	PageSize        int
	AsciiMode       bool
	FullShape       bool
}

type rimeBackend interface {
	Initialize(sharedDir, userDir string, firstRun bool) bool
	EnsureSession() bool
	DestroySession()
	ClearComposition()
	ProcessKey(req *pime.Request, translatedKeyCode, modifiers int) bool
	SelectCandidate(index int) bool
	State() rimeState
	SetOption(name string, value bool)
	GetOption(name string) bool
	SelectSchema(schemaID string) bool
	CurrentSchema() string
}

type backendCandidatePager interface {
	UsesBackendCandidatePaging() bool
}

// backendRedeployer is implemented by backends that can perform a full RIME
// redeployment to pick up on-disk configuration changes (for example an
// updated menu/page_size). Backends that do not implement it fall back to
// recreating the session.
type backendRedeployer interface {
	Redeploy() bool
}

type IME struct {
	*pime.TextServiceBase
	iconDir                  string
	style                    Style
	selectKeys               string
	reverseLookupDisplayMode string
	candidatePageSize        int
	candidatePageStart       int
	lastKeyDownCode          int
	lastKeySkip              int
	lastKeyDownRet           bool
	lastKeyUpCode            int
	lastKeyUpRet             bool
	keyComposing             bool
	backend                  rimeBackend
}

func New(client *pime.Client) pime.TextService {
	return &IME{
		TextServiceBase: pime.NewTextServiceBase(client),
		style: Style{
			DisplayTrayIcon:    true,
			CandidateFormat:    "{0} {1}",
			CandidatePerRow:    verticalCandidatesPerRow,
			CandidateUseCursor: true,
			FontFace:           "MingLiu",
			FontPoint:          20,
			InlinePreedit:      "composition",
			SoftCursor:         false,
		},
		reverseLookupDisplayMode: "default",
		candidatePageSize:        defaultCandidatePageSize,
	}
}

func (ime *IME) HandleRequest(req *pime.Request) *pime.Response {
	resp := pime.NewResponse(req.SeqNum, true)

	switch req.Method {
	case "onActivate":
		return ime.onActivate(req, resp)
	case "onDeactivate":
		return ime.onDeactivate(req, resp)
	case "filterKeyDown":
		return ime.filterKeyDown(req, resp)
	case "onKeyDown":
		return ime.onKeyDown(req, resp)
	case "filterKeyUp":
		return ime.filterKeyUp(req, resp)
	case "onKeyUp":
		return ime.onKeyUp(req, resp)
	case "onCompositionTerminated":
		return ime.onCompositionTerminated(req, resp)
	case "onCommand":
		return ime.onCommand(req, resp)
	case "onMenu":
		return ime.onMenu(req, resp)
	case "selectCandidate":
		return ime.onSelectCandidate(req, resp)
	default:
		resp.ReturnValue = 0
		return resp
	}
}

func (ime *IME) onActivate(req *pime.Request, resp *pime.Response) *pime.Response {
	log.Println("RIME 输入法已激活")
	ime.createSession(resp)
	ime.addButtons(resp)
	ime.updateLangStatus(req, resp)
	if ime.backend != nil {
		ime.applyStateToResponse(resp, ime.backend.State())
	}
	resp.ReturnValue = 1
	return resp
}

func (ime *IME) onDeactivate(req *pime.Request, resp *pime.Response) *pime.Response {
	log.Println("RIME 输入法已失活")
	ime.destroySession(resp)
	ime.removeButtons(resp)
	resp.ReturnValue = 1
	return resp
}

func (ime *IME) filterKeyDown(req *pime.Request, resp *pime.Response) *pime.Response {
	if ime.lastKeyDownCode == req.KeyCode {
		ime.lastKeySkip++
		if ime.lastKeySkip >= 2 {
			ime.lastKeyDownCode = 0
			ime.lastKeySkip = 0
		}
	} else {
		ime.lastKeyDownCode = req.KeyCode
		ime.lastKeySkip = 0
		ime.lastKeyDownRet = ime.processKey(req, false)
	}
	ime.lastKeyUpCode = 0
	resp.ReturnValue = boolToInt(ime.lastKeyDownRet)
	return resp
}

func (ime *IME) filterKeyUp(req *pime.Request, resp *pime.Response) *pime.Response {
	if ime.lastKeyUpCode == req.KeyCode {
		ime.lastKeyUpCode = 0
	} else {
		ime.lastKeyUpCode = req.KeyCode
		ime.lastKeyUpRet = ime.processKey(req, true)
	}
	ime.lastKeyDownCode = 0
	ime.lastKeySkip = 0
	resp.ReturnValue = boolToInt(ime.lastKeyUpRet)
	return resp
}

func (ime *IME) onKeyDown(req *pime.Request, resp *pime.Response) *pime.Response {
	if ime.shouldPassThroughModifierOnKey(req, ime.lastKeyDownRet) {
		resp.ReturnValue = 0
		return resp
	}
	resp.ReturnValue = boolToInt(ime.onKey(req, resp))
	return resp
}

func (ime *IME) onKeyUp(req *pime.Request, resp *pime.Response) *pime.Response {
	if ime.shouldPassThroughModifierOnKey(req, ime.lastKeyUpRet) {
		resp.ReturnValue = 0
		return resp
	}
	resp.ReturnValue = boolToInt(ime.onKey(req, resp))
	return resp
}

func (ime *IME) onSelectCandidate(req *pime.Request, resp *pime.Response) *pime.Response {
	index := -1
	if req.Data != nil {
		if raw, ok := req.Data["candidateIndex"].(float64); ok {
			index = int(raw)
		}
	}
	if index < 0 || ime.backend == nil {
		resp.ReturnValue = 0
		return resp
	}
	if !ime.backendUsesCandidatePaging() {
		index += ime.candidatePageStart
	}

	ime.createSession(resp)
	if !ime.backend.SelectCandidate(index) {
		resp.ReturnValue = 0
		return resp
	}

	resp.ReturnValue = 1
	ime.updateLangStatus(req, resp)
	ime.applyStateToResponse(resp, ime.backend.State())
	return resp
}

func (ime *IME) onCompositionTerminated(req *pime.Request, resp *pime.Response) *pime.Response {
	if req.Forced {
		ime.destroySession(resp)
	} else if ime.backend != nil {
		ime.backend.ClearComposition()
		ime.clearResponse(resp)
	}
	resp.ReturnValue = 1
	return resp
}

func (ime *IME) onCommand(req *pime.Request, resp *pime.Response) *pime.Response {
	commandID := commandIDFromRequest(req)
	if commandID == 0 {
		resp.ReturnValue = 0
		return resp
	}

	ime.createSession(resp)

	switch commandID {
	case ID_ASCII_MODE, ID_MODE_ICON:
		ime.toggleOption("ascii_mode")
	case ID_FULL_SHAPE:
		ime.toggleOption("full_shape")
	case ID_ASCII_PUNCT:
		ime.toggleOption("ascii_punct")
	case ID_TRADITIONALIZATION:
		ime.toggleOption("traditionalization")
	case ID_YIME_VARIABLE:
		ime.selectSchema("yime_variable")
	case ID_YIME_FULL:
		ime.selectSchema("yime_full")
	case ID_YIME_SHORTHAND:
		ime.selectSchema("yime_shorthand")
	case ID_DEPLOY:
		ime.redeployBackend()
	case ID_SYNC:
		log.Println("同步用户数据尚未实现")
	case ID_USER_DIR:
		ime.openPath(ime.userDir())
	case ID_SHARED_DIR:
		ime.openPath(ime.sharedDir())
	case ID_SYNC_DIR:
		ime.openPath(filepath.Join(ime.userDir(), "sync"))
	case ID_LOG_DIR:
		ime.openPath(filepath.Join(os.Getenv("LOCALAPPDATA"), "PIME", "Logs"))
	case ID_USER_LEXICON_ADD:
		ime.editUserLexicon()
	case ID_USER_LEXICON_EDIT:
		ime.editUserLexicon()
	case ID_USER_LEXICON_APPLY:
		if err := ime.applyUserLexicon(); err != nil {
			log.Printf("应用用户词库失败: %v", err)
			ime.showUserLexiconMessage("应用用户词库失败", err.Error(), "Error")
		} else {
			ime.showUserLexiconMessage("应用用户词库", "用户词库格式校验通过，已重建 Rime custom_phrase.txt。", "Information")
		}
	case ID_USER_LEXICON_EXPORT:
		ime.openPath(ime.userDir())
	case ID_USER_LEXICON_DELETE, ID_USER_LEXICON_IMPORT:
		log.Printf("用户词库命令尚未接入: %d", commandID)
	case ID_REVERSE_LOOKUP_DEFAULT:
		ime.setReverseLookupDisplayMode("default")
	case ID_REVERSE_LOOKUP_FULL:
		ime.setReverseLookupDisplayMode("full")
	case ID_REVERSE_LOOKUP_HIDDEN:
		ime.setReverseLookupDisplayMode("hidden")
	case ID_REVERSE_LOOKUP_STANDARD_PINYIN:
		ime.setReverseLookupDisplayMode("standard_pinyin")
	case ID_REVERSE_LOOKUP_YIME_PINYIN:
		ime.setReverseLookupDisplayMode("yime_pinyin")
	case ID_REVERSE_LOOKUP_KEY_SEQUENCE:
		ime.setReverseLookupDisplayMode("key_sequence")
	case ID_HELP_VIEW:
		ime.openPath(filepath.Join(ime.helpDir(), "README.md"))
	case ID_HELP_TRIAL_FEEDBACK:
		ime.openPath(filepath.Join(ime.helpDir(), "trial-feedback.md"))
	case ID_HELP_COPY_TRIAL_TEMPLATE:
		ime.copyTextToClipboard(ime.trialFeedbackTemplate())
	case ID_CANDIDATE_PAGE_SIZE_5, ID_CANDIDATE_PAGE_SIZE_6, ID_CANDIDATE_PAGE_SIZE_7, ID_CANDIDATE_PAGE_SIZE_8, ID_CANDIDATE_PAGE_SIZE_9:
		if err := ime.setCandidatePageSize(minCandidatePageSize + commandID - ID_CANDIDATE_PAGE_SIZE_5); err != nil {
			log.Printf("设置候选页大小失败: %v", err)
		}
	case ID_CANDIDATE_LAYOUT_TOGGLE:
		ime.setCandidateLayout(ime.style.CandidatePerRow <= verticalCandidatesPerRow, resp)
	default:
		log.Printf("未知命令: %d", commandID)
		resp.ReturnValue = 0
		return resp
	}

	ime.updateLangStatus(req, resp)
	if ime.commandShouldRefreshState(commandID) && ime.backend != nil {
		ime.applyStateToResponse(resp, ime.backend.State())
	}
	resp.ReturnValue = 1
	return resp
}

// commandShouldRefreshState reports whether an onCommand handler should push
// composition/candidate state back to the host. Display-only language-bar
// commands such as reverse-lookup mode must not refresh Rime state during the
// menu click callback; doing so after a session reload/redeploy destabilizes
// the host (see AGENTS.md).
func (ime *IME) commandShouldRefreshState(commandID int) bool {
	switch commandID {
	case ID_REVERSE_LOOKUP_DEFAULT, ID_REVERSE_LOOKUP_FULL, ID_REVERSE_LOOKUP_HIDDEN,
		ID_REVERSE_LOOKUP_STANDARD_PINYIN, ID_REVERSE_LOOKUP_YIME_PINYIN, ID_REVERSE_LOOKUP_KEY_SEQUENCE,
		ID_HELP_VIEW, ID_HELP_TRIAL_FEEDBACK, ID_HELP_COPY_TRIAL_TEMPLATE,
		ID_USER_DIR, ID_SHARED_DIR, ID_SYNC_DIR, ID_LOG_DIR, ID_SYNC:
		return false
	default:
		return true
	}
}

func commandIDFromRequest(req *pime.Request) int {
	if req == nil {
		return 0
	}
	if commandID := req.ID.IntValue(); commandID != 0 {
		return commandID
	}
	if req.Data == nil {
		return 0
	}
	raw, ok := req.Data["commandId"]
	if !ok {
		return 0
	}
	switch value := raw.(type) {
	case int:
		return value
	case int32:
		return int(value)
	case int64:
		return int(value)
	case float64:
		return int(value)
	case string:
		commandID, err := strconv.Atoi(strings.TrimSpace(value))
		if err == nil {
			return commandID
		}
	}
	return 0
}

func (ime *IME) setReverseLookupDisplayMode(mode string) {
	switch mode {
	case "default", "full", "hidden", "standard_pinyin", "yime_pinyin", "key_sequence":
		ime.reverseLookupDisplayMode = mode
	default:
		ime.reverseLookupDisplayMode = "default"
	}
}

func (ime *IME) onMenu(req *pime.Request, resp *pime.Response) *pime.Response {
	buttonID := req.ID.StringValue()
	if buttonID == "" && req.Data != nil {
		if raw, ok := req.Data["buttonId"].(string); ok {
			buttonID = raw
		} else if raw, ok := req.Data["id"].(string); ok {
			buttonID = raw
		}
	}
	if buttonID != "settings" && buttonID != "windows-mode-icon" && buttonID != "candidate-layout" && buttonID != "reverse-lookup" &&
		buttonID != "user-lexicon" && buttonID != "help" {
		resp.ReturnData = []map[string]interface{}{}
		resp.ReturnValue = 0
		return resp
	}

	switch buttonID {
	case "help":
		resp.ReturnData = ime.buildHelpMenu()
	case "candidate-layout":
		ime.setCandidateLayout(ime.style.CandidatePerRow <= verticalCandidatesPerRow, nil)
		resp.ReturnData = []map[string]interface{}{}
	case "reverse-lookup":
		resp.ReturnData = ime.buildReverseLookupMenu()
	case "user-lexicon":
		resp.ReturnData = ime.buildUserLexiconMenu()
	default:
		resp.ReturnData = ime.buildMenu()
	}
	resp.ReturnValue = 1
	return resp
}

func (ime *IME) Init(req *pime.Request) bool {
	log.Println("RIME 输入法初始化")
	exePath, err := os.Executable()
	if err != nil {
		log.Printf("获取可执行文件路径失败，原生 RIME 不可用: %v", err)
		return true
	}

	exeDir := filepath.Dir(exePath)
	ime.iconDir = filepath.Join(exeDir, "input_methods", "yime", "icons")
	// After installation this resolves to C:\Program Files (x86)\YIME\go-backend\input_methods\yime\data.
	sharedDir := filepath.Join(exeDir, "input_methods", "yime", "data")

	appData := os.Getenv("APPDATA")
	if appData == "" {
		log.Println("未找到 APPDATA，原生 RIME 不可用")
		return true
	}
	userDir := filepath.Join(appData, APP, "Rime")
	info, statErr := os.Stat(userDir)
	if statErr != nil {
		log.Printf("未找到用户 RIME 数据目录，原生 RIME 不可用: %v", statErr)
		return true
	}
	if !info.IsDir() {
		log.Println("未找到用户 RIME 数据目录，原生 RIME 不可用")
		return true
	}

	real := newNativeBackend()
	if real != nil && real.Initialize(sharedDir, userDir, false) {
		ime.backend = real
		if ps := readPageSizeFromCustomConfig(filepath.Join(userDir, "default.custom.yaml")); ps >= minCandidatePageSize && ps <= maxCandidatePageSize {
			ime.candidatePageSize = ps
		}
	} else {
		ime.backend = nil
	}
	return true
}

func (ime *IME) Close() {
	ime.destroySession(nil)
	log.Println("RIME 输入法关闭")
}

func (ime *IME) BackendAvailable() bool {
	return ime.backend != nil
}

func (ime *IME) processKey(req *pime.Request, isUp bool) bool {
	ime.createSession(nil)
	if ime.backend == nil {
		ime.logShortcutTrace(req, isUp, 0, 0, false, false)
		return false
	}
	if !isUp {
		ime.keyComposing = ime.isComposing()
	}
	if !isUp && ime.keyComposing {
		if !ime.backendUsesCandidatePaging() && ime.handleCandidatePageKey(req) {
			ime.logShortcutTrace(req, isUp, 0, 0, false, true)
			return true
		}
		if _, ok := candidateSelectionIndex(req); ok && ime.hasCandidates() {
			selected := ime.handleVisibleCandidateSelectionKey(req)
			ime.logShortcutTrace(req, isUp, 0, 0, selected, true)
			return true
		}
	}
	ime.candidatePageStart = 0
	translatedKeyCode := translateKeyCode(req)
	modifiers := translateModifiers(req, isUp)
	backendRet := ime.backend.ProcessKey(req, translatedKeyCode, modifiers)
	handled := backendRet
	if backendRet {
		ime.logShortcutTrace(req, isUp, translatedKeyCode, modifiers, backendRet, true)
		return true
	}
	if ime.keyComposing && req.KeyCode == vkReturn {
		handled = true
		ime.logShortcutTrace(req, isUp, translatedKeyCode, modifiers, backendRet, handled)
		return true
	}
	if (req.KeyCode == vkShift || req.KeyCode == vkCapital) &&
		(modifiers == 0 || modifiers == releaseMask) {
		handled = true
		ime.logShortcutTrace(req, isUp, translatedKeyCode, modifiers, backendRet, handled)
		return true
	}
	ime.logShortcutTrace(req, isUp, translatedKeyCode, modifiers, backendRet, handled)
	return false
}

func (ime *IME) logShortcutTrace(req *pime.Request, isUp bool, translatedKeyCode, modifiers int, backendRet, handled bool) {
	if req == nil {
		return
	}
	if modifiers&controlMask == 0 && modifiers&altMask == 0 && req.KeyCode != vkControl && req.KeyCode != vkMenu {
		return
	}

	eventType := "down"
	if isUp {
		eventType = "up"
	}
	log.Printf(
		"RIME 快捷键追踪 event=%s keyCode=%d charCode=%d translatedKey=%d modifiers=%d ctrl=%t alt=%t backendRet=%t handled=%t composing=%t",
		eventType,
		req.KeyCode,
		req.CharCode,
		translatedKeyCode,
		modifiers,
		(modifiers&controlMask) != 0 || req.KeyCode == vkControl,
		(modifiers&altMask) != 0 || req.KeyCode == vkMenu,
		backendRet,
		handled,
		ime.keyComposing,
	)
}

func (ime *IME) shouldPassThroughModifierOnKey(req *pime.Request, filterHandled bool) bool {
	if req == nil || filterHandled {
		return false
	}
	if req.KeyCode == vkControl || req.KeyCode == vkMenu {
		return true
	}
	if req.CharCode > 0 && req.CharCode < 0x20 {
		return true
	}
	return req.KeyStates.IsKeyDown(vkControl) || req.KeyStates.IsKeyDown(vkMenu)
}

func remapYimeCandidateSelectionKey(req *pime.Request) (int, bool) {
	switch req.KeyCode {
	case vkSpace:
		return int('1'), true
	case 0xC0: // VK_OEM_3: `
		return int('2'), true
	case 0xBD: // VK_OEM_MINUS: -
		return int('3'), true
	case 0xBB: // VK_OEM_PLUS: =
		return int('4'), true
	case 0xDC: // VK_OEM_5: backslash
		return int('5'), true
	}
	switch req.CharCode {
	case ' ':
		return int('1'), true
	case '`':
		return int('2'), true
	case '-':
		return int('3'), true
	case '=':
		return int('4'), true
	case '\\':
		return int('5'), true
	default:
		return 0, false
	}
}

func candidateSelectionIndex(req *pime.Request) (int, bool) {
	switch req.KeyCode {
	case vkSpace:
		return 0, true
	case 0xC0: // VK_OEM_3: `
		return 1, true
	case 0xBD: // VK_OEM_MINUS: -
		return 2, true
	case 0xBB: // VK_OEM_PLUS: =
		return 3, true
	case 0xDC: // VK_OEM_5: backslash
		return 4, true
	}
	switch req.CharCode {
	case ' ':
		return 0, true
	case '`':
		return 1, true
	case '-':
		return 2, true
	case '=':
		return 3, true
	case '\\':
		return 4, true
	default:
		return 0, false
	}
}

func isCandidatePageKey(req *pime.Request) bool {
	if req == nil {
		return false
	}
	switch req.KeyCode {
	case vkHome, vkPrior, vkNext, vkEnd:
		return true
	default:
		return false
	}
}

func (ime *IME) hasCandidates() bool {
	if ime.backend == nil {
		return false
	}
	return len(ime.backend.State().Candidates) > 0
}

func (ime *IME) handleCandidatePageKey(req *pime.Request) bool {
	if !isCandidatePageKey(req) || ime.backend == nil {
		return false
	}
	state := ime.backend.State()
	if len(state.Candidates) == 0 {
		return false
	}
	pageSize := ime.normalizedCandidatePageSize()
	lastStart := ((len(state.Candidates) - 1) / pageSize) * pageSize
	oldStart := ime.candidatePageStart
	switch req.KeyCode {
	case vkHome:
		ime.candidatePageStart = 0
	case vkPrior:
		ime.candidatePageStart -= pageSize
		if ime.candidatePageStart < 0 {
			ime.candidatePageStart = 0
		}
	case vkNext:
		if ime.candidatePageStart < lastStart {
			ime.candidatePageStart += pageSize
			if ime.candidatePageStart > lastStart {
				ime.candidatePageStart = lastStart
			}
		}
	case vkEnd:
		ime.candidatePageStart = lastStart
	}
	return ime.candidatePageStart != oldStart
}

func (ime *IME) handleVisibleCandidateSelectionKey(req *pime.Request) bool {
	if ime.backend == nil {
		return false
	}
	index, ok := candidateSelectionIndex(req)
	if !ok {
		return false
	}
	state := ime.backend.State()
	globalIndex := index
	if !ime.backendUsesCandidatePaging() {
		globalIndex += ime.candidatePageStart
	}
	if globalIndex < 0 || globalIndex >= len(state.Candidates) {
		return false
	}
	if !ime.backend.SelectCandidate(globalIndex) {
		return false
	}
	ime.candidatePageStart = 0
	return true
}

func (ime *IME) onKey(req *pime.Request, resp *pime.Response) bool {
	if ime.backend == nil {
		ime.clearResponse(resp)
		ime.keyComposing = false
		return true
	}
	ime.updateLangStatus(req, resp)
	state := ime.backend.State()
	ime.applyStateToResponse(resp, state)
	ime.keyComposing = state.Composition != "" || len(state.Candidates) > 0
	return true
}

func (ime *IME) applyStateToResponse(resp *pime.Response, state rimeState) {
	if state.PageSize >= minCandidatePageSize && state.PageSize <= maxCandidatePageSize {
		ime.candidatePageSize = state.PageSize
	}
	if state.CommitString != "" {
		resp.CommitString = state.CommitString
	}
	if state.Composition == "" {
		ime.clearResponse(resp)
		ime.keyComposing = false
		return
	}

	if len(state.Candidates) > 0 && ime.selectKeys != yimeCandidateSelectKeys {
		resp.SetSelKeys = yimeCandidateSelectKeys
		ime.selectKeys = yimeCandidateSelectKeys
	} else if len(state.Candidates) == 0 && state.SelectKeys != "" && state.SelectKeys != ime.selectKeys {
		resp.SetSelKeys = state.SelectKeys
		ime.selectKeys = state.SelectKeys
	}

	resp.CompositionString = state.Composition
	resp.CursorPos = state.CursorPos
	resp.CompositionCursor = state.CursorPos
	resp.SelStart = state.SelStart
	resp.SelEnd = state.SelEnd

	if len(state.Candidates) > 0 {
		visibleCandidates, cursor := ime.visibleCandidates(state.Candidates, state.CandidateCursor)
		resp.CandidateList = ime.formatCandidates(visibleCandidates)
		resp.CandidateCursor = cursor
		resp.ShowCandidates = true
	} else {
		ime.candidatePageStart = 0
		resp.ShowCandidates = false
	}
	ime.keyComposing = true
}

func (ime *IME) normalizedCandidatePageSize() int {
	if ime.candidatePageSize < minCandidatePageSize || ime.candidatePageSize > maxCandidatePageSize {
		return defaultCandidatePageSize
	}
	return ime.candidatePageSize
}

func (ime *IME) visibleCandidates(candidates []candidateItem, candidateCursor int) ([]candidateItem, int) {
	if len(candidates) == 0 {
		ime.candidatePageStart = 0
		return nil, 0
	}
	if ime.backendUsesCandidatePaging() {
		ime.candidatePageStart = 0
		if candidateCursor < 0 || candidateCursor >= len(candidates) {
			candidateCursor = 0
		}
		return candidates, candidateCursor
	}
	pageSize := ime.normalizedCandidatePageSize()
	lastStart := ((len(candidates) - 1) / pageSize) * pageSize
	if ime.candidatePageStart < 0 {
		ime.candidatePageStart = 0
	}
	if ime.candidatePageStart > lastStart {
		ime.candidatePageStart = lastStart
	}
	start := ime.candidatePageStart
	end := start + pageSize
	if end > len(candidates) {
		end = len(candidates)
	}
	cursor := candidateCursor - start
	if cursor < 0 || cursor >= end-start {
		cursor = 0
	}
	return candidates[start:end], cursor
}

func (ime *IME) backendUsesCandidatePaging() bool {
	if ime.backend == nil {
		return false
	}
	pager, ok := ime.backend.(backendCandidatePager)
	return ok && pager.UsesBackendCandidatePaging()
}

func (ime *IME) createSession(resp *pime.Response) {
	if ime.backend == nil {
		return
	}
	if !ime.backend.EnsureSession() {
		return
	}
	if resp != nil {
		resp.CustomizeUI = map[string]interface{}{
			"candFontName":  ime.style.FontFace,
			"candFontSize":  ime.style.FontPoint,
			"candPerRow":    ime.style.CandidatePerRow,
			"candUseCursor": ime.style.CandidateUseCursor,
		}
	}
}

func (ime *IME) destroySession(resp *pime.Response) {
	ime.clearResponse(resp)
	if ime.backend != nil {
		ime.backend.ClearComposition()
		ime.backend.DestroySession()
	}
	ime.keyComposing = false
	ime.selectKeys = ""
	ime.candidatePageStart = 0
}

func (ime *IME) clearResponse(resp *pime.Response) {
	if resp == nil {
		return
	}
	resp.CompositionString = ""
	resp.CursorPos = 0
	resp.CompositionCursor = 0
	resp.CandidateList = []string{}
	resp.CandidateCursor = 0
	resp.ShowCandidates = false
}

func (ime *IME) isComposing() bool {
	if ime.backend == nil {
		return false
	}
	state := ime.backend.State()
	return state.Composition != "" || len(state.Candidates) > 0
}

func (ime *IME) toggleOption(name string) {
	if ime.backend == nil {
		return
	}
	ime.backend.SetOption(name, !ime.backend.GetOption(name))
}

func (ime *IME) setCandidateLayout(horizontal bool, resp *pime.Response) {
	if horizontal {
		ime.style.CandidatePerRow = horizontalCandidatesPerRow
	} else {
		ime.style.CandidatePerRow = verticalCandidatesPerRow
	}
	if ime.backend != nil {
		ime.backend.SetOption("_horizontal", horizontal)
	}
	if resp != nil {
		if resp.CustomizeUI == nil {
			resp.CustomizeUI = map[string]interface{}{}
		}
		resp.CustomizeUI["candPerRow"] = ime.style.CandidatePerRow
		change := pime.ButtonInfo{
			ID:        "candidate-layout",
			CommandID: ID_CANDIDATE_LAYOUT_TOGGLE,
		}
		if iconPath := ime.iconPath(candidateLayoutIconName(horizontal)); iconPath != "" {
			change.Icon = iconPath
		}
		resp.ChangeButton = append(resp.ChangeButton, change)
	}
}

func (ime *IME) selectSchema(schemaID string) {
	if ime.backend == nil || schemaID == "" {
		return
	}
	if schemaPath := ime.prepareUserSchema(schemaID); schemaPath != "" {
		if !deploySchemaConfig(schemaPath) {
			log.Printf("部署方案失败: %s", schemaPath)
		}
	}
	if ime.backend.SelectSchema(schemaID) {
		ime.backend.ClearComposition()
	}
}

func (ime *IME) updateLangStatus(req *pime.Request, resp *pime.Response) {
	if !ime.style.DisplayTrayIcon || ime.backend == nil {
		return
	}
	asciiMode := ime.backend.GetOption("ascii_mode")
	fullShape := ime.backend.GetOption("full_shape")
	capsOn := req != nil && req.KeyStates.IsKeyToggled(vkCapital)

	if ime.Client != nil && ime.Client.IsWindows8Above {
		if iconPath := ime.iconPath(modeIconName(asciiMode, fullShape, capsOn)); iconPath != "" {
			resp.ChangeButton = append(resp.ChangeButton, pime.ButtonInfo{
				ID:   "windows-mode-icon",
				Icon: iconPath,
			})
		}
	}
	if iconPath := ime.iconPath(langIconName(asciiMode)); iconPath != "" {
		resp.ChangeButton = append(resp.ChangeButton, pime.ButtonInfo{
			ID:   "switch-lang",
			Icon: iconPath,
		})
	}
	if iconPath := ime.iconPath(shapeIconName(fullShape)); iconPath != "" {
		resp.ChangeButton = append(resp.ChangeButton, pime.ButtonInfo{
			ID:   "switch-shape",
			Icon: iconPath,
		})
	}
}

func (ime *IME) addButtons(resp *pime.Response) {
	if !ime.style.DisplayTrayIcon || ime.backend == nil {
		return
	}
	asciiMode := ime.backend.GetOption("ascii_mode")
	fullShape := ime.backend.GetOption("full_shape")
	if ime.Client != nil && ime.Client.IsWindows8Above {
		if iconPath := ime.iconPath(modeIconName(asciiMode, fullShape, false)); iconPath != "" {
			resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
				ID:        "windows-mode-icon",
				Icon:      iconPath,
				Tooltip:   "中西文切换",
				CommandID: ID_MODE_ICON,
			})
		}
	}
	if iconPath := ime.iconPath(langIconName(asciiMode)); iconPath != "" {
		resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
			ID:        "switch-lang",
			Icon:      iconPath,
			Text:      "中西文切换",
			Tooltip:   "中西文切换",
			CommandID: ID_ASCII_MODE,
		})
	}
	if iconPath := ime.iconPath(shapeIconName(fullShape)); iconPath != "" {
		resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
			ID:        "switch-shape",
			Icon:      iconPath,
			Text:      "全半宽切换",
			Tooltip:   "全宽/半宽切换",
			CommandID: ID_FULL_SHAPE,
		})
	}
	layoutButton := pime.ButtonInfo{
		ID:        "candidate-layout",
		Text:      "横竖排切换",
		Tooltip:   "排列方式",
		CommandID: ID_CANDIDATE_LAYOUT_TOGGLE,
		Type:      "button",
	}
	if iconPath := ime.iconPath(candidateLayoutIconName(ime.style.CandidatePerRow > verticalCandidatesPerRow)); iconPath != "" {
		layoutButton.Icon = iconPath
	}
	resp.AddButton = append(resp.AddButton, layoutButton)
	resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
		ID:      "reverse-lookup",
		Text:    "显示编码",
		Tooltip: "显示编码",
		Type:    "menu",
	})
	resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
		ID:      "user-lexicon",
		Text:    "用户词库",
		Tooltip: "用户词库",
		Type:    "menu",
	})
	if iconPath := ime.iconPath("config.ico"); iconPath != "" {
		resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
			ID:   "settings",
			Icon: iconPath,
			Text: "设置",
			Type: "menu",
		})
	}
	resp.AddButton = append(resp.AddButton, pime.ButtonInfo{
		ID:      "help",
		Text:    "帮助",
		Tooltip: "帮助",
		Type:    "menu",
	})
}

func (ime *IME) removeButtons(resp *pime.Response) {
	if !ime.style.DisplayTrayIcon || resp == nil {
		return
	}
	resp.RemoveButton = append(resp.RemoveButton, "switch-lang", "switch-shape", "candidate-layout", "reverse-lookup", "user-lexicon", "settings", "help")
	if ime.Client != nil && ime.Client.IsWindows8Above {
		resp.RemoveButton = append(resp.RemoveButton, "windows-mode-icon")
	}
}

func (ime *IME) formatCandidates(candidates []candidateItem) []string {
	formatted := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		text := candidate.Text
		if candidate.Comment != "" {
			if strings.Contains(ime.style.CandidateFormat, "{0}") && strings.Contains(ime.style.CandidateFormat, "{1}") {
				text = strings.ReplaceAll(ime.style.CandidateFormat, "{0}", candidate.Text)
				text = strings.ReplaceAll(text, "{1}", candidate.Comment)
			} else {
				text = candidate.Text + " " + candidate.Comment
			}
		}
		formatted = append(formatted, text)
	}
	return formatted
}

func (ime *IME) iconPath(name string) string {
	if ime.iconDir == "" || name == "" {
		return ""
	}
	iconPath := filepath.Join(ime.iconDir, name)
	if _, err := os.Stat(iconPath); err != nil {
		return ""
	}
	return iconPath
}

func (ime *IME) schemaAvailable(schemaID string) bool {
	return ime.schemaPath(schemaID) != ""
}

func (ime *IME) schemaPath(schemaID string) string {
	if schemaID == "" {
		return ""
	}
	schemaPath := filepath.Join(ime.sharedDir(), schemaID+".schema.yaml")
	info, err := os.Stat(schemaPath)
	if err == nil && !info.IsDir() {
		return schemaPath
	}
	return ""
}

func (ime *IME) prepareUserSchema(schemaID string) string {
	sharedSchemaPath := ime.schemaPath(schemaID)
	if sharedSchemaPath == "" {
		return ""
	}
	userDir := ime.userDir()
	if userDir == "" {
		return sharedSchemaPath
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		log.Printf("创建 RIME 用户目录失败: %v", err)
		return sharedSchemaPath
	}
	userSchemaPath := filepath.Join(userDir, schemaID+".schema.yaml")
	content, err := os.ReadFile(sharedSchemaPath)
	if err != nil {
		log.Printf("读取方案文件失败 %s: %v", sharedSchemaPath, err)
		return sharedSchemaPath
	}
	userSchemaContent := string(content)
	if strings.HasPrefix(schemaID, "yime_") {
		userSchemaContent = updateSchemaMenuPageSize(userSchemaContent, ime.normalizedCandidatePageSize())
	}
	if err := os.WriteFile(userSchemaPath, []byte(userSchemaContent), 0o644); err != nil {
		log.Printf("写入用户方案文件失败 %s: %v", userSchemaPath, err)
		return sharedSchemaPath
	}
	return userSchemaPath
}

func (ime *IME) buildMenu() []map[string]interface{} {
	asciiMode := ime.backend != nil && ime.backend.GetOption("ascii_mode")
	fullShape := ime.backend != nil && ime.backend.GetOption("full_shape")
	asciiPunct := ime.backend != nil && ime.backend.GetOption("ascii_punct")
	traditionalization := ime.backend != nil && ime.backend.GetOption("traditionalization")
	currentSchema := ""
	if ime.backend != nil {
		currentSchema = ime.backend.CurrentSchema()
	}

	asciiText := "中文 → 英文"
	if asciiMode {
		asciiText = "英文 → 中文"
	}
	shapeText := "半宽 → 全宽"
	if fullShape {
		shapeText = "全宽 → 半宽"
	}
	punctText := "中文标点 → 英文标点"
	if asciiPunct {
		punctText = "英文标点 → 中文标点"
	}
	traditionalizationText := "简体 → 繁体"
	if traditionalization {
		traditionalizationText = "繁体 → 简体"
	}

	return []map[string]interface{}{
		{"text": "模式", "submenu": []map[string]interface{}{
			{"id": ID_YIME_FULL, "text": "等长", "checked": currentSchema == "yime_full"},
			{"id": ID_YIME_VARIABLE, "text": "变长", "checked": currentSchema == "" || currentSchema == "yime_variable"},
			{"id": ID_YIME_SHORTHAND, "text": "省键", "checked": currentSchema == "yime_shorthand", "enabled": ime.schemaAvailable("yime_shorthand")},
		}},
		{"text": ""},
		{"id": ID_ASCII_MODE, "text": asciiText},
		{"id": ID_TRADITIONALIZATION, "text": traditionalizationText},
		{"id": ID_ASCII_PUNCT, "text": punctText},
		{"id": ID_FULL_SHAPE, "text": shapeText},
		{"text": ""},
		{"id": ID_CANDIDATE_LAYOUT_TOGGLE, "text": candidateLayoutToggleText(ime.style.CandidatePerRow > verticalCandidatesPerRow)},
		{"text": "候选项数", "submenu": ime.buildCandidatePageSizeMenu()},
		{"text": ""},
		{"id": ID_DEPLOY, "text": "重新部署(&D)"},
		{"id": ID_SYNC, "text": "同步(&S)"},
		{"text": "打开文件夹(&O)", "submenu": []map[string]interface{}{
			{"id": ID_USER_DIR, "text": "用户文件夹"},
			{"id": ID_SHARED_DIR, "text": "共享文件夹"},
			{"id": ID_SYNC_DIR, "text": "同步文件夹"},
			{"id": ID_LOG_DIR, "text": "日志文件夹"},
		}},
	}
}

func (ime *IME) buildReverseLookupMenu() []map[string]interface{} {
	return []map[string]interface{}{
		{"id": ID_REVERSE_LOOKUP_DEFAULT, "text": "默认：标准拼音 + 音元拼音", "checked": ime.reverseLookupDisplayMode == "default"},
		{"id": ID_REVERSE_LOOKUP_FULL, "text": "完整：标准拼音、音元拼音和键位序列", "checked": ime.reverseLookupDisplayMode == "full"},
		{"id": ID_REVERSE_LOOKUP_HIDDEN, "text": "隐藏编码", "checked": ime.reverseLookupDisplayMode == "hidden"},
		{"text": ""},
		{"id": ID_REVERSE_LOOKUP_STANDARD_PINYIN, "text": "仅标准拼音", "checked": ime.reverseLookupDisplayMode == "standard_pinyin"},
		{"id": ID_REVERSE_LOOKUP_YIME_PINYIN, "text": "仅音元拼音", "checked": ime.reverseLookupDisplayMode == "yime_pinyin"},
		{"id": ID_REVERSE_LOOKUP_KEY_SEQUENCE, "text": "仅键位序列", "checked": ime.reverseLookupDisplayMode == "key_sequence"},
	}
}


func (ime *IME) buildCandidatePageSizeMenu() []map[string]interface{} {
	pageSize := ime.candidatePageSize
	if pageSize < minCandidatePageSize || pageSize > maxCandidatePageSize {
		pageSize = defaultCandidatePageSize
	}
	items := make([]map[string]interface{}, 0, maxCandidatePageSize-minCandidatePageSize+1)
	for size := minCandidatePageSize; size <= maxCandidatePageSize; size++ {
		items = append(items, map[string]interface{}{
			"id":      ID_CANDIDATE_PAGE_SIZE_5 + size - minCandidatePageSize,
			"text":    strconv.Itoa(size) + " 项",
			"checked": size == pageSize,
		})
	}
	return items
}

func (ime *IME) buildUserLexiconMenu() []map[string]interface{} {
	return []map[string]interface{}{
		{"id": ID_USER_LEXICON_ADD, "text": "添加用户词条"},
		{"id": ID_USER_LEXICON_DELETE, "text": "删除用户词条", "enabled": false},
		{"text": ""},
		{"id": ID_USER_LEXICON_EDIT, "text": "编辑用户词库"},
		{"id": ID_USER_LEXICON_APPLY, "text": "应用用户词库"},
		{"text": ""},
		{"id": ID_USER_LEXICON_IMPORT, "text": "导入用户词库", "enabled": false},
		{"id": ID_USER_LEXICON_EXPORT, "text": "导出用户词库"},
	}
}

func (ime *IME) buildHelpMenu() []map[string]interface{} {
	return []map[string]interface{}{
		{"id": ID_HELP_VIEW, "text": "查看帮助"},
		{"id": ID_HELP_TRIAL_FEEDBACK, "text": "查看试用反馈说明"},
		{"id": ID_HELP_COPY_TRIAL_TEMPLATE, "text": "复制试用反馈模板"},
	}
}

func (ime *IME) sharedDir() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Join(filepath.Dir(exePath), "input_methods", "yime", "data")
}

func (ime *IME) userDir() string {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return ""
	}
	return filepath.Join(appData, APP, "Rime")
}

func (ime *IME) helpDir() string {
	exePath, err := os.Executable()
	if err != nil {
		return ""
	}
	return filepath.Join(filepath.Dir(exePath), "input_methods", "yime", "help")
}

func (ime *IME) userLexiconPath() string {
	userDir := ime.userDir()
	if userDir == "" {
		return ""
	}
	return filepath.Join(userDir, userLexiconSourceFileName)
}

func (ime *IME) rimeUserLexiconPath() string {
	userDir := ime.userDir()
	if userDir == "" {
		return ""
	}
	return filepath.Join(userDir, rimeUserLexiconFileName)
}

func (ime *IME) ensureUserLexiconFile() (string, error) {
	path := ime.userLexiconPath()
	if path == "" {
		return "", os.ErrNotExist
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", err
	}
	if _, err := os.Stat(path); err == nil {
		return path, nil
	} else if !os.IsNotExist(err) {
		return "", err
	}
	header := "# PIME Yime user phrases\n# format: phrase<TAB>numeric-tone-pinyin<TAB>weight\n# example: 中国\tzhong1 guo2\t1000000\n"
	return path, os.WriteFile(path, []byte(header), 0o644)
}

func (ime *IME) editUserLexicon() {
	path, err := ime.ensureUserLexiconFile()
	if err != nil {
		log.Printf("打开用户词库失败: %v", err)
		ime.showUserLexiconMessage("打开用户词库失败", err.Error(), "Error")
		return
	}
	ime.openPath(path)
}

func (ime *IME) addUserLexiconPhrase() error {
	return ime.startUserLexiconAddHelper(ime.currentYimeMode())
}

func (ime *IME) currentYimeMode() string {
	if ime.backend == nil {
		return "variable"
	}
	switch ime.backend.CurrentSchema() {
	case "yime_full":
		return "full"
	case "yime_shorthand":
		return "shorthand"
	default:
		return "variable"
	}
}

func (ime *IME) applyUserLexicon() error {
	sourcePath, err := ime.ensureUserLexiconFile()
	if err != nil {
		return err
	}
	targetPath := ime.rimeUserLexiconPath()
	if targetPath == "" {
		return os.ErrNotExist
	}
	if err := ime.writeRimeUserLexicon(sourcePath, targetPath, ime.currentYimeMode()); err != nil {
		return err
	}
	if ime.backend == nil {
		return nil
	}
	schemaID := ime.backend.CurrentSchema()
	if schemaID == "" {
		schemaID = "yime_variable"
	}
	ime.selectSchema(schemaID)
	return nil
}

func (ime *IME) encodeNumericTonePinyin(pinyin, mode string) (string, error) {
	codes, err := ime.loadPinyinCodeMap()
	if err != nil {
		return "", err
	}
	normalizedPinyin := normalizeNumericTonePinyinSyllableSpacing(pinyin)
	if normalizedPinyin == "" {
		return "", os.ErrInvalid
	}
	parts := strings.Fields(normalizedPinyin)
	var encoded strings.Builder
	for _, part := range parts {
		key := normalizeNumericTonePinyin(part)
		record, ok := codes[key]
		if !ok {
			return "", fmt.Errorf("找不到拼音 %q", part)
		}
		switch mode {
		case "full":
			encoded.WriteString(record.Full)
		case "shorthand":
			encoded.WriteString(record.Shorthand)
		default:
			encoded.WriteString(record.Variable)
		}
	}
	return encoded.String(), nil
}

type pinyinCodeRecord struct {
	Full      string
	Variable  string
	Shorthand string
}

func (ime *IME) loadPinyinCodeMap() (map[string]pinyinCodeRecord, error) {
	path := filepath.Join(ime.sharedDir(), "yime_pinyin_codes.tsv")
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	records := make(map[string]pinyinCodeRecord)
	scanner := bufio.NewScanner(file)
	first := true
	for scanner.Scan() {
		line := scanner.Text()
		if first {
			first = false
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 4 {
			continue
		}
		key := normalizeNumericTonePinyin(fields[0])
		record := pinyinCodeRecord{Full: fields[1], Variable: fields[2], Shorthand: fields[3]}
		records[key] = record
		if strings.Contains(key, "ü") {
			records[strings.ReplaceAll(key, "ü", "v")] = record
			records[strings.ReplaceAll(key, "ü", "u:")] = record
		}
	}
	return records, scanner.Err()
}

func normalizeNumericTonePinyin(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "u:", "ü")
	value = strings.ReplaceAll(value, "v", "ü")
	return value
}

func splitCompactNumericTonePinyinToken(token string) []string {
	normalizedToken := strings.TrimSpace(token)
	if normalizedToken == "" {
		return nil
	}

	parts := []string{}
	start := 0
	sawToneDigit := false
	for index, char := range normalizedToken {
		if char < '1' || char > '5' {
			continue
		}
		sawToneDigit = true
		if index == start {
			return []string{normalizedToken}
		}
		parts = append(parts, normalizedToken[start:index+1])
		start = index + 1
	}
	if !sawToneDigit || start != len(normalizedToken) {
		return []string{normalizedToken}
	}
	return parts
}

func normalizeNumericTonePinyinSyllableSpacing(rawPinyin string) string {
	normalizedTokens := []string{}
	for _, token := range strings.Fields(rawPinyin) {
		for _, part := range splitCompactNumericTonePinyinToken(token) {
			normalized := normalizeNumericTonePinyin(part)
			if normalized != "" {
				normalizedTokens = append(normalizedTokens, normalized)
			}
		}
	}
	return strings.Join(normalizedTokens, " ")
}

func isValidNumericTonePinyin(pinyin string) bool {
	parts := strings.Fields(pinyin)
	if len(parts) == 0 {
		return false
	}
	for _, part := range parts {
		if !isValidNumericTonePinyinSyllable(part) {
			return false
		}
	}
	return true
}

func isValidNumericTonePinyinSyllable(part string) bool {
	runes := []rune(part)
	if len(runes) < 2 {
		return false
	}
	last := runes[len(runes)-1]
	if last < '1' || last > '5' {
		return false
	}
	for _, char := range runes[:len(runes)-1] {
		if (char >= 'a' && char <= 'z') || char == 'ü' {
			continue
		}
		return false
	}
	return true
}

func (ime *IME) setCandidatePageSize(size int) error {
	if size < minCandidatePageSize || size > maxCandidatePageSize {
		size = defaultCandidatePageSize
	}
	userDir := ime.userDir()
	if userDir == "" {
		return os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return err
	}
	configPath := filepath.Join(userDir, "default.custom.yaml")
	content := ""
	if data, err := os.ReadFile(configPath); err == nil {
		content = string(data)
	} else if !os.IsNotExist(err) {
		return err
	}
	updated := updateDefaultCustomPageSize(content, size)
	if err := os.WriteFile(configPath, []byte(updated), 0o644); err != nil {
		return err
	}
	ime.candidatePageSize = size
	ime.candidatePageStart = 0
	if !deployDefaultCustomConfig(configPath) {
		log.Printf("部署默认候选数量配置失败，继续更新当前方案: %s", configPath)
	}
	if ime.backend != nil {
		schemaID := ime.backend.CurrentSchema()
		if schemaID == "" {
			schemaID = "yime_variable"
		}
		if customPath, err := ime.writeSchemaCustomPageSize(schemaID, size); err != nil {
			log.Printf("写入候选数量方案自定义配置失败: %v", err)
		} else if customPath != "" && !deploySchemaCustomConfig(customPath) {
			log.Printf("部署候选数量方案自定义配置失败: %s", customPath)
		}
		if schemaPath := ime.prepareUserSchema(schemaID); schemaPath != "" && !deploySchemaConfig(schemaPath) {
			log.Printf("部署候选数量方案配置失败: %s", schemaPath)
		}
		// Do not call RimeRedeploy here. Full redeploy during a language-bar click
		// invalidates librime inside the TSF callback and breaks subsequent menu
		// clicks such as reverse-lookup "仅音元拼音". Use a lightweight session
		// reload instead; full cache invalidation stays on the "重新部署" command.
		ime.reloadBackendSessionForSchema(schemaID)
		if newState := ime.backend.State(); newState.PageSize >= minCandidatePageSize && newState.PageSize <= maxCandidatePageSize {
			ime.candidatePageSize = newState.PageSize
		}
	}
	return nil
}

// redeployBackend re-runs a full RIME deployment for the current schema. It is
// used by the "重新部署" menu command to let users force configuration to be
// recompiled and reloaded.
func (ime *IME) redeployBackend() {
	if ime.backend == nil {
		return
	}
	schemaID := ime.backend.CurrentSchema()
	if schemaID == "" {
		schemaID = "yime_variable"
	}
	ime.reloadBackendForSchema(schemaID)
}

// reloadBackendSessionForSchema recreates the current Rime session without a
// full redeploy. It is safe to call from language-bar commands such as page
// size changes. It does not invalidate librime's compiled config cache.
func (ime *IME) reloadBackendSessionForSchema(schemaID string) {
	if ime.backend == nil {
		return
	}
	ime.backend.DestroySession()
	if ime.backend.EnsureSession() {
		ime.backend.SelectSchema(schemaID)
		ime.backend.ClearComposition()
	}
}

// reloadBackendForSchema makes freshly written RIME configuration take effect.
// Native RIME caches compiled schema configs in memory, so per-file deploys are
// not enough: a full redeploy is required to invalidate that cache. This path
// is reserved for the explicit "重新部署" command, not language-bar clicks.
func (ime *IME) reloadBackendForSchema(schemaID string) {
	if ime.backend == nil {
		return
	}
	if redeployer, ok := ime.backend.(backendRedeployer); ok {
		if redeployer.Redeploy() {
			if ime.backend.SelectSchema(schemaID) {
				ime.backend.ClearComposition()
			}
			return
		}
		log.Println("Rime 重新部署失败，回退到重建会话")
	}
	ime.reloadBackendSessionForSchema(schemaID)
}

func (ime *IME) writeSchemaCustomPageSize(schemaID string, size int) (string, error) {
	if schemaID == "" {
		return "", os.ErrNotExist
	}
	userDir := ime.userDir()
	if userDir == "" {
		return "", os.ErrNotExist
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		return "", err
	}
	configPath := filepath.Join(userDir, schemaID+".custom.yaml")
	content := ""
	if data, err := os.ReadFile(configPath); err == nil {
		content = string(data)
	} else if !os.IsNotExist(err) {
		return "", err
	}
	updated := updateDefaultCustomPageSize(content, size)
	if err := os.WriteFile(configPath, []byte(updated), 0o644); err != nil {
		return "", err
	}
	return configPath, nil
}

type userLexiconEntry struct {
	Phrase     string
	Pinyin     string
	Weight     string
	LineNumber int
}

func loadUserLexiconEntries(path string) ([]userLexiconEntry, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	entries := []userLexiconEntry{}
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 2 || len(fields) > 3 {
			return nil, fmt.Errorf("用户词库第 %d 行格式应为：词条<TAB>数字标调拼音<TAB>权重", lineNumber)
		}
		phrase := strings.TrimSpace(fields[0])
		pinyin := normalizeNumericTonePinyinSyllableSpacing(fields[1])
		weight := defaultUserLexiconWeight
		if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
			weight = strings.TrimSpace(fields[2])
		}
		if phrase == "" || pinyin == "" {
			return nil, fmt.Errorf("用户词库第 %d 行词条和数字标调拼音不能为空", lineNumber)
		}
		if !isValidNumericTonePinyin(pinyin) {
			return nil, fmt.Errorf("用户词库第 %d 行数字标调拼音格式错误：%s", lineNumber, pinyin)
		}
		if _, err := strconv.Atoi(weight); err != nil {
			return nil, fmt.Errorf("用户词库第 %d 行权重必须是整数", lineNumber)
		}
		entries = append(entries, userLexiconEntry{Phrase: phrase, Pinyin: pinyin, Weight: weight, LineNumber: lineNumber})
	}
	return entries, scanner.Err()
}

func (ime *IME) writeRimeUserLexicon(sourcePath, targetPath, mode string) error {
	entries, err := loadUserLexiconEntries(sourcePath)
	if err != nil {
		return err
	}

	var content strings.Builder
	content.WriteString("# Generated by PIME Yime from ")
	content.WriteString(userLexiconSourceFileName)
	content.WriteString("\n# format: phrase<TAB>code<TAB>weight\n")
	for _, entry := range entries {
		code, err := ime.encodeNumericTonePinyin(entry.Pinyin, mode)
		if err != nil {
			return fmt.Errorf("用户词库第 %d 行拼音 %q 无法转换: %w", entry.LineNumber, entry.Pinyin, err)
		}
		content.WriteString(entry.Phrase)
		content.WriteByte('\t')
		content.WriteString(code)
		content.WriteByte('\t')
		content.WriteString(entry.Weight)
		content.WriteByte('\n')
	}
	return os.WriteFile(targetPath, []byte(content.String()), 0o644)
}

func readPageSizeFromCustomConfig(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "menu/page_size:") {
			val := strings.TrimSpace(strings.TrimPrefix(trimmed, "menu/page_size:"))
			if n, err := strconv.Atoi(val); err == nil {
				return n
			}
		}
	}
	return 0
}

func updateDefaultCustomPageSize(content string, size int) string {
	line := "  menu/page_size: " + strconv.Itoa(size)
	if strings.TrimSpace(content) == "" {
		return "patch:\n" + line + "\n"
	}
	lines := strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
	for i, existing := range lines {
		if strings.HasPrefix(strings.TrimSpace(existing), "menu/page_size:") {
			indent := existing[:len(existing)-len(strings.TrimLeft(existing, " \t"))]
			lines[i] = indent + "menu/page_size: " + strconv.Itoa(size)
			return strings.TrimRight(strings.Join(lines, "\n"), "\n") + "\n"
		}
	}
	for i, existing := range lines {
		if strings.TrimSpace(existing) == "patch:" {
			lines = append(lines[:i+1], append([]string{line}, lines[i+1:]...)...)
			return strings.TrimRight(strings.Join(lines, "\n"), "\n") + "\n"
		}
	}
	return strings.TrimRight(content, "\r\n") + "\n\npatch:\n" + line + "\n"
}

func updateSchemaMenuPageSize(content string, size int) string {
	line := "  page_size: " + strconv.Itoa(size)
	if strings.TrimSpace(content) == "" {
		return "menu:\n" + line + "\n"
	}
	lines := strings.Split(strings.ReplaceAll(content, "\r\n", "\n"), "\n")
	for i, existing := range lines {
		if strings.HasPrefix(strings.TrimSpace(existing), "page_size:") {
			indent := existing[:len(existing)-len(strings.TrimLeft(existing, " \t"))]
			lines[i] = indent + "page_size: " + strconv.Itoa(size)
			return strings.TrimRight(strings.Join(lines, "\n"), "\n") + "\n"
		}
	}
	for i, existing := range lines {
		if strings.TrimSpace(existing) == "menu:" {
			lines = append(lines[:i+1], append([]string{line}, lines[i+1:]...)...)
			return strings.TrimRight(strings.Join(lines, "\n"), "\n") + "\n"
		}
	}
	return strings.TrimRight(content, "\r\n") + "\n\nmenu:\n" + line + "\n"
}

func (ime *IME) openPath(path string) {
	if path == "" {
		return
	}
	if err := exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", path).Start(); err != nil {
		log.Printf("打开路径失败 %s: %v", path, err)
	}
}

func (ime *IME) copyTextToClipboard(text string) {
	if text == "" {
		return
	}
	cmd := exec.Command("powershell.exe", "-NoProfile", "-Command", "Set-Clipboard -Value ([Console]::In.ReadToEnd())")
	cmd.Stdin = strings.NewReader(text)
	if err := cmd.Start(); err != nil {
		log.Printf("复制到剪贴板失败: %v", err)
	}
}

func (ime *IME) trialFeedbackTemplate() string {
	return `【Yime / PIME 试用反馈模板】
请选择最接近的一项：
- 装不上
- 能装但打不开
- 能打开但唤不起候选框
- 候选框能出来但不能上屏
- 第一次能用，重开后失效
- 基本能用，但某个键位或手感很怪

请补充：
1. 你是在什么程序里试的
2. 你做了什么操作
3. 实际看到了什么现象
`
}

func (ime *IME) openURL(rawURL string) {
	if rawURL == "" {
		return
	}
	if err := exec.Command("rundll32.exe", "url.dll,FileProtocolHandler", rawURL).Start(); err != nil {
		log.Printf("打开链接失败 %s: %v", rawURL, err)
	}
}

func modeIconName(asciiMode, fullShape, capsOn bool) string {
	lang := "chi"
	if asciiMode {
		lang = "eng"
	}
	shape := "half"
	if fullShape {
		shape = "full"
	}
	caps := "off"
	if capsOn {
		caps = "on"
	}
	return lang + "_" + shape + "_caps" + caps + ".ico"
}

func langIconName(asciiMode bool) string {
	if asciiMode {
		return "eng.ico"
	}
	return "chi.ico"
}

func shapeIconName(fullShape bool) string {
	if fullShape {
		return "full.ico"
	}
	return "half.ico"
}

func candidateLayoutIconName(horizontal bool) string {
	if horizontal {
		return "layout_horizontal.ico"
	}
	return "layout_vertical.ico"
}


func candidateLayoutToggleText(horizontal bool) string {
	if horizontal {
		return "横排 → 竖排"
	}
	return "竖排 → 横排"
}

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}
