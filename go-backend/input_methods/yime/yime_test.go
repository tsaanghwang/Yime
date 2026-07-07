package yime

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/EasyIME/pime-go/pime"
)

type testDictEntry struct {
	code  string
	words []candidateItem
}

type testBackend struct {
	session            bool
	destroyCount       int
	composition        string
	candidates         []candidateItem
	commitString       string
	asciiMode          bool
	fullShape          bool
	horizontal         bool
	schemaID           string
	returnKeyHandled   bool
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
	return &IME{
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
		candidatePageSize:     defaultCandidatePageSize,
		keysDown:              map[int]bool{},
		backend:               newTestBackend(),
	}
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

func TestInitWithMissingUserDirDoesNotPanic(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	ime := New(&pime.Client{ID: "test-client"}).(*IME)

	if !ime.Init(&pime.Request{}) {
		t.Fatal("expected Init to keep service available when user RIME data is missing")
	}
	if ime.BackendAvailable() {
		t.Fatal("expected native backend to stay unavailable without user RIME data")
	}
}

func TestRimeInitRetryAfterFailure(t *testing.T) {
	rimeInitMu.Lock()
	rimeInitDone = false
	rimeInitOK = false
	rimeInitMu.Unlock()
	t.Cleanup(func() {
		rimeInitMu.Lock()
		rimeInitDone = false
		rimeInitOK = false
		rimeInitMu.Unlock()
	})

	badDir := t.TempDir()
	t.Setenv("APPDATA", badDir)

	ime := New(&pime.Client{ID: "test-client"}).(*IME)
	ime.Init(&pime.Request{})
	if ime.BackendAvailable() {
		t.Fatal("expected backend unavailable with missing Rime data")
	}

	rimeInitMu.Lock()
	doneAfterFirst := rimeInitDone
	okAfterFirst := rimeInitOK
	rimeInitMu.Unlock()
	if !doneAfterFirst {
		t.Fatal("expected rimeInitDone true after first init attempt")
	}
	if okAfterFirst {
		t.Fatal("expected rimeInitOK false after failed init")
	}

	goodDir := t.TempDir()
	userRime := filepath.Join(goodDir, "PIME", "Rime")
	if err := os.MkdirAll(userRime, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("APPDATA", goodDir)

	ime2 := New(&pime.Client{ID: "test-client-2"}).(*IME)
	ime2.Init(&pime.Request{})

	rimeInitMu.Lock()
	doneAfterRetry := rimeInitDone
	rimeInitMu.Unlock()
	if !doneAfterRetry {
		t.Fatal("expected rimeInitDone true after retry")
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
	if len(resp.ChangeButton) == 0 || resp.ChangeButton[0].CommandID != ID_CANDIDATE_LAYOUT_TOGGLE {
		t.Fatalf("expected layout button command ID to be toggle, got %#v", resp.ChangeButton)
	}
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
	customNorm := strings.ReplaceAll(string(customData), "\r\n", "\n")
	if !strings.Contains(customNorm, "  menu/page_size: 7\n") && !strings.Contains(customNorm, "  \"menu/page_size\": 7\n") {
		t.Fatalf("expected current schema custom page size 7, got %q", customNorm)
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
}

func TestNewUIPowerShellCommandUsesWindowsPowerShellWithoutHidingUI(t *testing.T) {
	cmd := newUIPowerShellCommand("-NoProfile", "-Command", "Write-Output ok")

	if !strings.HasSuffix(strings.ToLower(cmd.Path), "\\powershell.exe") {
		t.Fatalf("expected powershell.exe path, got %q", cmd.Path)
	}
	if cmd.SysProcAttr == nil || !cmd.SysProcAttr.HideWindow {
		t.Fatalf("expected UI PowerShell command to hide only the backing console window, got %#v", cmd.SysProcAttr)
	}
}

func TestBuildDetachedUIPowerShellLauncherScriptQuotesProgramFilesArguments(t *testing.T) {
	script := buildDetachedUIPowerShellLauncherScript(
		"-NoProfile",
		"-STA",
		"-File",
		`C:\Program Files (x86)\YIME\go-backend\input_methods\yime\tool.ps1`,
		"-SharedDir",
		`C:\Program Files (x86)\YIME\go-backend\input_methods\yime\data`,
	)

	if !strings.Contains(script, "Start-Process -FilePath ") {
		t.Fatalf("expected detached launcher script to use Start-Process, got %q", script)
	}
	if !strings.Contains(script, `"-File" "C:\Program Files (x86)\YIME\go-backend\input_methods\yime\tool.ps1"`) {
		t.Fatalf("expected detached launcher script to preserve quoted Program Files script path, got %q", script)
	}
	if !strings.Contains(script, `"-SharedDir" "C:\Program Files (x86)\YIME\go-backend\input_methods\yime\data"`) {
		t.Fatalf("expected detached launcher script to preserve quoted Program Files shared-data path, got %q", script)
	}
	if !strings.Contains(script, "-WindowStyle Hidden") {
		t.Fatalf("expected detached launcher script to hide the helper console window, got %q", script)
	}
}

func TestWindowsPowerShellPathUsesSystemRootWhenAvailable(t *testing.T) {
	systemRoot := os.Getenv("SystemRoot")
	if systemRoot == "" {
		t.Skip("SystemRoot is not set")
	}

	got := strings.ToLower(windowsPowerShellPath())
	wantSuffix := strings.ToLower(filepath.Join("System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
	if !strings.HasSuffix(got, wantSuffix) {
		t.Fatalf("expected windowsPowerShellPath to use the Windows PowerShell binary under SystemRoot, got %q", got)
	}
}

func TestStandalonePowerShellScriptsDoNotContainSmartQuotes(t *testing.T) {
	scripts := map[string]string{
		"user lexicon manager": userLexiconManagerScript,
		"tool hub":             toolHubScript,
		"settings tool":        settingsToolScript,
		"diagnostics tool":     diagnosticsToolScript,
		"reverse lookup tool":  reverseLookupToolScript,
	}
	for name, script := range scripts {
		if strings.Contains(script, "“") || strings.Contains(script, "”") {
			t.Fatalf("expected %s PowerShell script to avoid smart quotes that break parsing", name)
		}
	}
}

// Regression guard for the "设置工具" instant-exit bug: the embedded PowerShell
// scripts were double-encoded (UTF-8 read as GBK then re-saved as UTF-8). The
// corruption left Unicode private-use / surrogate characters behind and, worse,
// swallowed the closing double quote of several string literals (e.g. `。"`
// became a single mangled glyph), which made PowerShell fail to parse the whole
// script so the window closed immediately. Any recurrence of that encoding
// damage reintroduces those code points, so fail fast if we see them again.
func TestStandalonePowerShellScriptsAreFreeOfEncodingCorruption(t *testing.T) {
	scripts := map[string]string{
		"user lexicon manager": userLexiconManagerScript,
		"tool hub":             toolHubScript,
		"settings tool":        settingsToolScript,
		"diagnostics tool":     diagnosticsToolScript,
		"reverse lookup tool":  reverseLookupToolScript,
	}
	for name, script := range scripts {
		for i, r := range script {
			if (r >= 0xE000 && r <= 0xF8FF) || (r >= 0xD800 && r <= 0xDFFF) || r == 0xFFFD {
				t.Fatalf("%s PowerShell script contains corruption marker %#U at byte offset %d; the file was likely re-saved with a wrong (non-UTF-8) encoding", name, r, i)
			}
		}
	}

	// The settings tool must keep its intended, human-readable labels/messages.
	// These exact strings were destroyed by the encoding corruption, so their
	// presence proves the recovery is intact.
	wantSettings := []string{
		"音元拼音",
		"变长", "等长", "省键",
		"隐藏编码", "标准拼音", "键位序列",
		"横排", "竖排",
		"当前设置：方案",
		"已复制设置摘要。",
		"Yime 设置面板",
		"应用并重建",
		"应用设置",
		"用户目录",
		"设置说明",
	}
	for _, want := range wantSettings {
		if !strings.Contains(settingsToolScript, want) {
			t.Fatalf("expected settings tool script to contain %q; encoding recovery may be incomplete", want)
		}
	}
	wantDiagnosticsUI := []string{
		"Yime 诊断面板",
		"复制结构化报告",
		"包含环境摘要",
		"问题反馈",
		"[内置] ",
		"[已保存] ",
	}
	for _, want := range wantDiagnosticsUI {
		if !strings.Contains(diagnosticsToolScript, want) {
			t.Fatalf("expected diagnostics tool script to contain %q; localization may be incomplete", want)
		}
	}
	wantReverseLookupUI := []string{
		"Yime 反查编码",
		"查询词条",
		"包含匹配",
		"数字标调",
		"标准拼音",
		"用户词库",
		"系统词库",
	}
	for _, want := range wantReverseLookupUI {
		if !strings.Contains(reverseLookupToolScript, want) {
			t.Fatalf("expected reverse lookup tool script to contain %q; localization may be incomplete", want)
		}
	}
}

func TestUserLexiconManagerScriptShowsDialogInsideTopLevelTry(t *testing.T) {
	if !strings.Contains(userLexiconManagerScript, "try {\n  [void]$form.ShowDialog()\n} catch {\n  Show-Error $_.Exception.Message\n}") {
		t.Fatalf("expected lexicon manager script to show dialog inside top-level try/catch")
	}
	if !strings.Contains(userLexiconManagerScript, "Edit-Entry") {
		t.Fatalf("expected lexicon manager script to expose entry editing")
	}
	if !strings.Contains(userLexiconManagerScript, "$searchBox.Add_TextChanged") {
		t.Fatalf("expected lexicon manager script to refresh from search changes")
	}
	if !strings.Contains(userLexiconManagerScript, "$listView.Add_DoubleClick") {
		t.Fatalf("expected lexicon manager script to support double-click editing")
	}
	if !strings.Contains(userLexiconManagerScript, "源词库: {0}") || !strings.Contains(userLexiconManagerScript, "生成词库: {1}") {
		t.Fatalf("expected lexicon manager script to show source and generated lexicon paths")
	}
	if !strings.Contains(userLexiconManagerScript, "权重") {
		t.Fatalf("expected lexicon manager script to expose lexicon-entry weight editing")
	}
	if !strings.Contains(userLexiconManagerScript, "Set-DirtyState") {
		t.Fatalf("expected lexicon manager script to track unapplied source-lexicon changes")
	}
	if !strings.Contains(userLexiconManagerScript, "Get-SortedEntries") {
		t.Fatalf("expected lexicon manager script to sort visible lexicon entries")
	}
	if !strings.Contains(userLexiconManagerScript, "$sortFieldComboBox.Add_SelectedIndexChanged") {
		t.Fatalf("expected lexicon manager script to refresh after sort field changes")
	}
	if !strings.Contains(userLexiconManagerScript, "$sortDirectionButton.Add_Click") {
		t.Fatalf("expected lexicon manager script to toggle sort direction")
	}
	if !strings.Contains(userLexiconManagerScript, "源词库有未应用改动") {
		t.Fatalf("expected lexicon manager script to warn about unapplied source changes")
	}
	if !strings.Contains(userLexiconManagerScript, "Get-SelectedPhrases") {
		t.Fatalf("expected lexicon manager script to support multi-selection workflows")
	}
	if !strings.Contains(userLexiconManagerScript, "Adjust-SelectedWeights") {
		t.Fatalf("expected lexicon manager script to support batch weight adjustment")
	}
	if !strings.Contains(userLexiconManagerScript, "Get-ImportConflictPreview") {
		t.Fatalf("expected lexicon manager script to preview import conflicts before applying them")
	}
	if !strings.Contains(userLexiconManagerScript, "Show-ImportConflictPreviewDialog") {
		t.Fatalf("expected lexicon manager script to show an import-conflict preview dialog")
	}
	if !strings.Contains(userLexiconManagerScript, "$form.Add_FormClosing") {
		t.Fatalf("expected lexicon manager script to warn before closing with unapplied changes")
	}
	if !strings.Contains(userLexiconManagerScript, "Show-SetWeightDialog") {
		t.Fatalf("expected lexicon manager script to support setting an exact weight")
	}
	if !strings.Contains(userLexiconManagerScript, "Assert-EntryFields") || !strings.Contains(userLexiconManagerScript, "请输入词条。") || !strings.Contains(userLexiconManagerScript, "请输入数字标调拼音，例如 zhong1 guo2。") {
		t.Fatalf("expected lexicon manager script to validate entry input with localized Chinese prompts")
	}
	if !strings.Contains(userLexiconManagerScript, "$confirmMessage = \"确定要删除 $($phrases.Count) 条词条吗？\"") || !strings.Contains(userLexiconManagerScript, "Add-OperationHistory \"删除词条 $($phrases.Count) 条\"") {
		t.Fatalf("expected delete-entry messages to avoid brittle PowerShell format-string placeholders")
	}
	if !strings.Contains(userLexiconManagerScript, "设置词条权重") {
		t.Fatalf("expected lexicon manager script to localize the exact-weight dialog")
	}
	if !strings.Contains(userLexiconManagerScript, "Set-SelectedWeights") {
		t.Fatalf("expected lexicon manager script to set exact weights for selected entries")
	}
	if !strings.Contains(userLexiconManagerScript, "Set-SelectionSummary") {
		t.Fatalf("expected lexicon manager script to summarize the current multi-selection")
	}
	if !strings.Contains(userLexiconManagerScript, "Refresh-OperationHistory") {
		t.Fatalf("expected lexicon manager script to render a recent-operation history panel")
	}
	if !strings.Contains(userLexiconManagerScript, "Add-OperationHistory") {
		t.Fatalf("expected lexicon manager script to append recent-operation history entries")
	}
	if !strings.Contains(userLexiconManagerScript, "Copy-RecentOperationSummary") {
		t.Fatalf("expected lexicon manager script to copy a structured recent-operation summary")
	}
	if !strings.Contains(userLexiconManagerScript, "Save-UndoSnapshot") {
		t.Fatalf("expected lexicon manager script to capture undo snapshots before source changes")
	}
	if !strings.Contains(userLexiconManagerScript, "Undo-LastSourceChange") {
		t.Fatalf("expected lexicon manager script to support undoing the most recent source change")
	}
	if !strings.Contains(userLexiconManagerScript, "SelectedConflictPhrases") {
		t.Fatalf("expected lexicon manager script to return checked conflict phrases from import preview")
	}
	if !strings.Contains(userLexiconManagerScript, "全选冲突") || !strings.Contains(userLexiconManagerScript, "清空冲突") {
		t.Fatalf("expected lexicon manager script to support selecting or clearing import conflicts")
	}
	if !strings.Contains(userLexiconManagerScript, "冲突项") || !strings.Contains(userLexiconManagerScript, "新增项") {
		t.Fatalf("expected lexicon manager script to split import preview between conflict and new-entry views")
	}
	if !strings.Contains(userLexiconManagerScript, "只看冲突") || !strings.Contains(userLexiconManagerScript, "只看新增") || !strings.Contains(userLexiconManagerScript, "查看全部") {
		t.Fatalf("expected lexicon manager script to expose import-preview view filters")
	}
	if !strings.Contains(userLexiconManagerScript, "复制导入摘要") {
		t.Fatalf("expected lexicon manager script to support copying an import-preview summary")
	}
	if !strings.Contains(userLexiconManagerScript, "$actionBlock = $Action.GetNewClosure()") || !strings.Contains(userLexiconManagerScript, "& $actionBlock") {
		t.Fatalf("expected lexicon manager action handlers to capture button/menu callbacks with GetNewClosure")
	}
	if !strings.Contains(userLexiconManagerScript, "Add-ActionButton \"打开目录\" { Open-UserFolder }") {
		t.Fatalf("expected lexicon manager script to expose the user lexicon directory as a top-level toolbar action")
	}
	if !strings.Contains(userLexiconManagerScript, "Set-SortFromColumn") {
		t.Fatalf("expected lexicon manager script to map column clicks into sort changes")
	}
	if !strings.Contains(userLexiconManagerScript, "$listView.Add_ColumnClick") {
		t.Fatalf("expected lexicon manager script to sort from list column clicks")
	}
	if !strings.Contains(userLexiconManagerScript, "$listView.Add_ItemSelectionChanged") {
		t.Fatalf("expected lexicon manager script to refresh selection summary from selection changes")
	}
	if !strings.Contains(userLexiconManagerScript, "$form.Add_Shown({") || !strings.Contains(userLexiconManagerScript, "[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea") || !strings.Contains(userLexiconManagerScript, "$form.Location = New-Object System.Drawing.Point($x, $y)") {
		t.Fatalf("expected lexicon manager script to restore a centered window when shown")
	}
	if !strings.Contains(userLexiconManagerScript, "$form.BeginInvoke([System.Windows.Forms.MethodInvoker]{") || !strings.Contains(userLexiconManagerScript, "$script:codeMap = Load-CodeMap") {
		t.Fatalf("expected lexicon manager script to defer code-map initialization until after the window is shown")
	}
	if strings.Contains(userLexiconManagerScript, "$form.TopMost = $true") || strings.Contains(userLexiconManagerScript, "$form.Activate()") || strings.Contains(userLexiconManagerScript, "$form.BringToFront()") {
		t.Fatalf("expected lexicon manager script to avoid aggressive foreground forcing that can collapse the language bar")
	}
	if !strings.Contains(userLexiconManagerScript, "try {\n  [void](Add-ActionButton \"添加词条\" { Add-Entry })") || !strings.Contains(userLexiconManagerScript, "} catch {\n  Show-Error $_.Exception.Message\n  return\n}") {
		t.Fatalf("expected lexicon manager script to guard toolbar/menu setup before ShowDialog")
	}
}

func TestToolHubScriptShowsDialogInsideTopLevelTry(t *testing.T) {
	if !strings.Contains(toolHubScript, "try {\n  [void]$form.ShowDialog()\n} catch {\n  Show-Error $_.Exception.Message\n}") {
		t.Fatalf("expected tool hub script to show dialog inside top-level try/catch")
	}
	if !strings.Contains(toolHubScript, "ConvertFrom-Json") {
		t.Fatalf("expected tool hub script to render from a manifest-driven payload")
	}
	if !strings.Contains(toolHubScript, "-WindowStyle Hidden") {
		t.Fatalf("expected tool hub script to hide child PowerShell console windows")
	}
	if !strings.Contains(toolHubScript, "function Quote-ProcessArgument") || !strings.Contains(toolHubScript, "$argumentLine = ($Tool.arguments | ForEach-Object { Quote-ProcessArgument ([string]$_) }) -join \" \"") {
		t.Fatalf("expected tool hub script to quote PowerShell child-process arguments so Program Files paths survive launch")
	}
	if !strings.Contains(toolHubScript, "\"run_executable\"") || !strings.Contains(toolHubScript, "Missing executable: ") || !strings.Contains(toolHubScript, "Start-Process -FilePath $Tool.target_path -ArgumentList $argumentLine") {
		t.Fatalf("expected tool hub script to launch standalone executables through a dedicated action path")
	}
	if !strings.Contains(toolHubScript, "$shouldClose = [bool]$Tool.close_after_launch") || !strings.Contains(toolHubScript, "return $shouldClose") {
		t.Fatalf("expected tool hub script to report when a child tool wants the hub to exit after launch")
	}
	if !strings.Contains(toolHubScript, "$closeTimer = New-Object System.Windows.Forms.Timer") || !strings.Contains(toolHubScript, "$form.Hide()") || !strings.Contains(toolHubScript, "$closeTimer.Start()") {
		t.Fatalf("expected tool hub script to defer self-close until after the click handler returns")
	}
	if !strings.Contains(toolHubScript, "$closeTimer.Interval = 800") {
		t.Fatalf("expected tool hub script to leave enough delay before closing so slower child windows can surface")
	}
	if !strings.Contains(toolHubScript, "$form.Add_Shown({") || !strings.Contains(toolHubScript, "[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea") || !strings.Contains(toolHubScript, "$form.Location = New-Object System.Drawing.Point($x, $y)") {
		t.Fatalf("expected tool hub script to restore a normal centered window when shown")
	}
	if strings.Contains(toolHubScript, "$form.TopMost = $true") || strings.Contains(toolHubScript, "$form.BringToFront()") {
		t.Fatalf("expected tool hub script to avoid aggressive foreground forcing that can lock input-method state")
	}
}

func TestStandaloneSettingsAndDiagnosticsScriptsProvideRealWindowShells(t *testing.T) {
	if !strings.Contains(settingsToolScript, "Yime 设置面板") {
		t.Fatalf("expected settings tool script panel copy")
	}
	if !strings.Contains(settingsToolScript, "Apply-Settings") {
		t.Fatalf("expected settings tool script to apply settings")
	}
	if !strings.Contains(settingsToolScript, `$applyAndRebuildButton.Text = "应用并重建"`) {
		t.Fatalf("expected settings tool script to expose an apply-and-rebuild action")
	}
	if !strings.Contains(settingsToolScript, "Invoke-RimeBuild") {
		t.Fatalf("expected settings tool script to rebuild runtime config when requested")
	}
	if !strings.Contains(settingsToolScript, "Write-StandaloneSettingsState") {
		t.Fatalf("expected settings tool script to persist standalone UI settings")
	}
	if !strings.Contains(settingsToolScript, "Read-ConfiguredSchema") || !strings.Contains(settingsToolScript, "Read-ConfiguredPageSize") {
		t.Fatalf("expected settings tool script to read current schema and page-size config")
	}
	if !strings.Contains(settingsToolScript, "previously_selected_schema") || !strings.Contains(settingsToolScript, "\"menu/page_size\"") {
		t.Fatalf("expected settings tool script to update the same schema and page-size files Yime already uses")
	}
	if strings.Contains(settingsToolScript, `'^(\\s*).*$'`) {
		t.Fatalf("expected settings tool script to use a whitespace indent regex, not a broken literal backslash-s pattern")
	}
	if !strings.Contains(settingsToolScript, `'^(\s*).*$'`) {
		t.Fatalf("expected settings tool script to preserve YAML line indentation when replacing schema and page-size keys")
	}
	if !strings.Contains(settingsToolScript, "Rebuild patch: keep any header such as __build_info:") {
		t.Fatalf("expected settings tool script to rebuild default.custom.yaml patch with a single schema_list entry")
	}
	if !strings.Contains(settingsToolScript, "reverse_lookup_display_mode") || !strings.Contains(settingsToolScript, "candidate_layout") {
		t.Fatalf("expected settings tool script to persist reverse-lookup and layout preferences")
	}
	if !strings.Contains(settingsToolScript, "$reverseLookupComboBox.SelectedItem.Value") || !strings.Contains(settingsToolScript, "$candidateLayoutComboBox.SelectedItem.Value") {
		t.Fatalf("expected settings tool script to read combo-box values from SelectedItem.Value")
	}
	if !strings.Contains(settingsToolScript, "修改方案或候选项数时请使用【应用并重建】。") {
		t.Fatalf("expected settings tool script to keep schema/page-size rebuild guidance without input-method activation claims")
	}
	if !strings.Contains(settingsToolScript, "设置说明") || !strings.Contains(settingsToolScript, "查看帮助") {
		t.Fatalf("expected settings tool script to expose guide entry points")
	}
	if !strings.Contains(settingsToolScript, "$form.Add_Shown({") || !strings.Contains(settingsToolScript, "[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea") || !strings.Contains(settingsToolScript, "$form.Location = New-Object System.Drawing.Point($x, $y)") || !strings.Contains(settingsToolScript, "Refresh-SettingsView") {
		t.Fatalf("expected settings tool script to restore a centered window and refresh state when shown")
	}
	if strings.Contains(settingsToolScript, "$form.TopMost = $true") || strings.Contains(settingsToolScript, "$form.Activate()") || strings.Contains(settingsToolScript, "$form.BringToFront()") {
		t.Fatalf("expected settings tool script to avoid aggressive foreground forcing that can collapse the language bar")
	}
	if strings.Contains(settingsToolScript, "try {\n  Refresh-SettingsView\n  [void]$form.ShowDialog()") {
		t.Fatalf("expected settings tool script not to refresh state before the dialog is shown")
	}
	if !strings.Contains(diagnosticsToolScript, "Yime 诊断面板") {
		t.Fatalf("expected diagnostics tool script shell copy")
	}
	if !strings.Contains(diagnosticsToolScript, "$form.Add_Shown({") || !strings.Contains(diagnosticsToolScript, "[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea") || !strings.Contains(diagnosticsToolScript, "$form.Location = New-Object System.Drawing.Point($x, $y)") {
		t.Fatalf("expected diagnostics tool script to restore a centered window when shown")
	}
	if !strings.Contains(diagnosticsToolScript, "$form.BeginInvoke([System.Windows.Forms.MethodInvoker]{") || !strings.Contains(diagnosticsToolScript, `Apply-ReportPreset "Issue-ready"`) {
		t.Fatalf("expected diagnostics tool script to defer the initial refresh until after the window is shown")
	}
	if strings.Contains(diagnosticsToolScript, "$form.TopMost = $true") || strings.Contains(diagnosticsToolScript, "$form.Activate()") || strings.Contains(diagnosticsToolScript, "$form.BringToFront()") {
		t.Fatalf("expected diagnostics tool script to avoid aggressive foreground forcing that can collapse the language bar")
	}
	if !strings.Contains(diagnosticsToolScript, "Refresh-Status") {
		t.Fatalf("expected diagnostics tool script to expose a refreshable status view")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-ProcessSummary") {
		t.Fatalf("expected diagnostics tool script to inspect running-process status")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-DeployerCheck") {
		t.Fatalf("expected diagnostics tool script to inspect installed deployer status")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-RimeUserFilesSummary") {
		t.Fatalf("expected diagnostics tool script to inspect key user Rime files")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-SettingsChainSummary") {
		t.Fatalf("expected diagnostics tool script to expose a dedicated settings-chain summary")
	}
	if !strings.Contains(diagnosticsToolScript, "Read-SettingsConfiguredSchema") || !strings.Contains(diagnosticsToolScript, "Read-SettingsConfiguredPageSize") {
		t.Fatalf("expected diagnostics tool script to parse configured schema and page size from the written settings files")
	}
	if !strings.Contains(diagnosticsToolScript, "Read-StandaloneSettingsSnapshot") {
		t.Fatalf("expected diagnostics tool script to parse standalone settings state JSON")
	}
	if !strings.Contains(diagnosticsToolScript, "复制结构化报告") {
		t.Fatalf("expected diagnostics tool script to support copying its structured report")
	}
	if !strings.Contains(diagnosticsToolScript, "Build-StructuredDiagnosticReport") {
		t.Fatalf("expected diagnostics tool script to build a structured shareable report")
	}
	if !strings.Contains(diagnosticsToolScript, "# Yime Diagnostics Report") {
		t.Fatalf("expected diagnostics tool script to label the structured report clearly")
	}
	if !strings.Contains(diagnosticsToolScript, "包含环境摘要") {
		t.Fatalf("expected diagnostics tool script to expose an environment-summary report option")
	}
	if !strings.Contains(diagnosticsToolScript, "包含建议操作") {
		t.Fatalf("expected diagnostics tool script to expose a recommended-actions report option")
	}
	if !strings.Contains(diagnosticsToolScript, "包含原始日志摘录") {
		t.Fatalf("expected diagnostics tool script to expose a raw-log report option")
	}
	if !strings.Contains(diagnosticsToolScript, "匿名化报告") {
		t.Fatalf("expected diagnostics tool script to expose an anonymize-report option")
	}
	if !strings.Contains(diagnosticsToolScript, "保留盘符") {
		t.Fatalf("expected diagnostics tool script to expose a keep-drive anonymization option")
	}
	if !strings.Contains(diagnosticsToolScript, "匿名模式：") {
		t.Fatalf("expected diagnostics tool script to expose an anonymize-mode selector")
	}
	if !strings.Contains(diagnosticsToolScript, "仅姓名") {
		t.Fatalf("expected diagnostics tool script to expose a names-only anonymization mode")
	}
	if !strings.Contains(diagnosticsToolScript, "日志摘录模式：") {
		t.Fatalf("expected diagnostics tool script to expose a raw-log excerpt mode selector")
	}
	if !strings.Contains(diagnosticsToolScript, "预设：") {
		t.Fatalf("expected diagnostics tool script to expose a report preset selector")
	}
	if !strings.Contains(diagnosticsToolScript, "Apply-ReportPreset") {
		t.Fatalf("expected diagnostics tool script to centralize report preset application")
	}
	if !strings.Contains(diagnosticsToolScript, "Apply-ReportOptions") {
		t.Fatalf("expected diagnostics tool script to apply report options from both built-in and saved presets")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-CurrentReportOptions") {
		t.Fatalf("expected diagnostics tool script to snapshot the current report options for saving")
	}
	if !strings.Contains(diagnosticsToolScript, "Load-SavedReportPresets") {
		t.Fatalf("expected diagnostics tool script to load saved report presets from user data")
	}
	if !strings.Contains(diagnosticsToolScript, "Save-SavedReportPresets") {
		t.Fatalf("expected diagnostics tool script to persist saved report presets to user data")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-SelectedSavedPresetName") {
		t.Fatalf("expected diagnostics tool script to detect when a saved preset is currently selected")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-SavedPresetIndexByName") {
		t.Fatalf("expected diagnostics tool script to look up saved presets by name")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-ExportedReportPresetPath") {
		t.Fatalf("expected diagnostics tool script to build a stable export path for current presets")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-ImportedReportPresetCandidates") {
		t.Fatalf("expected diagnostics tool script to discover importable preset files from user data")
	}
	if !strings.Contains(diagnosticsToolScript, "Show-ImportPresetPicker") {
		t.Fatalf("expected diagnostics tool script to present a dedicated picker for importing preset files")
	}
	if !strings.Contains(diagnosticsToolScript, "Refresh-PresetComboBoxItems") {
		t.Fatalf("expected diagnostics tool script to rebuild the preset list after saved-preset changes")
	}
	if !strings.Contains(diagnosticsToolScript, "diagnostics_report_presets.json") {
		t.Fatalf("expected diagnostics tool script to store saved presets in a stable user-data file")
	}
	if !strings.Contains(diagnosticsToolScript, "Issue-ready") {
		t.Fatalf("expected diagnostics tool script to expose an issue-ready preset")
	}
	if !strings.Contains(diagnosticsToolScript, `$presetComboBox.SelectedItem = (Format-BuiltInPresetDisplay "Issue-ready")`) {
		t.Fatalf("expected diagnostics tool script to select the built-in issue-ready preset label")
	}
	if !strings.Contains(diagnosticsToolScript, "function Format-BuiltInPresetDisplay") {
		t.Fatalf("expected diagnostics tool script to map built-in preset keys to Chinese labels")
	}
	if strings.Contains(diagnosticsToolScript, "Microsoft.VisualBasic") {
		t.Fatalf("expected diagnostics tool script to avoid Microsoft.VisualBasic startup dependency")
	}
	if !strings.Contains(diagnosticsToolScript, "function Show-TextInputDialog") {
		t.Fatalf("expected diagnostics tool script to provide a WinForms text-input dialog")
	}
	if !strings.Contains(diagnosticsToolScript, "try {\n  $script:savedReportPresets = Load-SavedReportPresets\n  Refresh-PresetComboBoxItems\n} catch {") {
		t.Fatalf("expected diagnostics tool script to guard preset initialization before ShowDialog")
	}
	if !strings.Contains(diagnosticsToolScript, "Local debugging") {
		t.Fatalf("expected diagnostics tool script to expose a local-debugging preset")
	}
	if !strings.Contains(diagnosticsToolScript, "Minimal share") {
		t.Fatalf("expected diagnostics tool script to expose a minimal-share preset")
	}
	if !strings.Contains(diagnosticsToolScript, "自定义") {
		t.Fatalf("expected diagnostics tool script to expose a custom preset state")
	}
	if !strings.Contains(diagnosticsToolScript, "Sync-ReportPresetSelection") {
		t.Fatalf("expected diagnostics tool script to resync the preset label after manual option changes")
	}
	if !strings.Contains(diagnosticsToolScript, "updatingPresetSelection") {
		t.Fatalf("expected diagnostics tool script to guard preset synchronization from recursive updates")
	}
	if !strings.Contains(diagnosticsToolScript, `$savePresetButton.Text = "保存"`) {
		t.Fatalf("expected diagnostics tool script to expose a save-preset action")
	}
	if !strings.Contains(diagnosticsToolScript, `$renamePresetButton.Text = "重命名"`) {
		t.Fatalf("expected diagnostics tool script to expose a rename-preset action")
	}
	if !strings.Contains(diagnosticsToolScript, `$deletePresetButton.Text = "删除"`) {
		t.Fatalf("expected diagnostics tool script to expose a delete-preset action")
	}
	if !strings.Contains(diagnosticsToolScript, `$exportPresetButton.Text = "导出"`) {
		t.Fatalf("expected diagnostics tool script to expose an export-preset action")
	}
	if !strings.Contains(diagnosticsToolScript, `$importPresetButton.Text = "导入"`) {
		t.Fatalf("expected diagnostics tool script to expose an import-preset action")
	}
	if !strings.Contains(diagnosticsToolScript, "导出诊断预设") {
		t.Fatalf("expected diagnostics tool script to guide exporting a preset to a user-side file")
	}
	if !strings.Contains(diagnosticsToolScript, "导入诊断预设") {
		t.Fatalf("expected diagnostics tool script to guide importing a preset from a user-side file")
	}
	if !strings.Contains(diagnosticsToolScript, "选择要导入的预设文件") {
		t.Fatalf("expected diagnostics tool script to show a file-picking dialog for importing presets")
	}
	if !strings.Contains(diagnosticsToolScript, "删除诊断预设") {
		t.Fatalf("expected diagnostics tool script to confirm deleting a saved preset")
	}
	if !strings.Contains(diagnosticsToolScript, "[已保存] ") {
		t.Fatalf("expected diagnostics tool script to label saved user presets distinctly")
	}
	if !strings.Contains(diagnosticsToolScript, "[内置] ") {
		t.Fatalf("expected diagnostics tool script to label built-in presets distinctly")
	}
	if !strings.Contains(diagnosticsToolScript, ".diagnostics_preset.json") {
		t.Fatalf("expected diagnostics tool script to export current presets to a dedicated file format")
	}
	if !strings.Contains(diagnosticsToolScript, "上下文窗口半径：") {
		t.Fatalf("expected diagnostics tool script to expose a context-window radius selector")
	}
	if !strings.Contains(diagnosticsToolScript, "10 行") || !strings.Contains(diagnosticsToolScript, "20 行") || !strings.Contains(diagnosticsToolScript, "40 行") {
		t.Fatalf("expected diagnostics tool script to expose concrete command-window radius choices")
	}
	if !strings.Contains(diagnosticsToolScript, "仅错误行") {
		t.Fatalf("expected diagnostics tool script to expose an error-only raw-log excerpt mode")
	}
	if !strings.Contains(diagnosticsToolScript, "最近命令窗口") {
		t.Fatalf("expected diagnostics tool script to expose a command-window raw-log excerpt mode")
	}
	if !strings.Contains(diagnosticsToolScript, "最近错误窗口") {
		t.Fatalf("expected diagnostics tool script to expose an error-window raw-log excerpt mode")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-EnvironmentSummaryLines") {
		t.Fatalf("expected diagnostics tool script to generate an environment summary section")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-LatestRecommendedActionLines") {
		t.Fatalf("expected diagnostics tool script to generate a recommended-actions section")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-RawLogExcerptLines") {
		t.Fatalf("expected diagnostics tool script to generate a raw-log excerpt section")
	}
	if !strings.Contains(diagnosticsToolScript, "Protect-SensitiveText") {
		t.Fatalf("expected diagnostics tool script to redact sensitive text in copied reports")
	}
	if !strings.Contains(diagnosticsToolScript, "Protect-ReportLines") {
		t.Fatalf("expected diagnostics tool script to redact report lines consistently")
	}
	if !strings.Contains(diagnosticsToolScript, "Convert-SectionLinesToMarkdown") {
		t.Fatalf("expected diagnostics tool script to normalize section formatting for copied reports")
	}
	if !strings.Contains(diagnosticsToolScript, "== Environment summary ==") {
		t.Fatalf("expected diagnostics tool script to define an environment summary section")
	}
	if !strings.Contains(diagnosticsToolScript, "== Raw log excerpt ==") {
		t.Fatalf("expected diagnostics tool script to define a raw log excerpt section")
	}
	if !strings.Contains(diagnosticsToolScript, "Anonymized: ") {
		t.Fatalf("expected diagnostics tool script to mark whether copied reports were anonymized")
	}
	if !strings.Contains(diagnosticsToolScript, "Anonymize mode: ") {
		t.Fatalf("expected diagnostics tool script to mark which anonymization mode was used")
	}
	if !strings.Contains(diagnosticsToolScript, "Keep drive letter: ") {
		t.Fatalf("expected diagnostics tool script to mark whether copied reports preserved drive letters")
	}
	if !strings.Contains(diagnosticsToolScript, "Excerpt mode") {
		t.Fatalf("expected diagnostics tool script to label which raw-log excerpt mode was used")
	}
	if !strings.Contains(diagnosticsToolScript, "\"tail\", \"errors\", \"command-window\", \"error-window\"") {
		t.Fatalf("expected diagnostics tool script to define the supported raw-log excerpt modes")
	}
	if !strings.Contains(diagnosticsToolScript, "\"full\", \"names-only\"") {
		t.Fatalf("expected diagnostics tool script to define the supported anonymization modes")
	}
	if !strings.Contains(diagnosticsToolScript, "<user>") {
		t.Fatalf("expected diagnostics tool script to replace usernames during anonymization")
	}
	if !strings.Contains(diagnosticsToolScript, "<path>") {
		t.Fatalf("expected diagnostics tool script to replace absolute paths during anonymization")
	}
	if !strings.Contains(diagnosticsToolScript, ":\\\\<path>") {
		t.Fatalf("expected diagnostics tool script to support keeping drive letters while redacting paths")
	}
	if !strings.Contains(diagnosticsToolScript, "ContextWindowRadius") {
		t.Fatalf("expected diagnostics tool script to parameterize context-window excerpt size")
	}
	if !strings.Contains(diagnosticsToolScript, "window around last command (") {
		t.Fatalf("expected diagnostics tool script to describe the selected command-window radius")
	}
	if !strings.Contains(diagnosticsToolScript, "window around last error-like line (") {
		t.Fatalf("expected diagnostics tool script to describe the selected error-window radius")
	}
	if !strings.Contains(diagnosticsToolScript, "== Findings ==") {
		t.Fatalf("expected diagnostics tool script to emit a findings section")
	}
	if !strings.Contains(diagnosticsToolScript, "== Settings chain ==") {
		t.Fatalf("expected diagnostics tool script to emit a dedicated settings-chain section")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-DiagnosticFindings") {
		t.Fatalf("expected diagnostics tool script to derive troubleshooting findings")
	}
	if !strings.Contains(diagnosticsToolScript, "== Log interpretation ==") {
		t.Fatalf("expected diagnostics tool script to emit a log interpretation section")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-LogInterpretation") {
		t.Fatalf("expected diagnostics tool script to derive log interpretation")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-CommandInterpretation") {
		t.Fatalf("expected diagnostics tool script to derive command-level interpretation")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-RecommendedActions") {
		t.Fatalf("expected diagnostics tool script to map log signals into recommended actions")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-CommandMeaning") {
		t.Fatalf("expected diagnostics tool script to translate command ids into user-facing meanings")
	}
	if !strings.Contains(diagnosticsToolScript, "Get-LineTimestamp") {
		t.Fatalf("expected diagnostics tool script to parse timestamps from recent log lines")
	}
	if !strings.Contains(diagnosticsToolScript, "Format-TimeGap") {
		t.Fatalf("expected diagnostics tool script to summarize time gaps between signals")
	}
	if !strings.Contains(diagnosticsToolScript, "method=onCommand|commandId=") {
		t.Fatalf("expected diagnostics tool script to inspect command-hit log patterns")
	}
	if !strings.Contains(diagnosticsToolScript, "commandId=(\\d+)") {
		t.Fatalf("expected diagnostics tool script to extract recent command ids")
	}
	if !strings.Contains(diagnosticsToolScript, "反查显示：音元拼音") {
		t.Fatalf("expected diagnostics tool script to map reverse-lookup command ids")
	}
	if !strings.Contains(diagnosticsToolScript, "候选项数：9") {
		t.Fatalf("expected diagnostics tool script to map candidate-count command ids")
	}
	if !strings.Contains(diagnosticsToolScript, "deploy|Redeploy|重新部署|部署") {
		t.Fatalf("expected diagnostics tool script to inspect deploy or reload log patterns")
	}
	if !strings.Contains(diagnosticsToolScript, "error|failed|timeout|unknown|错误|失败|hung|panic") {
		t.Fatalf("expected diagnostics tool script to inspect error-like log patterns")
	}
	if !strings.Contains(diagnosticsToolScript, "a recent command was seen, but no later deploy/reload timestamp was found") {
		t.Fatalf("expected diagnostics tool script to encode missing-post-command-deploy guidance")
	}
	if !strings.Contains(diagnosticsToolScript, "an error-like line appeared") {
		t.Fatalf("expected diagnostics tool script to encode post-command error timing guidance")
	}
	if !strings.Contains(diagnosticsToolScript, "命令到了但没看到 deploy/reload；先重试一次重新部署") {
		t.Fatalf("expected diagnostics tool script to recommend retrying deploy when commands arrive without deploy signals")
	}
	if !strings.Contains(diagnosticsToolScript, "最后一次部署早于最后一次命令；优先再做一次部署") {
		t.Fatalf("expected diagnostics tool script to recommend redeploy or restart when deploy lags behind the last command")
	}
	if !strings.Contains(diagnosticsToolScript, "先看最后一条 error-like line") {
		t.Fatalf("expected diagnostics tool script to recommend inspecting the last error-like line")
	}
	if !strings.Contains(diagnosticsToolScript, "PIMELauncher 在跑，但 server.exe 没在跑") {
		t.Fatalf("expected diagnostics tool script to encode launcher-vs-server guidance")
	}
	if !strings.Contains(diagnosticsToolScript, "安装里的二进制在，但 PIMELauncher 和 server 都没在跑") {
		t.Fatalf("expected diagnostics tool script to encode restart-needed guidance")
	}
	if !strings.Contains(diagnosticsToolScript, "tool-launcher.exe") {
		t.Fatalf("expected diagnostics tool script to inspect standalone tool launcher installation")
	}
	if !strings.Contains(diagnosticsToolScript, "yime_settings_state.json") {
		t.Fatalf("expected diagnostics tool script to inspect standalone settings state file")
	}
	if !strings.Contains(diagnosticsToolScript, "previously_selected_schema") || !strings.Contains(diagnosticsToolScript, "reverse_lookup_display_mode") || !strings.Contains(diagnosticsToolScript, "candidate_layout") {
		t.Fatalf("expected diagnostics tool script to surface key settings-chain values")
	}
	if !strings.Contains(diagnosticsToolScript, "onActivate only restores standalone reverse-lookup and layout preferences") {
		t.Fatalf("expected diagnostics tool script to explain that activation sync is limited to standalone UI preferences")
	}
}

func TestReverseLookupToolScriptProvidesStandaloneQueryShell(t *testing.T) {
	if !strings.Contains(reverseLookupToolScript, "Yime 反查编码") {
		t.Fatalf("expected reverse lookup tool script panel copy")
	}
	if !strings.Contains(reverseLookupToolScript, "Load-DictLookup") || !strings.Contains(reverseLookupToolScript, "yime_pinyin_codes.tsv") {
		t.Fatalf("expected reverse lookup tool script to load shared runtime data files")
	}
	if !strings.Contains(reverseLookupToolScript, "yime_user_phrases.txt") {
		t.Fatalf("expected reverse lookup tool script to consult the user phrase source file")
	}
	if !strings.Contains(reverseLookupToolScript, "Search-ReverseLookup") {
		t.Fatalf("expected reverse lookup tool script to centralize lookup queries")
	}
	if !strings.Contains(reverseLookupToolScript, "$form.Add_Shown({") || !strings.Contains(reverseLookupToolScript, "[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea") {
		t.Fatalf("expected reverse lookup tool script to restore a centered window when shown")
	}
	if !strings.Contains(reverseLookupToolScript, "$form.BeginInvoke([System.Windows.Forms.MethodInvoker]{") {
		t.Fatalf("expected reverse lookup tool script to defer data loading until after the window is shown")
	}
	if strings.Contains(reverseLookupToolScript, "$form.TopMost = $true") || strings.Contains(reverseLookupToolScript, "$form.Activate()") || strings.Contains(reverseLookupToolScript, "$form.BringToFront()") {
		t.Fatalf("expected reverse lookup tool script to avoid aggressive foreground forcing that can collapse the language bar")
	}
	if !strings.Contains(reverseLookupToolScript, "try {\n  [void]$form.ShowDialog()\n} catch {\n  Show-Error $_.Exception.Message\n}") {
		t.Fatalf("expected reverse lookup tool script to show dialog inside top-level try/catch")
	}
}

func TestBuildToolHubManifestProvidesExtensibleToolEntries(t *testing.T) {
	manifest := buildToolHubManifest(
		`C:\shared`,
		`C:\user`,
		`C:\help`,
		`C:\logs`,
		`C:\user\lexicon.ps1`,
		`C:\user\reverse_lookup.ps1`,
		`C:\user\settings.ps1`,
		`C:\user\diagnostics.ps1`,
		"variable",
	)
	if err := validateToolHubManifest(manifest); err != nil {
		t.Fatalf("expected valid tool hub manifest, got %v", err)
	}
	if manifest.Title != "Yime Tool Hub" {
		t.Fatalf("expected tool hub title, got %#v", manifest.Title)
	}
	if len(manifest.Tools) < 11 {
		t.Fatalf("expected framework-ready tool entries, got %#v", manifest.Tools)
	}
	required := map[string]bool{
		"lexicon-manager":      false,
		"reverse-lookup-tool":  false,
		"settings-tool":        false,
		"settings-data":       false,
		"shared-data":         false,
		"diagnostics-tool":    false,
		"diagnostics-guide":   false,
		"diagnostics-logs":    false,
		"settings-guide":      false,
		"help-readme":         false,
		"help-trial-feedback": false,
	}
	for _, tool := range manifest.Tools {
		if _, ok := required[tool.ID]; ok {
			required[tool.ID] = true
		}
		switch tool.ID {
		case "lexicon-manager", "reverse-lookup-tool", "settings-tool", "diagnostics-tool":
			if tool.ActionType != toolActionRunPowerShell {
				t.Fatalf("expected %s to launch the script directly, got %#v", tool.ID, tool)
			}
			switch tool.ID {
			case "lexicon-manager":
				if tool.TargetPath != `C:\user\lexicon.ps1` {
					t.Fatalf("expected lexicon-manager script path to be preserved, got %#v", tool)
				}
			case "reverse-lookup-tool":
				if tool.TargetPath != `C:\user\reverse_lookup.ps1` {
					t.Fatalf("expected reverse-lookup-tool script path to be preserved, got %#v", tool)
				}
			case "settings-tool":
				if tool.TargetPath != `C:\user\settings.ps1` {
					t.Fatalf("expected settings-tool script path to be preserved, got %#v", tool)
				}
			case "diagnostics-tool":
				if tool.TargetPath != `C:\user\diagnostics.ps1` {
					t.Fatalf("expected diagnostics-tool script path to be preserved, got %#v", tool)
				}
			}
			if len(tool.Arguments) == 0 || tool.Arguments[0] == "powershell-script" {
				t.Fatalf("expected %s direct script arguments without launcher shim, got %#v", tool.ID, tool.Arguments)
			}
			if !tool.CloseAfterLaunch {
				t.Fatalf("expected %s to close the tool hub after launch, got %#v", tool.ID, tool)
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
}

func TestToolHubScriptUsesShellExecuteForPowerShellChildren(t *testing.T) {
	if !strings.Contains(toolHubScript, "function Start-ShellExecuteProcess") {
		t.Fatalf("expected tool hub script to define a shell-execute launcher helper")
	}
	if !strings.Contains(toolHubScript, "$startInfo.UseShellExecute = $true") {
		t.Fatalf("expected tool hub script to use shell execute semantics for child launches")
	}
	if !strings.Contains(toolHubScript, `Start-ShellExecuteProcess -FilePath (Get-SystemPowerShellPath) -Arguments $arguments -WindowStyle Hidden`) {
		t.Fatalf("expected tool hub script to launch child PowerShell processes through the shell-execute helper")
	}
	if strings.Contains(toolHubScript, `Start-Process -FilePath "powershell.exe" -ArgumentList $argumentLine -WindowStyle Hidden`) {
		t.Fatalf("expected tool hub script not to use the old Start-Process PowerShell child launcher")
	}
	if !strings.Contains(toolHubScript, `"-WindowStyle",`) || !strings.Contains(toolHubScript, `"Hidden",`) {
		t.Fatalf("expected tool hub script to pass -WindowStyle Hidden to child PowerShell processes")
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

	if scheduled != 2 {
		t.Fatalf("expected both standalone-tool commands to be scheduled asynchronously, got %d", scheduled)
	}
	if runs != 0 {
		t.Fatalf("expected no standalone tool to launch synchronously inside onCommand, got %d immediate runs", runs)
	}
	if respLexicon.ShowCandidates || respToolHub.ShowCandidates {
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
	if rimePath := ime.rimeUserLexiconPath(); !strings.HasSuffix(rimePath, rimeUserLexiconFileName) {
		t.Fatalf("expected generated Rime lexicon path, got %q", rimePath)
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

	// The slimmed language bar must no longer expose a standalone reverse-lookup
	// button (now a 设置 submenu) or a 帮助 menu (now the 工具 button).
	for _, button := range resp.AddButton {
		if button.ID == "reverse-lookup" {
			t.Fatalf("expected reverse-lookup to move into the settings menu, still present as %#v", button)
		}
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
	for _, name := range []string{"lexicon.ico", "tools.ico"} {
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
		if button.ID == "lexicon-manager" || button.ID == "tools" {
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

	// reverse-lookup is no longer a top-level language-bar menu; it now lives as
	// a 显示编码 submenu inside 设置. Opening it as a button must be a no-op.
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
	payload := `{"reverse_lookup_display_mode":"standard_pinyin","candidate_layout":"horizontal"}`
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
	if ime.reverseLookupDisplayMode != "standard_pinyin" {
		t.Fatalf("expected standard_pinyin reverse lookup mode, got %q", ime.reverseLookupDisplayMode)
	}
	if ime.style.CandidatePerRow != horizontalCandidatesPerRow {
		t.Fatalf("expected horizontal candidate layout, got %d", ime.style.CandidatePerRow)
	}
	if !backend.horizontal {
		t.Fatal("expected backend horizontal option set from standalone settings")
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
