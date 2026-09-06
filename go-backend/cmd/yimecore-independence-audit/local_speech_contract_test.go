package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestLocalSpeechDescriptorOptionalAndStrict(t *testing.T) {
	if value, err := decodeLocalSpeechDescriptor([]byte(`{"version":"0.1.0-local.12"}`)); err != nil || value != nil {
		t.Fatal("legacy descriptor acquired a speech prerequisite")
	}
	good := `{"speech":{"capability_path":"speech-capability.json","default_enabled":false}}`
	if value, err := decodeLocalSpeechDescriptor([]byte(good)); err != nil || value == nil {
		t.Fatal("fixed optional declaration rejected")
	}
	for name, raw := range map[string]string{
		"null": `{"speech":null}`, "array": `{"speech":[]}`, "empty": `{"speech":{}}`,
		"missing_default": `{"speech":{"capability_path":"speech-capability.json"}}`,
		"missing_path":    `{"speech":{"default_enabled":false}}`,
		"enabled":         strings.Replace(good, "false", "true", 1),
		"null_default":    strings.Replace(good, "false", "null", 1),
		"alternate_path":  strings.Replace(good, "speech-capability.json", "speech/capability.json", 1),
		"escape":          strings.Replace(good, "speech-capability.json", "../speech-capability.json", 1),
		"unknown":         strings.Replace(good, `"default_enabled":false`, `"default_enabled":false,"extra":true`, 1),
		"duplicate_inner": strings.Replace(good, `"default_enabled":false`, `"default_enabled":false,"default_enabled":false`, 1),
		"duplicate_outer": `{"speech":null,` + good[1:],
		"case":            strings.Replace(good, `"speech"`, `"Speech"`, 1),
		"trailing":        good + `{}`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := decodeLocalSpeechDescriptor([]byte(raw)); err == nil {
				t.Fatal("invalid optional declaration accepted")
			}
		})
	}
}

type localSpeechFixture struct {
	root       string
	entries    map[string]manifestFile
	admitted   connectedspeech.AdmissionResult
	product    speechruntime.ProductManifest
	admission  speechruntime.AdmissionReceipt
	forward    map[string]any
	capability speechruntime.Capability
	binding    map[string]string
}

func localSpeechHash(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func (f *localSpeechFixture) write(t *testing.T, path string, data []byte) string {
	t.Helper()
	full := filepath.Join(f.root, filepath.FromSlash(path))
	if err := os.MkdirAll(filepath.Dir(full), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, data, 0600); err != nil {
		t.Fatal(err)
	}
	digest := localSpeechHash(data)
	f.entries[strings.ToLower(path)] = manifestFile{Path: path, Bytes: int64(len(data)), SHA256: digest}
	return digest
}

func (f *localSpeechFixture) writeJSON(t *testing.T, path string, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return f.write(t, path, data)
}

func reviewedLocalSpeechFixture(t *testing.T) connectedspeech.AdmissionResult {
	t.Helper()
	repo, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	paths := map[string]string{
		"review":    "docs/project/connected_speech/third_tone_stage5b_review.tsv",
		"decisions": "docs/project/connected_speech/third_tone_stage5b_decisions.tsv",
		"sources":   "docs/project/connected_speech/third_tone_stage5b_sources.tsv",
		"inventory": "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv",
		"layout":    "go-backend/input_methods/yime/data/yime_yinyuan_layout.json",
	}
	hashes := map[string]string{}
	for role, relative := range paths {
		paths[role] = filepath.Join(repo, filepath.FromSlash(relative))
		data, err := os.ReadFile(paths[role])
		if err != nil {
			t.Fatal(err)
		}
		hashes[role] = localSpeechHash(data)
	}
	// The formal admission reads only the fixed repository sources and returns
	// in-memory records. No historical generator, installed program or Rime runs.
	admitted, err := connectedspeech.AdmitStage5C(connectedspeech.AdmissionInput{
		ReviewPath: paths["review"], DecisionsPath: paths["decisions"], SourcesPath: paths["sources"],
		InventoryPath: paths["inventory"], LayoutPath: paths["layout"], ExpectedSHA256: hashes,
	})
	if err != nil {
		t.Fatal(err)
	}
	return admitted
}

// This is a synthetic packaging receipt, not a claim that this test executed
// the source pipeline. Fixed roles/paths exercise the production closure check.
func localSpeechForwardFixture(layoutHash string, admitted connectedspeech.AdmissionResult) map[string]any {
	inputs := map[string]string{}
	rows := []map[string]string{}
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
		digest := localSpeechHash([]byte("synthetic closure " + role))
		if role == "packaged_layout" {
			digest = layoutHash
		}
		inputs[path] = digest
		rows = append(rows, map[string]string{"role": role, "path": path, "sha256": digest})
	}
	ids := []string{}
	for _, record := range admitted.Records {
		ids = append(ids, record.ReviewID)
	}
	return map[string]any{"schema_version": "yimecore-speech-forward-source-v1", "passed": true, "record_count": 24, "syllable_count": 50,
		"record_ids": ids, "input_sha256": inputs, "inputs": rows,
		"checks": map[string]bool{"canonical_phrase_source": true, "canonical_inventory_membership": true, "formal_four_id_decomposition": true,
			"canonical_layout_projection": true, "semantic_tone_substitutions": true, "inputs_unchanged": true}}
}

func newLocalSpeechFixture(t *testing.T, root string) *localSpeechFixture {
	t.Helper()
	if root == "" {
		root = t.TempDir()
	}
	f := &localSpeechFixture{root: root, entries: map[string]manifestFile{}, admitted: reviewedLocalSpeechFixture(t)}
	for _, path := range append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...) {
		f.entries[strings.ToLower(path)] = manifestFile{Path: path}
	}
	var descriptor map[string]any
	if err := json.Unmarshal(localDescriptorFixture(t), &descriptor); err != nil {
		t.Fatal(err)
	}
	descriptor["package_contract"], descriptor["installable"], descriptor["version"] = localInstallableContract, true, "0.1.0-local.13"
	descriptor["speech"] = map[string]any{"capability_path": speechruntime.CapabilityFilename, "default_enabled": false}
	f.writeJSON(t, "local-product.json", descriptor)
	layoutHash := ""
	for _, name := range []string{"yime_yinyuan_layout.json", "yime_pinyin_codes.tsv", "pinyin_normalized.json", "yime_pua_pinyin.json"} {
		data, err := os.ReadFile(filepath.Join("../../input_methods/yime/data", name))
		if err != nil {
			t.Fatal(err)
		}
		digest := f.write(t, "data/"+name, data)
		if name == "yime_yinyuan_layout.json" {
			layoutHash = digest
		}
	}
	f.forward = localSpeechForwardFixture(layoutHash, f.admitted)
	recordHash := f.writeJSON(t, "speech/admitted-records.json", f.admitted)
	f.admission = speechruntime.AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24,
		Records: speechruntime.FileRef{Path: "admitted-records.json", SHA256: recordHash},
		Checks:  map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true},
		Modes:   map[string]speechruntime.AdmissionMode{}}
	disabled := false
	f.product = speechruntime.ProductManifest{SchemaVersion: speechruntime.ProductSchema, ModuleID: speechruntime.ModuleID, ApprovedRecords: 24,
		DefaultEnabled: &disabled, LayoutSHA256: layoutHash, Generation: yimebroker.BundleGenerationSpec{Version: "synthetic-auditor-generation", Modes: map[string]yimebroker.BundleModeSpec{}}}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var coreEntries, aliasEntries []yimecore.Entry
		for _, record := range f.admitted.Records {
			coreEntries = append(coreEntries, yimecore.Entry{Text: record.Text, Code: record.Codes[mode].Canonical, Weight: 100})
			aliasEntries = append(aliasEntries, yimecore.Entry{Text: record.Text, Code: record.Codes[mode].Alias, Weight: 1})
		}
		coreRel, aliasRel := "indexes/"+mode+"-core.yidx", "indexes/"+mode+"-stage5c.yidx"
		if err := os.MkdirAll(filepath.Join(root, "speech/indexes"), 0700); err != nil {
			t.Fatal(err)
		}
		core, err := yimecore.BuildIndexEntries(mode, coreEntries, filepath.Join(root, "speech/admitted-records.json"), filepath.Join(root, "speech", filepath.FromSlash(coreRel)))
		if err != nil {
			t.Fatal(err)
		}
		alias, err := yimecore.BuildIndexEntries(mode, aliasEntries, filepath.Join(root, "speech/admitted-records.json"), filepath.Join(root, "speech", filepath.FromSlash(aliasRel)))
		if err != nil {
			t.Fatal(err)
		}
		for _, path := range []string{coreRel, aliasRel} {
			data, err := os.ReadFile(filepath.Join(root, "speech", filepath.FromSlash(path)))
			if err != nil {
				t.Fatal(err)
			}
			f.write(t, "speech/"+path, data)
			if path == coreRel {
				f.write(t, "indexes/"+mode+".yidx", data)
			}
		}
		index := func(path, hash string) yimebroker.IndexSpec {
			return yimebroker.IndexSpec{Version: f.product.Generation.Version, Mode: mode, Path: path, ExpectedSHA256: hash}
		}
		f.product.Generation.Modes[mode] = yimebroker.BundleModeSpec{Core: index(coreRel, core.IndexSHA256), Modules: []yimebroker.BundleModuleSpec{{ID: speechruntime.ModuleID, Index: index(aliasRel, alias.IndexSHA256)}}}
		f.admission.Modes[mode] = speechruntime.AdmissionMode{CoreSHA256: core.IndexSHA256, ModuleSHA256: alias.IndexSHA256, CanonicalCount: 24, AliasCount: 24}
	}
	f.reseal(t)
	return f
}

func (f *localSpeechFixture) reseal(t *testing.T) {
	t.Helper()
	forwardHash := f.writeJSON(t, "speech/forward-source.json", f.forward)
	f.product.ForwardSource = speechruntime.FileRef{Path: "forward-source.json", SHA256: forwardHash}
	f.admission.ForwardSHA256 = forwardHash
	admissionHash := f.writeJSON(t, "speech/admission.json", f.admission)
	f.product.Admission = speechruntime.FileRef{Path: "admission.json", SHA256: admissionHash}
	productHash := f.writeJSON(t, speechruntime.ProductManifestPath, f.product)
	disabled := false
	f.capability = speechruntime.Capability{SchemaVersion: speechruntime.CapabilitySchema, Product: speechruntime.FileRef{Path: speechruntime.ProductManifestPath, SHA256: productHash}, DefaultEnabled: &disabled}
	capHash := f.writeJSON(t, speechruntime.CapabilityFilename, f.capability)
	f.binding = map[string]string{"schema_version": "yimecore-speech-build-binding-v1", "admission_summary_sha256": localSpeechHash([]byte("synthetic summary")),
		"source_inventory_sha256": localSpeechHash([]byte("synthetic source inventory")), "export_receipt_sha256": localSpeechHash([]byte("synthetic export receipt")),
		"capability_sha256": capHash, "product_manifest_sha256": productHash}
	f.writeJSON(t, "build/build-inputs.json", map[string]any{"schema_version": "yimecore-local-build-inputs-v1", "speech": f.binding})
}

func (f *localSpeechFixture) validate() error {
	return validateLocalContract(f.root, f.entries, localInstallableContract)
}

func TestLocalSpeechContractRequiresExactElevenFiles(t *testing.T) {
	f := newLocalSpeechFixture(t, "")
	if err := f.validate(); err != nil {
		t.Fatal("valid optional resources rejected", err)
	}
	if len(requiredLocalSpeechFiles) != 11 {
		t.Fatal("speech ownership set drifted")
	}
	for _, path := range requiredLocalSpeechFiles {
		t.Run(path, func(t *testing.T) {
			item := f.entries[path]
			delete(f.entries, path)
			defer func() { f.entries[path] = item }()
			if err := f.validate(); err == nil {
				t.Fatal("declared but unlisted speech resource accepted")
			}
		})
	}
	for _, path := range []string{"speech/unknown.json", "speech/sources/formal.py", "speech/YimeSpeechAdmission.exe", "unknown-product-file.json"} {
		t.Run(path, func(t *testing.T) {
			f.entries[strings.ToLower(path)] = manifestFile{Path: path}
			defer delete(f.entries, strings.ToLower(path))
			if err := f.validate(); err == nil {
				t.Fatal("undeclared additional product file accepted")
			}
		})
	}
	path := requiredLocalSpeechFiles[0]
	if err := os.Remove(filepath.Join(f.root, path)); err != nil {
		t.Fatal(err)
	}
	if err := f.validate(); err == nil {
		t.Fatal("declared but physically missing capability accepted")
	}
}

func TestLocalSpeechContractRejectsUnboundResources(t *testing.T) {
	for _, kind := range []string{"outer_hash", "inner_hash", "full_core", "variable_core", "shorthand_core", "layout", "records", "records_layout", "source_closure", "annotations", "capability_enabled", "product_enabled", "scope", "undeclared"} {
		t.Run(kind, func(t *testing.T) {
			f := newLocalSpeechFixture(t, "")
			switch kind {
			case "outer_hash":
				item := f.entries[speechruntime.CapabilityFilename]
				item.SHA256 = strings.Repeat("0", 64)
				f.entries[speechruntime.CapabilityFilename] = item
			case "inner_hash":
				f.write(t, "speech/indexes/full-stage5c.yidx", []byte("invalid synthetic index"))
			case "full_core", "variable_core", "shorthand_core":
				f.write(t, "indexes/"+strings.TrimSuffix(kind, "_core")+".yidx", []byte("different active core"))
			case "layout":
				f.write(t, "data/yime_yinyuan_layout.json", []byte("different active layout"))
			case "records":
				f.admission.Records.SHA256 = f.writeJSON(t, "speech/admitted-records.json", map[string]bool{"unknown": true})
				f.reseal(t)
			case "records_layout":
				f.admitted.InputSHA256["layout"] = strings.Repeat("0", 64)
				f.admission.Records.SHA256 = f.writeJSON(t, "speech/admitted-records.json", f.admitted)
				f.reseal(t)
			case "source_closure":
				delete(f.forward["input_sha256"].(map[string]string), "internal_data/manual_key_layout.json")
				f.reseal(t)
			case "annotations":
				f.write(t, "data/yime_pinyin_codes.tsv", []byte("header\ninvalid\n"))
			case "capability_enabled":
				value := true
				f.capability.DefaultEnabled = &value
				f.binding["capability_sha256"] = f.writeJSON(t, speechruntime.CapabilityFilename, f.capability)
				f.writeJSON(t, "build/build-inputs.json", map[string]any{"speech": f.binding})
			case "product_enabled":
				value := true
				f.product.DefaultEnabled = &value
				f.reseal(t)
			case "scope":
				f.product.ApprovedRecords = 25
				f.reseal(t)
			case "undeclared":
				var value map[string]any
				data, _ := os.ReadFile(filepath.Join(f.root, "local-product.json"))
				if err := json.Unmarshal(data, &value); err != nil {
					t.Fatal(err)
				}
				delete(value, "speech")
				value["version"] = "0.1.0-local.12"
				f.writeJSON(t, "local-product.json", value)
			}
			if err := f.validate(); err == nil {
				t.Fatal("unbound optional product resources accepted")
			}
		})
	}
}

func TestLocalSpeechBuildBindingPinsOnlyArchivedDigests(t *testing.T) {
	f := newLocalSpeechFixture(t, "")
	for _, kind := range []string{"missing", "null", "unknown", "duplicate", "schema", "capability", "product", "external_path", "upper_digest", "missing_digest"} {
		t.Run(kind, func(t *testing.T) {
			binding := map[string]string{}
			for key, value := range f.binding {
				binding[key] = value
			}
			switch kind {
			case "schema":
				binding["schema_version"] = "unknown"
			case "capability":
				binding["capability_sha256"] = strings.Repeat("0", 64)
			case "product":
				binding["product_manifest_sha256"] = strings.Repeat("0", 64)
			case "unknown":
				binding["extra"] = "unknown"
			case "external_path":
				binding["export_receipt_path"] = `C:\outside\receipt.json`
			case "upper_digest":
				binding["source_inventory_sha256"] = strings.ToUpper(binding["source_inventory_sha256"])
			case "missing_digest":
				delete(binding, "admission_summary_sha256")
			}
			data, _ := json.Marshal(map[string]any{"speech": binding})
			if kind == "missing" {
				data = []byte(`{}`)
			}
			if kind == "null" {
				data = []byte(`{"speech":null}`)
			}
			if kind == "duplicate" {
				data = append([]byte(`{"speech":null,`), data[1:]...)
			}
			f.write(t, "build/build-inputs.json", data)
			if err := validateLocalSpeechBuildBinding(f.root, &f.capability); err == nil {
				t.Fatal("invalid build evidence binding accepted")
			}
		})
	}
}

func TestLocalSpeechContractRejectsIndirectResources(t *testing.T) {
	f := newLocalSpeechFixture(t, "")
	path := filepath.Join(f.root, speechruntime.CapabilityFilename)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "synthetic-capability.json")
	if err := os.WriteFile(target, data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, path); err != nil {
		t.Skip("symbolic-link creation is unavailable; no indirect-path pass inferred")
	}
	if err := f.validate(); err == nil {
		t.Fatal("indirect speech payload accepted")
	}
}

func TestLocalSpeechAuditorPreservesOuterIntegrityAndLegacyScope(t *testing.T) {
	root := writeLocalFixture(t)
	for _, path := range requiredLocalMaintenanceFiles {
		full := filepath.Join(root, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("nonexecuted maintenance fixture"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	f := newLocalSpeechFixture(t, root)
	manifest := packageManifest{PackageContract: localInstallableContract, ToolVersion: "yimecore-local-builder-v1", GitCommit: "synthetic-auditor-fixture", Scope: "static synthetic package only"}
	for _, path := range append(append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...), requiredLocalSpeechFiles...) {
		data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path)))
		if err != nil {
			t.Fatal(err)
		}
		manifest.Files = append(manifest.Files, manifestFile{Path: path, Bytes: int64(len(data)), SHA256: localSpeechHash(data)})
	}
	f.writeJSON(t, "package-manifest.json", manifest)
	if report, err := auditPackage(root); err != nil || !report.Passed {
		t.Fatal("complete default-off package audit rejected", report.Failures)
	}
	// The outer walk must continue rejecting even an ordinary, non-executable
	// file that was not listed. No fixture executable is ever launched.
	f.write(t, "speech/unlisted.json", []byte(`{}`))
	if report, err := auditPackage(root); err == nil || report.ManifestIntegrityPassed {
		t.Fatal("unlisted optional payload bypassed the outer audit")
	}
	legacy, err := requiredFilesForContract(packageManifest{ToolVersion: "yimecore-e6c-staged-package-v1"})
	if err != nil || len(legacy) != len(requiredPackageFiles) {
		t.Fatal("historical static architecture requirements changed")
	}
}
