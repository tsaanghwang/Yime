package yime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"unicode/utf8"

	"github.com/EasyIME/pime-go/input_methods/yime/diagnostics"
	"github.com/EasyIME/pime-go/input_methods/yime/runtimechange"
	"github.com/EasyIME/pime-go/input_methods/yime/settings"
	"github.com/EasyIME/pime-go/input_methods/yime/toolhub"
	"github.com/EasyIME/pime-go/input_methods/yime/userlexicon"
	"github.com/EasyIME/pime-go/pime"
)

type testDictEntry struct {
	code  string
	words []candidateItem
}

type testBackend struct {
	session          bool
	destroyCount     int
	composition      string
	candidates       []candidateItem
	commitString     string
	asciiMode        bool
	fullShape        bool
	horizontal       bool
	schemaID         string
	returnKeyHandled bool
}

type configurableInitBackend struct {
	*testBackend
	initializeResult bool
}

func (b *configurableInitBackend) Initialize(sharedDir, userDir string, firstRun bool) bool {
	return b.initializeResult
}

type backendPagingTestBackend struct {
	*testBackend
	processedKeys []int
}

func (b *backendPagingTestBackend) UsesBackendCandidatePaging() bool {
	return true
}

func (b *backendPagingTestBackend) ProcessKey(req *pime.Request, translatedKeyCode, modifiers int) bool {
	b.processedKeys = append(b.processedKeys, translatedKeyCode)
	if req.KeyCode == vkNext {
		b.candidates = []candidateItem{{Text: "六"}, {Text: "七"}, {Text: "八"}, {Text: "九"}, {Text: "十"}}
		return true
	}
	return b.testBackend.ProcessKey(req, translatedKeyCode, modifiers)
}

// redeployTestBackend models a backend that supports full RIME redeployment,
// mirroring nativeBackend.Redeploy: it tears down the session and recreates it
// rather than requiring the caller to issue a separate DestroySession.
type redeployTestBackend struct {
	*testBackend
	redeployCount  int
	redeployResult bool
}

func (b *redeployTestBackend) Redeploy() bool {
	b.redeployCount++
	if !b.redeployResult {
		return false
	}
	b.DestroySession()
	b.EnsureSession()
	return true
}

type syncTestBackend struct {
	*testBackend
	syncCount  int
	syncResult bool
}

func (b *syncTestBackend) SyncUserData() bool {
	b.syncCount++
	return b.syncResult
}

func newTestBackend() *testBackend {
	return &testBackend{schemaID: "yime_variable", returnKeyHandled: true}
}

func (b *testBackend) Initialize(sharedDir, userDir string, firstRun bool) bool {
	return true
}

func (b *testBackend) EnsureSession() bool {
	b.session = true
	return true
}

func (b *testBackend) DestroySession() {
	b.destroyCount++
	b.session = false
	b.ClearComposition()
}

func (b *testBackend) ClearComposition() {
	b.composition = ""
	b.candidates = nil
	b.commitString = ""
}

func (b *testBackend) ProcessKey(req *pime.Request, translatedKeyCode, modifiers int) bool {
	b.commitString = ""
	keyCode := req.KeyCode
	charCode := req.CharCode
	if charCode == 0 && keyCode >= 'A' && keyCode <= 'Z' {
		charCode = keyCode + 32
	}
	if charCode == 0 && keyCode >= '0' && keyCode <= '9' {
		charCode = keyCode
	}
	if b.asciiMode && b.composition == "" && charCode >= 0x20 {
		return false
	}
	if modifiers&releaseMask != 0 {
		return false
	}

	if b.composition != "" && translatedKeyCode >= '1' && translatedKeyCode <= '9' {
		index := translatedKeyCode - '1'
		if index >= 0 && index < len(b.candidates) {
			b.commitString = b.candidates[index].Text
			b.composition = ""
			b.candidates = nil
			return true
		}
	}

	switch keyCode {
	case vkBack:
		if b.composition == "" {
			return false
		}
		b.composition = trimLastRuneForTest(b.composition)
		b.refreshCandidates()
		return true
	case vkEscape:
		if b.composition == "" {
			return false
		}
		b.ClearComposition()
		return true
	case vkReturn:
		if b.composition == "" {
			return false
		}
		if !b.returnKeyHandled {
			return false
		}
		b.commitString = b.currentCommit()
		b.composition = ""
		b.candidates = nil
		return true
	case vkSpace:
	}

	if (charCode >= 'a' && charCode <= 'z') || (charCode >= '0' && charCode <= '9') {
		b.composition += string(rune(charCode))
		b.refreshCandidates()
		return true
	}
	if charCode == '\'' && b.composition != "" && !strings.HasSuffix(b.composition, "'") {
		b.composition += "'"
		b.refreshCandidates()
		return true
	}
	if b.composition != "" && charCode >= 0x20 && charCode != '\'' {
		b.commitString = b.currentCommit() + string(rune(charCode))
		b.composition = ""
		b.candidates = nil
		return true
	}
	return false
}

func (b *testBackend) SelectCandidate(index int) bool {
	b.commitString = ""
	if index < 0 || index >= len(b.candidates) {
		return false
	}
	b.commitString = b.candidates[index].Text
	b.composition = ""
	b.candidates = nil
	return true
}

func (b *testBackend) State() rimeState {
	state := rimeState{
		CommitString:    b.commitString,
		Composition:     b.composition,
		CursorPos:       len(b.composition),
		Candidates:      append([]candidateItem(nil), b.candidates...),
		CandidateCursor: 0,
		SelectKeys:      "1234567890",
		AsciiMode:       b.asciiMode,
		FullShape:       b.fullShape,
	}
	b.commitString = ""
	return state
}

func (b *testBackend) SetOption(name string, value bool) {
	switch name {
	case "ascii_mode":
		b.asciiMode = value
	case "full_shape":
		b.fullShape = value
	case "_horizontal":
		b.horizontal = value
	}
}

func (b *testBackend) GetOption(name string) bool {
	switch name {
	case "ascii_mode":
		return b.asciiMode
	case "full_shape":
		return b.fullShape
	case "_horizontal":
		return b.horizontal
	default:
		return false
	}
}

func (b *testBackend) SelectSchema(schemaID string) bool {
	if schemaID == "" {
		return false
	}
	b.schemaID = schemaID
	b.ClearComposition()
	return true
}

func (b *testBackend) CurrentSchema() string {
	return b.schemaID
}

func (b *testBackend) currentCommit() string {
	if len(b.candidates) > 0 {
		return b.candidates[0].Text
	}
	return strings.ReplaceAll(b.composition, "'", "")
}

func (b *testBackend) refreshCandidates() {
	code := strings.ReplaceAll(b.composition, "'", "")
	if code == "" {
		b.candidates = nil
		return
	}
	results := make([]candidateItem, 0, 9)
	seen := make(map[string]struct{})
	appendWords := func(words []candidateItem) {
		for _, word := range words {
			if _, ok := seen[word.Text]; ok {
				continue
			}
			seen[word.Text] = struct{}{}
			results = append(results, word)
			if len(results) == 9 {
				return
			}
		}
	}
	for _, entry := range testDictionary() {
		if entry.code == code {
			appendWords(entry.words)
		}
	}
	for _, entry := range testDictionary() {
		if len(results) == 9 {
			break
		}
		if entry.code != code && strings.HasPrefix(entry.code, code) {
			appendWords(entry.words)
		}
	}
	if len(results) == 0 {
		results = []candidateItem{{Text: code}}
	}
	b.candidates = results
}

func testDictionary() []testDictEntry {
	return []testDictEntry{
		{code: "ni", words: []candidateItem{{Text: "你"}, {Text: "呢"}, {Text: "泥"}, {Text: "尼"}, {Text: "拟"}}},
		{code: "nihao", words: []candidateItem{{Text: "你好"}, {Text: "你号"}, {Text: "拟好"}}},
		{code: "nimen", words: []candidateItem{{Text: "你们"}}},
		{code: "zhong", words: []candidateItem{{Text: "中"}, {Text: "种"}, {Text: "重"}}},
		{code: "zhongwen", words: []candidateItem{{Text: "中文"}}},
	}
}

func trimLastRuneForTest(s string) string {
	if s == "" {
		return s
	}
	runes := []rune(s)
	return string(runes[:len(runes)-1])
}

func newTestIME() *IME {
	ime := &IME{
		TextServiceBase: pime.NewTextServiceBase(&pime.Client{ID: "test-client"}),
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
		reversePinyinBySchema: map[string]map[string]string{},
		reversePinyinLoaded:   map[string]bool{},
		yimePinyinBySchema:    map[string]map[string]string{},
		yimePinyinLoaded:      map[string]bool{},
		yimePUAByPinyin:       map[string]string{},
		candidatePageSize:     defaultCandidatePageSize,
		keysDown:              map[int]bool{},
		backend:               newTestBackend(),
	}
	userDir := filepath.Join(os.Getenv("APPDATA"), APP, "Rime")
	if event, err := runtimechange.Read(userDir); err == nil {
		ime.recordRuntimeChange(event)
	}
	return ime
}

func newRuntimeChangeTestIME() *IME {
	ime := newTestIME()
	ime.runtimeChangeRevision = 0
	ime.settingsChangeRevision = 0
	ime.lexiconChangeRevision = 0
	ime.redeployChangeRevision = 0
	return ime
}

func TestNewInitialState(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)

	if !ime.style.DisplayTrayIcon {
		t.Fatal("expected tray icon style enabled by default")
	}
	if backend.composition != "" {
		t.Fatalf("expected empty composition, got %q", backend.composition)
	}
	if len(backend.candidates) != 0 {
		t.Fatalf("expected no candidates, got %v", backend.candidates)
	}
	if ime.keyComposing {
		t.Fatal("expected keyComposing to be false initially")
	}
}

func TestRuntimeSettingsChangeSynchronizesActiveIME(t *testing.T) {
	root := t.TempDir()
	t.Setenv("APPDATA", root)
	userDir := filepath.Join(root, APP, "Rime")
	if err := settings.WriteState(userDir, settings.State{ReverseLookupDisplayMode: "yime_pinyin", CandidateLayout: "vertical"}); err != nil {
		t.Fatal(err)
	}
	event, err := runtimechange.Notify(userDir, runtimechange.ScopeSettings, false)
	if err != nil {
		t.Fatal(err)
	}
	ime := newRuntimeChangeTestIME()
	ime.pollRuntimeChange()
	if ime.runtimeChangeRevision != event.Revision {
		t.Fatalf("expected revision %d, got %d", event.Revision, ime.runtimeChangeRevision)
	}
	if ime.reverseLookupDisplayMode != "yime_pinyin" || ime.style.CandidatePerRow != verticalCandidatesPerRow {
		t.Fatalf("settings were not synchronized: mode=%q perRow=%d", ime.reverseLookupDisplayMode, ime.style.CandidatePerRow)
	}
	resp := ime.HandleRequest(&pime.Request{SeqNum: 1, Method: "onKeyboardStatusChanged"})
	if got := resp.CustomizeUI["candFontName"]; got != "YinYuan" {
		t.Fatalf("expected settings change to push PUA candidate font, got %#v", got)
	}
	if ime.pendingSchemaRedeploy != "" {
		t.Fatalf("non-build settings change should not redeploy, got %q", ime.pendingSchemaRedeploy)
	}
}

func TestRuntimeLexiconChangeClearsCachesAndSchedulesRedeploy(t *testing.T) {
	root := t.TempDir()
	t.Setenv("APPDATA", root)
	userDir := filepath.Join(root, APP, "Rime")
	if _, err := runtimechange.Notify(userDir, runtimechange.ScopeLexicon, true); err != nil {
		t.Fatal(err)
	}
	ime := newRuntimeChangeTestIME()
	ime.reversePinyinLoaded["yime_variable"] = true
	ime.yimePinyinLoaded["yime_variable"] = true
	ime.pollRuntimeChange()
	if ime.pendingSchemaRedeploy != "yime_variable" {
		t.Fatalf("expected yime_variable redeploy, got %q", ime.pendingSchemaRedeploy)
	}
	if len(ime.reversePinyinLoaded) != 0 || len(ime.yimePinyinLoaded) != 0 {
		t.Fatal("expected lexicon-derived caches to be cleared")
	}
}

func TestRuntimeChangesPreserveLexiconAndSettingsBeforePolling(t *testing.T) {
	root := t.TempDir()
	t.Setenv("APPDATA", root)
	userDir := filepath.Join(root, APP, "Rime")
	if err := settings.WriteState(userDir, settings.State{ReverseLookupDisplayMode: "hidden", CandidateLayout: "vertical"}); err != nil {
		t.Fatal(err)
	}
	if _, err := runtimechange.Notify(userDir, runtimechange.ScopeLexicon, true); err != nil {
		t.Fatal(err)
	}
	if _, err := runtimechange.Notify(userDir, runtimechange.ScopeSettings, false); err != nil {
		t.Fatal(err)
	}
	ime := newRuntimeChangeTestIME()
	ime.reversePinyinLoaded["yime_variable"] = true
	ime.yimePinyinLoaded["yime_variable"] = true
	ime.pollRuntimeChange()
	if ime.reverseLookupDisplayMode != "hidden" || ime.style.CandidatePerRow != verticalCandidatesPerRow {
		t.Fatal("expected the settings notification to be applied")
	}
	if len(ime.reversePinyinLoaded) != 0 || len(ime.yimePinyinLoaded) != 0 {
		t.Fatal("expected the earlier lexicon notification to clear caches")
	}
	if ime.pendingSchemaRedeploy != "yime_variable" {
		t.Fatalf("expected the earlier lexicon notification to schedule redeploy, got %q", ime.pendingSchemaRedeploy)
	}
}

func TestRuntimeChangeIsObservedByMultipleIMESessions(t *testing.T) {
	root := t.TempDir()
	t.Setenv("APPDATA", root)
	userDir := filepath.Join(root, APP, "Rime")
	if _, err := runtimechange.Notify(userDir, runtimechange.ScopeLexicon, true); err != nil {
		t.Fatal(err)
	}
	first := newRuntimeChangeTestIME()
	second := newRuntimeChangeTestIME()
	first.pollRuntimeChange()
	second.pollRuntimeChange()
	if first.pendingSchemaRedeploy != "yime_variable" || second.pendingSchemaRedeploy != "yime_variable" {
		t.Fatalf("all sessions must observe the marker: first=%q second=%q", first.pendingSchemaRedeploy, second.pendingSchemaRedeploy)
	}
}

func TestInitWithMissingUserDirDoesNotPanic(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	oldFactory := createRimeBackend
	createRimeBackend = func() rimeBackend {
		return &configurableInitBackend{testBackend: newTestBackend(), initializeResult: false}
	}
	t.Cleanup(func() { createRimeBackend = oldFactory })
	ime := New(&pime.Client{ID: "test-client"}).(*IME)

	if !ime.Init(&pime.Request{}) {
		t.Fatal("expected Init to keep service available when user RIME data is missing")
	}
	if ime.BackendAvailable() {
		t.Fatal("expected native backend to stay unavailable without user RIME data")
	}
}

func TestRimeInitRetryAfterFailure(t *testing.T) {
	oldFactory := createRimeBackend
	initializeResults := []bool{false, true}
	createRimeBackend = func() rimeBackend {
		result := initializeResults[0]
		initializeResults = initializeResults[1:]
		return &configurableInitBackend{testBackend: newTestBackend(), initializeResult: result}
	}
	t.Cleanup(func() { createRimeBackend = oldFactory })

	badDir := t.TempDir()
	t.Setenv("APPDATA", badDir)

	ime := New(&pime.Client{ID: "test-client"}).(*IME)
	ime.Init(&pime.Request{})
	if ime.BackendAvailable() {
		t.Fatal("expected backend unavailable with missing Rime data")
	}

	goodDir := t.TempDir()
	userRime := filepath.Join(goodDir, "PIME", "Rime")
	if err := os.MkdirAll(userRime, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("APPDATA", goodDir)

	ime2 := New(&pime.Client{ID: "test-client-2"}).(*IME)
	ime2.Init(&pime.Request{})
	if !ime2.BackendAvailable() {
		t.Fatal("expected a later initialization attempt to install the available backend")
	}
	if len(initializeResults) != 0 {
		t.Fatalf("expected both initialization attempts to run, remaining=%d", len(initializeResults))
	}
}

func TestFilterKeyDownProcessesKeyWithoutUpdatingUI(t *testing.T) {
	ime := newTestIME()

	resp := ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected n to be handled, got %d", resp.ReturnValue)
	}
	if resp.CompositionString != "" || len(resp.CandidateList) != 0 || resp.ShowCandidates {
		t.Fatalf("expected filterKeyDown not to emit UI state, got %#v", resp)
	}
}

func TestFilterKeyDownFallsBackToKeyCodeWhenCharCodeMissing(t *testing.T) {
	ime := newTestIME()

	resp := ime.filterKeyDown(&pime.Request{
		SeqNum:  2,
		KeyCode: 0x4E,
	}, pime.NewResponse(2, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected keyCode-only N to be handled, got %d", resp.ReturnValue)
	}
}

func TestOnKeyDownReflectsBackendStateAfterFilter(t *testing.T) {
	ime := newTestIME()

	ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))
	ime.filterKeyDown(&pime.Request{
		SeqNum:   2,
		KeyCode:  0x49,
		CharCode: 'i',
	}, pime.NewResponse(2, true))

	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   3,
		KeyCode:  0x49,
		CharCode: 'i',
	}, pime.NewResponse(3, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyDown to succeed, got %d", resp.ReturnValue)
	}
	if resp.CompositionString != "ni" {
		t.Fatalf("expected composition ni, got %q", resp.CompositionString)
	}
	if len(resp.CandidateList) == 0 || resp.CandidateList[0] != "你" {
		t.Fatalf("expected first exact candidate 你, got %v", resp.CandidateList)
	}
}

func TestOnKeyDownNumberExtendsComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "呢"}, {Text: "泥"}}
	ime.keyComposing = true

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:  4,
		KeyCode: 0x32,
	}, pime.NewResponse(4, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected number code input to be handled, got %d", filterResp.ReturnValue)
	}

	resp := ime.onKeyDown(&pime.Request{
		SeqNum:  5,
		KeyCode: 0x32,
	}, pime.NewResponse(5, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyDown after number input to succeed, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "" {
		t.Fatalf("expected number key not to commit candidate, got %q", resp.CommitString)
	}
	if backend.composition != "ni2" {
		t.Fatalf("expected number key to extend composition to ni2, got %q", backend.composition)
	}
}

func TestOnKeyDownBacktickSelectsSecondCandidate(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "呢"}, {Text: "泥"}}
	ime.keyComposing = true

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   4,
		KeyCode:  0xC0,
		CharCode: '`',
	}, pime.NewResponse(4, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected backtick selection to be handled, got %d", filterResp.ReturnValue)
	}

	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   5,
		KeyCode:  0xC0,
		CharCode: '`',
	}, pime.NewResponse(5, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyDown after selection to succeed, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "呢" {
		t.Fatalf("expected second candidate 呢, got %q", resp.CommitString)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset after candidate selection")
	}
}

func TestOnKeyDownMinusSelectsThirdCandidate(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "呢"}, {Text: "泥"}}
	ime.keyComposing = true

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   4,
		KeyCode:  0xBD,
		CharCode: '-',
	}, pime.NewResponse(4, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected minus selection to be handled, got %d", filterResp.ReturnValue)
	}

	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   5,
		KeyCode:  0xBD,
		CharCode: '-',
	}, pime.NewResponse(5, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyDown after selection to succeed, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "泥" {
		t.Fatalf("expected third candidate 泥, got %q", resp.CommitString)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset after candidate selection")
	}
}

func TestSelectCandidateByIndexCommitsCandidate(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "cand1"}, {Text: "cand2"}, {Text: "cand3"}, {Text: "cand4"}, {Text: "cand5"}, {Text: "cand6"}}
	ime.keyComposing = true

	resp := ime.HandleRequest(&pime.Request{
		Method: "selectCandidate",
		SeqNum: 6,
		Data: map[string]interface{}{
			"candidateIndex": float64(5),
		},
	})

	if resp.ReturnValue != 1 {
		t.Fatalf("expected selectCandidate to be handled, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "cand6" {
		t.Fatalf("expected sixth candidate cand6, got %q", resp.CommitString)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset after direct candidate selection")
	}
}

func TestSelectCandidateUsesVisiblePageOffset(t *testing.T) {
	ime := newTestIME()
	ime.candidatePageSize = 5
	ime.candidatePageStart = 5
	backend := ime.backend.(*testBackend)
	backend.composition = "abc"
	backend.candidates = []candidateItem{
		{Text: "一"}, {Text: "二"}, {Text: "三"}, {Text: "四"}, {Text: "五"},
		{Text: "六"}, {Text: "七"}, {Text: "八"}, {Text: "九"},
	}
	ime.keyComposing = true

	resp := ime.HandleRequest(&pime.Request{
		Method: "selectCandidate",
		SeqNum: 7,
		Data: map[string]interface{}{
			"candidateIndex": float64(0),
		},
	})

	if resp.ReturnValue != 1 {
		t.Fatalf("expected selectCandidate to be handled, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "六" {
		t.Fatalf("expected first visible candidate on second page 六, got %q", resp.CommitString)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset after paged candidate selection")
	}
}

func TestOnKeyDownBackspaceUpdatesComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	ime.filterKeyDown(&pime.Request{
		SeqNum:  5,
		KeyCode: 0x08,
	}, pime.NewResponse(5, true))
	resp := ime.onKeyDown(&pime.Request{
		SeqNum:  6,
		KeyCode: 0x08,
	}, pime.NewResponse(6, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected backspace to be handled, got %d", resp.ReturnValue)
	}
	if backend.composition != "n" {
		t.Fatalf("expected composition n after backspace, got %q", backend.composition)
	}
	if resp.CompositionString != "n" {
		t.Fatalf("expected response composition n, got %q", resp.CompositionString)
	}
	if len(resp.CandidateList) == 0 {
		t.Fatal("expected candidates to remain after backspace")
	}
}

func TestOnKeyDownEscapeClearsComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	ime.filterKeyDown(&pime.Request{
		SeqNum:  6,
		KeyCode: 0x1B,
	}, pime.NewResponse(6, true))
	resp := ime.onKeyDown(&pime.Request{
		SeqNum:  7,
		KeyCode: 0x1B,
	}, pime.NewResponse(7, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected escape to be handled, got %d", resp.ReturnValue)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected composition state cleared")
	}
	if resp.CompositionString != "" || resp.ShowCandidates {
		t.Fatalf("expected cleared UI, got %#v", resp)
	}
}

func TestOnKeyDownSpaceCommitsFirstCandidate(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	ime.filterKeyDown(&pime.Request{
		SeqNum:  7,
		KeyCode: 0x20,
	}, pime.NewResponse(7, true))
	resp := ime.onKeyDown(&pime.Request{
		SeqNum:  8,
		KeyCode: 0x20,
	}, pime.NewResponse(8, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected space to be handled, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "你" {
		t.Fatalf("expected first candidate 你, got %q", resp.CommitString)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset after commit")
	}
}

func TestOnKeyDownPunctuationCommitsComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	ime.filterKeyDown(&pime.Request{
		SeqNum:   8,
		KeyCode:  int('.'),
		CharCode: int('.'),
	}, pime.NewResponse(8, true))
	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   9,
		KeyCode:  int('.'),
		CharCode: int('.'),
	}, pime.NewResponse(9, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected punctuation to be handled while composing, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "你." {
		t.Fatalf("expected punctuation commit 你., got %q", resp.CommitString)
	}
}

func TestOnKeyDownUnhandledKeyReturnsZero(t *testing.T) {
	ime := newTestIME()

	resp := ime.filterKeyDown(&pime.Request{
		SeqNum:   9,
		KeyCode:  0x70,
		CharCode: 0,
	}, pime.NewResponse(9, true))

	if resp.ReturnValue != 0 {
		t.Fatalf("expected unrelated key to be ignored, got %d", resp.ReturnValue)
	}
}

func TestOnKeyDownAsciiModePassesThroughWhenIdle(t *testing.T) {
	ime := newTestIME()
	ime.backend.SetOption("ascii_mode", true)

	resp := ime.filterKeyDown(&pime.Request{
		SeqNum:   10,
		KeyCode:  int('A'),
		CharCode: int('a'),
	}, pime.NewResponse(10, true))

	if resp.ReturnValue != 0 {
		t.Fatalf("expected ascii mode to pass through idle typing, got %d", resp.ReturnValue)
	}
}

func TestRapidSameKeyNotSwallowedAfterKeyUp(t *testing.T) {
	ime := newTestIME()

	resp1 := ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))
	if resp1.ReturnValue != 1 {
		t.Fatalf("expected first n to be handled, got %d", resp1.ReturnValue)
	}

	ime.filterKeyUp(&pime.Request{
		SeqNum:  2,
		KeyCode: 0x4E,
	}, pime.NewResponse(2, true))

	resp2 := ime.filterKeyDown(&pime.Request{
		SeqNum:   3,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(3, true))
	if resp2.ReturnValue != 1 {
		t.Fatalf("expected second n after key-up to be handled, got %d", resp2.ReturnValue)
	}
}

func TestDuplicateKeyDownWithoutKeyUpSuppressed(t *testing.T) {
	ime := newTestIME()

	resp1 := ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))
	if resp1.ReturnValue != 1 {
		t.Fatalf("expected first n to be handled, got %d", resp1.ReturnValue)
	}

	resp2 := ime.filterKeyDown(&pime.Request{
		SeqNum:   2,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(2, true))
	if resp2.ReturnValue != 1 {
		t.Fatalf("expected duplicate key-down to reuse last return value, got %d", resp2.ReturnValue)
	}

	ime.filterKeyUp(&pime.Request{
		SeqNum:  3,
		KeyCode: 0x4E,
	}, pime.NewResponse(3, true))

	resp3 := ime.filterKeyDown(&pime.Request{
		SeqNum:   4,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(4, true))
	if resp3.ReturnValue != 1 {
		t.Fatalf("expected n after key-up to be handled again, got %d", resp3.ReturnValue)
	}
}

func TestKeyUpClearsKeyDownState(t *testing.T) {
	ime := newTestIME()

	ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))

	if !ime.keysDown[0x4E] {
		t.Fatal("expected key to be tracked as down")
	}

	ime.filterKeyUp(&pime.Request{
		SeqNum:  2,
		KeyCode: 0x4E,
	}, pime.NewResponse(2, true))

	if ime.keysDown[0x4E] {
		t.Fatal("expected key to be cleared after key-up")
	}
}

func TestSetCandidatePageSizePreservesComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)

	ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  0x4E,
		CharCode: 'n',
	}, pime.NewResponse(1, true))
	ime.filterKeyDown(&pime.Request{
		SeqNum:   2,
		KeyCode:  0x49,
		CharCode: 'i',
	}, pime.NewResponse(2, true))
	ime.onKeyDown(&pime.Request{
		SeqNum:   3,
		KeyCode:  0x49,
		CharCode: 'i',
	}, pime.NewResponse(3, true))

	if backend.composition != "ni" {
		t.Fatalf("expected composition 'ni' before page size change, got %q", backend.composition)
	}

	tmpDir := t.TempDir()
	t.Setenv("APPDATA", tmpDir)
	ime.setCandidatePageSize(7)

	if backend.composition != "ni" {
		t.Fatalf("expected composition 'ni' preserved after page size change, got %q", backend.composition)
	}
	if ime.candidatePageSize != 7 {
		t.Fatalf("expected candidatePageSize 7, got %d", ime.candidatePageSize)
	}
}

func TestReturnKeyCommitsRawInputDuringComposition(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "呢"}}
	ime.keyComposing = true
	backend.returnKeyHandled = false

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  vkReturn,
		CharCode: '\r',
	}, pime.NewResponse(1, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected return key to be handled, got %d", filterResp.ReturnValue)
	}

	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   2,
		KeyCode:  vkReturn,
		CharCode: '\r',
	}, pime.NewResponse(2, true))
	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyDown to succeed, got %d", resp.ReturnValue)
	}
	if resp.CommitString != "ni" {
		t.Fatalf("expected raw composition 'ni' committed, got %q", resp.CommitString)
	}
	if ime.keyComposing {
		t.Fatal("expected keyComposing to be false after return commits raw input")
	}
}

func TestReturnKeyPassesThroughWhenNotComposing(t *testing.T) {
	ime := newTestIME()

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   1,
		KeyCode:  vkReturn,
		CharCode: '\r',
	}, pime.NewResponse(1, true))
	if filterResp.ReturnValue != 0 {
		t.Fatalf("expected return key to pass through when not composing, got %d", filterResp.ReturnValue)
	}
}

func TestControlKeyPassesThroughWhenIdle(t *testing.T) {
	ime := newTestIME()

	resp := ime.filterKeyDown(&pime.Request{
		SeqNum:  10,
		KeyCode: vkControl,
	}, pime.NewResponse(10, true))

	if resp.ReturnValue != 0 {
		t.Fatalf("expected bare ctrl to pass through, got %d", resp.ReturnValue)
	}
}

// Regression: if filterKeyDown does not handle a bare Ctrl key, onKeyDown must return
// unhandled as well; otherwise the host still thinks the IME consumed the modifier.
func TestOnKeyDownBareControlUnhandledWhenFilterDoesNotHandle(t *testing.T) {
	ime := newTestIME()
	const seq = 20
	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:  seq,
		KeyCode: vkControl,
	}, pime.NewResponse(seq, true))
	if filterResp.ReturnValue != 0 {
		t.Fatalf("expected filterKeyDown bare Ctrl unhandled, got %d", filterResp.ReturnValue)
	}
	onResp := ime.onKeyDown(&pime.Request{
		SeqNum:  seq + 1,
		KeyCode: vkControl,
	}, pime.NewResponse(seq+1, true))
	if onResp.ReturnValue != 0 {
		t.Fatalf("expected onKeyDown bare Ctrl unhandled when filter did not handle, got %d", onResp.ReturnValue)
	}
}

func TestOnKeyDownControlShortcutUnhandledWhenFilterDoesNotHandle(t *testing.T) {
	ime := newTestIME()
	const seq = 22
	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   seq,
		KeyCode:  int('A'),
		CharCode: 1,
	}, pime.NewResponse(seq, true))
	if filterResp.ReturnValue != 0 {
		t.Fatalf("expected filterKeyDown ctrl+a unhandled, got %d", filterResp.ReturnValue)
	}
	onResp := ime.onKeyDown(&pime.Request{
		SeqNum:   seq + 1,
		KeyCode:  int('A'),
		CharCode: 1,
	}, pime.NewResponse(seq+1, true))
	if onResp.ReturnValue != 0 {
		t.Fatalf("expected onKeyDown ctrl+a unhandled when filter did not handle, got %d", onResp.ReturnValue)
	}
}

// Regression: same contract as TestOnKeyDownBareControlUnhandledWhenFilterDoesNotHandle for key-up / Alt.
func TestOnKeyUpBareAltUnhandledWhenFilterDoesNotHandle(t *testing.T) {
	ime := newTestIME()
	const seq = 21
	filterResp := ime.filterKeyUp(&pime.Request{
		SeqNum:  seq,
		KeyCode: vkMenu,
	}, pime.NewResponse(seq, true))
	if filterResp.ReturnValue != 0 {
		t.Fatalf("expected filterKeyUp bare Alt unhandled, got %d", filterResp.ReturnValue)
	}
	onResp := ime.onKeyUp(&pime.Request{
		SeqNum:  seq + 1,
		KeyCode: vkMenu,
	}, pime.NewResponse(seq+1, true))
	if onResp.ReturnValue != 0 {
		t.Fatalf("expected onKeyUp bare Alt unhandled when filter did not handle, got %d", onResp.ReturnValue)
	}
}

func TestOnCommandHandlesKnownAndMissingCommand(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	validResp := ime.onCommand(&pime.Request{
		SeqNum: 11,
		ID:     pime.FlexibleID{Int: ID_ASCII_MODE, IsInt: true},
	}, pime.NewResponse(11, true))
	if validResp.ReturnValue != 1 {
		t.Fatalf("expected known command to be handled, got %d", validResp.ReturnValue)
	}
	if !ime.backend.GetOption("ascii_mode") {
		t.Fatal("expected ascii mode toggled on")
	}
	if backend.composition != "ni" {
		t.Fatalf("expected test composition preserved until backend handles key flow, got %q", backend.composition)
	}

	missingResp := ime.onCommand(&pime.Request{
		SeqNum: 12,
	}, pime.NewResponse(12, true))
	if missingResp.ReturnValue != 0 {
		t.Fatalf("expected missing commandId to be ignored, got %d", missingResp.ReturnValue)
	}
}

func TestYimeCommandIDsStayOutOfLowHostCollisionRange(t *testing.T) {
	commandIDs := []int{
		ID_MODE_ICON,
		ID_ASCII_MODE,
		ID_FULL_SHAPE,
		ID_ASCII_PUNCT,
		ID_TRADITIONALIZATION,
		ID_DEPLOY,
		ID_SYNC,
		ID_SYNC_DIR,
		ID_SHARED_DIR,
		ID_USER_DIR,
		ID_LOG_DIR,
		ID_YIME_VARIABLE,
		ID_YIME_FULL,
		ID_YIME_SHORTHAND,
		ID_USER_LEXICON_ADD,
		ID_USER_LEXICON_DELETE,
		ID_USER_LEXICON_EDIT,
		ID_USER_LEXICON_APPLY,
		ID_USER_LEXICON_IMPORT,
		ID_USER_LEXICON_EXPORT,
		ID_USER_LEXICON_MANAGER,
		ID_REVERSE_LOOKUP_DEFAULT,
		ID_REVERSE_LOOKUP_FULL,
		ID_REVERSE_LOOKUP_HIDDEN,
		ID_REVERSE_LOOKUP_STANDARD_PINYIN,
		ID_REVERSE_LOOKUP_YIME_PINYIN,
		ID_REVERSE_LOOKUP_KEY_SEQUENCE,
		ID_HELP_VIEW,
		ID_HELP_TRIAL_FEEDBACK,
		ID_HELP_COPY_TRIAL_TEMPLATE,
		ID_HELP_TOOL_HUB,
		ID_REVERSE_LOOKUP_TOOL,
		ID_CANDIDATE_PAGE_SIZE_5,
		ID_CANDIDATE_PAGE_SIZE_6,
		ID_CANDIDATE_PAGE_SIZE_7,
		ID_CANDIDATE_PAGE_SIZE_8,
		ID_CANDIDATE_PAGE_SIZE_9,
		ID_CANDIDATE_LAYOUT_TOGGLE,
	}

	for _, commandID := range commandIDs {
		if commandID < 3000 {
			t.Fatalf("expected Yime command ID %d to stay above the low host-collision range", commandID)
		}
	}
}

func TestOnCommandIgnoresLegacyLowIDCollisionForReverseLookupYimePinyin(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()
	ime.reverseLookupDisplayMode = "key_sequence"

	resp := ime.onCommand(&pime.Request{
		SeqNum: 13,
		ID:     pime.FlexibleID{Int: 44, IsInt: true},
	}, pime.NewResponse(13, true))

	if resp.ReturnValue != 0 {
		t.Fatalf("expected legacy low id collision to be ignored, got %d", resp.ReturnValue)
	}
	if ime.reverseLookupDisplayMode != "key_sequence" {
		t.Fatalf("expected reverse lookup mode unchanged on low id collision, got %q", ime.reverseLookupDisplayMode)
	}
	if backend.composition != "ni" {
		t.Fatalf("expected composition preserved on low id collision, got %q", backend.composition)
	}
}

func TestOnCommandSwitchesYimeSchema(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := ime.onCommand(&pime.Request{
		SeqNum: 14,
		ID:     pime.FlexibleID{Int: ID_YIME_FULL, IsInt: true},
	}, pime.NewResponse(14, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected schema switch command to be handled, got %d", resp.ReturnValue)
	}
	if backend.CurrentSchema() != "yime_full" {
		t.Fatalf("expected yime_full schema, got %q", backend.CurrentSchema())
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected schema switch to clear active composition")
	}

	backend.composition = "ni"
	backend.refreshCandidates()

	resp = ime.onCommand(&pime.Request{
		SeqNum: 15,
		ID:     pime.FlexibleID{Int: ID_YIME_SHORTHAND, IsInt: true},
	}, pime.NewResponse(15, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected shorthand schema switch command to be handled, got %d", resp.ReturnValue)
	}
	if backend.CurrentSchema() != "yime_shorthand" {
		t.Fatalf("expected yime_shorthand schema, got %q", backend.CurrentSchema())
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected shorthand schema switch to clear active composition")
	}
}

func TestOnMenuReturnsSettingsMenu(t *testing.T) {
	ime := newTestIME()

	resp := ime.onMenu(&pime.Request{
		SeqNum: 15,
		ID:     pime.FlexibleID{String: "settings"},
	}, pime.NewResponse(15, true))

	items, ok := resp.ReturnData.([]map[string]interface{})
	if !ok || len(items) == 0 {
		t.Fatalf("expected settings menu items, got %#v", resp.ReturnData)
	}
	if text, ok := items[0]["text"].(string); !ok || text == "" {
		t.Fatalf("expected first menu item text, got %#v", items[0])
	}
	modeMenu := findSubmenuItem(t, items, "模式")
	if len(modeMenu) != 3 {
		t.Fatalf("expected mode submenu with full/variable/shorthand items, got %#v", modeMenu)
	}
	if text, ok := modeMenu[0]["text"].(string); !ok || text != "等长" {
		t.Fatalf("expected full mode menu item first, got %#v", modeMenu[0])
	}
	if text, ok := modeMenu[1]["text"].(string); !ok || text != "变长" {
		t.Fatalf("expected variable mode menu item second, got %#v", modeMenu[1])
	}
	if checked, ok := modeMenu[1]["checked"].(bool); !ok || !checked {
		t.Fatalf("expected variable mode checked by default, got %#v", modeMenu[1])
	}
	if text, ok := modeMenu[2]["text"].(string); !ok || text != "省键" {
		t.Fatalf("expected shorthand mode menu item third, got %#v", modeMenu[2])
	}
	if checked, ok := modeMenu[2]["checked"].(bool); !ok || checked {
		t.Fatalf("expected shorthand mode unchecked by default, got %#v", modeMenu[2])
	}
	if enabled, ok := modeMenu[2]["enabled"].(bool); !ok || enabled {
		t.Fatalf("expected shorthand mode disabled without bundled schema, got %#v", modeMenu[2])
	}
	item := findTopLevelMenuItem(t, items, ID_CANDIDATE_LAYOUT_TOGGLE)
	if text, ok := item["text"].(string); !ok || text != "竖排 → 横排" {
		t.Fatalf("expected top-level vertical-to-horizontal toggle text, got %#v", item)
	}
	pageSizeMenu := findSubmenuItem(t, items, "候选项数")
	if hasSubmenuItem(pageSizeMenu, "排列方式") {
		t.Fatalf("expected candidate count submenu to stay flat, got %#v", pageSizeMenu)
	}
	if len(pageSizeMenu) != 5 {
		t.Fatalf("expected five direct page-size items, got %#v", pageSizeMenu)
	}
	item = findMenuItem(t, pageSizeMenu, ID_CANDIDATE_PAGE_SIZE_5)
	if checked, ok := item["checked"].(bool); !ok || !checked {
		t.Fatalf("expected page size 5 checked by default, got %#v", item)
	}
	item = findMenuItem(t, pageSizeMenu, ID_CANDIDATE_PAGE_SIZE_9)
	if text, ok := item["text"].(string); !ok || text != "9 项" {
		t.Fatalf("expected page size 9 menu text, got %#v", item)
	}

	// 显示编码 (reverse lookup) moved off the language bar into a single settings
	// submenu. It must stay one level deep with the four display modes.
	reverseMenu := findSubmenuItem(t, items, "显示编码")
	if len(reverseMenu) != 4 {
		t.Fatalf("expected four reverse-lookup display modes in settings submenu, got %#v", reverseMenu)
	}
	if item := findMenuItem(t, reverseMenu, ID_REVERSE_LOOKUP_KEY_SEQUENCE); item["text"] != "键位序列" {
		t.Fatalf("expected key-sequence reverse lookup item in settings submenu, got %#v", item)
	}
	if item := findMenuItem(t, reverseMenu, ID_REVERSE_LOOKUP_YIME_PINYIN); item["text"] != "音元拼音" {
		t.Fatalf("expected yime-pinyin reverse lookup item in settings submenu, got %#v", item)
	}

	if item := findTopLevelMenuItem(t, items, ID_DEPLOY); item["text"] != "重新部署 Rime(&D)" {
		t.Fatalf("expected deploy command to remain in settings root, got %#v", item)
	}
	if item := findTopLevelMenuItem(t, items, ID_SYNC); item["text"] != "同步 Rime 用户数据(&S)" {
		t.Fatalf("expected sync command to remain in settings root, got %#v", item)
	}
	openFolderMenu := findSubmenuItem(t, items, "打开数据与日志文件夹(&O)")
	if len(openFolderMenu) != 4 {
		t.Fatalf("expected open-folder submenu to remain in settings root, got %#v", openFolderMenu)
	}
	if item := findTopLevelMenuItem(t, openFolderMenu, ID_USER_DIR); item["text"] != "用户 Rime 数据目录" {
		t.Fatalf("expected user-data directory label, got %#v", item)
	}
	if item := findTopLevelMenuItem(t, openFolderMenu, ID_SHARED_DIR); item["text"] != "内置共享数据目录" {
		t.Fatalf("expected shared-data directory label, got %#v", item)
	}
	if item := findTopLevelMenuItem(t, openFolderMenu, ID_SYNC_DIR); item["text"] != "Rime 同步目录" {
		t.Fatalf("expected sync directory label, got %#v", item)
	}
	if item := findTopLevelMenuItem(t, openFolderMenu, ID_LOG_DIR); item["text"] != "PIME 日志目录" {
		t.Fatalf("expected log directory label, got %#v", item)
	}
}

func TestOnCommandAcceptsDataCommandIDForCandidatePageSize(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()

	resp := ime.onCommand(&pime.Request{
		SeqNum: 28,
		Data: map[string]interface{}{
			"commandId": strconv.Itoa(ID_CANDIDATE_PAGE_SIZE_7),
		},
	}, pime.NewResponse(28, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected string commandId page size command to be handled, got %d", resp.ReturnValue)
	}
	if ime.candidatePageSize != 7 {
		t.Fatalf("expected current session page size 7, got %d", ime.candidatePageSize)
	}
}

func TestOnCommandAcceptsSubmenuItemIDForReverseLookupYimePinyin(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := &redeployTestBackend{testBackend: newTestBackend(), redeployResult: true}
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()
	ime.backend = backend

	resp := ime.onCommand(&pime.Request{
		SeqNum: 29,
		ID:     pime.FlexibleID{String: "reverse-lookup"},
		Data: map[string]interface{}{
			"id": float64(ID_REVERSE_LOOKUP_YIME_PINYIN),
		},
	}, pime.NewResponse(29, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected reverse-lookup submenu item id to be handled, got %d", resp.ReturnValue)
	}
	if ime.reverseLookupDisplayMode != "yime_pinyin" {
		t.Fatalf("expected yime_pinyin mode, got %q", ime.reverseLookupDisplayMode)
	}
	if got := resp.CustomizeUI["candFontName"]; got != "YinYuan" {
		t.Fatalf("expected submenu switch to apply YinYuan candidate font, got %#v", got)
	}
	if backend.redeployCount != 0 {
		t.Fatalf("expected reverse lookup submenu click to avoid redeploy, got %d", backend.redeployCount)
	}
	if backend.destroyCount != 0 {
		t.Fatalf("expected reverse lookup submenu click to avoid session reload, destroyCount=%d", backend.destroyCount)
	}
	if resp.CompositionString != "" || resp.ShowCandidates || len(resp.CandidateList) != 0 {
		t.Fatalf("expected reverse lookup submenu click not to refresh host candidate state, got %#v", resp)
	}
	if backend.composition != "ni" {
		t.Fatalf("expected composition preserved, got %q", backend.composition)
	}
}

func TestOnCommandSwitchesCandidateLayout(t *testing.T) {
	ime := newTestIME()
	seedLangBarToggleIcons(t, ime)
	backend := ime.backend.(*testBackend)

	resp := ime.onCommand(&pime.Request{
		SeqNum: 16,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_LAYOUT_TOGGLE, IsInt: true},
	}, pime.NewResponse(16, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected layout toggle command to be handled, got %d", resp.ReturnValue)
	}
	if ime.style.CandidatePerRow != horizontalCandidatesPerRow {
		t.Fatalf("expected horizontal candPerRow after toggle from vertical, got %d", ime.style.CandidatePerRow)
	}
	if !backend.horizontal {
		t.Fatal("expected backend _horizontal option to be true")
	}
	if got := resp.CustomizeUI["candPerRow"]; got != horizontalCandidatesPerRow {
		t.Fatalf("expected customizeUI candPerRow %d, got %#v", horizontalCandidatesPerRow, got)
	}

	resp = ime.onCommand(&pime.Request{
		SeqNum: 17,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_LAYOUT_TOGGLE, IsInt: true},
	}, pime.NewResponse(17, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected layout toggle command to be handled, got %d", resp.ReturnValue)
	}
	if ime.style.CandidatePerRow != verticalCandidatesPerRow {
		t.Fatalf("expected vertical candPerRow after toggle from horizontal, got %d", ime.style.CandidatePerRow)
	}
	if backend.horizontal {
		t.Fatal("expected backend _horizontal option to be false")
	}
	if change := findLangBarChangeButton(resp.ChangeButton, "candidate-layout"); change == nil || change.Icon == "" || change.Text != "" {
		t.Fatalf("expected candidate-layout button update to be icon-only, got %#v", resp.ChangeButton)
	}
}

func TestIMEDisplayNameIsYime(t *testing.T) {
	data, err := os.ReadFile("ime.json")
	if err != nil {
		t.Fatalf("read ime.json failed: %v", err)
	}
	var profile struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(data, &profile); err != nil {
		t.Fatalf("parse ime.json failed: %v", err)
	}
	if profile.Name != "音元" {
		t.Fatalf("expected IME list name 音元, got %q", profile.Name)
	}
}

func TestLanguageBarToggleButtonsUseStableTwoCharacterLabels(t *testing.T) {
	ime := newTestIME()
	seedLangBarToggleIcons(t, ime)
	resp := pime.NewResponse(1, true)
	ime.addButtons(resp)

	if button := findLangBarButton(resp.AddButton, "switch-lang"); button == nil || button.Text != "中西" {
		t.Fatalf("expected switch-lang button to show 中西, got %#v", button)
	}
	if button := findLangBarButton(resp.AddButton, "switch-shape"); button == nil || button.Text != "全半" {
		t.Fatalf("expected switch-shape button to show 全半, got %#v", button)
	}
	if button := findLangBarButton(resp.AddButton, "candidate-layout"); button == nil || button.Text != "横竖" {
		t.Fatalf("expected candidate-layout button to show 横竖, got %#v", button)
	}
	for _, id := range []string{"switch-lang", "switch-shape", "candidate-layout"} {
		if button := findLangBarButton(resp.AddButton, id); button == nil || button.Icon == "" {
			t.Fatalf("expected %s to carry its state icon, got %#v", id, button)
		}
	}

	asciiResp := ime.onCommand(&pime.Request{
		SeqNum: 2,
		ID:     pime.FlexibleID{Int: ID_ASCII_MODE, IsInt: true},
	}, pime.NewResponse(2, true))
	if change := findLangBarChangeButton(asciiResp.ChangeButton, "switch-lang"); change == nil || change.Icon == "" || change.Text != "" {
		t.Fatalf("expected switch-lang update to be icon-only, got %#v", asciiResp.ChangeButton)
	}

	shapeResp := ime.onCommand(&pime.Request{
		SeqNum: 3,
		ID:     pime.FlexibleID{Int: ID_FULL_SHAPE, IsInt: true},
	}, pime.NewResponse(3, true))
	if change := findLangBarChangeButton(shapeResp.ChangeButton, "switch-shape"); change == nil || change.Icon == "" || change.Text != "" {
		t.Fatalf("expected switch-shape update to be icon-only, got %#v", shapeResp.ChangeButton)
	}

	layoutResp := ime.onCommand(&pime.Request{
		SeqNum: 4,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_LAYOUT_TOGGLE, IsInt: true},
	}, pime.NewResponse(4, true))
	if change := findLangBarChangeButton(layoutResp.ChangeButton, "candidate-layout"); change == nil || change.Icon == "" || change.Text != "" {
		t.Fatalf("expected candidate-layout update to be icon-only, got %#v", layoutResp.ChangeButton)
	}
}

func TestNativeLanguageBarLeavesToggleIdentityAndSortToHost(t *testing.T) {
	root := filepath.Clean(filepath.Join("..", "..", ".."))
	paths := []string{
		filepath.Join(root, "PIMETextService", "PIMELangBarButton.cpp"),
		filepath.Join(root, "PIMETextService", "PIMELangBarButton.h"),
		filepath.Join(root, "PIMETextService", "PIMEClient.cpp"),
		filepath.Join(root, "PIMETextService", "PIMEClient.h"),
	}
	var combined strings.Builder
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		combined.Write(data)
	}
	source := combined.String()
	for _, forbidden := range []string{"nextLangBarButtonSort_", "sortOrder_", "info->ulSort", "_GUID_LBI_SWITCH_LANG", "_GUID_LBI_SWITCH_SHAPE", "_GUID_LBI_CANDIDATE_LAYOUT"} {
		if strings.Contains(source, forbidden) {
			t.Fatalf("native language bar must leave toggle identity and ordering to the host; found %q", forbidden)
		}
	}
	if !strings.Contains(source, "_GUID_LBI_INPUTMODE") {
		t.Fatal("the Windows input-mode icon must retain its system GUID")
	}
}

func findLangBarButton(buttons []pime.ButtonInfo, id string) *pime.ButtonInfo {
	for i := range buttons {
		if buttons[i].ID == id {
			return &buttons[i]
		}
	}
	return nil
}

func seedLangBarToggleIcons(t *testing.T, ime *IME) {
	t.Helper()
	iconDir := t.TempDir()
	for _, name := range []string{
		"chi.ico",
		"eng.ico",
		"half.ico",
		"full.ico",
		"layout_vertical.ico",
		"layout_horizontal.ico",
	} {
		if err := os.WriteFile(filepath.Join(iconDir, name), []byte("icon"), 0o644); err != nil {
			t.Fatalf("seed toggle icon %s: %v", name, err)
		}
	}
	ime.iconDir = iconDir
}

func TestOnKeyDoesNotRefreshUnrelatedLangBarToggleButtons(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := pime.NewResponse(20, true)
	if !ime.onKey(&pime.Request{SeqNum: 20, KeyCode: 'h'}, resp) {
		t.Fatal("expected key to be handled")
	}
	for _, change := range resp.ChangeButton {
		switch change.ID {
		case "switch-lang", "switch-shape", "candidate-layout":
			t.Fatalf("expected onKey not to refresh toggle button %q, got %#v", change.ID, resp.ChangeButton)
		}
	}
}

func TestOnCommandAsciiModeUpdatesOnlyStableLangButtonIcon(t *testing.T) {
	ime := newTestIME()
	seedLangBarToggleIcons(t, ime)

	resp := ime.onCommand(&pime.Request{
		SeqNum: 21,
		ID:     pime.FlexibleID{Int: ID_ASCII_MODE, IsInt: true},
	}, pime.NewResponse(21, true))

	if len(resp.AddButton) != 0 || len(resp.RemoveButton) != 0 {
		t.Fatalf("expected in-place button update, got add=%#v remove=%#v", resp.AddButton, resp.RemoveButton)
	}
	found := false
	for _, change := range resp.ChangeButton {
		switch change.ID {
		case "switch-lang":
			found = true
			if change.Text != "" || change.Icon == "" {
				t.Fatalf("expected switch-lang icon-only change, got %#v", change)
			}
		case "switch-shape", "candidate-layout":
			t.Fatalf("expected ascii toggle not to refresh %q, got %#v", change.ID, resp.ChangeButton)
		}
	}
	if !found {
		t.Fatalf("expected switch-lang change, got %#v", resp.ChangeButton)
	}
}

func findLangBarChangeButton(buttons []pime.ButtonInfo, id string) *pime.ButtonInfo {
	return findLangBarButton(buttons, id)
}

func TestCandidatePageSizeCommandUpdatesCurrentSessionEvenIfDeployFails(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	resp := ime.onCommand(&pime.Request{
		SeqNum: 27,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_PAGE_SIZE_7, IsInt: true},
	}, pime.NewResponse(27, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected page size command to be handled, got %d", resp.ReturnValue)
	}
	if ime.candidatePageSize != 7 {
		t.Fatalf("expected current session page size 7, got %d", ime.candidatePageSize)
	}
	if ime.candidatePageStart != 0 {
		t.Fatalf("expected page start reset, got %d", ime.candidatePageStart)
	}
}

func TestCandidatePageSizeCommandRestoresCompositionState(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := ime.onCommand(&pime.Request{
		SeqNum: 44,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_PAGE_SIZE_7, IsInt: true},
	}, pime.NewResponse(44, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected page size command to be handled, got %d", resp.ReturnValue)
	}
	if ime.candidatePageSize != 7 {
		t.Fatalf("expected current session page size 7, got %d", ime.candidatePageSize)
	}
	// Session reload now preserves composition by replaying keys after rebuild.
	if backend.composition != "ni" {
		t.Fatalf("expected composition 'ni' preserved after page size session reload, got %q", backend.composition)
	}
}

func TestCandidatePageSizeCommandUpdatesCurrentUserSchema(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	sharedDir := ime.sharedDir()
	if err := os.MkdirAll(sharedDir, 0o755); err != nil {
		t.Fatal(err)
	}
	sharedSchemaPath := filepath.Join(sharedDir, "yime_variable.schema.yaml")
	if err := os.WriteFile(sharedSchemaPath, []byte("schema:\n  schema_id: yime_variable\n\nmenu:\n  page_size: 9\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	resp := ime.onCommand(&pime.Request{
		SeqNum: 29,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_PAGE_SIZE_7, IsInt: true},
	}, pime.NewResponse(29, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected page size command to be handled, got %d", resp.ReturnValue)
	}
	userSchemaPath := filepath.Join(ime.userDir(), "yime_variable.schema.yaml")
	data, err := os.ReadFile(userSchemaPath)
	if err != nil {
		t.Fatal(err)
	}
	normalized := strings.ReplaceAll(string(data), "\r\n", "\n")
	if !strings.Contains(normalized, "  page_size: 7\n") {
		t.Fatalf("expected current user schema page size 7, got %q", normalized)
	}
	customData, err := os.ReadFile(filepath.Join(ime.userDir(), "yime_variable.custom.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if got := readPageSizeFromCustomConfig(filepath.Join(ime.userDir(), "yime_variable.custom.yaml")); got != 7 {
		t.Fatalf("expected current schema custom page size 7, got %d from %q", got, string(customData))
	}
	if backend.destroyCount != 1 || !backend.session {
		t.Fatalf("expected current Rime session to reload after page size change, destroyCount=%d session=%t", backend.destroyCount, backend.session)
	}
}

func TestSetCandidatePageSizeDoesNotRedeploy(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := &redeployTestBackend{testBackend: newTestBackend(), redeployResult: true}
	backend.session = true
	ime.backend = backend

	resp := ime.onCommand(&pime.Request{
		SeqNum: 41,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_PAGE_SIZE_7, IsInt: true},
	}, pime.NewResponse(41, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected page size command to be handled, got %d", resp.ReturnValue)
	}
	if backend.redeployCount != 0 {
		t.Fatalf("expected page size change to avoid full redeploy, got %d", backend.redeployCount)
	}
	if backend.destroyCount != 1 {
		t.Fatalf("expected one lightweight session reload, destroyCount=%d", backend.destroyCount)
	}
	if !backend.session {
		t.Fatal("expected a fresh session after reload")
	}
	if backend.schemaID != "yime_variable" {
		t.Fatalf("expected schema to be reselected after reload, got %q", backend.schemaID)
	}
	if ime.candidatePageSize != 7 {
		t.Fatalf("expected current session page size 7, got %d", ime.candidatePageSize)
	}
}

func TestDeployCommandRedeploysCurrentSchema(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := &redeployTestBackend{testBackend: newTestBackend(), redeployResult: true}
	backend.session = true
	backend.schemaID = "yime_full"
	ime.backend = backend

	resp := ime.onCommand(&pime.Request{
		SeqNum: 43,
		ID:     pime.FlexibleID{Int: ID_DEPLOY, IsInt: true},
	}, pime.NewResponse(43, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected deploy command to be handled, got %d", resp.ReturnValue)
	}
	if backend.redeployCount != 1 {
		t.Fatalf("expected deploy command to trigger one redeploy, got %d", backend.redeployCount)
	}
	if backend.schemaID != "yime_full" {
		t.Fatalf("expected current schema preserved across redeploy, got %q", backend.schemaID)
	}
}

func TestSyncCommandUsesNativeRimeUserDataSyncWithoutRefreshingHostState(t *testing.T) {
	ime := newTestIME()
	backend := &syncTestBackend{testBackend: newTestBackend(), syncResult: true}
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()
	ime.backend = backend

	resp := ime.onCommand(&pime.Request{
		SeqNum: 44,
		ID:     pime.FlexibleID{Int: ID_SYNC, IsInt: true},
	}, pime.NewResponse(44, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected sync command to be handled, got %d", resp.ReturnValue)
	}
	if backend.syncCount != 1 {
		t.Fatalf("expected sync command to trigger one native user-data sync, got %d", backend.syncCount)
	}
	if resp.CompositionString != "" || resp.ShowCandidates || len(resp.CandidateList) != 0 {
		t.Fatalf("expected sync command not to refresh host candidate state, got %#v", resp)
	}
	if backend.destroyCount != 0 {
		t.Fatalf("expected sync command not to reload the session, destroyCount=%d", backend.destroyCount)
	}
	if backend.composition != "ni" {
		t.Fatalf("expected composition preserved across sync, got %q", backend.composition)
	}
}

func TestCandidatePageSizeLimitsVisibleCandidates(t *testing.T) {
	ime := newTestIME()
	ime.candidatePageSize = 5
	state := rimeState{
		Composition: "abc",
		Candidates: []candidateItem{
			{Text: "一"}, {Text: "二"}, {Text: "三"}, {Text: "四"}, {Text: "五"},
			{Text: "六"}, {Text: "七"}, {Text: "八"}, {Text: "九"},
		},
	}
	resp := pime.NewResponse(20, true)

	ime.applyStateToResponse(resp, state)

	if resp.SetSelKeys != "1234567890" {
		t.Fatalf("expected numeric candidate labels, got %q", resp.SetSelKeys)
	}
	if len(resp.CandidateList) != 5 {
		t.Fatalf("expected 5 visible candidates, got %#v", resp.CandidateList)
	}
	if resp.CandidateList[0] != "一" || resp.CandidateList[4] != "五" {
		t.Fatalf("expected first page candidates 一-五, got %#v", resp.CandidateList)
	}
}

func TestCandidatePageDownShowsNextVisibleCandidates(t *testing.T) {
	ime := newTestIME()
	ime.candidatePageSize = 5
	backend := ime.backend.(*testBackend)
	backend.composition = "abc"
	backend.candidates = []candidateItem{
		{Text: "一"}, {Text: "二"}, {Text: "三"}, {Text: "四"}, {Text: "五"},
		{Text: "六"}, {Text: "七"}, {Text: "八"}, {Text: "九"},
	}

	filterResp := ime.filterKeyDown(&pime.Request{SeqNum: 21, KeyCode: vkNext}, pime.NewResponse(21, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected PgDn to be handled for local candidate paging, got %d", filterResp.ReturnValue)
	}
	resp := ime.onKeyDown(&pime.Request{SeqNum: 22, KeyCode: vkNext}, pime.NewResponse(22, true))

	if got, want := resp.CandidateList, []string{"六", "七", "八", "九"}; strings.Join(got, "") != strings.Join(want, "") {
		t.Fatalf("expected second page candidates %#v, got %#v", want, got)
	}
}

func TestBackendPagingPageDownPassesThroughToBackend(t *testing.T) {
	ime := newTestIME()
	ime.candidatePageSize = 5
	backend := &backendPagingTestBackend{testBackend: newTestBackend()}
	backend.composition = "abc"
	backend.candidates = []candidateItem{{Text: "一"}, {Text: "二"}, {Text: "三"}, {Text: "四"}, {Text: "五"}}
	ime.backend = backend
	ime.keyComposing = true

	filterResp := ime.filterKeyDown(&pime.Request{SeqNum: 25, KeyCode: vkNext}, pime.NewResponse(25, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected PgDn to be handled by backend paging, got %d", filterResp.ReturnValue)
	}
	if ime.candidatePageStart != 0 {
		t.Fatalf("expected backend paging not to alter local page start, got %d", ime.candidatePageStart)
	}
	if len(backend.processedKeys) == 0 || backend.processedKeys[0] != translateKeyCode(&pime.Request{KeyCode: vkNext}) {
		t.Fatalf("expected PgDn to pass through to backend, got %#v", backend.processedKeys)
	}

	resp := ime.onKeyDown(&pime.Request{SeqNum: 26, KeyCode: vkNext}, pime.NewResponse(26, true))
	if got, want := resp.CandidateList, []string{"六", "七", "八", "九", "十"}; strings.Join(got, "") != strings.Join(want, "") {
		t.Fatalf("expected backend-provided page candidates %#v, got %#v", want, got)
	}
}

func TestOutOfRangeCandidateShortcutIsConsumedOnShortPage(t *testing.T) {
	ime := newTestIME()
	ime.candidatePageSize = 5
	ime.candidatePageStart = 5
	ime.keyComposing = true
	backend := ime.backend.(*testBackend)
	backend.composition = "abc"
	backend.candidates = []candidateItem{
		{Text: "一"}, {Text: "二"}, {Text: "三"}, {Text: "四"}, {Text: "五"},
		{Text: "六"}, {Text: "七"}, {Text: "八"}, {Text: "九"},
	}

	filterResp := ime.filterKeyDown(&pime.Request{
		SeqNum:   23,
		KeyCode:  0xDC,
		CharCode: '\\',
	}, pime.NewResponse(23, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected out-of-range shortcut to be consumed, got %d", filterResp.ReturnValue)
	}
	resp := ime.onKeyDown(&pime.Request{
		SeqNum:   24,
		KeyCode:  0xDC,
		CharCode: '\\',
	}, pime.NewResponse(24, true))

	if resp.CommitString != "" {
		t.Fatalf("expected no candidate commit for out-of-range shortcut, got %q", resp.CommitString)
	}
	if backend.composition != "abc" || len(backend.candidates) != 9 {
		t.Fatalf("expected composition and candidates to remain, got composition=%q candidates=%#v", backend.composition, backend.candidates)
	}
	if got, want := resp.CandidateList, []string{"六", "七", "八", "九"}; strings.Join(got, "") != strings.Join(want, "") {
		t.Fatalf("expected second page candidates %#v, got %#v", want, got)
	}
}

func TestUpdateDefaultCustomPageSize(t *testing.T) {
	created := updateDefaultCustomPageSize("", 7)
	if created != "patch:\n  \"menu/page_size\": 7\n" {
		t.Fatalf("expected new default.custom.yaml content, got %q", created)
	}

	updated := updateDefaultCustomPageSize("patch:\n  schema_list:\n    - schema: yime_variable\n", 8)
	if !strings.Contains(updated, "  \"menu/page_size\": 8\n") {
		t.Fatalf("expected page size inserted under patch, got %q", updated)
	}

	replaced := updateDefaultCustomPageSize("patch:\n  menu/page_size: 5\n", 9)
	if strings.Count(replaced, "menu/page_size") != 1 || !strings.Contains(replaced, "  \"menu/page_size\": 9\n") {
		t.Fatalf("expected page size replacement, got %q", replaced)
	}
}

func TestUpdateDefaultCustomPageSizeReplacesQuotedKey(t *testing.T) {
	replaced := updateDefaultCustomPageSize("patch:\n  \"menu/page_size\": 5\n", 6)
	if strings.Count(replaced, "menu/page_size") != 1 || !strings.Contains(replaced, "  \"menu/page_size\": 6\n") {
		t.Fatalf("expected quoted page size replacement, got %q", replaced)
	}
}

func TestUpdateSchemaMenuPageSize(t *testing.T) {
	replaced := updateSchemaMenuPageSize("schema:\n  schema_id: yime_variable\n\nmenu:\n  page_size: 9\n", 6)
	if strings.Count(replaced, "page_size:") != 1 || !strings.Contains(replaced, "  page_size: 6\n") {
		t.Fatalf("expected schema page size replacement, got %q", replaced)
	}

	inserted := updateSchemaMenuPageSize("schema:\n  schema_id: yime_variable\n\nmenu:\n", 8)
	if !strings.Contains(inserted, "menu:\n  page_size: 8\n") {
		t.Fatalf("expected schema page size inserted under menu, got %q", inserted)
	}
}

func TestReadPageSizeFromCustomConfig(t *testing.T) {
	if got := readPageSizeFromCustomConfig(filepath.Join(t.TempDir(), "missing.yaml")); got != 0 {
		t.Fatalf("expected 0 for missing file, got %d", got)
	}

	dir := t.TempDir()
	path := filepath.Join(dir, "default.custom.yaml")
	if err := os.WriteFile(path, []byte("patch:\n  menu/page_size: 7\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readPageSizeFromCustomConfig(path); got != 7 {
		t.Fatalf("expected page size 7, got %d", got)
	}

	if err := os.WriteFile(path, []byte("patch:\n  \"menu/page_size\": 8\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readPageSizeFromCustomConfig(path); got != 8 {
		t.Fatalf("expected quoted page size 8, got %d", got)
	}

	if err := os.WriteFile(path, []byte("patch:\n  \"menu/page_size\": 9 # user preference\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readPageSizeFromCustomConfig(path); got != 9 {
		t.Fatalf("expected page size 9 with inline comment, got %d", got)
	}

	if err := os.WriteFile(path, []byte("patch:\n  menu/page_size: 6#compact\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := readPageSizeFromCustomConfig(path); got != 6 {
		t.Fatalf("expected page size 6 with no-space comment, got %d", got)
	}
}

func TestUserLexiconManagerLaunchesNativeExecutable(t *testing.T) {
	ime := newTestIME()
	path := ime.lexiconManagerToolPath()
	if !strings.HasSuffix(strings.ToLower(path), `\lexicon-manager.exe`) {
		t.Fatalf("expected lexicon manager native executable path, got %q", path)
	}
}

func TestToolHubLaunchesNativeExecutable(t *testing.T) {
	ime := newTestIME()
	path := ime.toolHubPath()
	if !strings.HasSuffix(strings.ToLower(path), `\tool-hub.exe`) {
		t.Fatalf("expected tool hub native executable path, got %q", path)
	}
}

func TestReverseLookupToolLaunchesNativeExecutable(t *testing.T) {
	ime := newTestIME()
	path := ime.reverseLookupToolPath()
	if !strings.HasSuffix(strings.ToLower(path), `\reverse-lookup.exe`) {
		t.Fatalf("expected reverse lookup native executable path, got %q", path)
	}
}
func TestUserLexiconPackageSupportsLexiconWorkflows(t *testing.T) {
	if userlexicon.SourceFileName != "yime_user_phrases.txt" {
		t.Fatalf("expected stable user lexicon source filename")
	}
	preview := userlexicon.BuildImportPreview(
		[]userlexicon.Entry{{Phrase: "中国", Pinyin: "zhong1 guo2", Weight: "1000000"}},
		[]userlexicon.Entry{{Phrase: "中国", Pinyin: "zhong1 guo3", Weight: "2000000"}, {Phrase: "北京", Pinyin: "bei3 jing1", Weight: "1000000"}},
	)
	if preview.ReplaceCount != 1 || preview.NewCount != 1 {
		t.Fatalf("expected import preview to split replace/new counts, got %#v", preview)
	}
}

func TestToolHubPackageSupportsManifestLaunchActions(t *testing.T) {
	if toolhub.ActionRunExecutable != "run_executable" {
		t.Fatalf("expected executable action type constant")
	}
	manifest := toolhub.Manifest{
		Title: "test",
		Tools: []toolhub.Entry{{
			ID: "sample", Label: "sample", ActionType: toolhub.ActionOpenPath, TargetPath: `C:\`,
		}},
	}
	if err := toolhub.Validate(manifest); err != nil {
		t.Fatalf("expected valid tool hub manifest, got %v", err)
	}
}

func TestSettingsToolLaunchesNativeExecutable(t *testing.T) {
	ime := newTestIME()
	path := ime.settingsToolPath()
	if !strings.HasSuffix(strings.ToLower(path), `\settings-tool.exe`) {
		t.Fatalf("expected settings tool native executable path, got %q", path)
	}
}

func TestDiagnosticsToolLaunchesNativeExecutable(t *testing.T) {
	ime := newTestIME()
	path := ime.diagnosticsToolPath()
	if !strings.HasSuffix(strings.ToLower(path), `\diagnostics-tool.exe`) {
		t.Fatalf("expected diagnostics tool native executable path, got %q", path)
	}
}

func TestSettingsPackageSupportsStandaloneToolWorkflow(t *testing.T) {
	options := settings.ReverseLookupOptions()
	if len(options) == 0 {
		t.Fatalf("expected reverse lookup combo options")
	}
	layoutOptions := settings.CandidateLayoutOptions()
	if len(layoutOptions) != 2 {
		t.Fatalf("expected horizontal and vertical layout options, got %d", len(layoutOptions))
	}
	if settings.SchemaVariable == "" || settings.SchemaFull == "" {
		t.Fatalf("expected schema constants")
	}
}

func TestDiagnosticsPackageSupportsStructuredReports(t *testing.T) {
	opts := diagnostics.DefaultIssueReadyOptions()
	if !opts.IncludeEnvironmentSummary || !opts.IncludeRecommendedActions || !opts.IncludeRawLogExcerpt {
		t.Fatalf("expected issue-ready preset to include report sections, got %#v", opts)
	}
	report := diagnostics.BuildStructuredReport(diagnostics.Context{
		UserDir:   t.TempDir(),
		SharedDir: t.TempDir(),
		HelpDir:   t.TempDir(),
		LogDir:    t.TempDir(),
	}, opts)
	if !strings.Contains(report, "# Yime Diagnostics Report") {
		t.Fatalf("expected structured report header, got %q", report)
	}
}

func TestBuildToolHubManifestProvidesExtensibleToolEntries(t *testing.T) {
	manifest := buildToolHubManifest(
		`C:\shared`,
		`C:\user`,
		`C:\help`,
		`C:\logs`,
		`C:\go-backend\lexicon-manager.exe`,
		`C:\go-backend\reverse-lookup.exe`,
		`C:\go-backend\system-lexicon-audit.exe`,
		`C:\go-backend\blocklist-manager.exe`,
		`C:\go-backend\settings-tool.exe`,
		`C:\go-backend\diagnostics-tool.exe`,
		"variable",
	)
	if err := validateToolHubManifest(manifest); err != nil {
		t.Fatalf("expected valid tool hub manifest, got %v", err)
	}
	if manifest.Title != "Yime 工具箱" {
		t.Fatalf("expected tool hub title, got %#v", manifest.Title)
	}
	if len(manifest.Tools) < 10 {
		t.Fatalf("expected framework-ready tool entries, got %#v", manifest.Tools)
	}
	required := map[string]bool{
		"lexicon-manager":        false,
		"reverse-lookup-tool":    false,
		"system-lexicon-audit":   false,
		"user-blocklist-manager": false,
		"settings-tool":          false,
		"settings-data":          false,
		"shared-data":            false,
		"diagnostics-tool":       false,
		"help-readme":            false,
		"help-trial-feedback":    false,
	}
	diagnosticsIndex := -1
	settingsDataIndex := -1
	for index, tool := range manifest.Tools {
		if _, ok := required[tool.ID]; ok {
			required[tool.ID] = true
		}
		switch tool.ID {
		case "diagnostics-tool":
			diagnosticsIndex = index
		case "settings-data":
			settingsDataIndex = index
		}
		switch tool.ID {
		case "lexicon-manager", "reverse-lookup-tool", "system-lexicon-audit", "user-blocklist-manager", "settings-tool", "diagnostics-tool":
			if tool.ActionType != toolActionRunExecutable {
				t.Fatalf("expected %s to launch native executable, got %#v", tool.ID, tool)
			}
			if tool.CloseAfterLaunch {
				t.Fatalf("expected %s to keep the tool hub open after launch, got %#v", tool.ID, tool)
			}
			switch tool.ID {
			case "lexicon-manager":
				if tool.TargetPath != `C:\go-backend\lexicon-manager.exe` {
					t.Fatalf("expected lexicon-manager executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) < 6 || tool.Arguments[0] != "-SharedDir" || tool.Arguments[2] != "-UserDir" || tool.Arguments[4] != "-Mode" {
					t.Fatalf("expected lexicon-manager executable arguments, got %#v", tool.Arguments)
				}
			case "reverse-lookup-tool":
				if tool.TargetPath != `C:\go-backend\reverse-lookup.exe` {
					t.Fatalf("expected reverse-lookup-tool executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) < 6 || tool.Arguments[0] != "-SharedDir" || tool.Arguments[2] != "-UserDir" || tool.Arguments[4] != "-Mode" {
					t.Fatalf("expected reverse-lookup-tool executable arguments, got %#v", tool.Arguments)
				}
			case "system-lexicon-audit":
				if tool.TargetPath != `C:\go-backend\system-lexicon-audit.exe` {
					t.Fatalf("expected system-lexicon-audit executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) < 6 || tool.Arguments[0] != "-SharedDir" || tool.Arguments[2] != "-UserDir" || tool.Arguments[4] != "-Mode" {
					t.Fatalf("expected system-lexicon-audit executable arguments, got %#v", tool.Arguments)
				}
			case "user-blocklist-manager":
				if tool.TargetPath != `C:\go-backend\blocklist-manager.exe` {
					t.Fatalf("expected user-blocklist-manager executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) != 2 || tool.Arguments[0] != "-UserDir" || tool.Arguments[1] != `C:\user` {
					t.Fatalf("expected user-blocklist-manager executable arguments, got %#v", tool.Arguments)
				}
			case "settings-tool":
				if tool.TargetPath != `C:\go-backend\settings-tool.exe` {
					t.Fatalf("expected settings-tool executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) < 8 || tool.Arguments[0] != "-UserDir" || tool.Arguments[2] != "-SharedDir" || tool.Arguments[4] != "-HelpDir" || tool.Arguments[6] != "-LogDir" {
					t.Fatalf("expected settings-tool executable arguments, got %#v", tool.Arguments)
				}
			case "diagnostics-tool":
				if tool.TargetPath != `C:\go-backend\diagnostics-tool.exe` {
					t.Fatalf("expected diagnostics-tool executable path to be preserved, got %#v", tool)
				}
				if len(tool.Arguments) < 8 || tool.Arguments[0] != "-UserDir" || tool.Arguments[2] != "-SharedDir" || tool.Arguments[4] != "-HelpDir" || tool.Arguments[6] != "-LogDir" {
					t.Fatalf("expected diagnostics-tool executable arguments, got %#v", tool.Arguments)
				}
			}
		default:
			if tool.CloseAfterLaunch {
				t.Fatalf("expected non-executable helper %s not to close the tool hub, got %#v", tool.ID, tool)
			}
		}
	}
	for id, found := range required {
		if !found {
			t.Fatalf("expected tool hub entry %q in %#v", id, manifest.Tools)
		}
	}
	if diagnosticsIndex < 0 || settingsDataIndex < 0 {
		t.Fatalf("expected diagnostics-tool and settings-data entries in %#v", manifest.Tools)
	}
	if diagnosticsIndex >= settingsDataIndex {
		t.Fatalf("expected diagnostics-tool before settings-data, got diagnostics=%d settings-data=%d", diagnosticsIndex, settingsDataIndex)
	}
	if manifest.Summary != "" || manifest.Note != "" {
		t.Fatalf("expected empty summary/note in tool hub manifest, got summary=%q note=%q", manifest.Summary, manifest.Note)
	}
}

func TestToolHubPackageSupportsExecutableChildren(t *testing.T) {
	if toolhub.ActionRunExecutable != "run_executable" {
		t.Fatalf("expected executable action type constant for native tool children")
	}
}

func TestValidateToolHubManifestRejectsDuplicateIDs(t *testing.T) {
	manifest := toolHubManifest{
		Title: "dup check",
		Tools: []toolHubEntry{
			{ID: "same", Label: "One", TargetPath: `C:\one`},
			{ID: "same", Label: "Two", TargetPath: `C:\two`},
		},
	}
	if err := validateToolHubManifest(manifest); err == nil || !strings.Contains(err.Error(), "duplicated") {
		t.Fatalf("expected duplicate-id validation error, got %v", err)
	}
}

func TestOnCommandSwitchesReverseLookupDisplayMode(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := ime.onCommand(&pime.Request{
		SeqNum: 16,
		ID:     pime.FlexibleID{Int: ID_REVERSE_LOOKUP_KEY_SEQUENCE, IsInt: true},
	}, pime.NewResponse(16, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected reverse lookup display command to be handled, got %d", resp.ReturnValue)
	}
	if ime.reverseLookupDisplayMode != "key_sequence" {
		t.Fatalf("expected key_sequence mode, got %q", ime.reverseLookupDisplayMode)
	}
	if resp.CompositionString != "" || resp.ShowCandidates || len(resp.CandidateList) != 0 {
		t.Fatalf("expected reverse lookup command not to refresh host candidate state, got %#v", resp)
	}
	if backend.composition != "ni" {
		t.Fatalf("expected backend composition untouched, got %q", backend.composition)
	}

	reverseMenu := ime.buildReverseLookupMenu()
	keySequence := findMenuItem(t, reverseMenu, ID_REVERSE_LOOKUP_KEY_SEQUENCE)
	if checked, ok := keySequence["checked"].(bool); !ok || !checked {
		t.Fatalf("expected key sequence reverse lookup item checked, got %#v", keySequence)
	}
}

func TestOnCommandSchedulesStandaloneToolsOutsideTSFCallback(t *testing.T) {
	ime := newTestIME()

	originalScheduler := scheduleStandaloneToolLaunch
	defer func() { scheduleStandaloneToolLaunch = originalScheduler }()

	scheduled := 0
	runs := 0
	scheduleStandaloneToolLaunch = func(run func() error, onError func(error)) {
		scheduled++
		if run == nil {
			t.Fatalf("expected standalone-tool callback to be provided")
		}
		if onError == nil {
			t.Fatalf("expected standalone-tool error handler to be provided")
		}
	}

	respLexicon := ime.onCommand(&pime.Request{
		SeqNum: 88,
		ID:     pime.FlexibleID{Int: ID_USER_LEXICON_MANAGER, IsInt: true},
	}, pime.NewResponse(88, true))
	if respLexicon.ReturnValue != 1 {
		t.Fatalf("expected lexicon-manager command to be handled, got %d", respLexicon.ReturnValue)
	}

	respToolHub := ime.onCommand(&pime.Request{
		SeqNum: 89,
		ID:     pime.FlexibleID{Int: ID_HELP_TOOL_HUB, IsInt: true},
	}, pime.NewResponse(89, true))
	if respToolHub.ReturnValue != 1 {
		t.Fatalf("expected tool-hub command to be handled, got %d", respToolHub.ReturnValue)
	}

	respReverseLookup := ime.onCommand(&pime.Request{
		SeqNum: 90,
		ID:     pime.FlexibleID{Int: ID_REVERSE_LOOKUP_TOOL, IsInt: true},
	}, pime.NewResponse(90, true))
	if respReverseLookup.ReturnValue != 1 {
		t.Fatalf("expected reverse-lookup command to be handled, got %d", respReverseLookup.ReturnValue)
	}

	if scheduled != 3 {
		t.Fatalf("expected all standalone-tool commands to be scheduled asynchronously, got %d", scheduled)
	}
	if runs != 0 {
		t.Fatalf("expected no standalone tool to launch synchronously inside onCommand, got %d immediate runs", runs)
	}
	if respLexicon.ShowCandidates || respToolHub.ShowCandidates || respReverseLookup.ShowCandidates {
		t.Fatalf("expected standalone-tool commands not to refresh candidate UI during TSF callback")
	}
}

func TestLookupStandardPinyinUsesPinyinNormalizedChainASCII(t *testing.T) {
	ime := newTestIME()
	ime.numericToMarkedLoaded = true
	ime.numericToMarkedPinyin = map[string]string{
		"ri4":   "ri-marked",
		"ben3":  "ben-marked",
		"jin1":  "jin-marked",
		"tian1": "tian-marked",
	}
	ime.reversePinyinLoaded = map[string]bool{"yime_variable": true}
	ime.reversePinyinBySchema = map[string]map[string]string{
		"yime_variable": {
			"q":  "ri4",
			"j":  "ben3",
			"ab": "jin1",
			"c":  "tian1",
		},
	}
	ime.yimePinyinLoaded = map[string]bool{"yime_variable": true}
	ime.yimePinyinBySchema = map[string]map[string]string{
		"yime_variable": {
			"word": "qj",
			"x":    "ab",
			"y":    "c",
		},
	}

	if got := ime.lookupStandardPinyin("word"); got != "ri-marked ben-marked" {
		t.Fatalf("expected word code to decode through pinyin_normalized chain, got %q", got)
	}
	if got := ime.lookupStandardPinyin("xy"); got != "jin-marked tian-marked" {
		t.Fatalf("expected rune fallback to decode through pinyin_normalized chain, got %q", got)
	}
}

func TestOnCommandReverseLookupYimePinyinDoesNotRedeploy(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := &redeployTestBackend{testBackend: newTestBackend(), redeployResult: true}
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()
	ime.backend = backend

	resp := ime.onCommand(&pime.Request{
		SeqNum: 47,
		ID:     pime.FlexibleID{Int: ID_REVERSE_LOOKUP_YIME_PINYIN, IsInt: true},
	}, pime.NewResponse(47, true))

	if resp.ReturnValue != 1 {
		t.Fatalf("expected 仅音元拼音 command to be handled, got %d", resp.ReturnValue)
	}
	if ime.reverseLookupDisplayMode != "yime_pinyin" {
		t.Fatalf("expected yime_pinyin mode, got %q", ime.reverseLookupDisplayMode)
	}
	if backend.redeployCount != 0 {
		t.Fatalf("expected reverse lookup click to avoid redeploy, got %d", backend.redeployCount)
	}
	if backend.destroyCount != 0 {
		t.Fatalf("expected reverse lookup click to avoid session reload, destroyCount=%d", backend.destroyCount)
	}
	if resp.CompositionString != "" || resp.ShowCandidates {
		t.Fatalf("expected no candidate refresh on reverse lookup click, got %#v", resp)
	}
	if backend.composition != "ni" {
		t.Fatalf("expected composition preserved, got %q", backend.composition)
	}
}

func TestPageSizeThenReverseLookupYimePinyinDoesNotRedeploy(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := &redeployTestBackend{testBackend: newTestBackend(), redeployResult: true}
	backend.session = true
	backend.composition = "ni"
	backend.refreshCandidates()
	ime.backend = backend

	pageResp := ime.onCommand(&pime.Request{
		SeqNum: 48,
		ID:     pime.FlexibleID{Int: ID_CANDIDATE_PAGE_SIZE_7, IsInt: true},
	}, pime.NewResponse(48, true))
	if pageResp.ReturnValue != 1 {
		t.Fatalf("expected page size command to be handled, got %d", pageResp.ReturnValue)
	}

	reverseResp := ime.onCommand(&pime.Request{
		SeqNum: 49,
		ID:     pime.FlexibleID{Int: ID_REVERSE_LOOKUP_YIME_PINYIN, IsInt: true},
	}, pime.NewResponse(49, true))
	if reverseResp.ReturnValue != 1 {
		t.Fatalf("expected 仅音元拼音 command to be handled, got %d", reverseResp.ReturnValue)
	}
	if backend.redeployCount != 0 {
		t.Fatalf("expected no redeploy across page size then reverse lookup, got %d", backend.redeployCount)
	}
	if ime.reverseLookupDisplayMode != "yime_pinyin" {
		t.Fatalf("expected yime_pinyin mode, got %q", ime.reverseLookupDisplayMode)
	}
	if reverseResp.ShowCandidates || reverseResp.CompositionString != "" {
		t.Fatalf("expected reverse lookup not to push candidate state, got %#v", reverseResp)
	}
}

func TestNormalizeNumericTonePinyin(t *testing.T) {
	tests := map[string]string{
		" Lv4 ": "lü4",
		"lu:4":  "lü4",
		"Nv3":   "nü3",
	}
	for input, want := range tests {
		if got := normalizeNumericTonePinyin(input); got != want {
			t.Fatalf("normalizeNumericTonePinyin(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestNormalizeNumericTonePinyinSyllableSpacing(t *testing.T) {
	tests := map[string]string{
		"ri4ben3":      "ri4 ben3",
		"jin1 ri4":     "jin1 ri4",
		"lvan2 nve4":   "lüan2 nüe4",
		"duori4":       "duori4",
		" zhong1guo2 ": "zhong1 guo2",
	}
	for input, want := range tests {
		if got := normalizeNumericTonePinyinSyllableSpacing(input); got != want {
			t.Fatalf("normalizeNumericTonePinyinSyllableSpacing(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestLoadUserLexiconEntriesNormalizesNumericTonePinyin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "yime_user_phrases.txt")
	content := "# header\n日本\tri4ben3\t1000000\n女儿\tnv3 er2\t1000000\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write fixture failed: %v", err)
	}

	entries, err := loadUserLexiconEntries(path)
	if err != nil {
		t.Fatalf("loadUserLexiconEntries failed: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %#v", entries)
	}
	if entries[0].Pinyin != "ri4 ben3" || entries[1].Pinyin != "nü3 er2" {
		t.Fatalf("expected normalized pinyin, got %#v", entries)
	}
}

func TestLoadUserLexiconEntriesRejectsInvalidWeight(t *testing.T) {
	path := filepath.Join(t.TempDir(), "yime_user_phrases.txt")
	content := "日本\tri4 ben3\theavy\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write fixture failed: %v", err)
	}

	_, err := loadUserLexiconEntries(path)
	if err == nil || !strings.Contains(err.Error(), "权重必须是整数") {
		t.Fatalf("expected invalid weight error, got %v", err)
	}
}

func TestLoadUserLexiconEntriesRejectsInvalidPinyin(t *testing.T) {
	path := filepath.Join(t.TempDir(), "yime_user_phrases.txt")
	content := "日本\tri4 ben\t1000000\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write fixture failed: %v", err)
	}

	_, err := loadUserLexiconEntries(path)
	if err == nil || !strings.Contains(err.Error(), "数字标调拼音格式错误") {
		t.Fatalf("expected invalid pinyin error, got %v", err)
	}
}

func TestLoadUserLexiconEntriesRejectsExtraColumns(t *testing.T) {
	path := filepath.Join(t.TempDir(), "yime_user_phrases.txt")
	content := "日本\tri4 ben3\t1000000\textra\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write fixture failed: %v", err)
	}

	_, err := loadUserLexiconEntries(path)
	if err == nil || !strings.Contains(err.Error(), "格式应为") {
		t.Fatalf("expected format error, got %v", err)
	}
}

func TestEnsureUserLexiconFileCreatesEditableNumericToneSource(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()

	path, err := ime.ensureUserLexiconFile()
	if err != nil {
		t.Fatalf("ensureUserLexiconFile failed: %v", err)
	}
	if !strings.HasSuffix(path, userLexiconSourceFileName) {
		t.Fatalf("expected editable source path, got %q", path)
	}
	if rimePath := ime.rimeUserLexiconPath("variable"); !strings.HasSuffix(rimePath, "custom_phrase_variable.txt") {
		t.Fatalf("expected generated Rime lexicon path for variable mode, got %q", rimePath)
	}
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read user lexicon source failed: %v", err)
	}
	if !strings.Contains(string(content), "numeric-tone-pinyin") || !strings.Contains(string(content), "zhong1 guo2") {
		t.Fatalf("expected numeric-tone pinyin source header, got %q", string(content))
	}
}

func TestBuildMenuIncludesYimeUserLexiconMenu(t *testing.T) {
	ime := newTestIME()

	userLexiconMenu := ime.buildUserLexiconMenu()
	if len(userLexiconMenu) != 1 {
		t.Fatalf("expected single lexicon-manager entry, got %#v", userLexiconMenu)
	}
	item := findTopLevelMenuItem(t, userLexiconMenu, ID_USER_LEXICON_MANAGER)
	if item["text"] != "打开词库管理" {
		t.Fatalf("expected lexicon manager entry text, got %#v", item)
	}
}

func TestAddButtonsIncludesTopLevelMenuButtons(t *testing.T) {
	ime := newTestIME()
	resp := pime.NewResponse(17, true)

	ime.addButtons(resp)

	want := map[string]bool{
		"candidate-layout": false,
		"lexicon-manager":  false,
		"reverse-lookup":   false,
		"tools":            false,
	}
	for _, button := range resp.AddButton {
		if _, ok := want[button.ID]; !ok {
			continue
		}
		want[button.ID] = true
		switch button.ID {
		case "candidate-layout":
			if button.Type != "button" {
				t.Fatalf("expected candidate-layout button to be a direct toggle button, got %#v", button)
			}
			if button.CommandID != ID_CANDIDATE_LAYOUT_TOGGLE {
				t.Fatalf("expected candidate-layout button to toggle to horizontal by default, got %#v", button)
			}
		case "lexicon-manager":
			// The user lexicon entry is a single-layer button: clicking it must
			// directly deliver ID_USER_LEXICON_MANAGER through onCommand instead
			// of opening a one-item menu. Keeping the command id on the button is
			// what keeps that host click path from falling back to command 0.
			if button.Type != "button" {
				t.Fatalf("expected lexicon-manager to be a direct button, got %#v", button)
			}
			if button.CommandID != ID_USER_LEXICON_MANAGER {
				t.Fatalf("expected lexicon-manager button to carry ID_USER_LEXICON_MANAGER, got %#v", button)
			}
		case "reverse-lookup":
			if button.Type != "button" {
				t.Fatalf("expected reverse-lookup to be a direct button, got %#v", button)
			}
			if button.CommandID != ID_REVERSE_LOOKUP_TOOL {
				t.Fatalf("expected reverse-lookup button to carry ID_REVERSE_LOOKUP_TOOL, got %#v", button)
			}
			if button.Text != "反查编码" {
				t.Fatalf("expected reverse-lookup button text 反查编码, got %#v", button)
			}
		case "tools":
			// The former 帮助 menu became a single 工具 button that opens the
			// aggregated tool hub directly. It must carry ID_HELP_TOOL_HUB so the
			// host click path reaches the async launcher instead of command 0.
			if button.Type != "button" {
				t.Fatalf("expected tools to be a direct button, got %#v", button)
			}
			if button.CommandID != ID_HELP_TOOL_HUB {
				t.Fatalf("expected tools button to carry ID_HELP_TOOL_HUB, got %#v", button)
			}
			if button.Text != "工具" {
				t.Fatalf("expected tools button text 工具, got %#v", button)
			}
		default:
			if button.Type != "menu" {
				t.Fatalf("expected %s button to be a menu, got %#v", button.ID, button)
			}
		}
	}
	for id, found := range want {
		if !found {
			t.Fatalf("expected %s button in %#v", id, resp.AddButton)
		}
	}

	// The former 帮助 menu became a single 工具 button; reverse-lookup is now a
	// direct language-bar button again for fast native lookup.
	for _, button := range resp.AddButton {
		if button.ID == "help" {
			t.Fatalf("expected 帮助 menu to be replaced by the 工具 button, still present as %#v", button)
		}
	}

	for _, button := range resp.AddButton {
		if button.ID == "lexicon-manager" {
			if button.Text != "用户词库" {
				t.Fatalf("expected lexicon-manager button text 用户词库, got %#v", button)
			}
			break
		}
	}
}

// TestUserLexiconAndToolsButtonsUseIcons wires the 用户词库 and 工具 buttons to
// their icon assets so the language bar can later switch to an icon-only look.
// The buttons must still carry text as a fallback when the icon is missing.
func TestUserLexiconAndToolsButtonsUseIcons(t *testing.T) {
	iconDir := t.TempDir()
	for _, name := range []string{"lexicon.ico", "tools.ico", "reverse-lookup.ico"} {
		if err := os.WriteFile(filepath.Join(iconDir, name), []byte("icon"), 0o644); err != nil {
			t.Fatalf("failed to seed icon %s: %v", name, err)
		}
	}

	ime := newTestIME()
	ime.iconDir = iconDir
	resp := pime.NewResponse(21, true)
	ime.addButtons(resp)

	wantIcon := map[string]string{
		"lexicon-manager": filepath.Join(iconDir, "lexicon.ico"),
		"reverse-lookup":  filepath.Join(iconDir, "reverse-lookup.ico"),
		"tools":           filepath.Join(iconDir, "tools.ico"),
	}
	seen := map[string]bool{}
	for _, button := range resp.AddButton {
		want, ok := wantIcon[button.ID]
		if !ok {
			continue
		}
		seen[button.ID] = true
		if button.Icon != want {
			t.Fatalf("expected %s button icon %q, got %#v", button.ID, want, button)
		}
		if button.Text == "" {
			t.Fatalf("expected %s button to keep its text as an icon-off fallback, got %#v", button.ID, button)
		}
	}
	for id := range wantIcon {
		if !seen[id] {
			t.Fatalf("expected %s button to be present with an icon", id)
		}
	}

	// Missing icon files must degrade gracefully to a text-only button, never
	// drop the button.
	ime.iconDir = filepath.Join(iconDir, "does-not-exist")
	resp = pime.NewResponse(22, true)
	ime.addButtons(resp)
	for _, button := range resp.AddButton {
		if button.ID == "lexicon-manager" || button.ID == "tools" || button.ID == "reverse-lookup" {
			if button.Icon != "" {
				t.Fatalf("expected %s button to have no icon when the file is missing, got %#v", button.ID, button)
			}
			if button.Text == "" {
				t.Fatalf("expected %s button to keep text when the icon is missing, got %#v", button.ID, button)
			}
		}
	}
}

func TestOnMenuReturnsTopLevelLayoutAndUserLexiconMenus(t *testing.T) {
	ime := newTestIME()

	layoutResp := ime.onMenu(&pime.Request{
		SeqNum: 17,
		ID:     pime.FlexibleID{String: "candidate-layout"},
	}, pime.NewResponse(17, true))
	layoutItems, ok := layoutResp.ReturnData.([]map[string]interface{})
	if !ok || len(layoutItems) != 0 {
		t.Fatalf("expected empty candidate layout menu (toggle is now a button), got %#v", layoutResp.ReturnData)
	}

	// reverse-lookup is a direct language-bar button; opening it as a menu must be a no-op.
	reverseResp := ime.onMenu(&pime.Request{
		SeqNum: 18,
		ID:     pime.FlexibleID{String: "reverse-lookup"},
	}, pime.NewResponse(18, true))
	if reverseResp.ReturnValue != 0 {
		t.Fatalf("expected reverse-lookup to no longer be a top-level menu, got return %d", reverseResp.ReturnValue)
	}

	userResp := ime.onMenu(&pime.Request{
		SeqNum: 19,
		ID:     pime.FlexibleID{String: "lexicon-manager"},
	}, pime.NewResponse(19, true))
	userItems, ok := userResp.ReturnData.([]map[string]interface{})
	if !ok || len(userItems) != 1 {
		t.Fatalf("expected lexicon manager menu item, got %#v", userResp.ReturnData)
	}
	if item := findTopLevelMenuItem(t, userItems, ID_USER_LEXICON_MANAGER); item["text"] != "打开词库管理" {
		t.Fatalf("expected lexicon manager item text, got %#v", item)
	}
}

func findSubmenuItem(t *testing.T, items []map[string]interface{}, text string) []map[string]interface{} {
	t.Helper()
	for _, item := range items {
		if item["text"] != text {
			continue
		}
		submenu, ok := item["submenu"].([]map[string]interface{})
		if !ok {
			t.Fatalf("expected submenu for %q, got %#v", text, item)
		}
		return submenu
	}
	t.Fatalf("expected submenu item %q in %#v", text, items)
	return nil
}

func hasSubmenuItem(items []map[string]interface{}, text string) bool {
	for _, item := range items {
		if item["text"] == text {
			_, ok := item["submenu"].([]map[string]interface{})
			return ok
		}
	}
	return false
}

func findMenuItem(t *testing.T, items []map[string]interface{}, id int) map[string]interface{} {
	t.Helper()
	for _, item := range items {
		if gotID, ok := item["id"].(int); ok && gotID == id {
			return item
		}
		if submenu, ok := item["submenu"].([]map[string]interface{}); ok {
			if found := findMenuItemInSubmenu(submenu, id); found != nil {
				return found
			}
		}
	}
	t.Fatalf("expected menu item id %d in %#v", id, items)
	return nil
}

func findTopLevelMenuItem(t *testing.T, items []map[string]interface{}, id int) map[string]interface{} {
	t.Helper()
	for _, item := range items {
		if gotID, ok := item["id"].(int); ok && gotID == id {
			return item
		}
	}
	t.Fatalf("expected top-level menu item id %d in %#v", id, items)
	return nil
}

func findMenuItemInSubmenu(items []map[string]interface{}, id int) map[string]interface{} {
	for _, item := range items {
		if gotID, ok := item["id"].(int); ok && gotID == id {
			return item
		}
		if submenu, ok := item["submenu"].([]map[string]interface{}); ok {
			if found := findMenuItemInSubmenu(submenu, id); found != nil {
				return found
			}
		}
	}
	return nil
}

func TestHandleRequestCompositionTerminatedResetsState(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 13,
		Method: "onCompositionTerminated",
	})

	if !resp.Success {
		t.Fatal("expected composition termination response to succeed")
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected state reset on composition termination")
	}
}

func TestHandleRequestOnDeactivateReturnsHandled(t *testing.T) {
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.composition = "ni"
	backend.refreshCandidates()

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 14,
		Method: "onDeactivate",
	})

	if resp.ReturnValue != 1 {
		t.Fatalf("expected onDeactivate to return 1, got %d", resp.ReturnValue)
	}
	if backend.composition != "" || backend.candidates != nil {
		t.Fatal("expected deactivate to clear composition state")
	}
}

func TestHandleRequestOnCompartmentChangedReturnsHandled(t *testing.T) {
	ime := newTestIME()

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 15,
		Method: "onCompartmentChanged",
	})

	if !resp.Success {
		t.Fatal("expected onCompartmentChanged response to succeed")
	}
	if resp.ReturnValue != 1 {
		t.Fatalf("expected onCompartmentChanged to return 1, got %d", resp.ReturnValue)
	}
}

func TestHandleRequestOnKeyboardStatusChangedReturnsHandled(t *testing.T) {
	ime := newTestIME()

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 16,
		Method: "onKeyboardStatusChanged",
	})

	if !resp.Success {
		t.Fatal("expected onKeyboardStatusChanged response to succeed")
	}
	if resp.ReturnValue != 1 {
		t.Fatalf("expected onKeyboardStatusChanged to return 1, got %d", resp.ReturnValue)
	}
}

func TestReadStandaloneSettingsStateNormalizesValues(t *testing.T) {
	path := filepath.Join(t.TempDir(), "yime_settings_state.json")
	payload := `{"reverse_lookup_display_mode":"yime_pinyin","candidate_layout":"horizontal"}`
	if err := os.WriteFile(path, []byte(payload), 0o644); err != nil {
		t.Fatalf("write settings state failed: %v", err)
	}

	state := readStandaloneSettingsState(path)
	if state.ReverseLookupDisplayMode != "yime_pinyin" {
		t.Fatalf("expected yime_pinyin reverse lookup mode, got %q", state.ReverseLookupDisplayMode)
	}
	if state.CandidateLayout != "horizontal" {
		t.Fatalf("expected horizontal layout, got %q", state.CandidateLayout)
	}

	if got := readStandaloneSettingsState(filepath.Join(t.TempDir(), "missing.json")); got.ReverseLookupDisplayMode != "" || got.CandidateLayout != "" {
		t.Fatalf("expected zero state for missing file, got %#v", got)
	}
}

func TestReadSelectedSchemaFromUserConfig(t *testing.T) {
	userDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(userDir, "user.yaml"), []byte("var:\n  previously_selected_schema: yime_full\n"), 0o644); err != nil {
		t.Fatalf("write user.yaml failed: %v", err)
	}
	if got := readSelectedSchemaFromUserConfig(userDir); got != "yime_full" {
		t.Fatalf("expected yime_full from user.yaml, got %q", got)
	}

	if err := os.Remove(filepath.Join(userDir, "user.yaml")); err != nil {
		t.Fatalf("remove user.yaml failed: %v", err)
	}
	if err := os.WriteFile(filepath.Join(userDir, "default.custom.yaml"), []byte("patch:\n  schema_list:\n    - schema: yime_shorthand\n"), 0o644); err != nil {
		t.Fatalf("write default.custom.yaml failed: %v", err)
	}
	if got := readSelectedSchemaFromUserConfig(userDir); got != "yime_shorthand" {
		t.Fatalf("expected yime_shorthand from default.custom.yaml, got %q", got)
	}

	corruptedUser := filepath.Join(userDir, "user.yaml")
	if err := os.WriteFile(corruptedUser, []byte("var:\n  previously_selected_schema: yime_variablepreviously_selected_schema: yime_variable\n"), 0o644); err != nil {
		t.Fatalf("write corrupted user.yaml failed: %v", err)
	}
	if got := readSelectedSchemaFromUserConfig(userDir); got != "yime_variable" {
		t.Fatalf("expected corrupted user.yaml to recover yime_variable prefix, got %q", got)
	}
}

func TestOnActivateSyncsStandaloneSettingsState(t *testing.T) {
	userDir := t.TempDir()
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.schemaID = "yime_variable"
	ime.style.CandidatePerRow = verticalCandidatesPerRow
	ime.reverseLookupDisplayMode = "key_sequence"
	t.Setenv("APPDATA", userDir)

	statePath := filepath.Join(userDir, APP, "Rime", "yime_settings_state.json")
	if err := os.MkdirAll(filepath.Dir(statePath), 0o755); err != nil {
		t.Fatalf("mkdir settings state dir failed: %v", err)
	}
	payload := `{"reverse_lookup_display_mode":"yime_pinyin","candidate_layout":"horizontal"}`
	if err := os.WriteFile(statePath, []byte(payload), 0o644); err != nil {
		t.Fatalf("write settings state failed: %v", err)
	}

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 23,
		Method: "onActivate",
	})

	if !resp.Success || resp.ReturnValue != 1 {
		t.Fatalf("expected activate response handled, got %#v", resp)
	}
	if ime.reverseLookupDisplayMode != "yime_pinyin" {
		t.Fatalf("expected yime_pinyin reverse lookup mode, got %q", ime.reverseLookupDisplayMode)
	}
	if ime.style.CandidatePerRow != horizontalCandidatesPerRow {
		t.Fatalf("expected horizontal candidate layout, got %d", ime.style.CandidatePerRow)
	}
	if !backend.horizontal {
		t.Fatal("expected backend horizontal option set from standalone settings")
	}
	if got := resp.CustomizeUI["candFontName"]; got != "YinYuan" {
		t.Fatalf("expected activation to apply PUA candidate font after loading settings, got %#v", got)
	}
	if got := resp.CustomizeUI["candPerRow"]; got != horizontalCandidatesPerRow {
		t.Fatalf("expected activation to apply persisted candidate layout, got %#v", got)
	}
}

func TestOnActivateDoesNotApplySchemaOrPageSizeFromStandaloneFiles(t *testing.T) {
	userDir := t.TempDir()
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.schemaID = "yime_variable"
	ime.candidatePageSize = defaultCandidatePageSize
	t.Setenv("APPDATA", userDir)

	rimeUserDir := filepath.Join(userDir, APP, "Rime")
	if err := os.MkdirAll(rimeUserDir, 0o755); err != nil {
		t.Fatalf("mkdir user dir failed: %v", err)
	}
	if err := os.WriteFile(filepath.Join(rimeUserDir, "user.yaml"), []byte("var:\n  previously_selected_schema: yime_full\n"), 0o644); err != nil {
		t.Fatalf("write user.yaml failed: %v", err)
	}
	if err := os.WriteFile(filepath.Join(rimeUserDir, "default.custom.yaml"), []byte("patch:\n  schema_list:\n    - schema: yime_full\n  \"menu/page_size\": 7\n"), 0o644); err != nil {
		t.Fatalf("write default.custom.yaml failed: %v", err)
	}
	if err := os.WriteFile(filepath.Join(rimeUserDir, "yime_settings_state.json"), []byte(`{"reverse_lookup_display_mode":"hidden","candidate_layout":"vertical"}`), 0o644); err != nil {
		t.Fatalf("write settings state failed: %v", err)
	}

	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 24,
		Method: "onActivate",
	})

	if !resp.Success || resp.ReturnValue != 1 {
		t.Fatalf("expected activate response handled, got %#v", resp)
	}
	if backend.schemaID != "yime_variable" {
		t.Fatalf("expected onActivate not to switch schema from standalone files, got %q", backend.schemaID)
	}
	if ime.candidatePageSize != defaultCandidatePageSize {
		t.Fatalf("expected onActivate not to change candidate page size, got %d", ime.candidatePageSize)
	}
	if backend.destroyCount != 0 {
		t.Fatalf("expected onActivate not to reload the backend session, destroyCount=%d", backend.destroyCount)
	}
	if ime.reverseLookupDisplayMode != "hidden" {
		t.Fatalf("expected standalone UI state to still apply reverse lookup mode, got %q", ime.reverseLookupDisplayMode)
	}
}

func TestJoinRuneLookupPartialMissing(t *testing.T) {
	lookup := map[string]string{
		"你": "ni3",
		"好": "hao3",
	}
	if got := joinRuneLookup("你好", lookup, " "); got != "ni3 hao3" {
		t.Fatalf("expected full match, got %q", got)
	}
	if got := joinRuneLookup("你X", lookup, " "); got != "ni3 ?" {
		t.Fatalf("expected partial match with placeholder, got %q", got)
	}
	if got := joinRuneLookup("X好", lookup, " "); got != "? hao3" {
		t.Fatalf("expected partial match with leading placeholder, got %q", got)
	}
	if got := joinRuneLookup("XY", lookup, " "); got != "? ?" {
		t.Fatalf("expected all placeholders for all-missing text, got %q", got)
	}
	if got := joinRuneLookup("你X好", lookup, " "); got != "ni3 ? hao3" {
		t.Fatalf("expected mixed match with middle placeholder, got %q", got)
	}
	if got := joinRuneLookup("", lookup, " "); got != "" {
		t.Fatalf("expected empty for empty input, got %q", got)
	}
}

func TestLookupStandardPinyinPartialMissing(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	ime.numericToMarkedPinyin = map[string]string{
		"ni3":  "ní",
		"hao3": "hǎo",
	}
	ime.reversePinyinLoaded = map[string]bool{"yime_variable": true}
	ime.reversePinyinBySchema = map[string]map[string]string{
		"yime_variable": {
			"n": "ni3",
			"h": "hao3",
		},
	}
	ime.yimePinyinLoaded = map[string]bool{"yime_variable": true}
	ime.yimePinyinBySchema = map[string]map[string]string{
		"yime_variable": {
			"你": "n",
			"好": "h",
		},
	}

	if got := ime.lookupStandardPinyin("你好"); got != "nǐ hǎo" {
		t.Fatalf("expected full pinyin, got %q", got)
	}
	if got := ime.lookupStandardPinyin("你𠀀"); got != "nǐ ?" {
		t.Fatalf("expected partial pinyin with placeholder for CJKV char without mapping, got %q", got)
	}
	if got := ime.lookupStandardPinyin("𠀀好"); got != "? hǎo" {
		t.Fatalf("expected leading placeholder for CJKV char without mapping, got %q", got)
	}
	if got := ime.lookupStandardPinyin("你𠀀好"); got != "nǐ ? hǎo" {
		t.Fatalf("expected mixed pinyin with middle placeholder, got %q", got)
	}
}

func TestYimePinyinCandidateCommentUsesActualCodeAndLeavesKeySequenceUntouched(t *testing.T) {
	ime := newTestIME()
	ime.reversePinyinLoaded = map[string]bool{"yime_variable": true}
	ime.reversePinyinBySchema = map[string]map[string]string{
		"yime_variable": {
			"2uji": "qing1",
			"$udm": "yan4",
			"3udm": "jian4",
		},
	}
	ime.yimePUALoaded = true
	ime.yimePUAByPinyin = map[string]string{
		"qing1": "\ue4fd\ue509\ue515\ue527",
		"yan4":  "\ue500\ue509\ue513\ue526",
		"jian4": "\ue4fc\ue509\ue513\ue526",
	}

	original := []candidateItem{{Text: "青砚验键", Comment: "2uji$udm$udm3udm"}}
	ime.reverseLookupDisplayMode = "yime_pinyin"
	display := ime.reverseLookupDisplayCandidates(original)
	if got, want := display[0].Comment, "\ue4fd\ue509\ue515\ue527\ue500\ue509\ue513\ue526\ue500\ue509\ue513\ue526\ue4fc\ue509\ue513\ue526"; got != want {
		t.Fatalf("expected PUA annotation decoded from actual candidate code, got %q want %q", got, want)
	}
	if original[0].Comment != "2uji$udm$udm3udm" {
		t.Fatalf("expected source candidate comment to remain unchanged, got %q", original[0].Comment)
	}

	ime.reverseLookupDisplayMode = "key_sequence"
	display = ime.reverseLookupDisplayCandidates(original)
	if got := display[0].Comment; got != "2uji$udm$udm3udm" {
		t.Fatalf("expected key-sequence mode to preserve ASCII input code, got %q", got)
	}
}

func TestBundledYimePUAMapContainsExpectedPhonologicalMappings(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("data", "yime_pua_pinyin.json"))
	if err != nil {
		t.Fatal(err)
	}
	var pinyinByPUA map[string][]string
	if err := json.Unmarshal(data, &pinyinByPUA); err != nil {
		t.Fatal(err)
	}
	expected := map[string]string{
		"qing1": "\ue4fd\ue509\ue515\ue527",
		"yan4":  "\ue500\ue509\ue513\ue526",
		"jian4": "\ue4fc\ue509\ue513\ue526",
	}
	found := map[string]string{}
	for pua, values := range pinyinByPUA {
		for _, value := range values {
			found[normalizeNumericTonePinyin(value)] = pua
		}
	}
	for pinyin, want := range expected {
		if got := found[pinyin]; got != want {
			t.Fatalf("expected bundled PUA mapping %s=%q, got %q", pinyin, want, got)
		}
	}
}

func TestCreateSessionUsesYinYuanFontOnlyForPUAAnnotations(t *testing.T) {
	ime := newTestIME()
	ime.backend.(*testBackend).session = true

	ime.reverseLookupDisplayMode = "yime_pinyin"
	resp := pime.NewResponse(1, true)
	ime.createSession(resp)
	if got := resp.CustomizeUI["candFontName"]; got != "YinYuan" {
		t.Fatalf("expected YinYuan candidate font for PUA annotations, got %#v", got)
	}

	ime.reverseLookupDisplayMode = "key_sequence"
	resp = pime.NewResponse(2, true)
	ime.createSession(resp)
	if got := resp.CustomizeUI["candFontName"]; got != ime.style.FontFace {
		t.Fatalf("expected configured candidate font outside PUA mode, got %#v", got)
	}
}

func TestApplyUserLexiconWritesAllThreeModes(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true

	sharedDir := ime.sharedDir()
	if err := os.MkdirAll(sharedDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tsvContent := "pinyin_tone\tfull\nzhong1\tqsdf\nguo2\tHsdf\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(tsvContent), 0o644); err != nil {
		t.Fatal(err)
	}

	sourcePath, err := ime.ensureUserLexiconFile()
	if err != nil {
		t.Fatalf("ensureUserLexiconFile failed: %v", err)
	}
	userEntry := "中国\tzhong1 guo2\t1000000\n"
	if err := os.WriteFile(sourcePath, []byte(userEntry), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := ime.applyUserLexicon(); err != nil {
		t.Fatalf("applyUserLexicon failed: %v", err)
	}

	userDir := ime.userDir()
	for _, mode := range yimeModes {
		targetPath := filepath.Join(userDir, "custom_phrase_"+mode+".txt")
		data, err := os.ReadFile(targetPath)
		if err != nil {
			t.Fatalf("expected custom_phrase_%s.txt to exist, got error: %v", mode, err)
		}
		content := string(data)
		if !strings.Contains(content, "中国") {
			t.Fatalf("expected custom_phrase_%s.txt to contain phrase, got %q", mode, content)
		}
	}

	varData, _ := os.ReadFile(filepath.Join(userDir, "custom_phrase_variable.txt"))
	fullData, _ := os.ReadFile(filepath.Join(userDir, "custom_phrase_full.txt"))
	shortData, _ := os.ReadFile(filepath.Join(userDir, "custom_phrase_shorthand.txt"))
	varContent := string(varData)
	fullContent := string(fullData)
	shortContent := string(shortData)

	if varContent == fullContent || varContent == shortContent || fullContent == shortContent {
		t.Fatalf("expected different encodings per mode, got variable=%q full=%q shorthand=%q", varContent, fullContent, shortContent)
	}
}

func TestApplyUserLexiconRunsExternalBuildAndSchedulesReload(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.schemaID = "yime_full"

	sharedDir := ime.sharedDir()
	if err := os.MkdirAll(sharedDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tsvContent := "pinyin_tone\tfull\nzhong1\tqsdf\nguo2\tHsdf\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(tsvContent), 0o644); err != nil {
		t.Fatal(err)
	}

	sourcePath, err := ime.ensureUserLexiconFile()
	if err != nil {
		t.Fatalf("ensureUserLexiconFile failed: %v", err)
	}
	if err := os.WriteFile(sourcePath, []byte("中国\tzhong1 guo2\t1000000\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	buildCalls := 0
	oldRunBuild := runRimeExternalBuild
	runRimeExternalBuild = func(gotSharedDir, gotUserDir string) bool {
		buildCalls++
		if gotSharedDir != sharedDir || gotUserDir != ime.userDir() {
			t.Fatalf("unexpected build args sharedDir=%q userDir=%q", gotSharedDir, gotUserDir)
		}
		return true
	}
	defer func() { runRimeExternalBuild = oldRunBuild }()

	if err := ime.applyUserLexicon(); err != nil {
		t.Fatalf("applyUserLexicon failed: %v", err)
	}
	if buildCalls != 1 {
		t.Fatalf("expected one external build, got %d", buildCalls)
	}
	if ime.pendingSchemaRedeploy != "yime_full" {
		t.Fatalf("expected pendingSchemaRedeploy to be yime_full, got %q", ime.pendingSchemaRedeploy)
	}
	if backend.schemaID != "yime_full" {
		t.Fatalf("expected schema to remain yime_full after reload, got %q", backend.schemaID)
	}
}

func TestRimeUserLexiconPathPerMode(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	for _, mode := range yimeModes {
		path := ime.rimeUserLexiconPath(mode)
		expected := "custom_phrase_" + mode + ".txt"
		if !strings.HasSuffix(path, expected) {
			t.Fatalf("expected rimeUserLexiconPath(%q) to end with %q, got %q", mode, expected, path)
		}
	}
}

func TestCandidatePageStartPreservedOnRejectedKey(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	ime.candidatePageStart = 1

	req := &pime.Request{SeqNum: 1, KeyCode: 0x41, CharCode: 'a'}
	ime.processKey(req, true)

	if ime.candidatePageStart != 1 {
		t.Fatalf("expected candidatePageStart preserved on key-up (rejected), got %d", ime.candidatePageStart)
	}
}

func TestCandidatePageStartResetOnAcceptedKey(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}}
	ime.candidatePageStart = 5

	req := &pime.Request{
		SeqNum:   1,
		KeyCode:  0x41,
		CharCode: 'a',
	}
	ime.processKey(req, false)

	if ime.candidatePageStart != 0 {
		t.Fatalf("expected candidatePageStart reset when backend accepts key, got %d", ime.candidatePageStart)
	}
}

func TestConcurrentKeyAndCommandNoDataRace(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}, {Text: "尼"}}

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			ime.processKey(&pime.Request{SeqNum: 1, KeyCode: 0x41, CharCode: 'a'}, false)
		}()
		go func() {
			defer wg.Done()
			ime.onCommand(&pime.Request{SeqNum: 1, ID: pime.FlexibleID{Int: ID_ASCII_MODE, IsInt: true}}, pime.NewResponse(1, true))
		}()
	}
	wg.Wait()
}

func TestLargeCandidateListGoSidePaging(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true

	candidates := make([]candidateItem, 25)
	for i := range candidates {
		candidates[i] = candidateItem{Text: string(rune('A' + i))}
	}
	backend.composition = "test"
	backend.candidates = candidates
	ime.candidatePageSize = 5
	ime.keyComposing = true

	ime.processKey(&pime.Request{SeqNum: 1, KeyCode: vkNext}, false)
	if ime.candidatePageStart != 5 {
		t.Fatalf("expected page start 5 after PageDown, got %d", ime.candidatePageStart)
	}

	ime.processKey(&pime.Request{SeqNum: 2, KeyCode: vkNext}, false)
	if ime.candidatePageStart != 10 {
		t.Fatalf("expected page start 10 after second PageDown, got %d", ime.candidatePageStart)
	}

	ime.processKey(&pime.Request{SeqNum: 3, KeyCode: vkPrior}, false)
	if ime.candidatePageStart != 5 {
		t.Fatalf("expected page start 5 after PageUp, got %d", ime.candidatePageStart)
	}

	ime.processKey(&pime.Request{SeqNum: 4, KeyCode: vkHome}, false)
	if ime.candidatePageStart != 0 {
		t.Fatalf("expected page start 0 after Home, got %d", ime.candidatePageStart)
	}

	ime.processKey(&pime.Request{SeqNum: 5, KeyCode: vkEnd}, false)
	if ime.candidatePageStart != 20 {
		t.Fatalf("expected page start 20 after End, got %d", ime.candidatePageStart)
	}
}

func TestUnicodeBoundaryEmojiAndExtendedHan(t *testing.T) {
	lookup := map[string]string{
		"你": "ni3",
		"好": "hao3",
	}

	if got := joinRuneLookup("你好", lookup, " "); got != "ni3 hao3" {
		t.Fatalf("expected basic CJK, got %q", got)
	}

	if got := joinRuneLookup("你😀好", lookup, " "); got != "ni3 ? hao3" {
		t.Fatalf("expected emoji placeholder, got %q", got)
	}

	if got := joinRuneLookup("你𠀀好", lookup, " "); got != "ni3 ? hao3" {
		t.Fatalf("expected CJK Ext-B placeholder, got %q", got)
	}

	if got := joinRuneLookup("你𠀀", lookup, " "); got != "ni3 ?" {
		t.Fatalf("expected trailing CJK Ext-B placeholder, got %q", got)
	}

	smp := "\U00020000"
	if utf8.RuneLen([]rune(smp)[0]) != 4 {
		t.Fatalf("expected 4-byte rune for CJK Ext-B, got %d", utf8.RuneLen([]rune(smp)[0]))
	}
}

func TestSchemaSwitchFailureDuringComposition(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}}

	ime.selectSchema("yime_full")
	if backend.composition != "" {
		t.Fatalf("expected composition cleared after successful schema switch, got %q", backend.composition)
	}

	backend.composition = "hao"
	backend.candidates = []candidateItem{{Text: "好"}}
	backend.schemaID = ""
	ime.selectSchema("")
	if backend.composition != "hao" {
		t.Fatalf("expected composition preserved when schema switch skipped (empty ID), got %q", backend.composition)
	}
}

func TestLongUserPhraseLexiconBuild(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true

	sharedDir := ime.sharedDir()
	if err := os.MkdirAll(sharedDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tsvContent := "pinyin_tone\tfull\nzhong1\tqsdf\nguo2\tHsdf\n"
	if err := os.WriteFile(filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), []byte(tsvContent), 0o644); err != nil {
		t.Fatal(err)
	}

	sourcePath, err := ime.ensureUserLexiconFile()
	if err != nil {
		t.Fatalf("ensureUserLexiconFile failed: %v", err)
	}

	longPhrase := ""
	for i := 0; i < 50; i++ {
		longPhrase += "中国"
	}
	longPinyin := ""
	for i := 0; i < 50; i++ {
		if i > 0 {
			longPinyin += " "
		}
		longPinyin += "zhong1 guo2"
	}
	entry := longPhrase + "\t" + longPinyin + "\t1000000\n"
	if err := os.WriteFile(sourcePath, []byte(entry), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := ime.applyUserLexicon(); err != nil {
		t.Fatalf("applyUserLexicon failed for long phrase: %v", err)
	}

	userDir := ime.userDir()
	for _, mode := range yimeModes {
		data, err := os.ReadFile(filepath.Join(userDir, "custom_phrase_"+mode+".txt"))
		if err != nil {
			t.Fatalf("expected custom_phrase_%s.txt for long phrase, got error: %v", mode, err)
		}
		if !strings.Contains(string(data), longPhrase) {
			t.Fatalf("expected long phrase in %s mode output", mode)
		}
	}
}

func TestCompositionTerminatedNonForced(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}}

	resp := ime.onCompositionTerminated(&pime.Request{SeqNum: 1, Forced: false}, pime.NewResponse(1, true))
	if resp.ReturnValue != 1 {
		t.Fatalf("expected ReturnValue 1, got %d", resp.ReturnValue)
	}
	if backend.composition != "" {
		t.Fatalf("expected composition cleared on non-forced termination, got %q", backend.composition)
	}
	if backend.session != true {
		t.Fatalf("expected session preserved on non-forced termination, got %t", backend.session)
	}
}

func TestCompositionTerminatedForced(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := newTestIME()
	backend := ime.backend.(*testBackend)
	backend.session = true
	backend.composition = "ni"
	backend.candidates = []candidateItem{{Text: "你"}}

	resp := ime.onCompositionTerminated(&pime.Request{SeqNum: 1, Forced: true}, pime.NewResponse(1, true))
	if resp.ReturnValue != 1 {
		t.Fatalf("expected ReturnValue 1, got %d", resp.ReturnValue)
	}
	if backend.session != false {
		t.Fatalf("expected session destroyed on forced termination, got %t", backend.session)
	}
}
