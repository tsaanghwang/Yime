//go:build windows

package yime

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/pime"
)

type realRimeTestSession struct {
	sessionID RimeSessionId
	userDir   string
}

func newRealRimeSession(t *testing.T) realRimeTestSession {
	t.Helper()

	dataDir := rimeRuntimeTestDataDir(t)
	userDir := filepath.Join(t.TempDir(), "Rime")
	writeRuntimeTestDefaultCustom(t, userDir)

	if !RimeInit(dataDir, userDir, APP, APP_VERSION, false) {
		t.Fatal("RimeInit failed")
	}

	sessionID, ok := StartSession()
	if !ok || sessionID == 0 {
		Finalize()
		t.Fatal("StartSession failed")
	}
	t.Cleanup(func() {
		EndSession(sessionID)
		Finalize()
	})
	if !SelectSchema(sessionID, "yime_variable") {
		t.Fatal("expected yime_variable schema to be selectable")
	}
	t.Logf("runtime test user dir: %s", userDir)
	t.Logf("ascii_mode before typing: %t", GetOption(sessionID, "ascii_mode"))
	t.Logf("full_shape before typing: %t", GetOption(sessionID, "full_shape"))
	SetOption(sessionID, "ascii_mode", false)
	t.Logf("ascii_mode after forcing off: %t", GetOption(sessionID, "ascii_mode"))
	return realRimeTestSession{sessionID: sessionID, userDir: userDir}
}

func writeRuntimeTestDefaultCustom(t *testing.T, userDir string) {
	t.Helper()
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("failed to create test Rime user dir: %v", err)
	}
	content := strings.Join([]string{
		"patch:",
		"  schema_list:",
		"    - schema: yime_variable",
		"    - schema: yime_full",
		"    - schema: yime_shorthand",
		"    - schema: luna_pinyin",
		"",
	}, "\n")
	if err := os.WriteFile(filepath.Join(userDir, "default.custom.yaml"), []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write test default.custom.yaml: %v", err)
	}
}

func rimeRuntimeTestDataDir(t *testing.T) string {
	t.Helper()
	if os.Getenv("YIME_RUN_REAL_RIME_TESTS") != "1" {
		t.Skip("set YIME_RUN_REAL_RIME_TESTS=1 to run real Rime integration tests")
	}
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("failed to locate rime runtime test directory")
	}
	return filepath.Join(filepath.Dir(filename), "data")
}

func TestRealRimeCanCommitText(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID

	// Every current Yime syllable starts with a real or virtual shouyin. The
	// older fds/rew smoke inputs started in the musical portion of a syllable;
	// table_translator used to offer arbitrary whole-table prefixes for them,
	// but they are not valid continuous Yime input prefixes.
	for _, input := range []string{"bj", "guew", `\lda`} {
		t.Run(input, func(t *testing.T) {
			ClearComposition(sessionID)
			for _, key := range []rune(input) {
				if !ProcessKey(sessionID, int(key), 0) {
					if composition, ok := GetComposition(sessionID); ok {
						t.Logf("composition after failed %q: %#v", key, composition)
					}
					if menu, ok := GetMenu(sessionID); ok {
						t.Logf("menu after failed %q: %#v", key, menu)
					}
					t.Fatalf("ProcessKey failed for %q", key)
				}
			}

			menu, ok := GetMenu(sessionID)
			if !ok || len(menu.Candidates) == 0 {
				t.Fatalf("expected candidates after %s, got %#v", input, menu)
			}
			t.Logf("candidates after %s: %#v", input, menu.Candidates)

			if !ProcessKey(sessionID, int(' '), 0) {
				t.Fatal("ProcessKey failed for space")
			}

			commit, ok := GetCommit(sessionID)
			if !ok {
				t.Fatal("expected commit after space")
			}
			t.Logf("commit text for %s: %q", input, commit.Text)

			if commit.Text == "" || commit.Text == input {
				t.Fatalf("expected converted text commit for %s, got %q", input, commit.Text)
			}
		})
	}
}

func TestRealRimeKeepsCandidatesWhileCompletingFinalSyllable(t *testing.T) {
	session := newRealRimeSession(t)
	prefixes := []string{
		`\lda1m,.]e`,
		`\lda1m,.]eg`,
		`\lda1m,.]egu`,
		`\lda1m,.]egue`,
		`\lda1m,.]eguew`,
		`\lda1m,.]eguew8`,
		`\lda1m,.]eguew8w`,
		`\lda1m,.]eguew8we`,
		`\lda1m,.]eguew8we;`,
	}
	for _, input := range prefixes {
		t.Run(input, func(t *testing.T) {
			ClearComposition(session.sessionID)
			typeASCII(t, session.sessionID, input)
			menu, ok := GetMenu(session.sessionID)
			if !ok || len(menu.Candidates) == 0 {
				t.Fatalf("continuous tail completion disappeared after %q: %#v", input, menu)
			}
			t.Logf("candidates after %q: %#v", input, menu.Candidates)
			keptSentencePrefix := false
			for _, candidate := range menu.Candidates {
				if strings.HasPrefix(candidate.Text, "\u8fde\u7eed\u7684") {
					keptSentencePrefix = true
					break
				}
			}
			if !keptSentencePrefix {
				t.Fatalf("tail completion lost the completed sentence prefix after %q: %#v", input, menu.Candidates)
			}
		})
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, `\lda1m,.]eguew8we;`)
	menu, ok := GetMenu(session.sessionID)
	if !ok {
		t.Fatal("expected final sentence candidates")
	}
	for _, candidate := range menu.Candidates {
		if candidate.Text == "\u8fde\u7eed\u7684\u8fc7\u7a0b" {
			return
		}
	}
	t.Fatalf("expected final sentence candidate, got %#v", menu.Candidates)
}

func TestRealRimeAllSchemasComposeSentence(t *testing.T) {
	session := newRealRimeSession(t)

	tests := []struct {
		schemaID string
		input    string
		want     string
	}{
		{schemaID: "yime_variable", input: "bjbj", want: "幅幅"},
		{schemaID: "yime_full", input: "bjjjbjjj", want: "幅幅"},
		{schemaID: "yime_shorthand", input: "bjbj", want: "幅幅"},
		{schemaID: "yime_variable", input: "bj'f", want: "幅啊"},
		{schemaID: "yime_full", input: "bjjj'fff", want: "幅啊"},
		{schemaID: "yime_shorthand", input: "bj'f", want: "幅啊"},
		// User-reported real layout sequence entered without a delimiter. It
		// includes the uppercase J symbol from the layout's Shift layer.
		{schemaID: "yime_variable", input: "]s8u\\e4fa7J9wo", want: "打出了三只手"},
	}
	for _, test := range tests {
		t.Run(test.schemaID+"/"+test.want, func(t *testing.T) {
			ClearComposition(session.sessionID)
			if !SelectSchema(session.sessionID, test.schemaID) {
				t.Fatalf("expected %s schema to be selectable", test.schemaID)
			}
			typeASCII(t, session.sessionID, test.input)
			menu, ok := GetMenu(session.sessionID)
			if !ok {
				t.Fatalf("expected sentence candidates after %q", test.input)
			}
			for _, candidate := range menu.Candidates {
				if candidate.Text == test.want {
					return
				}
			}
			t.Fatalf("expected generated sentence %s after %q, got %#v", test.want, test.input, menu.Candidates)
		})
	}
}

func TestRealRimeNavigatorCanMoveWithinSentenceComposition(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	before, ok := GetComposition(session.sessionID)
	if !ok || before.Preedit == "" {
		t.Fatalf("expected sentence composition before navigation, got %#v", before)
	}

	if !processRealKey(session.sessionID, &pime.Request{
		KeyCode:   vkLeft,
		KeyStates: keyStatesDown(vkControl),
	}) {
		t.Fatal("expected Ctrl+Left to be handled by Rime navigator")
	}
	after, ok := GetComposition(session.sessionID)
	if !ok || after.Preedit == "" {
		t.Fatalf("expected composition to survive navigation, got %#v", after)
	}
	if after.CursorPos >= before.CursorPos {
		t.Fatalf("expected Ctrl+Left to move the preedit cursor left, before=%#v after=%#v", before, after)
	}
	if menu, ok := GetMenu(session.sessionID); !ok || len(menu.Candidates) == 0 {
		t.Fatalf("expected candidates for the repositioned segment, got %#v", menu)
	}
}

func TestRealRimeNavigatorSelectionKeepsSentenceComposition(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	initialMenu, ok := GetMenu(session.sessionID)
	if !ok || len(initialMenu.Candidates) == 0 {
		t.Fatalf("expected initial sentence candidates, got %#v", initialMenu)
	}
	if !processRealKey(session.sessionID, &pime.Request{
		KeyCode:   vkLeft,
		KeyStates: keyStatesDown(vkControl),
	}) {
		t.Fatal("expected Ctrl+Left to be handled by Rime navigator")
	}

	menu, ok := GetMenu(session.sessionID)
	if !ok || len(menu.Candidates) < 2 {
		t.Fatalf("expected at least two candidates for the repositioned segment, got %#v", menu)
	}
	t.Logf("repositioned candidates: %#v", menu.Candidates)
	if !SelectCandidate(session.sessionID, 1) {
		t.Fatal("expected second candidate selection to be handled")
	}

	composition, compositionOK := GetComposition(session.sessionID)
	commit, committed := GetCommit(session.sessionID)
	menuAfter, menuOK := GetMenu(session.sessionID)
	t.Logf("after correction: composition=%#v menu=%#v commit=%#v committed=%t",
		composition, menuAfter, commit, committed)
	if !compositionOK || composition.Preedit == "" {
		t.Fatal("expected sentence composition to remain after correcting the earlier segment")
	}
	if committed {
		t.Fatalf("segment correction must not commit the whole sentence, got %#v", commit)
	}
	if !menuOK || len(menuAfter.Candidates) == 0 {
		t.Fatalf("expected candidates for the preserved sentence tail, got %#v", menuAfter)
	}

	correctedPrefix := menu.Candidates[1].Text
	selectedTail := menuAfter.Candidates[0].Text
	if !SelectCandidate(session.sessionID, 0) {
		t.Fatal("expected preserved tail candidate selection to be handled")
	}
	finalCommit, ok := GetCommit(session.sessionID)
	if !ok {
		t.Fatal("expected final segment selection to commit the corrected sentence")
	}
	if want := correctedPrefix + selectedTail; finalCommit.Text != want {
		t.Fatalf("expected corrected sentence commit %q, got %#v", want, finalCommit)
	}

	typeASCII(t, session.sessionID, "bjjjbjjj")
	learnedMenu, ok := GetMenu(session.sessionID)
	if !ok {
		t.Fatal("expected candidates after retyping the corrected sentence input")
	}
	initialRank := -1
	for index, candidate := range initialMenu.Candidates {
		if candidate.Text == finalCommit.Text {
			initialRank = index
			break
		}
	}
	learnedRank := -1
	for index, candidate := range learnedMenu.Candidates {
		if candidate.Text == finalCommit.Text {
			learnedRank = index
			break
		}
	}
	if learnedRank < 0 {
		t.Fatalf("expected corrected sentence %q to remain available after learning, got %#v",
			finalCommit.Text, learnedMenu.Candidates)
	}
	if initialRank >= 0 && learnedRank >= initialRank {
		t.Fatalf("expected correction learning to improve %q from rank %d, got rank %d",
			finalCommit.Text, initialRank, learnedRank)
	}
}

func TestRealRimePrintableLayoutKeysAreNeverPagingBindings(t *testing.T) {
	session := newRealRimeSession(t)
	for _, key := range []rune{'-', '=', ',', '.', '/'} {
		t.Run(string(key), func(t *testing.T) {
			ClearComposition(session.sessionID)
			typeASCII(t, session.sessionID, "3")
			// Put the menu on a later page when possible. The printable key must
			// still go to the speller instead of becoming PageUp/PageDown.
			_ = processRealKey(session.sessionID, &pime.Request{KeyCode: vkNext})
			if !ProcessKey(session.sessionID, int(key), 0) {
				t.Fatalf("printable layout key %q was not handled", key)
			}
			composition, ok := GetComposition(session.sessionID)
			if !ok || !strings.HasSuffix(composition.Preedit, string(key)) {
				t.Fatalf("printable layout key %q did not enter composition: %#v", key, composition)
			}
		})
	}
}

func TestRealRimeCanSelectYimeShorthandSchema(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID
	schemaPath := prepareRuntimeTestUserSchema(t, session.userDir, "yime_shorthand")

	if !deploySchemaConfig(schemaPath) {
		t.Fatalf("expected yime_shorthand schema deploy to succeed: %s", schemaPath)
	}

	if !SelectSchema(sessionID, "yime_shorthand") {
		t.Fatal("expected yime_shorthand schema to be selectable")
	}
	if schemaID, ok := GetCurrentSchema(sessionID); !ok || schemaID != "yime_shorthand" {
		t.Fatalf("expected current schema yime_shorthand, got %q ok=%t", schemaID, ok)
	}

	typeASCII(t, sessionID, "bj")
	menu, ok := GetMenu(sessionID)
	if !ok || len(menu.Candidates) == 0 {
		t.Fatalf("expected shorthand candidates after bj, got %#v", menu)
	}
}

func prepareRuntimeTestUserSchema(t *testing.T, userDir, schemaID string) string {
	t.Helper()
	sharedPath := filepath.Join(rimeRuntimeTestDataDir(t), schemaID+".schema.yaml")
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("failed to create user Rime directory: %v", err)
	}
	content, err := os.ReadFile(sharedPath)
	if err != nil {
		t.Fatalf("failed to read schema: %v", err)
	}
	userPath := filepath.Join(userDir, schemaID+".schema.yaml")
	if err := os.WriteFile(userPath, content, 0o644); err != nil {
		t.Fatalf("failed to write user schema: %v", err)
	}
	return userPath
}

func TestRealRimeControlShortcuts(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID

	tests := []struct {
		name string
		req  *pime.Request
	}{
		{
			name: "ctrl+a",
			req: &pime.Request{
				KeyCode:   'A',
				CharCode:  1,
				KeyStates: keyStatesDown(vkControl),
			},
		},
		{
			name: "ctrl+grave",
			req: &pime.Request{
				KeyCode:   0xC0,
				CharCode:  '`',
				KeyStates: keyStatesDown(vkControl),
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ClearComposition(sessionID)

			translatedKey := translateKeyCode(tc.req)
			modifiers := translateModifiers(tc.req, false)
			handled := ProcessKey(sessionID, translatedKey, modifiers)

			t.Logf("request: keyCode=%d charCode=%d translatedKey=%d modifiers=%d handled=%t",
				tc.req.KeyCode, tc.req.CharCode, translatedKey, modifiers, handled)

			if composition, ok := GetComposition(sessionID); ok {
				t.Logf("composition: %#v", composition)
			} else {
				t.Log("composition: <none>")
			}

			if menu, ok := GetMenu(sessionID); ok {
				t.Logf("menu: %#v", menu)
			} else {
				t.Log("menu: <none>")
			}

			if commit, ok := GetCommit(sessionID); ok {
				t.Logf("commit: %#v", commit)
			} else {
				t.Log("commit: <none>")
			}
		})
	}
}

func TestRealRimeBackspaceUpdatesComposition(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID
	ClearComposition(sessionID)

	typeASCII(t, sessionID, "bj")
	before, ok := GetComposition(sessionID)
	if !ok || before.Preedit == "" {
		t.Fatalf("expected composition before backspace, got %#v", before)
	}

	handled := processRealKey(sessionID, &pime.Request{KeyCode: vkBack})
	after, ok := GetComposition(sessionID)
	if !handled {
		t.Fatal("expected backspace to be handled")
	}
	if !ok || after.Preedit == "" {
		t.Fatalf("expected composition to remain after backspace, got %#v", after)
	}
	if len([]rune(after.Preedit)) >= len([]rune(before.Preedit)) {
		t.Fatalf("expected shorter composition after backspace, before=%q after=%q", before.Preedit, after.Preedit)
	}
	if menu, ok := GetMenu(sessionID); !ok || len(menu.Candidates) == 0 {
		t.Fatalf("expected candidates to remain after backspace, got %#v", menu)
	}
}

func TestRealRimeEscapeClearsComposition(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID
	ClearComposition(sessionID)

	typeASCII(t, sessionID, "bj")
	if composition, ok := GetComposition(sessionID); !ok || composition.Preedit == "" {
		t.Fatalf("expected composition before escape, got %#v", composition)
	}

	handled := processRealKey(sessionID, &pime.Request{KeyCode: vkEscape})
	composition, compositionOK := GetComposition(sessionID)
	menu, menuOK := GetMenu(sessionID)
	if !handled {
		t.Fatal("expected escape to be handled")
	}
	if !compositionOK || composition.Preedit != "" {
		t.Fatalf("expected escape to clear composition, got %#v", composition)
	}
	if menuOK && len(menu.Candidates) != 0 {
		t.Fatalf("expected escape to clear candidates, got %#v", menu)
	}
}

func TestRealRimePunctuationKeys(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID

	tests := []struct {
		name          string
		req           *pime.Request
		allowedCommit []string
	}{
		{
			name: "grave",
			req: &pime.Request{
				KeyCode:  0xC0,
				CharCode: '`',
			},
			allowedCommit: []string{"、", "`", "｀"},
		},
		{
			name: "pipe",
			req: &pime.Request{
				KeyCode:  0xDC,
				CharCode: '|',
			},
			allowedCommit: []string{"|", "·", "｜"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ClearComposition(sessionID)

			handled := processRealKey(sessionID, tc.req)
			commit, commitOK := GetCommit(sessionID)
			composition, compositionOK := GetComposition(sessionID)
			menu, menuOK := GetMenu(sessionID)

			t.Logf("request=%s handled=%t commit=%#v composition=%#v menu=%#v", tc.name, handled, commit, composition, menu)

			if !handled {
				t.Fatalf("expected %s key to be handled", tc.name)
			}
			if commitOK && commit.Text != "" {
				if !containsAny(tc.allowedCommit, commit.Text) {
					t.Fatalf("unexpected commit for %s: %q", tc.name, commit.Text)
				}
				return
			}
			if compositionOK && composition.Preedit != "" {
				return
			}
			if menuOK && len(menu.Candidates) > 0 {
				return
			}
			t.Fatalf("expected %s key to produce visible output", tc.name)
		})
	}
}

func TestRealRimeAcceptsNewLayoutPunctuationAndShiftCodes(t *testing.T) {
	session := newRealRimeSession(t)
	sessionID := session.sessionID
	if !SelectSchema(sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	tests := []struct {
		name string
		keys []*pime.Request
	}{
		{"minus shouyin", []*pime.Request{{KeyCode: 0xBD, CharCode: '-'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'J', CharCode: 'j'}}},
		{"equals shouyin", []*pime.Request{{KeyCode: 0xBB, CharCode: '='}, {KeyCode: 'U', CharCode: 'u'}, {KeyCode: 'U', CharCode: 'u'}, {KeyCode: 'U', CharCode: 'u'}}},
		{"backslash shouyin", []*pime.Request{{KeyCode: 0xDC, CharCode: '\\'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'J', CharCode: 'j'}}},
		{"shift comma musical", []*pime.Request{{KeyCode: 'H', CharCode: 'h'}, {KeyCode: 0xBC, CharCode: '<', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 0xBC, CharCode: '<', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 0xBC, CharCode: '<', KeyStates: keyStatesDown(vkShift)}}},
		{"shift letter and punctuation musical", []*pime.Request{{KeyCode: 0xDE, CharCode: '\''}, {KeyCode: 'M', CharCode: 'M', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 0xBC, CharCode: '<', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 0xBE, CharCode: '>', KeyStates: keyStatesDown(vkShift)}}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ClearComposition(sessionID)
			for _, req := range test.keys {
				if !processRealKey(sessionID, req) {
					t.Fatalf("expected key %q to be handled", rune(req.CharCode))
				}
			}
			if menu, ok := GetMenu(sessionID); !ok || len(menu.Candidates) == 0 {
				t.Fatalf("expected candidates, got %#v", menu)
			}
		})
	}
}

func keyStatesDown(codes ...int) pime.KeyStates {
	states := make(pime.KeyStates, 256)
	for _, code := range codes {
		if code >= 0 && code < len(states) {
			states[code] = 1 << 7
		}
	}
	return states
}

func processRealKey(sessionID RimeSessionId, req *pime.Request) bool {
	return ProcessKey(sessionID, translateKeyCode(req), translateModifiers(req, false))
}

func typeASCII(t *testing.T, sessionID RimeSessionId, input string) {
	t.Helper()
	for _, key := range input {
		if !ProcessKey(sessionID, int(key), 0) {
			t.Fatalf("ProcessKey failed for %q", key)
		}
	}
}

func rimeMenuAfterASCII(t *testing.T, sessionID RimeSessionId, input string) (RimeMenu, bool) {
	t.Helper()
	ClearComposition(sessionID)
	typeASCII(t, sessionID, input)
	return GetMenu(sessionID)
}

func rimeProbeInputWithMinCandidates(t *testing.T, sessionID RimeSessionId, min int) (string, RimeMenu) {
	t.Helper()
	for _, input := range []string{"bj", "fds", "rew", "'sdf", "jkl"} {
		menu, ok := rimeMenuAfterASCII(t, sessionID, input)
		if ok && len(menu.Candidates) >= min {
			return input, menu
		}
	}
	t.Skipf("bundled dictionary has no input with at least %d candidates", min)
	return "", RimeMenu{}
}

func writeUserSchemaWithPageSize(t *testing.T, dataDir, userDir, schemaID string, size int) string {
	t.Helper()
	sharedPath := filepath.Join(dataDir, schemaID+".schema.yaml")
	content, err := os.ReadFile(sharedPath)
	if err != nil {
		t.Fatalf("failed to read shared schema: %v", err)
	}
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		t.Fatalf("failed to create user Rime dir: %v", err)
	}
	userPath := filepath.Join(userDir, schemaID+".schema.yaml")
	updated := updateSchemaMenuPageSize(string(content), size)
	if err := os.WriteFile(userPath, []byte(updated), 0o644); err != nil {
		t.Fatalf("failed to write user schema: %v", err)
	}
	return userPath
}

// TestRealRimeRedeployAppliesPageSize guards the fix for the "候选窗体" page size
// setting: writing menu/page_size into the schema and calling RimeRedeploy must
// invalidate librime's cached config so the new page size takes effect. A plain
// per-file deploy without redeploy leaves the running engine on the stale value.
func TestRealRimeRedeployAppliesPageSize(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	userDir := filepath.Join(t.TempDir(), "Rime")
	writeRuntimeTestDefaultCustom(t, userDir)

	if !RimeInit(dataDir, userDir, APP, APP_VERSION, false) {
		t.Fatal("RimeInit failed")
	}
	defer Finalize()

	baseline, ok := StartSession()
	if !ok || baseline == 0 {
		t.Fatal("StartSession failed")
	}
	if !SelectSchema(baseline, "yime_variable") {
		t.Fatal("expected yime_variable schema to be selectable")
	}
	SetOption(baseline, "ascii_mode", false)
	const input = "bj"
	typeASCII(t, baseline, input)
	baselineMenu, gotBaselineMenu := GetMenu(baseline)
	if !gotBaselineMenu {
		t.Fatal("expected baseline menu")
	}
	t.Logf("baseline input=%q page size=%d candidates=%d", input, baselineMenu.PageSize, len(baselineMenu.Candidates))
	EndSession(baseline)

	const wantPageSize = 8
	userSchemaPath := writeUserSchemaWithPageSize(t, dataDir, userDir, "yime_variable", wantPageSize)
	if !deploySchemaConfig(userSchemaPath) {
		t.Fatalf("expected user schema deploy to succeed: %s", userSchemaPath)
	}
	if !RimeRedeploy() {
		t.Fatal("RimeRedeploy failed")
	}

	sessionID, ok := StartSession()
	if !ok || sessionID == 0 {
		t.Fatal("StartSession after redeploy failed")
	}
	defer EndSession(sessionID)
	if !SelectSchema(sessionID, "yime_variable") {
		t.Fatal("expected yime_variable schema to be selectable after redeploy")
	}
	SetOption(sessionID, "ascii_mode", false)
	typeASCII(t, sessionID, input)
	menu, gotMenu := GetMenu(sessionID)
	if !gotMenu {
		t.Fatal("expected menu after redeploy")
	}
	t.Logf("after redeploy input=%q page size=%d candidates=%d", input, menu.PageSize, len(menu.Candidates))
	if menu.PageSize != wantPageSize {
		t.Fatalf("expected page size %d after redeploy, got %d", wantPageSize, menu.PageSize)
	}
	if len(menu.Candidates) > wantPageSize {
		t.Fatalf("expected at most %d visible candidates, got %d", wantPageSize, len(menu.Candidates))
	}
}

// TestRealRimeExternalBuildAppliesPageSize guards the safe page-size path used
// by language-bar clicks: rebuild config outside the current process, then
// recreate the Rime session so librime picks up the new menu.page_size without
// an in-callback RimeRedeploy.
func TestRealRimeExternalBuildAppliesPageSize(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	userDir := filepath.Join(t.TempDir(), "Rime")
	writeRuntimeTestDefaultCustom(t, userDir)

	if !RimeInit(dataDir, userDir, APP, APP_VERSION, false) {
		t.Fatal("RimeInit failed")
	}
	defer Finalize()

	baseline, ok := StartSession()
	if !ok || baseline == 0 {
		t.Fatal("StartSession failed")
	}
	if !SelectSchema(baseline, "yime_variable") {
		t.Fatal("expected yime_variable schema to be selectable")
	}
	SetOption(baseline, "ascii_mode", false)
	const input = "bj"
	typeASCII(t, baseline, input)
	baselineMenu, gotBaselineMenu := GetMenu(baseline)
	if !gotBaselineMenu {
		t.Fatal("expected baseline menu")
	}
	t.Logf("baseline input=%q page size=%d candidates=%d", input, baselineMenu.PageSize, len(baselineMenu.Candidates))
	EndSession(baseline)

	const wantPageSize = 8
	userSchemaPath := writeUserSchemaWithPageSize(t, dataDir, userDir, "yime_variable", wantPageSize)
	if !deploySchemaConfig(userSchemaPath) {
		t.Fatalf("expected user schema deploy to succeed: %s", userSchemaPath)
	}

	deployerPath := findRimeExternalDeployer(dataDir)
	if deployerPath == "" {
		t.Skip("external rime_deployer not available")
	}
	cmd := exec.Command(deployerPath, "--build", userDir, dataDir, filepath.Join(userDir, "build"))
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("external rime_deployer build failed: %v\n%s", err, out)
	} else {
		t.Logf("external build output: %s", strings.TrimSpace(string(out)))
	}

	sessionID, ok := StartSession()
	if !ok || sessionID == 0 {
		t.Fatal("StartSession after external build failed")
	}
	defer EndSession(sessionID)
	if !SelectSchema(sessionID, "yime_variable") {
		t.Fatal("expected yime_variable schema to be selectable after external build")
	}
	SetOption(sessionID, "ascii_mode", false)
	typeASCII(t, sessionID, input)
	menu, gotMenu := GetMenu(sessionID)
	if !gotMenu {
		t.Fatal("expected menu after external build")
	}
	t.Logf("after external build input=%q page size=%d candidates=%d", input, menu.PageSize, len(menu.Candidates))
	if menu.PageSize != wantPageSize {
		t.Fatalf("expected page size %d after external build, got %d", wantPageSize, menu.PageSize)
	}
	if len(menu.Candidates) > wantPageSize {
		t.Fatalf("expected at most %d visible candidates after external build, got %d", wantPageSize, len(menu.Candidates))
	}
}

func containsAny(candidates []string, got string) bool {
	for _, candidate := range candidates {
		if strings.Contains(got, candidate) {
			return true
		}
	}
	return false
}
