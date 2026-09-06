package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningconfig"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func speechProductWrite(t *testing.T, path string, data []byte) string {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func speechBrokerProductFixture(t *testing.T, reviewed ...connectedspeech.AdmissionResult) (multiModeConfig, *yimecore.FileIndex) {
	t.Helper()
	root := t.TempDir()
	config := multiModeConfig{indexRoot: filepath.Join(root, "active-indexes"), annotationDataDir: filepath.Join(root, "active-data"), speechProductRoot: filepath.Join(root, "own-product"), speechProductManifest: speechruntime.ProductManifestPath, speechSettings: filepath.Join(root, "state", "speech.json"), userModelSourceID: "existing-normal-product-namespace", userSnapshot: filepath.Join(root, "state", "model.json"), userJournal: filepath.Join(root, "state", "model.journal")}
	speechRoot := filepath.Join(config.speechProductRoot, "speech")
	writeJSON := func(path string, value any) string {
		data, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return speechProductWrite(t, path, data)
	}
	layoutHash := speechProductWrite(t, filepath.Join(config.annotationDataDir, "yime_yinyuan_layout.json"), []byte("synthetic-active-layout"))
	if len(reviewed) > 0 {
		// Explicit repository-only reviewed data, copied into the private fixture.
		for _, name := range []string{"yime_yinyuan_layout.json", "yime_pinyin_codes.tsv", "pinyin_normalized.json", "yime_pua_pinyin.json", "yime_pinyin_reverse_source.tsv"} {
			data, err := os.ReadFile(filepath.Join("..", "..", "input_methods", "yime", "data", name))
			if err != nil {
				t.Fatal(err)
			}
			hash := speechProductWrite(t, filepath.Join(config.annotationDataDir, name), data)
			if name == "yime_yinyuan_layout.json" {
				layoutHash = hash
			}
		}
	}
	inputs := map[string]string{}
	var inputRows []map[string]string
	// Fixed synthetic closure, independently checked by production ReadForward.
	for role, path := range map[string]string{
		"review":                  "docs/project/connected_speech/third_tone_stage5b_review.tsv",
		"decisions":               "docs/project/connected_speech/third_tone_stage5b_decisions.tsv",
		"rule_sources":            "docs/project/connected_speech/third_tone_stage5b_sources.tsv",
		"scope":                   "docs/project/connected_speech/third_tone_sandhi_scope.tsv",
		"phrase_pronunciations":   "internal_data/phrase_pinyin/phrase_pinyin.txt",
		"canonical_inventory":     "internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json",
		"canonical_decomposition": "internal_data/yime_syllable_decomposition.tsv",
		"packaged_decomposition":  "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv",
		"canonical_layout":        "internal_data/manual_key_layout.json",
		"packaged_layout":         "go-backend/input_methods/yime/data/yime_yinyuan_layout.json",
		"semantic_initials":       "syllable/yinyuan/zaoyin_yinyuan_enhanced.json",
		"semantic_musical":        "syllable/yinyuan/yueyin_yinyuan_enhanced.json",
		"canonical_symbols":       "internal_data/key_to_symbol.json",
		"initial_codepoints":      "syllable/yinyuan/shouyin_codepoint.json",
		"initial_analysis":        "syllable/pianyin/zaoyin_pianyin.json",
		"musical_attributes":      "syllable/yinyuan/variables_of_attributes.json",
		"pianyin_sequence":        "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json",
		"marked_finals":           "syllable/yinyuan/ganyin.json",
		"neutral_exceptions":      "internal_data/pinyin_source_db/neutral_tone_encoding_exceptions.json",
		"formal_pipeline":         "syllable/analysis/syllable_encoding_pipeline.py",
		"formal_splitter":         "syllable/analysis/syllable_splitter.py",
		"formal_encoder":          "syllable/codec/yinjie_encoder.py",
		"formal_initial_encoder":  "syllable/analysis/shouyin_encoder.py",
		"formal_initial_source":   "syllable/analysis/zaoyin_pianyin_source.py",
		"formal_musical_encoder":  "syllable/analysis/ganyin_encoder.py",
		"formal_musical_mapper":   "syllable/analysis/yueyin_mapper.py",
		"formal_id_chain":         "yime/utils/yinyuan_id_chain.py",
		"validator":               "tools/lexicon/validate_connected_speech_forward.py",
		"formal_import_01":        "syllable/__init__.py",
		"formal_import_02":        "syllable/analysis/__init__.py",
		"formal_import_03":        "syllable/analysis/ganyin_categorizer.py",
		"formal_import_04":        "syllable/analysis/ganyin_yinyuan_slots.py",
		"formal_import_05":        "syllable/analysis/segment_split.py",
		"formal_import_06":        "syllable/analysis/syllable.py",
		"formal_import_07":        "syllable/analysis/syllable_analyzer.py",
		"formal_import_08":        "syllable/analysis/syllable_categorizer.py",
		"formal_import_09":        "syllable/codec/__init__.py",
		"formal_import_10":        "syllable/codec/input_shorthand/__init__.py",
		"formal_import_11":        "syllable/codec/input_shorthand/tone_omission.py",
		"formal_import_12":        "syllable/codec/model_full_code/__init__.py",
		"formal_import_13":        "syllable/codec/model_full_code/structure.py",
		"formal_import_14":        "syllable/codec/neutral_tone_encoding.py",
		"formal_import_15":        "syllable/codec/paths.py",
		"formal_import_16":        "syllable/codec/variable_length_yinyuan/__init__.py",
		"formal_import_17":        "syllable/codec/variable_length_yinyuan/transform.py",
		"formal_import_18":        "syllable/codec/yinjie.py",
		"formal_import_19":        "syllable/codec/yinjie_api_manifest.py",
		"formal_import_20":        "syllable/codec/yinjie_decoder.py",
		"formal_import_21":        "yime/__init__.py",
		"formal_import_22":        "yime/utils/__init__.py",
		"formal_import_23":        "yime/utils/backup.py",
		"formal_import_24":        "yime/utils/charfilter.py",
		"formal_import_25":        "yime/utils/marked_pinyin.py",
		"formal_import_26":        "yime/utils/pinyin_normalizer.py",
		"formal_import_27":        "yime/utils/pinyin_zhuyin.py",
		"formal_import_28":        "yime/utils/reverse_key_value_pairs.py",
	} {
		sum := sha256.Sum256([]byte("synthetic " + role))
		hash := hex.EncodeToString(sum[:])
		if role == "packaged_layout" {
			hash = layoutHash
		}
		inputs[path] = hash
		inputRows = append(inputRows, map[string]string{"role": role, "path": path, "sha256": hash})
	}
	var ids []string
	for i := 1; i <= 24; i++ {
		ids = append(ids, fmt.Sprintf("T3-5B-%03d", i))
	}
	forwardHash := writeJSON(filepath.Join(speechRoot, "forward-source.json"), map[string]any{"schema_version": "yimecore-speech-forward-source-v1", "passed": true, "record_count": 24, "syllable_count": 50, "record_ids": ids, "input_sha256": inputs, "inputs": inputRows, "checks": map[string]bool{"canonical_phrase_source": true, "canonical_inventory_membership": true, "formal_four_id_decomposition": true, "canonical_layout_projection": true, "semantic_tone_substitutions": true, "inputs_unchanged": true}})
	recordsHash := writeJSON(filepath.Join(speechRoot, "admitted-records.json"), map[string]bool{"synthetic_packaging_only": true})
	if len(reviewed) > 0 {
		recordsHash = writeJSON(filepath.Join(speechRoot, "admitted-records.json"), reviewed[0])
	}
	admission := speechruntime.AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24, ForwardSHA256: forwardHash, Records: speechruntime.FileRef{Path: "admitted-records.json", SHA256: recordsHash}, Checks: map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true}, Modes: map[string]speechruntime.AdmissionMode{}}
	generation := yimebroker.BundleGenerationSpec{Version: "synthetic-normal-product-generation", Modes: map[string]yimebroker.BundleModeSpec{}}
	var current *yimecore.FileIndex
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var entries []yimecore.Entry
		for i := 0; i < 24; i++ {
			entries = append(entries, yimecore.Entry{Text: fmt.Sprintf("合成%02d", i), Code: fmt.Sprintf("ab%02d", i), Weight: 1})
			if len(reviewed) > 0 {
				record := reviewed[0].Records[i]
				entries[i] = yimecore.Entry{Text: record.Text, Code: record.Codes[mode].Canonical, Weight: 1}
			}
		}
		core := speechProductIndex(t, filepath.Join(speechRoot, "indexes"), mode, mode+"-core", entries)
		if mode == "variable" {
			current = core
		}
		data, err := os.ReadFile(filepath.Join(speechRoot, "indexes", mode+"-core.yidx"))
		if err != nil {
			t.Fatal(err)
		}
		speechProductWrite(t, filepath.Join(config.indexRoot, mode+".yidx"), data)
		for i := range entries {
			entries[i].Code = fmt.Sprintf("xy%02d", i)
			if len(reviewed) > 0 {
				entries[i].Code = reviewed[0].Records[i].Codes[mode].Alias
			}
		}
		module := speechProductIndex(t, filepath.Join(speechRoot, "indexes"), mode, mode+"-stage5c", entries)
		generation.Modes[mode] = yimebroker.BundleModeSpec{Core: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: "indexes/" + mode + "-core.yidx", ExpectedSHA256: core.SHA256()}, Modules: []yimebroker.BundleModuleSpec{{ID: speechruntime.ModuleID, Index: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: "indexes/" + mode + "-stage5c.yidx", ExpectedSHA256: module.SHA256()}}}}
		admission.Modes[mode] = speechruntime.AdmissionMode{CoreSHA256: core.SHA256(), ModuleSHA256: module.SHA256(), CanonicalCount: 24, AliasCount: 24}
	}
	receiptHash := writeJSON(filepath.Join(speechRoot, "admission.json"), admission)
	disabled := false
	config.speechProductSHA = writeJSON(filepath.Join(config.speechProductRoot, speechruntime.ProductManifestPath), speechruntime.ProductManifest{SchemaVersion: speechruntime.ProductSchema, ModuleID: speechruntime.ModuleID, ApprovedRecords: 24, DefaultEnabled: &disabled, LayoutSHA256: layoutHash, Admission: speechruntime.FileRef{Path: "admission.json", SHA256: receiptHash}, ForwardSource: speechruntime.FileRef{Path: "forward-source.json", SHA256: forwardHash}, Generation: generation})
	writeJSON(filepath.Join(config.speechProductRoot, speechruntime.CapabilityFilename), speechruntime.Capability{SchemaVersion: speechruntime.CapabilitySchema, Product: speechruntime.FileRef{Path: speechruntime.ProductManifestPath, SHA256: config.speechProductSHA}, DefaultEnabled: &disabled})
	return config, current
}

func TestSpeechProductRealSettingsSnapshotsAndGenerationFailClosed(t *testing.T) {
	config, core := speechBrokerProductFixture(t)
	product, err := openBrokerSpeechProduct(config)
	if err != nil {
		t.Fatal(err)
	}
	defer product.Close()
	model, err := yimecore.NewUserModel(config.userModelSourceID)
	if err != nil {
		t.Fatal(err)
	}
	newEngine := func() engineapi.Engine {
		modules, err := product.Modules("variable", core)
		if err != nil {
			t.Fatal(err)
		}
		engine, err := buildMultiModeEngine(config, "variable", core, modules, model, nil)
		if err != nil {
			t.Fatal(err)
		}
		return engine
	}
	hasModule := func(engine engineapi.Engine, code string) bool {
		for _, candidate := range speechProductApply(t, engine, code).State.Candidates {
			if strings.HasPrefix(candidate.SourceID, speechruntime.ModuleID+"@") {
				return true
			}
		}
		return false
	}
	oldOff := newEngine()
	if hasModule(oldOff, "xy00") {
		t.Fatal("missing settings enabled static speech")
	}
	if err := speechruntime.SaveSettings(config.speechSettings, true, true); err != nil {
		t.Fatal(err)
	}
	enabled := newEngine()
	if !hasModule(enabled, "xy00") || hasModule(oldOff, "xy00") {
		t.Fatal("new setting failed session snapshot isolation")
	}
	result := speechProductApply(t, enabled, "xy00")
	selected := ""
	for _, candidate := range result.State.Candidates {
		if candidate.Text == "合成00" {
			selected = candidate.ID
		}
	}
	if selected == "" {
		t.Fatal("enabled synthetic alias absent")
	}
	if _, err := enabled.Select(selected); err != nil {
		t.Fatal(err)
	}
	generation := model.Generation()
	if err := speechruntime.SaveSettings(config.speechSettings, false, true); err != nil {
		t.Fatal(err)
	}
	newOff := newEngine()
	if hasModule(newOff, "xy01") || !hasModule(enabled, "xy01") {
		t.Fatal("off changed old engine or failed new engine")
	}
	if model.Generation() != generation || model.SourceID() != config.userModelSourceID {
		t.Fatal("toggle changed normal model")
	}
	if err := speechruntime.SaveSettings(config.speechSettings, true, true); err != nil {
		t.Fatal(err)
	}
	changed := speechProductIndex(t, t.TempDir(), "variable", "new-core", []yimecore.Entry{{Text: "新布局", Code: "zz", Weight: 1}})
	if _, err := product.Modules("variable", changed); err == nil {
		t.Fatal("new core mixed with old module")
	}
	if model.Generation() != generation {
		t.Fatal("rejected new session modified learning")
	}
	speechProductWrite(t, config.speechSettings, []byte("{}"))
	if _, err := product.Modules("variable", core); err == nil {
		t.Fatal("new session silently accepted corrupt settings")
	}
	if _, err := os.Stat(config.userSnapshot); !os.IsNotExist(err) {
		t.Fatal("snapshot checks opened durable state")
	}
}

func TestSpeechProductOffAllowsExistingAlternativeLayoutButOnStartupRejects(t *testing.T) {
	config, _ := speechBrokerProductFixture(t)
	speechProductWrite(t, filepath.Join(config.annotationDataDir, "yime_yinyuan_layout.json"), []byte("alternative-layout"))
	product, err := openBrokerSpeechProduct(config)
	if err != nil {
		t.Fatal("disabled capability blocked existing layout", err)
	}
	_ = product.Close()
	if err := speechruntime.SaveSettings(config.speechSettings, true, true); err != nil {
		t.Fatal(err)
	}
	if product, err := openBrokerSpeechProduct(config); err == nil {
		_ = product.Close()
		t.Fatal("enabled startup mixed layout")
	}
	if _, err := os.Stat(config.userSnapshot); !os.IsNotExist(err) {
		t.Fatal("rejected mismatch opened durable state")
	}
}

func speechProductIndex(t *testing.T, root, mode, name string, entries []yimecore.Entry) *yimecore.FileIndex {
	t.Helper()
	source := filepath.Join(root, name+"-provenance.json")
	path := filepath.Join(root, name+".yidx")
	speechProductWrite(t, source, []byte("synthetic-only"))
	if _, err := yimecore.BuildIndexEntries(mode, entries, source, path); err != nil {
		t.Fatal(err)
	}
	index, err := yimecore.OpenResidentFileIndex(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = index.Close() })
	return index
}

func speechProductApply(t *testing.T, engine engineapi.Engine, code string) engineapi.Result {
	t.Helper()
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			t.Fatal(err)
		}
	}
	return result
}

func TestSpeechProductNormalBuilderPreservesAllExistingLayersAndLearning(t *testing.T) {
	for _, mode := range []string{"full", "variable", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			core := speechProductIndex(t, root, mode, "core", []yimecore.Entry{{Text: "核心词", Code: "ab", Weight: 100}, {Text: "屏蔽项", Code: "ab", Weight: 99}})
			professional := speechProductIndex(t, root, mode, "professional", []yimecore.Entry{{Text: "专业词", Code: "ab", Weight: 80}})
			speech := speechProductIndex(t, root, mode, "speech", []yimecore.Entry{{Text: "语流词", Code: "ab", Weight: 1}})
			speechProductWrite(t, filepath.Join(root, "custom_phrase_"+mode+".txt"), []byte("# synthetic user lexicon\n用户词\tab\t9999\n"))
			blocklist := filepath.Join(root, "blocklist.txt")
			speechProductWrite(t, blocklist, []byte("屏蔽项\n"))
			config := multiModeConfig{userLexiconDir: root, userBlocklist: blocklist, learningConfig: filepath.Join(root, "learning.json")}
			model, err := yimecore.NewUserModel("existing-normal-product-namespace")
			if err != nil {
				t.Fatal(err)
			}
			modules := []yimecore.BundleModule{{ID: "professional:synthetic", Index: professional}, {ID: speechruntime.ModuleID, Index: speech}}
			engine, err := buildMultiModeEngine(config, mode, core, modules, model, &candidateannotation.Resolver{})
			if err != nil {
				t.Fatal(err)
			}
			result := speechProductApply(t, engine, "ab")
			seen := map[string]string{}
			for _, candidate := range result.State.Candidates {
				seen[candidate.Text] = candidate.ID
				if candidate.Annotations.KeySequence != "ab" {
					t.Fatal("annotations lost in composed engine")
				}
			}
			for _, text := range []string{"核心词", "专业词", "语流词", "用户词"} {
				if seen[text] == "" {
					t.Fatal("normal builder dropped a source layer")
				}
			}
			if seen["屏蔽项"] != "" {
				t.Fatal("blocklist did not cover module composition")
			}
			before := model.Generation()
			if selected, err := engine.Select(seen["语流词"]); err != nil || selected.Commit != "语流词" {
				t.Fatal("module selection/commit failed")
			}
			if model.Generation() <= before || model.SourceID() != "existing-normal-product-namespace" {
				t.Fatal("speech changed or bypassed normal learning namespace")
			}
			generation := model.Generation()
			withoutSpeech, err := buildMultiModeEngine(config, mode, core, modules[:1], model, &candidateannotation.Resolver{})
			if err != nil {
				t.Fatal(err)
			}
			for _, candidate := range speechProductApply(t, withoutSpeech, "ab").State.Candidates {
				if strings.HasPrefix(candidate.SourceID, speechruntime.ModuleID+"@") {
					t.Fatal("disabled new engine retained static speech module")
				}
			}
			oldHasSpeech := false
			for _, candidate := range speechProductApply(t, engine, "ab").State.Candidates {
				oldHasSpeech = oldHasSpeech || candidate.Text == "语流词"
			}
			if !oldHasSpeech || model.Generation() != generation {
				t.Fatal("new engine construction changed old session or learning")
			}
			if err := learningconfig.Save(config.learningConfig, false); err != nil {
				t.Fatal(err)
			}
			inactive, err := enabledUserModel(config.learningConfig, model)
			if err != nil || inactive != nil {
				t.Fatal("normal learning switch ignored")
			}
			withoutLearning, err := buildMultiModeEngine(config, mode, core, modules, inactive, nil)
			if err != nil {
				t.Fatal(err)
			}
			result = speechProductApply(t, withoutLearning, "ab")
			if len(result.State.Candidates) == 0 {
				t.Fatal("learning-disabled input failed")
			}
			if _, err := withoutLearning.Select(result.State.Candidates[0].ID); err != nil {
				t.Fatal(err)
			}
			if model.Generation() != generation {
				t.Fatal("learning-disabled composition mutated model")
			}
		})
	}
}

func TestSpeechProductFlagsKeepSeparateNormalAndExperimentEntries(t *testing.T) {
	root := t.TempDir()
	settings := filepath.Join(root, "speech.json")
	if speechProductRequested(nil) || !speechProductRequested([]string{"speech-settings"}) {
		t.Fatal("explicit flag classification")
	}
	if err := validateSpeechProductFlags(speechProductFlags, root, root, speechruntime.ProductManifestPath, strings.Repeat("a", 64), settings); err != nil {
		t.Fatal(err)
	}
	for _, names := range [][]string{speechProductFlags[:3], append(append([]string{}, speechProductFlags...), "speech-experiment-root")} {
		if err := validateSpeechProductFlags(names, root, root, speechruntime.ProductManifestPath, strings.Repeat("a", 64), settings); err == nil {
			t.Fatal("mixed/incomplete flags accepted")
		}
	}
	if product, err := openBrokerSpeechProduct(multiModeConfig{}); err != nil || product != nil {
		t.Fatal("old core-only path now needs capability")
	}
}

// Only the freshly compiled test executable enters this helper. It drives the
// actual main/runMultiMode functions, never an installed or historical image.
func TestSpeechProductProcessEntry(t *testing.T) {
	if os.Getenv("YIME_SYNTHETIC_PRODUCT_TEST_CHILD") != "1" {
		return
	}
	for i, arg := range os.Args {
		if arg == "--" {
			os.Args = append([]string{os.Args[0]}, os.Args[i+1:]...)
			break
		}
	}
	flag.CommandLine = flag.NewFlagSet("synthetic-product-broker", flag.ExitOnError)
	main()
	os.Exit(0)
}

func runSpeechProductTestProcess(t *testing.T, root string, args []string, input string) ([]byte, error) {
	t.Helper()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, executable, append([]string{"-test.run=^TestSpeechProductProcessEntry$", "--"}, args...)...)
	command.Dir = root
	command.Env = []string{"YIME_SYNTHETIC_PRODUCT_TEST_CHILD=1"}
	for _, key := range []string{"SYSTEMROOT", "WINDIR", "COMSPEC"} {
		if value := os.Getenv(key); value != "" {
			command.Env = append(command.Env, key+"="+value)
		}
	}
	for _, key := range []string{"APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "USERPROFILE"} {
		path := filepath.Join(root, "private-environment", key)
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
		command.Env = append(command.Env, key+"="+path)
	}
	command.Stdin = strings.NewReader(input)
	output, err := command.CombinedOutput()
	if ctx.Err() != nil {
		t.Fatal("synthetic normal Broker process timed out")
	}
	return output, err
}

func TestSpeechProductNormalCLIRejectsBeforeDurableAndKeepsLegacyNamespace(t *testing.T) {
	for _, kind := range []string{"legacy_core_only", "missing_capability", "bad_settings", "experiment_namespace"} {
		t.Run(kind, func(t *testing.T) {
			root := t.TempDir()
			indexRoot := filepath.Join(root, "indexes")
			for _, mode := range []string{"full", "variable", "shorthand"} {
				_ = speechProductIndex(t, indexRoot, mode, mode, []yimecore.Entry{{Text: "合成", Code: "ab", Weight: 1}})
			}
			state := filepath.Join(root, "state")
			snapshot := filepath.Join(state, "model.json")
			args := []string{"-index-root", indexRoot, "-trusted-client-id", "synthetic-normal-client", "-user-model-snapshot", snapshot, "-user-model-journal", filepath.Join(state, "model.journal"), "-user-model-source-id", "existing-normal-product-namespace"}
			if kind != "legacy_core_only" {
				install := filepath.Join(root, "own-product")
				if err := os.Mkdir(install, 0700); err != nil {
					t.Fatal(err)
				}
				settings := filepath.Join(root, "speech.json")
				hash := strings.Repeat("a", 64)
				if kind == "bad_settings" {
					hash = speechProductWrite(t, filepath.Join(install, "speech", "product.json"), []byte("{}"))
					data, _ := json.Marshal(map[string]any{"schema_version": speechruntime.CapabilitySchema, "default_enabled": false, "product": speechruntime.FileRef{Path: speechruntime.ProductManifestPath, SHA256: hash}})
					speechProductWrite(t, filepath.Join(install, speechruntime.CapabilityFilename), data)
					speechProductWrite(t, settings, []byte(`{"schema_version":"yimecore-speech-settings-v1","enabled":null}`))
				}
				if kind == "experiment_namespace" {
					args[len(args)-1] = speechruntime.ModelNamespace
				}
				args = append(args, "-speech-product-root", install, "-speech-product-manifest", speechruntime.ProductManifestPath, "-speech-product-sha256", hash, "-speech-settings", settings)
			}
			input := `{"version":1,"sequence":1,"operation":"open","mode":"variable"}` + "\n"
			output, err := runSpeechProductTestProcess(t, root, args, input)
			if kind == "legacy_core_only" {
				if err != nil {
					t.Fatalf("legacy normal process: %v %s", err, output)
				}
				var response yimebroker.Response
				if err := json.Unmarshal(output, &response); err != nil || response.Error != nil || response.SessionID == "" {
					t.Fatal("normal transport did not create session")
				}
				model, err := yimecore.OpenUserModel(snapshot, "existing-normal-product-namespace")
				if err != nil || model.SourceID() != "existing-normal-product-namespace" {
					t.Fatal("normal durable namespace changed")
				}
				if _, err := os.Stat(filepath.Join(root, "speech.json")); !os.IsNotExist(err) {
					t.Fatal("legacy path created speech state")
				}
			} else {
				if err == nil {
					t.Fatal("invalid product startup succeeded")
				}
				if _, err := os.Stat(state); !os.IsNotExist(err) {
					t.Fatal("rejected startup opened durable state")
				}
			}
		})
	}
}
