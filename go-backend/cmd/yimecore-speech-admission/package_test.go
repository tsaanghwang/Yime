package main

import (
	"bytes"
	"crypto/sha256"
	"debug/pe"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/symlinkfixture"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

// These are synthetic packaging/parser fixtures. They do not assert linguistic
// approval and the stub PE images are inspected only, never executed.
var packageFixtureSources = map[string]string{
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
}

type speechPackageFixture struct {
	repo, source, output, broker, tool string
	forward                            speechruntime.ForwardReceipt
}

func packageFixtureWrite(t *testing.T, path string, data []byte) string {
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

func packageFixtureJSON(t *testing.T, path string, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return packageFixtureWrite(t, path, data)
}

func packageFixturePE(t *testing.T, machine uint16) []byte {
	t.Helper()
	data := make([]byte, 128)
	copy(data, "MZ")
	binary.LittleEndian.PutUint32(data[60:], 128)
	var buffer bytes.Buffer
	buffer.Write(data)
	buffer.Write([]byte{'P', 'E', 0, 0})
	header := pe.FileHeader{Machine: machine, SizeOfOptionalHeader: uint16(binary.Size(pe.OptionalHeader64{})), Characteristics: pe.IMAGE_FILE_EXECUTABLE_IMAGE}
	if err := binary.Write(&buffer, binary.LittleEndian, header); err != nil {
		t.Fatal(err)
	}
	optional := pe.OptionalHeader64{Magic: 0x20b, NumberOfRvaAndSizes: 16}
	if err := binary.Write(&buffer, binary.LittleEndian, optional); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func newSpeechPackageFixture(t *testing.T) *speechPackageFixture {
	t.Helper()
	base := t.TempDir()
	f := &speechPackageFixture{repo: filepath.Join(base, "source-repository"), source: filepath.Join(base, "speech-admission-fresh-fixture"), output: filepath.Join(base, "speech-admission-package-fixture"), broker: filepath.Join(base, "new-build", "broker.exe"), tool: filepath.Join(base, "new-build", "tool.exe")}
	f.forward = speechruntime.ForwardReceipt{SchemaVersion: "yimecore-speech-forward-source-v1", Passed: true, RecordCount: 24, SyllableCount: 50, InputSHA256: map[string]string{}, Checks: map[string]bool{"canonical_phrase_source": true, "canonical_inventory_membership": true, "formal_four_id_decomposition": true, "canonical_layout_projection": true, "semantic_tone_substitutions": true, "inputs_unchanged": true}}
	for role, path := range packageFixtureSources {
		digest := packageFixtureWrite(t, filepath.Join(f.repo, filepath.FromSlash(path)), []byte("synthetic static audit source "+role))
		f.forward.InputSHA256[path] = digest
		f.forward.Inputs = append(f.forward.Inputs, struct {
			Role   string `json:"role"`
			Path   string `json:"path"`
			SHA256 string `json:"sha256"`
		}{role, path, digest})
	}
	for i := 1; i <= 24; i++ {
		f.forward.RecordIDs = append(f.forward.RecordIDs, fmt.Sprintf("T3-5B-%03d", i))
	}
	forwardHash := packageFixtureJSON(t, filepath.Join(f.source, "forward-source.json"), f.forward)
	recordHash := packageFixtureJSON(t, filepath.Join(f.source, "admitted-records.json"), map[string]any{"fixture_only": true})
	receipt := speechruntime.AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24, ForwardSHA256: forwardHash, Records: speechruntime.FileRef{Path: "admitted-records.json", SHA256: recordHash}, Checks: map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true}, Modes: map[string]speechruntime.AdmissionMode{}}
	generation := yimebroker.BundleGenerationSpec{Version: "synthetic-packaging-only", Modes: map[string]yimebroker.BundleModeSpec{}}
	if err := os.Mkdir(filepath.Join(f.source, "indexes"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var coreEntries, moduleEntries []yimecore.Entry
		for i := 0; i < 24; i++ {
			coreEntries = append(coreEntries, yimecore.Entry{Text: fmt.Sprintf("合成测试%02d", i), Code: fmt.Sprintf("abc%02d", i), Weight: 100})
			moduleEntries = append(moduleEntries, yimecore.Entry{Text: fmt.Sprintf("合成测试%02d", i), Code: fmt.Sprintf("xyz%02d", i), Weight: 1})
		}
		corePath, modulePath := "indexes/"+mode+"-core.yidx", "indexes/"+mode+"-stage5c.yidx"
		core, err := yimecore.BuildIndexEntries(mode, coreEntries, filepath.Join(f.source, "admitted-records.json"), filepath.Join(f.source, filepath.FromSlash(corePath)))
		if err != nil {
			t.Fatal(err)
		}
		module, err := yimecore.BuildIndexEntries(mode, moduleEntries, filepath.Join(f.source, "admitted-records.json"), filepath.Join(f.source, filepath.FromSlash(modulePath)))
		if err != nil {
			t.Fatal(err)
		}
		generation.Modes[mode] = yimebroker.BundleModeSpec{Core: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: corePath, ExpectedSHA256: core.IndexSHA256}, Modules: []yimebroker.BundleModuleSpec{{ID: speechruntime.ModuleID, Index: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: modulePath, ExpectedSHA256: module.IndexSHA256}}}}
		receipt.Modes[mode] = speechruntime.AdmissionMode{CoreSHA256: core.IndexSHA256, ModuleSHA256: module.IndexSHA256, CanonicalCount: 24, AliasCount: 24}
	}
	receiptHash := packageFixtureJSON(t, filepath.Join(f.source, "admission.json"), receipt)
	bundle := speechruntime.Manifest{SchemaVersion: speechruntime.Schema, ApprovedRecords: 24, Admission: speechruntime.FileRef{Path: "admission.json", SHA256: receiptHash}, ForwardSource: speechruntime.FileRef{Path: "forward-source.json", SHA256: forwardHash}, Generation: generation}
	packageFixtureJSON(t, filepath.Join(f.source, "bundle-off.json"), bundle)
	bundle.Enabled = true
	packageFixtureJSON(t, filepath.Join(f.source, "bundle-on.json"), bundle)
	packageFixtureWrite(t, f.broker, packageFixturePE(t, pe.IMAGE_FILE_MACHINE_AMD64))
	packageFixtureWrite(t, f.tool, packageFixturePE(t, pe.IMAGE_FILE_MACHINE_AMD64))
	return f
}

func (f *speechPackageFixture) seal(t *testing.T) string {
	t.Helper()
	brokerHash, err := speechruntime.HashFile(f.broker)
	if err != nil {
		t.Fatal(err)
	}
	if err := packageCandidateWithTool(f.repo, f.source, f.output, f.broker, brokerHash, f.tool); err != nil {
		t.Fatal(err)
	}
	digest, err := speechruntime.HashFile(filepath.Join(f.output, candidatePackageManifest))
	if err != nil {
		t.Fatal(err)
	}
	return digest
}

func TestSpeechPackageSelfContainedRelocationAndReadOnlyVerification(t *testing.T) {
	f := newSpeechPackageFixture(t)
	digest := f.seal(t)
	manifest, err := verifyPackage(f.output, digest)
	if err != nil {
		t.Fatal(err)
	}
	if len(manifest.Files) != 69 || *manifest.Installable || *manifest.DefaultEnabled {
		t.Fatal("incorrect sealed policy")
	}
	// Renaming owned fixture roots removes all original source paths without
	// deleting data, showing that verification needs only the sealed directory.
	for _, path := range []string{f.repo, f.source, filepath.Dir(f.broker)} {
		if err := os.Rename(path, path+"-unavailable"); err != nil {
			t.Fatal(err)
		}
	}
	moved := filepath.Join(t.TempDir(), "speech-admission-package-relocated")
	if err := os.Rename(f.output, moved); err != nil {
		t.Fatal(err)
	}
	actual, err := verifyPackage(moved, digest)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(manifest, actual) {
		t.Fatal("relocation changed manifest")
	}
	after, err := speechruntime.HashFile(filepath.Join(moved, candidatePackageManifest))
	if err != nil || after != digest {
		t.Fatal("readonly verification changed sealed package")
	}
	if _, err := os.Stat(filepath.Join(moved, "state")); !os.IsNotExist(err) {
		t.Fatal("verification created model state")
	}
}

func TestSpeechPackageStrictManifestPolicyAndFileSet(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(map[string]any)
	}{
		{"unknown_top", func(m map[string]any) { m["install_script"] = "forbidden" }},
		{"case_alias_top", func(m map[string]any) { m["INSTALLABLE"] = m["installable"]; delete(m, "installable") }},
		{"missing_installable", func(m map[string]any) { delete(m, "installable") }},
		{"null_installable", func(m map[string]any) { m["installable"] = nil }},
		{"installable", func(m map[string]any) { m["installable"] = true }},
		{"missing_default_enabled", func(m map[string]any) { delete(m, "default_enabled") }},
		{"enabled_default", func(m map[string]any) { m["default_enabled"] = true }},
		{"enabled_bundle_default", func(m map[string]any) { m["default_bundle"] = "bundle-on.json" }},
		{"wrong_architecture", func(m map[string]any) { m["architecture"] = "windows-arm64" }},
		{"wrong_schema", func(m map[string]any) { m["schema_version"] = "local-product" }},
		{"missing_payload", func(m map[string]any) { m["files"] = m["files"].([]any)[1:] }},
		{"extra_payload", func(m map[string]any) { m["files"] = append(m["files"].([]any), m["files"].([]any)[0]) }},
		{"duplicate_role", func(m map[string]any) { files := m["files"].([]any); files[1] = files[0] }},
		{"wrong_role", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["role"] = "unknown" }},
		{"wrong_path", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["path"] = "../outside" }},
		{"windows_path", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["path"] = "bin\\YimeBroker-speech.exe" }},
		{"uppercase_hash", func(m map[string]any) {
			item := m["files"].([]any)[0].(map[string]any)
			item["sha256"] = strings.ToUpper(item["sha256"].(string))
		}},
		{"invalid_hash", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["sha256"] = strings.Repeat("z", 64) }},
		{"wrong_size", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["size"] = float64(1) }},
		{"missing_size", func(m map[string]any) { delete(m["files"].([]any)[0].(map[string]any), "size") }},
		{"unknown_file_field", func(m map[string]any) { m["files"].([]any)[0].(map[string]any)["optional"] = true }},
	}
	f := newSpeechPackageFixture(t)
	f.seal(t)
	path := filepath.Join(f.output, candidatePackageManifest)
	original, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var value map[string]any
			if err := json.Unmarshal(original, &value); err != nil {
				t.Fatal(err)
			}
			tc.mutate(value)
			hash := packageFixtureJSON(t, path, value)
			if _, err := verifyPackage(f.output, hash); err == nil {
				t.Fatal("malformed package accepted")
			}
		})
	}
	for _, tc := range []struct {
		name string
		data []byte
	}{
		{"duplicate_json_key", bytes.Replace(original, []byte("{"), []byte("{\"installable\":false,"), 1)},
		{"trailing_json", append(append([]byte{}, original...), []byte("{}")...)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hash := packageFixtureWrite(t, path, tc.data)
			if _, err := verifyPackage(f.output, hash); err == nil {
				t.Fatal("ambiguous package JSON accepted")
			}
		})
	}
}

func TestSpeechPackageRejectsIncompleteOrChangedPayload(t *testing.T) {
	for _, relative := range []string{"bin/YimeBroker-speech.exe", "bin/YimeSpeechAdmission.exe", "sources/internal_data/phrase_pinyin/phrase_pinyin.txt", "sources/internal_data/manual_key_layout.json", "sources/syllable/codec/yinjie_encoder.py", "indexes/full-core.yidx", "indexes/full-stage5c.yidx", "indexes/variable-core.yidx", "indexes/variable-stage5c.yidx", "indexes/shorthand-core.yidx", "indexes/shorthand-stage5c.yidx"} {
		t.Run(relative, func(t *testing.T) {
			f := newSpeechPackageFixture(t)
			digest := f.seal(t)
			path := filepath.Join(f.output, filepath.FromSlash(relative))
			if err := os.Rename(path, path+".missing"); err != nil {
				t.Fatal(err)
			}
			if _, err := verifyPackage(f.output, digest); err == nil {
				t.Fatal("missing required payload accepted")
			}
		})
	}
	for _, kind := range []string{"unknown_file", "unknown_directory", "tampered_source", "tampered_index", "wrong_broker_arch", "wrong_tool_arch"} {
		t.Run(kind, func(t *testing.T) {
			f := newSpeechPackageFixture(t)
			digest := f.seal(t)
			switch kind {
			case "unknown_file":
				packageFixtureWrite(t, filepath.Join(f.output, "unexpected.txt"), []byte("fixture"))
			case "unknown_directory":
				if err := os.Mkdir(filepath.Join(f.output, "unexpected"), 0700); err != nil {
					t.Fatal(err)
				}
			case "tampered_source":
				packageFixtureWrite(t, filepath.Join(f.output, "sources", "internal_data", "manual_key_layout.json"), []byte("changed"))
			case "tampered_index":
				packageFixtureWrite(t, filepath.Join(f.output, "indexes", "full-stage5c.yidx"), []byte("changed"))
			case "wrong_broker_arch", "wrong_tool_arch":
				relative := "bin/YimeBroker-speech.exe"
				if kind == "wrong_tool_arch" {
					relative = "bin/YimeSpeechAdmission.exe"
				}
				path := filepath.Join(f.output, filepath.FromSlash(relative))
				hash := packageFixtureWrite(t, path, packageFixturePE(t, pe.IMAGE_FILE_MACHINE_ARM64))
				manifest, err := readPackageManifest(f.output, digest)
				if err != nil {
					t.Fatal(err)
				}
				for i := range manifest.Files {
					if manifest.Files[i].Path == relative {
						manifest.Files[i].SHA256 = hash
					}
				}
				digest = packageFixtureJSON(t, filepath.Join(f.output, candidatePackageManifest), manifest)
			}
			if _, err := verifyPackage(f.output, digest); err == nil {
				t.Fatal("changed or indirect payload accepted")
			}
		})
	}
}

func TestSpeechPackageCreationRejectsUnpinnedSourceAndExistingOutput(t *testing.T) {
	for _, kind := range []string{"missing_broker_pin", "wrong_broker_pin", "wrong_broker_arch", "wrong_tool_arch", "changed_forward_input", "existing_output", "nested_output", "bad_index"} {
		t.Run(kind, func(t *testing.T) {
			f := newSpeechPackageFixture(t)
			pin, err := speechruntime.HashFile(f.broker)
			if err != nil {
				t.Fatal(err)
			}
			switch kind {
			case "missing_broker_pin":
				pin = ""
			case "wrong_broker_pin":
				pin = strings.Repeat("0", 64)
			case "wrong_broker_arch":
				pin = packageFixtureWrite(t, f.broker, packageFixturePE(t, pe.IMAGE_FILE_MACHINE_I386))
			case "wrong_tool_arch":
				packageFixtureWrite(t, f.tool, packageFixturePE(t, pe.IMAGE_FILE_MACHINE_ARM64))
			case "changed_forward_input":
				packageFixtureWrite(t, filepath.Join(f.repo, "internal_data", "manual_key_layout.json"), []byte("changed"))
			case "existing_output":
				if err := os.Mkdir(f.output, 0700); err != nil {
					t.Fatal(err)
				}
			case "nested_output":
				f.output = filepath.Join(f.source, "speech-admission-package-nested")
			case "bad_index":
				packageFixtureWrite(t, filepath.Join(f.source, "indexes", "shorthand-stage5c.yidx"), []byte("changed"))
			}
			if err := packageCandidateWithTool(f.repo, f.source, f.output, f.broker, pin, f.tool); err == nil {
				t.Fatal("unsafe package creation accepted")
			}
			if kind != "existing_output" {
				if _, err := os.Stat(f.output); !os.IsNotExist(err) {
					t.Fatal("failed preflight created output")
				}
			}
		})
	}
}

func TestSpeechPackagePrivateChildEnvironmentAndFreshOutput(t *testing.T) {
	root := filepath.Join(t.TempDir(), "speech-admission-exercise-environment")
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	inherited := []string{"SystemRoot=C:\\Windows", "YIME_BROKER_SMOKE=1", "yime_lexicon_external_root=outside", "RIME_DATA_DIR=private-user", "PIME_HOME=production", "APPDATA=user-roaming", "LOCALAPPDATA=user-local", "TEMP=user-temp", "TMP=user-tmp", "USERPROFILE=user-profile", "PATH=untrusted-bin", "SECRET=private", "=C:=user-working-dir"}
	launch, err := packageChildLaunch(root, inherited)
	if err != nil {
		t.Fatal(err)
	}
	if launch.directory != root {
		t.Fatal("private child cwd not fixed")
	}
	actual := map[string]string{}
	for _, pair := range launch.environment {
		key, value, _ := strings.Cut(pair, "=")
		actual[strings.ToUpper(key)] = value
		if strings.HasPrefix(strings.ToUpper(key), "YIME") || strings.HasPrefix(strings.ToUpper(key), "RIME") || strings.HasPrefix(strings.ToUpper(key), "PIME") {
			t.Fatal("product switch leaked")
		}
	}
	if len(actual) != 6 || actual["SYSTEMROOT"] != "C:\\Windows" {
		t.Fatal("unexpected inherited child environment")
	}
	for _, key := range []string{"APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "USERPROFILE"} {
		wanted := filepath.Join(root, "private-environment", strings.ToLower(key))
		if actual[key] != wanted {
			t.Fatal("private path not isolated")
		}
		if info, err := os.Stat(wanted); err != nil || !info.IsDir() {
			t.Fatal("private path absent")
		}
	}
	f := newSpeechPackageFixture(t)
	digest := f.seal(t)
	for _, output := range []string{f.output, filepath.Join(f.output, "speech-admission-exercise-nested"), filepath.Dir(f.output), root} {
		if err := exercisePackage(f.output, digest, output); err == nil {
			t.Fatal("nonfresh or overlapping exercise output accepted")
		}
	}
	if _, err := verifyPackage(f.output, digest); err != nil {
		t.Fatal("failed exercise altered sealed package")
	}
}

func TestSpeechPackageRejectsSymlinkPayload(t *testing.T) {
	f := newSpeechPackageFixture(t)
	digest := f.seal(t)
	if _, err := verifyPackage(f.output, digest); err != nil {
		t.Fatal("plain fixture rejected", err)
	}
	target := filepath.Join(f.output, "admitted-records.json")
	renamed := filepath.Join(t.TempDir(), "fixture-records.json")
	if err := os.Rename(target, renamed); err != nil {
		t.Fatal(err)
	}
	symlinkfixture.Create(t, renamed, target)
	_, err := verifyPackage(f.output, digest)
	symlinkfixture.Rejected(t, err, symlinkfixture.PackageDiagnostic())
}

func TestSpeechPackageCloneCopiesOnlyRuntimeAndPreservesSeal(t *testing.T) {
	f := newSpeechPackageFixture(t)
	digest := f.seal(t)
	manifest, err := verifyPackage(f.output, digest)
	if err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(t.TempDir(), "speech-admission-exercise-clone")
	if err := os.Mkdir(output, 0700); err != nil {
		t.Fatal(err)
	}
	launch, brokerSHA, err := clonePackageRuntime(f.output, output, manifest, []string{"YIME_BROKER_SMOKE=1", "APPDATA=production"})
	if err != nil {
		t.Fatal(err)
	}
	if launch.directory != output || !packageDigest(brokerSHA) {
		t.Fatal("clone launch identity missing")
	}
	count := 0
	if err := filepath.WalkDir(output, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !entry.IsDir() {
			count++
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if count != 12 {
		t.Fatalf("clone has %d files, want only 12 runtime files", count)
	}
	for _, name := range []string{"state", "sources", "package-manifest.json", "process-outcome.json", "bin/YimeSpeechAdmission.exe"} {
		if _, err := os.Stat(filepath.Join(output, filepath.FromSlash(name))); !os.IsNotExist(err) {
			t.Fatal("clone copied forbidden state/tool/source")
		}
	}
	if err := verifyPackageRuntime(output); err != nil {
		t.Fatal(err)
	}
	if _, err := verifyPackage(f.output, digest); err != nil {
		t.Fatal("clone changed sealed input")
	}
	if _, _, err := clonePackageRuntime(f.output, output, manifest, nil); err == nil {
		t.Fatal("clone silently overwrote existing files")
	}
}

func packageFixturePEWithImport(t *testing.T, library string, delay bool) []byte {
	t.Helper()
	data := make([]byte, 128)
	copy(data, "MZ")
	binary.LittleEndian.PutUint32(data[60:], 128)
	var buffer bytes.Buffer
	buffer.Write(data)
	buffer.Write([]byte{'P', 'E', 0, 0})
	header := pe.FileHeader{Machine: pe.IMAGE_FILE_MACHINE_AMD64, NumberOfSections: 1, SizeOfOptionalHeader: uint16(binary.Size(pe.OptionalHeader64{})), Characteristics: pe.IMAGE_FILE_EXECUTABLE_IMAGE}
	optional := pe.OptionalHeader64{Magic: 0x20b, NumberOfRvaAndSizes: 16}
	optional.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_IMPORT] = pe.DataDirectory{VirtualAddress: 4096, Size: 40}
	if delay {
		optional.DataDirectory[pe.IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT] = pe.DataDirectory{VirtualAddress: 4096, Size: 40}
	}
	section := pe.SectionHeader32{VirtualSize: 512, VirtualAddress: 4096, SizeOfRawData: 512, PointerToRawData: 512}
	copy(section.Name[:], ".idata")
	for _, value := range []any{header, optional, section} {
		if err := binary.Write(&buffer, binary.LittleEndian, value); err != nil {
			t.Fatal(err)
		}
	}
	buffer.Write(make([]byte, 512-buffer.Len()))
	imports := make([]byte, 512)
	// No named symbol is needed: DLL-name validation must also cover imports
	// that would be omitted by debug/pe.ImportedSymbols (e.g. ordinal only).
	binary.LittleEndian.PutUint32(imports[12:16], 4096+64)
	copy(imports[64:], library)
	buffer.Write(imports)
	return buffer.Bytes()
}

func TestSpeechPackagePEImportClosure(t *testing.T) {
	for _, tc := range []struct {
		name, library    string
		delay, wantError bool
	}{
		{"system_library", "KERNEL32.dll", false, false},
		{"rime", "rime.dll", false, true},
		{"rime_case", "LiBRiMe.dll", false, true},
		{"pime", "PIMETextService.dll", false, true},
		{"delay_import", "KERNEL32.dll", true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "synthetic-never-execute.exe")
			packageFixtureWrite(t, path, packageFixturePEWithImport(t, tc.library, tc.delay))
			if err := requireAMD64Executable(path); (err != nil) != tc.wantError {
				t.Fatalf("import validation error=%v", err)
			}
		})
	}
}
