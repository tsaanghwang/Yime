//go:build windows

package yime

import (
	"encoding/csv"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/settings"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
	"github.com/tsaanghwang/Yime/go-backend/pime"
)

type realRimeTestSession struct {
	sessionID RimeSessionId
	userDir   string
}

// rawCompositionRuntimeBackend keeps the direct typeASCII test fixture from
// consuming a delayed commit before the click. Production consumes commits
// after every key response; the fixture types the whole probe before asking
// for state.
type rawCompositionRuntimeBackend struct {
	*nativeBackend
	caretCalls  []int
	caretResult bool
}

func (b *rawCompositionRuntimeBackend) SetCompositionCaret(rawPosition int) bool {
	b.caretCalls = append(b.caretCalls, rawPosition)
	b.caretResult = SetRawCaretPos(b.sessionID, rawPosition)
	return b.caretResult
}

func (b *rawCompositionRuntimeBackend) State() rimeState {
	state := rimeState{}
	if composition, ok := GetComposition(b.sessionID); ok {
		state.Composition = composition.Preedit
		state.CompositionPreview = composition.CommitTextPreview
		state.CursorPos = utf8ByteOffsetToRuneIndex(
			composition.Preedit, composition.CursorPos)
		state.SelStart = utf8ByteOffsetToRuneIndex(
			composition.Preedit, composition.SelStart)
		state.SelEnd = utf8ByteOffsetToRuneIndex(
			composition.Preedit, composition.SelEnd)
	}
	if menu, ok := GetMenu(b.sessionID); ok {
		for _, candidate := range menu.Candidates {
			state.Candidates = append(state.Candidates, candidateItem{
				Text: candidate.Text, Comment: candidate.Comment,
			})
		}
		state.CandidateCursor = menu.HighlightedCandidateIndex
		state.SelectKeys = menu.SelectKeys
		state.PageSize = menu.PageSize
	}
	return state
}

func newRealRimeSession(t *testing.T) realRimeTestSession {
	return newRealRimeSessionWithManagedRefresh(t, false)
}

func newRealRimeSessionWithManagedRefresh(t *testing.T, refresh bool) realRimeTestSession {
	t.Helper()

	dataDir := rimeRuntimeTestDataDir(t)
	userDir := filepath.Join(t.TempDir(), "Rime")
	writeRuntimeTestDefaultCustom(t, userDir)
	if refresh {
		if _, err := userlexicon.RefreshRimeData(dataDir, userDir); err != nil {
			t.Fatalf("refresh managed Rime data: %v", err)
		}
	}

	if !RimeInit(dataDir, userDir, APP, APP_VERSION, refresh) {
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

func TestRealRimeNeutralToneEntryAcrossAllThreeSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	codeMap, err := reverselookup.LoadSharedCodeMap(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	session := newRealRimeSession(t)
	for _, test := range []struct {
		schema string
		mode   reverselookup.Mode
	}{
		{"yime_variable", reverselookup.ModeVariable},
		{"yime_full", reverselookup.ModeFull},
		{"yime_shorthand", reverselookup.ModeShorthand},
	} {
		t.Run(test.schema, func(t *testing.T) {
			if !SelectSchema(session.sessionID, test.schema) {
				t.Fatalf("expected %s to be selectable", test.schema)
			}
			ClearComposition(session.sessionID)
			code, _, err := reverselookup.EncodeNumericTonePinyin(codeMap, "zhuo1 zi5", test.mode)
			if err != nil {
				t.Fatal(err)
			}
			for _, key := range code {
				if !ProcessKey(session.sessionID, int(key), 0) {
					t.Fatalf("ProcessKey failed for %q in %s", key, test.schema)
				}
			}
			menu, ok := GetMenu(session.sessionID)
			if !ok {
				t.Fatalf("expected menu for %s after %q", test.schema, code)
			}
			found := false
			for _, candidate := range menu.Candidates {
				if candidate.Text == "桌子" {
					found = true
					break
				}
			}
			if !found {
				t.Fatalf("neutral-tone candidate 桌子 missing in %s after %q: %#v", test.schema, code, menu.Candidates)
			}
		})
	}
}

func TestRealRimeDedicatedHRenderedInitialAcrossAllThreeSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	codeMap, err := reverselookup.LoadSharedCodeMap(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	session := newRealRimeSession(t)
	for _, test := range []struct {
		schema string
		mode   reverselookup.Mode
	}{
		{"yime_variable", reverselookup.ModeVariable},
		{"yime_full", reverselookup.ModeFull},
		{"yime_shorthand", reverselookup.ModeShorthand},
	} {
		t.Run(test.schema, func(t *testing.T) {
			if !SelectSchema(session.sessionID, test.schema) {
				t.Fatalf("expected %s to be selectable", test.schema)
			}
			code, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, "yu3 yan2", test.mode)
			if encodeErr != nil {
				t.Fatal(encodeErr)
			}
			if !strings.HasPrefix(code, "`") {
				t.Fatalf("yu3 must retain N25 backtick in %s, got %q", test.schema, code)
			}
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, code, "语言"); !found {
				t.Fatalf("candidate 语言 missing in %s after %q", test.schema, code)
			}
		})
	}
}

func TestRealRimeExplicitErhuaMixedRoutesAcrossAllThreeSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	session := newRealRimeSessionWithManagedRefresh(t, true)
	for _, mode := range []string{"variable", "full", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			schema := "yime_" + mode
			if !SelectSchema(session.sessionID, schema) {
				t.Fatalf("expected %s to be selectable", schema)
			}
			entries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_erhua_mixed_"+mode+".dict.yaml"))
			codes := []string{}
			for _, entry := range entries {
				if entry.Text == "一阵儿" {
					codes = append(codes, entry.Code)
				}
			}
			if len(codes) != 2 || codes[0] == codes[1] {
				t.Fatalf("%s must expose distinct suffix and fused routes for 一阵儿: %v", mode, codes)
			}
			for _, code := range codes {
				if _, found := findRealRimeCandidate(t, session.sessionID, code, "一阵儿"); !found {
					t.Fatalf("explicit-erhua candidate 一阵儿 missing in %s after %q", schema, code)
				}
			}

			sentenceEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_erhua_mixed_sentence_"+mode+".dict.yaml"))
			fusedSentenceCodes := map[string]string{}
			for _, entry := range sentenceEntries {
				if entry.Text == "大婶儿" || entry.Text == "打转儿" {
					fusedSentenceCodes[entry.Text] = strings.ReplaceAll(entry.Code, " ", "")
				}
			}
			if fusedSentenceCodes["大婶儿"] == "" || fusedSentenceCodes["打转儿"] == "" {
				t.Fatalf("%s lacks sentence spellings for 大婶儿/打转儿: %v", mode, fusedSentenceCodes)
			}
			continuousCode := fusedSentenceCodes["大婶儿"] + fusedSentenceCodes["打转儿"]
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, continuousCode, "大婶儿打转儿"); !found {
				t.Fatalf("explicit-erhua sentence 大婶儿打转儿 missing in %s after %q", schema, continuousCode)
			}
			coreEntriesForSentence := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"))
			workCode := ""
			for _, entry := range coreEntriesForSentence {
				if entry.Text == "工作" {
					workCode = strings.ReplaceAll(entry.Code, " ", "")
					break
				}
			}
			if workCode == "" {
				t.Fatalf("%s lacks core code for 工作", mode)
			}
			mixedCode := fusedSentenceCodes["大婶儿"] + workCode
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, mixedCode, "大婶儿工作"); !found {
				t.Fatalf("mixed sentence 大婶儿工作 missing in %s after %q", schema, mixedCode)
			}

			coreSentenceCodes := map[string]string{}
			for _, entry := range coreEntriesForSentence {
				if entry.Text == "石头" || entry.Text == "滚动" || entry.Text == "表演" || entry.Text == "选手" {
					coreSentenceCodes[entry.Text] = strings.ReplaceAll(entry.Code, " ", "")
				}
			}
			if coreSentenceCodes["石头"] == "" || coreSentenceCodes["滚动"] == "" {
				t.Fatalf("%s lacks core lexical-neutral sentence inputs: %v", mode, coreSentenceCodes)
			}
			neutralContinuousCode := coreSentenceCodes["石头"] + coreSentenceCodes["滚动"]
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, neutralContinuousCode, "石头滚动"); !found {
				t.Fatalf("lexical-neutral sentence 石头滚动 missing in %s after %q", schema, neutralContinuousCode)
			}

			pscSentenceEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_psc_peripheral_sentence_"+mode+".dict.yaml"))
			pscNeutralCode := ""
			for _, entry := range pscSentenceEntries {
				if entry.Text == "商量" {
					pscNeutralCode = strings.ReplaceAll(entry.Code, " ", "")
					break
				}
			}
			if pscNeutralCode == "" {
				t.Fatalf("%s lacks reviewed PSC neutral-tone sentence spelling for 商量", mode)
			}
			pscNeutralContinuousCode := pscNeutralCode + workCode
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, pscNeutralContinuousCode, "商量工作"); !found {
				t.Fatalf("reviewed PSC neutral-tone sentence 商量工作 missing in %s after %q", schema, pscNeutralContinuousCode)
			}

			thirdToneEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_third_tone_stage5c_"+mode+".dict.yaml"))
			thirdToneCodes := map[string]string{}
			for _, entry := range thirdToneEntries {
				if entry.Text == "表演" || entry.Text == "选手" {
					thirdToneCodes[entry.Text] = strings.ReplaceAll(entry.Code, " ", "")
				}
			}
			for _, text := range []string{"表演", "选手"} {
				if thirdToneCodes[text] == "" {
					t.Fatalf("%s lacks reviewed third-tone surface code for %s", mode, text)
				}
				if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, thirdToneCodes[text], text); !found {
					t.Fatalf("reviewed third-tone candidate %s missing in %s after %q", text, schema, thirdToneCodes[text])
				}
				if coreSentenceCodes[text] == "" || coreSentenceCodes[text] == thirdToneCodes[text] {
					t.Fatalf("%s must preserve a distinct canonical code for %s", mode, text)
				}
				if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, coreSentenceCodes[text], text); !found {
					t.Fatalf("canonical third-tone candidate %s missing in %s after %q", text, schema, coreSentenceCodes[text])
				}
			}
			thirdToneContinuousCode := thirdToneCodes["表演"] + workCode
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, thirdToneContinuousCode, "表演工作"); !found {
				t.Fatalf("reviewed third-tone sentence 表演工作 missing in %s after %q", schema, thirdToneContinuousCode)
			}

			// 刀刃儿 is absent from the curated core: its suffix-compatible
			// route stays in the PSC low-frequency layer while the explicit
			// erhua overlay contributes only the fused route.
			fusedCode := ""
			for _, entry := range entries {
				if entry.Text == "刀刃儿" {
					fusedCode = entry.Code
					break
				}
			}
			pscEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_psc_peripheral_"+mode+".dict.yaml"))
			suffixCode := ""
			for _, entry := range pscEntries {
				if entry.Text == "刀刃儿" {
					suffixCode = entry.Code
					break
				}
			}
			if fusedCode == "" || suffixCode == "" || fusedCode == suffixCode {
				t.Fatalf("%s must expose split low-frequency suffix/fused routes for 刀刃儿: suffix=%q fused=%q", mode, suffixCode, fusedCode)
			}
			for _, code := range []string{suffixCode, fusedCode} {
				if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, code, "刀刃儿"); !found {
					t.Fatalf("explicit low-frequency erhua candidate 刀刃儿 missing in %s after %q", schema, code)
				}
			}

			// 所有专用派生音元均使用明确登记的 Shift 层键；Rime
			// 必须保留大写键，不能折叠为基础音元。
			for _, trial := range []struct {
				text      string
				shiftKeys string
			}{
				{text: "好玩儿", shiftKeys: "FD"},
				{text: "单个儿", shiftKeys: "EW"},
				{text: "香肠儿", shiftKeys: "TY"},
				{text: "人影儿", shiftKeys: "X"},
				{text: "加油儿", shiftKeys: "P"},
				{text: "小鞋儿", shiftKeys: "UI"},
				{text: "雨点儿", shiftKeys: "S"},
				{text: "火锅儿", shiftKeys: "R"},
				{text: "红包儿", shiftKeys: "FP"},
				{text: "衣兜儿", shiftKeys: "RP"},
				{text: "泪珠儿", shiftKeys: "P"},
			} {
				shiftCode := ""
				for _, entry := range entries {
					if entry.Text == trial.text && strings.ContainsAny(entry.Code, trial.shiftKeys) {
						shiftCode = entry.Code
						break
					}
				}
				if shiftCode == "" {
					t.Fatalf("%s overlay lacks dedicated Shift-layer fused code for %s", mode, trial.text)
				}
				if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, shiftCode, trial.text); !found {
					t.Fatalf("Shift-layer erhua candidate %s missing in %s after %q", trial.text, schema, shiftCode)
				}
			}
		})
	}
}

func TestRealRimeParticleAStage6DDualTrackAcrossAllThreeSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	session := newRealRimeSessionWithManagedRefresh(t, true)
	for _, mode := range []string{"variable", "full", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			schema := "yime_" + mode
			if !SelectSchema(session.sessionID, schema) {
				t.Fatalf("expected %s to be selectable", schema)
			}
			particleAEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_particle_a_stage6d_"+mode+".dict.yaml"))
			coreEntries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_"+mode+".dict.yaml"))
			for _, text := range []string{"样子啊", "走啊走"} {
				particleASurfaceCode, particleACanonicalCode := "", ""
				for _, entry := range particleAEntries {
					if entry.Text == text {
						particleASurfaceCode = strings.ReplaceAll(entry.Code, " ", "")
						break
					}
				}
				for _, entry := range coreEntries {
					if entry.Text == text {
						particleACanonicalCode = strings.ReplaceAll(entry.Code, " ", "")
						break
					}
				}
				if particleASurfaceCode == "" || particleACanonicalCode == "" || particleASurfaceCode == particleACanonicalCode {
					t.Fatalf("%s must expose distinct particle-a surface/canonical routes for %s: surface=%q canonical=%q", mode, text, particleASurfaceCode, particleACanonicalCode)
				}
				for _, code := range []string{particleASurfaceCode, particleACanonicalCode} {
					if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, code, text); !found {
						t.Fatalf("particle-a dual-track candidate %s missing in %s after %q", text, schema, code)
					}
				}
			}
		})
	}
}

func TestRealRimePSCPeripheralAcrossAllThreeSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	session := newRealRimeSessionWithManagedRefresh(t, true)
	for _, mode := range []string{"variable", "full", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			schema := "yime_" + mode
			if !SelectSchema(session.sessionID, schema) {
				t.Fatalf("expected %s to be selectable", schema)
			}
			entries := readBundledErhuaDictionary(t, filepath.Join(dataDir, "yime_psc_peripheral_"+mode+".dict.yaml"))
			code := ""
			for _, entry := range entries {
				if entry.Text == "打点" {
					code = entry.Code
					break
				}
			}
			if code == "" {
				t.Fatalf("%s PSC peripheral dictionary lacks 打点", mode)
			}
			input := strings.ReplaceAll(code, " ", "")
			if _, found := findRealRimeCandidateAcrossPages(t, session.sessionID, input, "打点"); !found {
				t.Fatalf("PSC peripheral candidate 打点 missing in %s after %q", schema, input)
			}
		})
	}
}

func TestRealRimeStage2BYiBuAliasesAndRollbackAcrossAllSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	repoRoot := filepath.Clean(filepath.Join(dataDir, "..", "..", "..", ".."))
	trial, err := connectedspeech.RunStage2BRimeTrial(connectedspeech.DefaultStage2BTrialConfig(repoRoot))
	if err != nil {
		t.Fatal(err)
	}
	if !trial.Summary.Passed || trial.Summary.TrialAliasCount != 2 || trial.Summary.ThreeModeEntryCount != 6 {
		t.Fatalf("unexpected Stage 2B package summary: %#v", trial.Summary)
	}
	codeMap, err := reverselookup.LoadSharedCodeMap(dataDir)
	if err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		text            string
		canonical       string
		alias           string
		baseDynamicPath bool
	}{
		{text: "不至于", canonical: "bu4 zhi4 yu2", alias: "bu2 zhi4 yu2", baseDynamicPath: true},
		{text: "一本", canonical: "yi1 ben3", alias: "yi4 ben3", baseDynamicPath: false},
	}
	modes := []struct {
		schema string
		mode   reverselookup.Mode
	}{
		{"yime_variable", reverselookup.ModeVariable},
		{"yime_full", reverselookup.ModeFull},
		{"yime_shorthand", reverselookup.ModeShorthand},
	}

	runPhase := func(name string, installTrial bool) {
		t.Run(name, func(t *testing.T) {
			userDir := filepath.Join(t.TempDir(), "Rime")
			writeRuntimeTestDefaultCustom(t, userDir)
			if installTrial {
				copyStage2BTrialFiles(t, connectedspeech.DefaultStage2BTrialConfig(repoRoot).OutputDir, userDir)
			} else {
				writeStage2BDisabledPatches(t, connectedspeech.DefaultStage2BTrialConfig(repoRoot).OutputDir, userDir)
			}
			if !RimeInit(dataDir, userDir, APP, APP_VERSION, true) {
				t.Fatal("RimeInit failed")
			}
			sessionID, ok := StartSession()
			if !ok || sessionID == 0 {
				Finalize()
				t.Fatal("StartSession failed")
			}
			defer func() {
				EndSession(sessionID)
				Finalize()
			}()
			SetOption(sessionID, "ascii_mode", false)

			for _, mode := range modes {
				if !SelectSchema(sessionID, mode.schema) {
					t.Fatalf("expected %s to be selectable", mode.schema)
				}
				for _, item := range tests {
					canonicalCode, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, item.canonical, mode.mode)
					if encodeErr != nil {
						t.Fatal(encodeErr)
					}
					if _, found := findRealRimeCandidate(t, sessionID, canonicalCode, item.text); !found {
						t.Fatalf("canonical path %s/%s missing after %q", mode.schema, item.text, canonicalCode)
					}

					aliasCode, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, item.alias, mode.mode)
					if encodeErr != nil {
						t.Fatal(encodeErr)
					}
					index, found := findRealRimeCandidate(t, sessionID, aliasCode, item.text)
					if found != installTrial {
						t.Fatalf("trial path %s/%s after %q found=%t want=%t", mode.schema, item.text, aliasCode, found, installTrial)
					}
					if installTrial {
						if !SelectCandidate(sessionID, index) {
							t.Fatalf("failed to select trial candidate %s/%s at %d", mode.schema, item.text, index)
						}
						commit, committed := GetCommit(sessionID)
						if !committed || commit.Text != item.text {
							t.Fatalf("trial commit %s/%s = %#v committed=%t", mode.schema, item.text, commit, committed)
						}
					}
				}
			}
		})
	}

	runPhase("module-enabled", true)
	runPhase("module-disabled-rollback", false)
	t.Run("base-dynamic-sentence-observation", func(t *testing.T) {
		userDir := filepath.Join(t.TempDir(), "Rime")
		writeRuntimeTestDefaultCustom(t, userDir)
		writeStage2BDynamicBasePatches(t, userDir)
		if !RimeInit(dataDir, userDir, APP, APP_VERSION, true) {
			t.Fatal("RimeInit failed")
		}
		sessionID, ok := StartSession()
		if !ok || sessionID == 0 {
			Finalize()
			t.Fatal("StartSession failed")
		}
		defer func() {
			EndSession(sessionID)
			Finalize()
		}()
		SetOption(sessionID, "ascii_mode", false)
		for _, mode := range modes {
			if !SelectSchema(sessionID, mode.schema) {
				t.Fatalf("expected %s to be selectable", mode.schema)
			}
			for _, item := range tests {
				aliasCode, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, item.alias, mode.mode)
				if encodeErr != nil {
					t.Fatal(encodeErr)
				}
				if _, found := findRealRimeCandidate(t, sessionID, aliasCode, item.text); found != item.baseDynamicPath {
					t.Fatalf("base dynamic sentence path %s/%s after %q found=%t want=%t", mode.schema, item.text, aliasCode, found, item.baseDynamicPath)
				}
			}
		}
	})
}

func copyStage2BTrialFiles(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, name := range []string{
		"yime_connected_speech_stage2b_full.dict.yaml",
		"yime_connected_speech_stage2b_variable.dict.yaml",
		"yime_connected_speech_stage2b_shorthand.dict.yaml",
		"yime_full.custom.yaml",
		"yime_variable.custom.yaml",
		"yime_shorthand.custom.yaml",
	} {
		payload, err := os.ReadFile(filepath.Join(sourceDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name), payload, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func writeStage2BDisabledPatches(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, schema := range []string{"full", "variable", "shorthand"} {
		name := "yime_connected_speech_stage2b_baseline_" + schema
		payload, err := os.ReadFile(filepath.Join(sourceDir, name+".dict.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name+".dict.yaml"), payload, 0o644); err != nil {
			t.Fatal(err)
		}
		content := "patch:\n  translator/dictionary: " + name + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(userDir, "yime_"+schema+".custom.yaml"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func writeStage2BDynamicBasePatches(t *testing.T, userDir string) {
	t.Helper()
	for _, schema := range []string{"full", "variable", "shorthand"} {
		content := "patch:\n  translator/dictionary: yime_" + schema + "\n  translator/enable_sentence: true\n"
		if err := os.WriteFile(filepath.Join(userDir, "yime_"+schema+".custom.yaml"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRealRimeStage3NeutralSamplesAndRollbackAcrossAllSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	repoRoot := filepath.Clean(filepath.Join(dataDir, "..", "..", "..", ".."))
	impact, err := connectedspeech.RunNeutralLexiconImpactAudit(connectedspeech.DefaultNeutralLexiconImpactConfig(repoRoot))
	if err != nil {
		t.Fatal(err)
	}
	if !impact.Summary.Passed {
		t.Fatalf("unexpected Stage 3-0 impact summary: %#v", impact.Summary)
	}
	trial, err := connectedspeech.RunNeutralStage3RimeTrial(connectedspeech.DefaultNeutralStage3TrialConfig(repoRoot))
	if err != nil {
		t.Fatal(err)
	}
	if !trial.Summary.Passed || len(trial.Cases) == 0 || trial.Summary.ThreeModeEntryCount != len(trial.Cases)*3 {
		t.Fatalf("unexpected Stage 3-1 package: summary=%#v cases=%d", trial.Summary, len(trial.Cases))
	}

	modes := []struct {
		schema string
		mode   string
	}{
		{"yime_variable", "variable"},
		{"yime_full", "full"},
		{"yime_shorthand", "shorthand"},
	}
	runPhase := func(name string, enabled bool) {
		t.Run(name, func(t *testing.T) {
			userDir := filepath.Join(t.TempDir(), "Rime")
			writeRuntimeTestDefaultCustom(t, userDir)
			if enabled {
				copyStage3NeutralTrialFiles(t, connectedspeech.DefaultNeutralStage3TrialConfig(repoRoot).OutputDir, userDir)
			} else {
				writeStage3NeutralDisabledPatches(t, connectedspeech.DefaultNeutralStage3TrialConfig(repoRoot).OutputDir, userDir)
			}
			if !RimeInit(dataDir, userDir, APP, APP_VERSION, true) {
				t.Fatal("RimeInit failed")
			}
			sessionID, ok := StartSession()
			if !ok || sessionID == 0 {
				Finalize()
				t.Fatal("StartSession failed")
			}
			defer func() {
				EndSession(sessionID)
				Finalize()
			}()
			SetOption(sessionID, "ascii_mode", false)
			for _, mode := range modes {
				if !SelectSchema(sessionID, mode.schema) {
					t.Fatalf("expected %s to be selectable", mode.schema)
				}
				for _, item := range trial.Cases {
					canonicalInput := strings.ReplaceAll(item.CanonicalCodes[mode.mode], " ", "")
					if _, found := findRealRimeCandidate(t, sessionID, canonicalInput, item.Text); !found {
						t.Fatalf("canonical path %s/%s missing", mode.schema, item.Text)
					}
					surfaceInput := strings.ReplaceAll(item.SurfaceCodes[mode.mode], " ", "")
					index, found := findRealRimeCandidate(t, sessionID, surfaceInput, item.Text)
					if found != enabled {
						t.Fatalf("Stage 3-1 alias %s/%s found=%t want=%t", mode.schema, item.Text, found, enabled)
					}
					if !enabled {
						continue
					}
					switch item.ExpectedRankEffects[mode.mode] {
					case "no_competitor", "would_become_top":
						if index != 0 {
							t.Fatalf("%s/%s expected at bucket top, got index %d", mode.schema, item.Text, index)
						}
					case "below_existing_top":
						if index == 0 {
							t.Fatalf("%s/%s expected below an existing candidate", mode.schema, item.Text)
						}
					}
				}
			}
		})
	}
	runPhase("module-enabled", true)
	runPhase("module-disabled-rollback", false)
}

func copyStage3NeutralTrialFiles(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, name := range []string{
		"yime_connected_speech_stage3_full.dict.yaml",
		"yime_connected_speech_stage3_variable.dict.yaml",
		"yime_connected_speech_stage3_shorthand.dict.yaml",
		"yime_full.custom.yaml",
		"yime_variable.custom.yaml",
		"yime_shorthand.custom.yaml",
	} {
		payload, err := os.ReadFile(filepath.Join(sourceDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name), payload, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func writeStage3NeutralDisabledPatches(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, schema := range []string{"full", "variable", "shorthand"} {
		name := "yime_connected_speech_stage3_baseline_" + schema
		payload, err := os.ReadFile(filepath.Join(sourceDir, name+".dict.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name+".dict.yaml"), payload, 0o644); err != nil {
			t.Fatal(err)
		}
		content := "patch:\n  translator/dictionary: " + name + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(userDir, "yime_"+schema+".custom.yaml"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRealRimeStage3FullBatchSmokeAndBaseObservationAcrossAllSchemas(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	repoRoot := filepath.Clean(filepath.Join(dataDir, "..", "..", "..", ".."))
	if _, err := connectedspeech.RunNeutralLexiconImpactAudit(connectedspeech.DefaultNeutralLexiconImpactConfig(repoRoot)); err != nil {
		t.Fatal(err)
	}
	batch, err := connectedspeech.RunNeutralStage3FullBatchAudit(connectedspeech.DefaultNeutralStage3FullBatchConfig(repoRoot))
	if err != nil {
		t.Fatal(err)
	}
	if !batch.Summary.Passed || len(batch.SmokeCases) == 0 {
		t.Fatalf("unexpected Stage 3-2 full-batch result: %#v", batch.Summary)
	}
	modes := []struct {
		schema string
		mode   string
	}{
		{"yime_variable", "variable"},
		{"yime_full", "full"},
		{"yime_shorthand", "shorthand"},
	}
	baselineFound := map[string]bool{}
	runPhase := func(name string, enabled bool) {
		t.Run(name, func(t *testing.T) {
			userDir := filepath.Join(t.TempDir(), "Rime")
			writeRuntimeTestDefaultCustom(t, userDir)
			if enabled {
				copyStage3FullBatchFiles(t, connectedspeech.DefaultNeutralStage3FullBatchConfig(repoRoot).OutputDir, userDir)
			} else {
				writeStage3FullBatchDisabledPatches(t, userDir)
			}
			if !RimeInit(dataDir, userDir, APP, APP_VERSION, true) {
				t.Fatal("RimeInit failed")
			}
			sessionID, ok := StartSession()
			if !ok || sessionID == 0 {
				Finalize()
				t.Fatal("StartSession failed")
			}
			defer func() {
				EndSession(sessionID)
				Finalize()
			}()
			SetOption(sessionID, "ascii_mode", false)
			for _, mode := range modes {
				if !SelectSchema(sessionID, mode.schema) {
					t.Fatalf("expected %s to be selectable", mode.schema)
				}
				for _, item := range batch.SmokeCases {
					input := strings.ReplaceAll(item.SurfaceCodes[mode.mode], " ", "")
					_, found := findRealRimeCandidate(t, sessionID, input, item.Text)
					key := mode.mode + "\x00" + item.Text
					if !enabled {
						baselineFound[key] = found
						continue
					}
					if !found {
						t.Fatalf("Stage 3-2 full-batch alias %s/%s missing after module enable", mode.schema, item.Text)
					}
				}
			}
		})
	}
	runPhase("base-dynamic-observation", false)
	runPhase("module-enabled", true)
	missingFromBase := 0
	for _, found := range baselineFound {
		if !found {
			missingFromBase++
		}
	}
	if missingFromBase == 0 {
		t.Fatal("all smoke aliases were already available through the base dictionary; trial did not exercise a new path")
	}
}

func TestRealRimeStage3FullBatchHighRiskPrefixOrdering(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	repoRoot := filepath.Clean(filepath.Join(dataDir, "..", "..", "..", ".."))
	if _, err := connectedspeech.RunNeutralLexiconImpactAudit(connectedspeech.DefaultNeutralLexiconImpactConfig(repoRoot)); err != nil {
		t.Fatal(err)
	}
	config := connectedspeech.DefaultNeutralStage3FullBatchConfig(repoRoot)
	if _, err := connectedspeech.RunNeutralStage3FullBatchAudit(config); err != nil {
		t.Fatal(err)
	}
	probes := loadStage3HighRiskPrefixProbes(t, filepath.Join(config.OutputDir, "prefix_impact.tsv"), 0)
	if len(probes) == 0 {
		t.Fatal("expected pure-completion prefix probes")
	}
	type snapshot struct {
		first      string
		candidates []string
	}
	baseline := map[string]snapshot{}
	firstChangedByMode := map[string]int{}
	pageChangedByMode := map[string]int{}
	pageWithNewTextByMode := map[string]int{}
	runPhase := func(name string, enabled bool) {
		t.Run(name, func(t *testing.T) {
			userDir := filepath.Join(t.TempDir(), "Rime")
			writeRuntimeTestDefaultCustom(t, userDir)
			if enabled {
				writeStage3CombinedDictionaryPatches(t, config.OutputDir, userDir)
			}
			if !RimeInit(dataDir, userDir, APP, APP_VERSION, true) {
				t.Fatal("RimeInit failed")
			}
			sessionID, ok := StartSession()
			if !ok || sessionID == 0 {
				Finalize()
				t.Fatal("StartSession failed")
			}
			defer func() {
				EndSession(sessionID)
				Finalize()
			}()
			SetOption(sessionID, "ascii_mode", false)
			for _, probe := range probes {
				if !SelectSchema(sessionID, "yime_"+probe.mode) {
					t.Fatalf("expected yime_%s to be selectable", probe.mode)
				}
				ClearComposition(sessionID)
				typeASCII(t, sessionID, probe.code)
				menu, ok := GetMenu(sessionID)
				if !ok || len(menu.Candidates) == 0 {
					t.Fatalf("%s/%q has no candidates", probe.mode, probe.code)
				}
				texts := make([]string, 0, len(menu.Candidates))
				for _, candidate := range menu.Candidates {
					texts = append(texts, candidate.Text)
				}
				key := probe.mode + "\x00" + probe.code
				if !enabled {
					baseline[key] = snapshot{first: texts[0], candidates: texts}
					continue
				}
				before := baseline[key]
				if texts[0] != before.first {
					firstChangedByMode[probe.mode]++
					t.Logf("first candidate changed mode=%s code=%q net_new=%d: %q -> %q", probe.mode, probe.code, probe.netNew, before.first, texts[0])
				}
				if strings.Join(texts, "\x00") != strings.Join(before.candidates, "\x00") {
					pageChangedByMode[probe.mode]++
					t.Logf("candidate page changed mode=%s code=%q net_new=%d: %q -> %q", probe.mode, probe.code, probe.netNew, before.candidates, texts)
				}
				if stage3CandidatePageHasNewText(before.candidates, texts) {
					pageWithNewTextByMode[probe.mode]++
				}
			}
		})
	}
	runPhase("baseline", false)
	runPhase("combined-base-and-alias", true)
	t.Logf("pure-completion prefix probes=%d first_changed=%v page_changed=%v page_with_new_text=%v", len(probes), firstChangedByMode, pageChangedByMode, pageWithNewTextByMode)
	if len(baseline) != len(probes) {
		t.Fatalf("captured %d baseline snapshots for %d probes", len(baseline), len(probes))
	}
	if len(firstChangedByMode) != 0 {
		t.Fatalf("pure-completion aliases changed first candidates: %v", firstChangedByMode)
	}
}

func stage3CandidatePageHasNewText(before, after []string) bool {
	old := map[string]bool{}
	for _, text := range before {
		old[text] = true
	}
	for _, text := range after {
		if !old[text] {
			return true
		}
	}
	return false
}

type stage3PrefixProbe struct {
	mode   string
	code   string
	netNew int
}

func loadStage3HighRiskPrefixProbes(t *testing.T, path string, perMode int) []stage3PrefixProbe {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	rows, err := reader.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	header := map[string]int{}
	for index, name := range rows[0] {
		header[name] = index
	}
	probesByMode := map[string][]stage3PrefixProbe{}
	for _, row := range rows[1:] {
		if len(row) != len(rows[0]) || row[header["relation"]] != "old_exact_prefix_of_new" {
			continue
		}
		netNew, _ := strconv.Atoi(row[header["net_new_visible_text_count"]])
		newExact, _ := strconv.Atoi(row[header["new_exact_text_count_at_trigger"]])
		if netNew == 0 || newExact != 0 {
			continue
		}
		mode := row[header["mode"]]
		probesByMode[mode] = append(probesByMode[mode], stage3PrefixProbe{mode: mode, code: row[header["trigger_code"]], netNew: netNew})
	}
	result := []stage3PrefixProbe{}
	for _, mode := range []string{"variable", "full", "shorthand"} {
		probes := probesByMode[mode]
		sort.Slice(probes, func(i, j int) bool {
			if probes[i].netNew != probes[j].netNew {
				return probes[i].netNew > probes[j].netNew
			}
			return probes[i].code < probes[j].code
		})
		if perMode == 0 {
			result = append(result, probes...)
			continue
		}
		if len(probes) < perMode {
			t.Fatalf("%s has only %d high-risk prefix probes", mode, len(probes))
		}
		result = append(result, probes[:perMode]...)
	}
	return result
}

func writeStage3CombinedDictionaryPatches(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, mode := range []string{"variable", "full", "shorthand"} {
		aliasName := "yime_connected_speech_stage3_2_" + mode
		payload, err := os.ReadFile(filepath.Join(sourceDir, aliasName+".dict.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, aliasName+".dict.yaml"), payload, 0o644); err != nil {
			t.Fatal(err)
		}
		combinedName := "yime_connected_speech_stage3_2_combined_" + mode
		combined := strings.Join([]string{
			"---",
			"name: " + combinedName,
			"version: \"stage3-2-prefix-probe-v1\"",
			"sort: by_weight",
			"use_preset_vocabulary: false",
			"import_tables:",
			"  - yime_" + mode,
			"  - " + aliasName,
			"...",
			"",
		}, "\n")
		if err := os.WriteFile(filepath.Join(userDir, combinedName+".dict.yaml"), []byte(combined), 0o644); err != nil {
			t.Fatal(err)
		}
		patch := "patch:\n  translator/dictionary: " + combinedName + "\n"
		if err := os.WriteFile(filepath.Join(userDir, "yime_"+mode+".custom.yaml"), []byte(patch), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func copyStage3FullBatchFiles(t *testing.T, sourceDir, userDir string) {
	t.Helper()
	for _, name := range []string{
		"yime_connected_speech_stage3_2_full.dict.yaml",
		"yime_connected_speech_stage3_2_variable.dict.yaml",
		"yime_connected_speech_stage3_2_shorthand.dict.yaml",
		"yime_full.custom.yaml",
		"yime_variable.custom.yaml",
		"yime_shorthand.custom.yaml",
	} {
		payload, err := os.ReadFile(filepath.Join(sourceDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(userDir, name), payload, 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func writeStage3FullBatchDisabledPatches(t *testing.T, userDir string) {
	t.Helper()
	for _, schema := range []string{"full", "variable", "shorthand"} {
		content := "patch:\n  translator/dictionary: yime_" + schema + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(userDir, "yime_"+schema+".custom.yaml"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func findRealRimeCandidate(t *testing.T, sessionID RimeSessionId, input, text string) (int, bool) {
	t.Helper()
	ClearComposition(sessionID)
	typeASCII(t, sessionID, input)
	menu, ok := GetMenu(sessionID)
	if !ok {
		return -1, false
	}
	for index, candidate := range menu.Candidates {
		if candidate.Text == text {
			return index, true
		}
	}
	return -1, false
}

func findRealRimeCandidateAcrossPages(t *testing.T, sessionID RimeSessionId, input, text string) (int, bool) {
	t.Helper()
	ClearComposition(sessionID)
	typeASCII(t, sessionID, input)
	for page := 0; page < 100; page++ {
		menu, ok := GetMenu(sessionID)
		if !ok {
			return -1, false
		}
		for index, candidate := range menu.Candidates {
			if candidate.Text == text {
				return menu.PageNo*menu.PageSize + index, true
			}
		}
		if menu.IsLastPage || !ProcessKey(sessionID, rimeNext, 0) {
			return -1, false
		}
	}
	t.Fatalf("candidate paging exceeded 100 pages for %q after %q", text, input)
	return -1, false
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

func TestRealRimeOwnedSegmentRPCMovesWithoutCommittingSentence(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	// The real PIME key path consumes each pending commit in the key response.
	// typeASCII talks to librime directly, so drain any earlier auto-commit
	// before isolating the click RPC.
	_, _ = GetCommit(session.sessionID)
	backend := &nativeBackend{sessionID: session.sessionID}
	ime := newSegmentNavigationIME(backend)
	resp := ime.HandleRequest(&pime.Request{
		SeqNum: 1, Method: "selectCompositionSegment", CursorPos: 0, SelEnd: 4,
	})
	if resp.ReturnValue != 1 {
		t.Fatalf("expected owned segment RPC to be handled, got %#v", resp)
	}
	if resp.CompositionString == "" {
		t.Fatal("segment navigation must preserve the sentence composition")
	}
	if resp.CommitString != "" {
		t.Fatalf("segment navigation must not commit the sentence, got %q", resp.CommitString)
	}
	if resp.SelStart != 0 {
		t.Fatalf("expected the first segment to become active, got [%d,%d)",
			resp.SelStart, resp.SelEnd)
	}
}

func TestRealRimeOwnedSegmentRPCReachesLaterSegment(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	backend := &rawCompositionRuntimeBackend{
		nativeBackend: &nativeBackend{sessionID: session.sessionID},
	}
	ime := newSegmentNavigationIME(backend)
	segments := ime.compositionSegmentsForState(backend.State())
	if len(segments) != 2 {
		t.Fatalf("expected two clickable sentence segments, got %#v", segments)
	}
	if input, ok := GetRawInput(session.sessionID); !ok || input != "bjjjbjjj" {
		t.Fatalf("expected full raw input before callback, got %q ok=%v", input, ok)
	}
	if _, ok := interface{}(backend).(backendCompositionCaret); !ok {
		t.Fatal("runtime backend must expose direct composition caret navigation")
	}
	if rawCaret, activeIndex, ok := ime.rawCaretForCompositionSegment(
		backend.State(), segments[1].Start, segments[1].End,
	); !ok || rawCaret != 4 || activeIndex != 1 {
		t.Fatalf("expected second segment to map to entry caret 4, got %d index=%d ok=%v",
			rawCaret, activeIndex, ok)
	}

	req := &pime.Request{
		SeqNum:    1,
		Method:    "selectCompositionSegment",
		CursorPos: segments[1].Start,
		SelEnd:    segments[1].End,
	}
	// Initialization and runtime-change polling are covered separately. Call
	// the RPC handler directly so this test isolates the live librime click.
	resp := ime.onSelectCompositionSegment(req, pime.NewResponse(req.SeqNum, true))
	if resp.ReturnValue != 1 || resp.CompositionString == "" {
		t.Fatalf("later segment callback must preserve composition, calls=%#v result=%v resp=%#v",
			backend.caretCalls, backend.caretResult, resp)
	}
	if resp.CommitString != "" {
		t.Fatalf("later segment callback must not commit, got %q", resp.CommitString)
	}
	if len(resp.CompositionSegments) != 2 || !resp.CompositionSegments[1].Active {
		t.Fatalf("later segment should be highlighted, got %#v", resp.CompositionSegments)
	}
	if len(resp.CandidateList) == 0 {
		t.Fatalf("expected candidates for the clicked segment, got %#v", resp.CandidateList)
	}
	if strings.Contains(resp.CandidateList[0], "幅幅") {
		t.Fatalf("later segment must show local candidates, not a sentence prefix: %#v",
			resp.CandidateList)
	}
	if len(backend.caretCalls) != 2 ||
		backend.caretCalls[0] != 4 || backend.caretCalls[1] != 8 {
		t.Fatalf("expected second-segment bounds [4,8], got %#v",
			backend.caretCalls)
	}
}

func TestRealRimeLaterSegmentCorrectionCommitsPreservedPrefix(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	_, _ = GetCommit(session.sessionID)
	backend := &nativeBackend{sessionID: session.sessionID}
	ime := newSegmentNavigationIME(backend)
	segments := ime.compositionSegmentsForState(backend.State())
	if len(segments) != 2 {
		t.Fatalf("expected two correction segments, got %#v", segments)
	}

	clickRequest := &pime.Request{
		SeqNum:    1,
		Method:    "selectCompositionSegment",
		CursorPos: segments[1].Start,
		SelEnd:    segments[1].End,
	}
	clickResponse := ime.onSelectCompositionSegment(
		clickRequest, pime.NewResponse(clickRequest.SeqNum, true))
	if clickResponse.ReturnValue != 1 ||
		len(clickResponse.CompositionSegments) != 2 ||
		!clickResponse.CompositionSegments[1].Active {
		t.Fatalf("second segment should be ready for correction, got %#v",
			clickResponse)
	}

	targetCandidate := -1
	for index, candidate := range backend.State().Candidates {
		if candidate.Text == "逼" {
			targetCandidate = index
			break
		}
	}
	if targetCandidate < 0 {
		t.Fatal("expected a second-segment alternative candidate 逼")
	}
	selectRequest := &pime.Request{
		SeqNum: 2,
		Method: "selectCandidate",
		Data: map[string]interface{}{
			"candidateIndex": float64(targetCandidate),
		},
	}
	selectResponse := ime.onSelectCandidate(
		selectRequest, pime.NewResponse(selectRequest.SeqNum, true))
	if selectResponse.CommitString != "幅逼" {
		t.Fatalf("expected preserved prefix and corrected tail to commit together, got %#v",
			selectResponse)
	}
	if selectResponse.CompositionString != "" {
		t.Fatalf("final-segment correction should finish the sentence, got %#v",
			selectResponse)
	}
}

func TestRealRimeMiddleSegmentCorrectionRestoresFullSentence(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	// 编辑区内袋下划线的玉编码文字。Keep this fixture aligned with
	// the bundled full-schema codes while exercising the correction workflow.
	typeASCII(t, session.sessionID,
		"bjfa3lkj2mmmnvcl]fdl1jdshuds1jdz]eee`m,.bjfa-sss=oca6JKL")
	_, _ = GetCommit(session.sessionID)
	backend := &nativeBackend{sessionID: session.sessionID}
	ime := newSegmentNavigationIME(backend)
	segments := ime.compositionSegmentsForState(backend.State())
	if len(segments) != 14 {
		t.Fatalf("expected complete 14-character sentence preview, got %#v", segments)
	}
	targetIndex := -1
	for index, segment := range segments {
		if segment.Text == "袋" {
			targetIndex = index
			break
		}
	}
	if targetIndex != 4 {
		t.Fatalf("expected 袋 at segment 4, got index=%d segments=%#v",
			targetIndex, segments)
	}

	clickRequest := &pime.Request{
		SeqNum:    1,
		Method:    "selectCompositionSegment",
		CursorPos: segments[targetIndex].Start,
		SelEnd:    segments[targetIndex].End,
	}
	clickResponse := ime.onSelectCompositionSegment(
		clickRequest, pime.NewResponse(clickRequest.SeqNum, true))
	if clickResponse.ReturnValue != 1 ||
		len(clickResponse.CompositionSegments) != len(segments) ||
		!clickResponse.CompositionSegments[targetIndex].Active {
		t.Fatalf("middle segment should be ready for local correction, got %#v",
			clickResponse)
	}

	targetCandidate := -1
	targetState := backend.State()
	for index, candidate := range targetState.Candidates {
		if candidate.Text == "带" {
			targetCandidate = index
			break
		}
	}
	if targetCandidate < 0 {
		t.Fatalf("expected local same-syllable candidate 带, got %#v",
			targetState.Candidates)
	}
	selectRequest := &pime.Request{
		SeqNum: 2,
		Method: "selectCandidate",
		Data: map[string]interface{}{
			"candidateIndex": float64(targetCandidate),
		},
	}
	selectResponse := ime.onSelectCandidate(
		selectRequest, pime.NewResponse(selectRequest.SeqNum, true))
	if selectResponse.CommitString != "" {
		t.Fatalf("middle correction must not commit before remaining review, got %#v",
			selectResponse)
	}
	if len(selectResponse.CompositionSegments) != len(segments) {
		t.Fatalf("middle correction must restore the full sentence row, got %#v",
			selectResponse.CompositionSegments)
	}
	if selectResponse.CompositionSegments[targetIndex].Text != "带" {
		t.Fatalf("expected corrected segment 带, got %#v",
			selectResponse.CompositionSegments[targetIndex])
	}
	if selectResponse.CompositionSegments[targetIndex+1].Text != "下" ||
		selectResponse.CompositionSegments[len(segments)-1].Text != "字" {
		t.Fatalf("middle correction lost the suffix, got %#v",
			selectResponse.CompositionSegments)
	}
}

func TestRealRimeRawCaretCanReachSentenceSegments(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}

	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	input, ok := GetRawInput(session.sessionID)
	if !ok || input != "bjjjbjjj" {
		t.Fatalf("expected raw sentence input, got %q ok=%v", input, ok)
	}
	for _, caret := range []int{4, 8} {
		if !SetRawCaretPos(session.sessionID, caret) {
			t.Fatalf("expected raw caret %d to be accepted", caret)
		}
		composition, compositionOK := GetComposition(session.sessionID)
		menu, menuOK := GetMenu(session.sessionID)
		t.Logf("caret=%d preedit=%q preview=%q selection=[%d,%d) candidates=%#v",
			caret, composition.Preedit, composition.CommitTextPreview,
			composition.SelStart, composition.SelEnd, menu.Candidates)
		if !compositionOK || composition.Preedit == "" {
			t.Fatalf("caret %d cleared composition: %#v", caret, composition)
		}
		if !menuOK || len(menu.Candidates) == 0 {
			t.Fatalf("caret %d produced no candidates: %#v", caret, menu)
		}
	}
}

func TestRealRimeReportsSentencePreviewAcrossNavigatorSegments(t *testing.T) {
	session := newRealRimeSession(t)
	if !SelectSchema(session.sessionID, "yime_full") {
		t.Fatal("expected yime_full schema to be selectable")
	}
	ClearComposition(session.sessionID)
	typeASCII(t, session.sessionID, "bjjjbjjj")
	native := &nativeBackend{sessionID: session.sessionID}
	mapper := newSegmentNavigationIME(native)
	initialSegments := mapper.compositionSegmentsForState(native.State())
	if len(initialSegments) != 2 ||
		initialSegments[0].Text != "幅" || initialSegments[0].Code != "bjjj" ||
		initialSegments[1].Text != "幅" || initialSegments[1].Code != "bjjj" {
		t.Fatalf("expected [幅 bjjj] [幅 bjjj], got %#v", initialSegments)
	}

	for step := 0; step < 4; step++ {
		composition, ok := GetComposition(session.sessionID)
		if !ok || composition.Preedit == "" {
			t.Fatalf("step %d: expected composition, got %#v", step, composition)
		}
		menu, _ := GetMenu(session.sessionID)
		t.Logf("step=%d preedit=%q preview=%q cursor=%d selection=[%d,%d) highlighted=%d candidates=%#v",
			step, composition.Preedit, composition.CommitTextPreview,
			composition.CursorPos, composition.SelStart, composition.SelEnd,
			menu.HighlightedCandidateIndex, menu.Candidates)
		if step == 3 {
			break
		}
		if !processRealKey(session.sessionID, &pime.Request{
			KeyCode: vkLeft, KeyStates: keyStatesDown(vkControl),
		}) {
			break
		}
	}

	if !SelectCandidate(session.sessionID, 1) {
		t.Fatal("expected alternate first-segment candidate selection")
	}
	composition, _ := GetComposition(session.sessionID)
	menu, _ := GetMenu(session.sessionID)
	t.Logf("after-selection preedit=%q preview=%q cursor=%d selection=[%d,%d) highlighted=%d candidates=%#v",
		composition.Preedit, composition.CommitTextPreview,
		composition.CursorPos, composition.SelStart, composition.SelEnd,
		menu.HighlightedCandidateIndex, menu.Candidates)
	updatedSegments := mapper.compositionSegmentsForState(native.State())
	if len(updatedSegments) != 2 ||
		updatedSegments[0].Text != "逼" || updatedSegments[0].Code != "bjjj" ||
		updatedSegments[1].Text != "幅" || updatedSegments[1].Code != "bjjj" ||
		!updatedSegments[1].Active {
		t.Fatalf("expected [逼 bjjj] [幅 bjjj] with active tail, got %#v",
			updatedSegments)
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

	for index := 0; index < learnedRank; index++ {
		if !ProcessKey(session.sessionID, rimeDown, 0) {
			t.Fatalf("expected Down to highlight learned candidate at rank %d", learnedRank)
		}
	}
	highlightedMenu, ok := GetMenu(session.sessionID)
	if !ok || highlightedMenu.HighlightedCandidateIndex != learnedRank {
		t.Fatalf("expected learned candidate highlighted at %d, got %#v",
			learnedRank, highlightedMenu)
	}

	ime := newSegmentNavigationIME(&nativeBackend{sessionID: session.sessionID})
	forgetReq := &pime.Request{
		SeqNum:    100,
		KeyCode:   vkDelete,
		KeyStates: keyStatesDown(vkControl),
	}
	filterResp := ime.filterKeyDown(forgetReq, pime.NewResponse(forgetReq.SeqNum, true))
	if filterResp.ReturnValue != 1 {
		t.Fatalf("expected Ctrl+Delete quick forget to be handled, got %#v", filterResp)
	}
	onResp := ime.onKeyDown(forgetReq, pime.NewResponse(forgetReq.SeqNum+1, true))
	if onResp.ShowMessage == nil ||
		onResp.ShowMessage.Message != "已遗忘："+finalCommit.Text {
		t.Fatalf("expected quick-forget feedback for %q, got %#v",
			finalCommit.Text, onResp.ShowMessage)
	}
	if onResp.CommitString != "" || onResp.CompositionString == "" {
		t.Fatalf("quick forget must refresh candidates without committing, got %#v", onResp)
	}

	afterMenu, ok := GetMenu(session.sessionID)
	if !ok {
		t.Fatal("expected candidate menu to remain after quick forget")
	}
	afterRank := -1
	for index, candidate := range afterMenu.Candidates {
		if candidate.Text == finalCommit.Text {
			afterRank = index
			break
		}
	}
	if afterRank >= 0 && afterRank <= learnedRank {
		t.Fatalf("expected forgotten candidate %q to disappear or lose its learned rank %d, got %d in %#v",
			finalCommit.Text, learnedRank, afterRank, afterMenu.Candidates)
	}
}

func TestRealRimeQuickForgetAvailableInAllSchemas(t *testing.T) {
	session := newRealRimeSession(t)
	for _, schemaID := range []string{
		settings.SchemaVariable,
		settings.SchemaFull,
		settings.SchemaShorthand,
	} {
		t.Run(schemaID, func(t *testing.T) {
			ClearComposition(session.sessionID)
			if !SelectSchema(session.sessionID, schemaID) {
				t.Fatalf("expected schema %q to be selectable", schemaID)
			}
			typeASCII(t, session.sessionID, "bj")
			before, ok := GetMenu(session.sessionID)
			if !ok || len(before.Candidates) < 2 {
				t.Fatalf("expected candidates before quick forget in %q, got %#v",
					schemaID, before)
			}
			target := before.Candidates[0].Text

			ime := newSegmentNavigationIME(&nativeBackend{sessionID: session.sessionID})
			req := &pime.Request{
				SeqNum:    200,
				KeyCode:   vkDelete,
				KeyStates: keyStatesDown(vkControl),
			}
			filterResp := ime.filterKeyDown(req, pime.NewResponse(req.SeqNum, true))
			if filterResp.ReturnValue != 1 {
				t.Fatalf("expected Ctrl+Delete to be handled in %q, got %#v",
					schemaID, filterResp)
			}
			onResp := ime.onKeyDown(req, pime.NewResponse(req.SeqNum+1, true))
			if onResp.ShowMessage == nil ||
				onResp.ShowMessage.Message != "已遗忘："+target {
				t.Fatalf("expected quick-forget feedback in %q, got %#v",
					schemaID, onResp.ShowMessage)
			}
			if onResp.CommitString != "" || onResp.CompositionString == "" {
				t.Fatalf("quick forget must preserve composition in %q, got %#v",
					schemaID, onResp)
			}

			after, ok := GetMenu(session.sessionID)
			if !ok || len(after.Candidates) == 0 {
				t.Fatalf("expected refreshed candidates in %q, got %#v",
					schemaID, after)
			}
			if after.Candidates[0].Text != target {
				t.Fatalf("quick forget must not remove the system dictionary candidate %q in %q, got %#v",
					target, schemaID, after.Candidates)
			}
		})
	}
}

func TestRealRimeExplicitCandidateForgetAvailableInAllSchemas(t *testing.T) {
	session := newRealRimeSession(t)
	for _, schemaID := range []string{
		settings.SchemaVariable,
		settings.SchemaFull,
		settings.SchemaShorthand,
	} {
		t.Run(schemaID, func(t *testing.T) {
			ClearComposition(session.sessionID)
			if !SelectSchema(session.sessionID, schemaID) {
				t.Fatalf("expected schema %q to be selectable", schemaID)
			}
			typeASCII(t, session.sessionID, "bj")
			before, ok := GetMenu(session.sessionID)
			if !ok || len(before.Candidates) < 2 {
				t.Fatalf("expected two candidates before explicit quick forget in %q, got %#v",
					schemaID, before)
			}
			target := before.Candidates[1].Text

			ime := newSegmentNavigationIME(&nativeBackend{sessionID: session.sessionID})
			stateResp := pime.NewResponse(300, true)
			ime.applyStateToResponse(stateResp, ime.backend.State())
			req := &pime.Request{
				SeqNum: 301,
				Method: "forgetCandidate",
				Data: map[string]interface{}{
					"candidateIndex": float64(1),
				},
			}
			resp := ime.HandleRequest(req)
			if resp.ReturnValue != 1 {
				t.Fatalf("expected explicit candidate forget to be handled in %q, got %#v",
					schemaID, resp)
			}
			if resp.ShowMessage == nil ||
				resp.ShowMessage.Message != "已遗忘："+target {
				t.Fatalf("expected explicit quick-forget feedback for %q in %q, got %#v",
					target, schemaID, resp.ShowMessage)
			}
			if resp.CommitString != "" || resp.CompositionString == "" {
				t.Fatalf("explicit quick forget must preserve composition in %q, got %#v",
					schemaID, resp)
			}

			after, ok := GetMenu(session.sessionID)
			if !ok || len(after.Candidates) == 0 {
				t.Fatalf("expected candidates after explicit quick forget in %q, got %#v",
					schemaID, after)
			}
			found := false
			for _, candidate := range after.Candidates {
				if candidate.Text == target {
					found = true
					break
				}
			}
			if !found {
				t.Fatalf("explicit quick forget must not remove system candidate %q in %q, got %#v",
					target, schemaID, after.Candidates)
			}
		})
	}
}

func TestRealRimePrintableLayoutKeysAreNeverPagingBindings(t *testing.T) {
	session := newRealRimeSession(t)
	for _, key := range []rune{'`', '-', '=', ',', '.', '/'} {
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

func TestRealRimeBuildsCoreModesFromSingleSchemaList(t *testing.T) {
	dataDir := rimeRuntimeTestDataDir(t)
	initialUserDir := filepath.Join(t.TempDir(), "Rime")
	if err := os.MkdirAll(initialUserDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(initialUserDir, "default.custom.yaml"),
		[]byte("patch:\n  schema_list:\n    - schema: yime_variable\n  \"menu/page_size\": 5\n"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if !RimeInit(dataDir, initialUserDir, APP, APP_VERSION, false) {
		t.Fatal("RimeInit failed")
	}
	sessionID, ok := StartSession()
	if !ok || sessionID == 0 {
		Finalize()
		t.Fatal("StartSession failed")
	}
	if !SelectSchema(sessionID, "yime_variable") {
		EndSession(sessionID)
		Finalize()
		t.Fatal("expected initial yime_variable schema")
	}
	EndSession(sessionID)
	Finalize()

	var variableUserDir string
	for _, schemaID := range []string{
		settings.SchemaVariable,
		settings.SchemaFull,
		settings.SchemaShorthand,
	} {
		t.Run(schemaID, func(t *testing.T) {
			userDir := filepath.Join(t.TempDir(), "Rime")
			if err := os.MkdirAll(userDir, 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(
				filepath.Join(userDir, "default.custom.yaml"),
				[]byte("patch:\n  schema_list:\n    - schema: yime_variable\n  \"menu/page_size\": 5\n"),
				0o644,
			); err != nil {
				t.Fatal(err)
			}
			if err := settings.Apply(
				userDir,
				dataDir,
				schemaID,
				5,
				"hidden",
				"vertical",
				true,
			); err != nil {
				t.Fatalf("building curated core schema %s failed: %v", schemaID, err)
			}
			if err := validateCompiledRimeSchema(userDir, schemaID); err != nil {
				t.Fatal(err)
			}
			if schemaID == settings.SchemaVariable {
				variableUserDir = userDir
			}
		})
	}

	if variableUserDir == "" {
		t.Fatal("variable schema build directory was not captured")
	}
	if !RimeInit(dataDir, variableUserDir, APP, APP_VERSION, false) {
		t.Fatal("RimeInit after external core schema build failed")
	}
	sessionID, ok = StartSession()
	if !ok || sessionID == 0 {
		Finalize()
		t.Fatal("StartSession after external core schema build failed")
	}
	defer func() {
		EndSession(sessionID)
		Finalize()
	}()
	if !SelectSchema(sessionID, settings.SchemaVariable) {
		t.Fatal("expected externally built yime_variable schema to be selectable")
	}
	SetOption(sessionID, "ascii_mode", false)
	typeASCII(t, sessionID, "bj")
	menu, ok := GetMenu(sessionID)
	if !ok || len(menu.Candidates) == 0 {
		t.Fatalf("expected curated core candidates after bj, got %#v", menu)
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
		{"shift FDS a-rhotic", []*pime.Request{{KeyCode: 'H', CharCode: 'h'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 'D', CharCode: 'd'}, {KeyCode: 'O', CharCode: 'o'}, {KeyCode: 0xBD, CharCode: '-'}, {KeyCode: 'S', CharCode: 's'}, {KeyCode: 'S', CharCode: 'S', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 'S', CharCode: 'S', KeyStates: keyStatesDown(vkShift)}}},
		{"shift REW back-mid-rhotic", []*pime.Request{{KeyCode: 0xDD, CharCode: ']'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 'A', CharCode: 'a'}, {KeyCode: 'G', CharCode: 'g'}, {KeyCode: 'R', CharCode: 'r'}, {KeyCode: 'E', CharCode: 'E', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 'W', CharCode: 'W', KeyStates: keyStatesDown(vkShift)}}},
		{"shift QTY nasal-a-rhotic", []*pime.Request{{KeyCode: '1', CharCode: '1'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 0xBA, CharCode: ';'}, {KeyCode: '8', CharCode: '8'}, {KeyCode: 'S', CharCode: 's'}, {KeyCode: 'T', CharCode: 'T', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 'Y', CharCode: 'Y', KeyStates: keyStatesDown(vkShift)}}},
		{"shift VCX nasal-back-mid-rhotic", []*pime.Request{{KeyCode: '0', CharCode: '0'}, {KeyCode: 'X', CharCode: 'x'}, {KeyCode: 'C', CharCode: 'c'}, {KeyCode: 'A', CharCode: 'a'}, {KeyCode: 'Y', CharCode: 'y'}, {KeyCode: 'L', CharCode: 'l'}, {KeyCode: 'X', CharCode: 'X', KeyStates: keyStatesDown(vkShift)}, {KeyCode: 'X', CharCode: 'X', KeyStates: keyStatesDown(vkShift)}}},
		{"shift PAZ u-rhotic", []*pime.Request{{KeyCode: '3', CharCode: '3'}, {KeyCode: 'J', CharCode: 'j'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 'F', CharCode: 'f'}, {KeyCode: 'Y', CharCode: 'y'}, {KeyCode: 'L', CharCode: 'l'}, {KeyCode: 'E', CharCode: 'e'}, {KeyCode: 'P', CharCode: 'P', KeyStates: keyStatesDown(vkShift)}}},
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
