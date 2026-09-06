package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type exportFixture struct {
	config  productExportConfig
	summary map[string]any
	forward speechruntime.ForwardReceipt
}

func newProductExportFixture(t *testing.T) *exportFixture {
	t.Helper()
	base := newSpeechPackageFixture(t)
	root := filepath.Dir(base.source)
	f := &exportFixture{config: productExportConfig{repo: base.repo, root: base.source, indexes: filepath.Join(root, "normal-indexes"), data: filepath.Join(root, "normal-data"), output: filepath.Join(root, "speech-product-export-fixture"), receipt: filepath.Join(root, "speech-product-export-mapping.json")}, forward: base.forward}
	repo, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	// The linguistic data is the existing fixed reviewed batch. Other files and
	// process outcomes are explicitly synthetic parser/packaging fixtures.
	roles := map[string]string{"review": "docs/project/connected_speech/third_tone_stage5b_review.tsv", "decisions": "docs/project/connected_speech/third_tone_stage5b_decisions.tsv", "sources": "docs/project/connected_speech/third_tone_stage5b_sources.tsv", "inventory": "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv", "layout": "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"}
	hashes := map[string]string{}
	paths := map[string]string{}
	for role, relative := range roles {
		data, err := os.ReadFile(filepath.Join(repo, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(base.repo, filepath.FromSlash(relative))
		hashes[role] = packageFixtureWrite(t, path, data)
		paths[role] = path
		f.forward.InputSHA256[relative] = hashes[role]
		for index := range f.forward.Inputs {
			if f.forward.Inputs[index].Path == relative {
				f.forward.Inputs[index].SHA256 = hashes[role]
			}
		}
	}
	admitted, err := connectedspeech.AdmitStage5C(connectedspeech.AdmissionInput{ReviewPath: paths["review"], DecisionsPath: paths["decisions"], SourcesPath: paths["sources"], InventoryPath: paths["inventory"], LayoutPath: paths["layout"], ExpectedSHA256: hashes})
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"yime_yinyuan_layout.json", "yime_pinyin_codes.tsv", "pinyin_normalized.json", "yime_pua_pinyin.json", "yime_pinyin_reverse_source.tsv"} {
		data, err := os.ReadFile(filepath.Join(repo, "go-backend", "input_methods", "yime", "data", name))
		if err != nil {
			t.Fatal(err)
		}
		packageFixtureWrite(t, filepath.Join(f.config.data, name), data)
	}
	for _, path := range exportFixedSources {
		if _, err := os.Stat(filepath.Join(base.repo, filepath.FromSlash(path))); os.IsNotExist(err) {
			packageFixtureWrite(t, filepath.Join(base.repo, filepath.FromSlash(path)), []byte("synthetic source "+path))
		}
	}
	for _, tree := range []string{"go-backend/input_methods/yime", "go-backend/cmd", "go-backend/internal", "syllable", "yime"} {
		packageFixtureWrite(t, filepath.Join(base.repo, filepath.FromSlash(tree), "export_fixture.go"), []byte("package fixture\n"))
	}
	forwardHash := packageFixtureJSON(t, filepath.Join(base.source, "forward-source.json"), f.forward)
	recordHash := packageFixtureJSON(t, filepath.Join(base.source, "admitted-records.json"), admitted)
	receipt := speechruntime.AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24, ForwardSHA256: forwardHash, Records: speechruntime.FileRef{Path: "admitted-records.json", SHA256: recordHash}, Checks: map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true}, Modes: map[string]speechruntime.AdmissionMode{}}
	generation := yimebroker.BundleGenerationSpec{Version: "synthetic-product-export-generation", Modes: map[string]yimebroker.BundleModeSpec{}}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var dictionary strings.Builder
		dictionary.WriteString("---\nname: synthetic_export\nversion: '1'\n...\n")
		var aliases []yimecore.Entry
		for _, record := range admitted.Records {
			fmt.Fprintf(&dictionary, "%s\t%s\t100\n", record.Text, record.Codes[mode].Canonical)
			aliases = append(aliases, yimecore.Entry{Text: record.Text, Code: record.Codes[mode].Alias, Weight: 1})
		}
		source := filepath.Join(base.repo, "go-backend", "input_methods", "yime", "data", "yime_"+mode+".dict.yaml")
		normalSource := filepath.Join(f.config.data, "yime_"+mode+".dict.yaml")
		packageFixtureWrite(t, source, []byte(dictionary.String()))
		packageFixtureWrite(t, normalSource, []byte(dictionary.String()))
		coreRelative := "indexes/" + mode + "-core.yidx"
		moduleRelative := "indexes/" + mode + "-stage5c.yidx"
		core, err := yimecore.BuildIndexFile(mode, source, filepath.Join(base.source, filepath.FromSlash(coreRelative)))
		if err != nil {
			t.Fatal(err)
		}
		if err = os.MkdirAll(f.config.indexes, 0700); err != nil {
			t.Fatal(err)
		}
		normal, err := yimecore.BuildIndexFile(mode, normalSource, filepath.Join(f.config.indexes, mode+".yidx"))
		if err != nil {
			t.Fatal(err)
		}
		if normal.SourcePath == core.SourcePath || normal.IndexSHA256 != core.IndexSHA256 {
			t.Fatal("independent source locations changed deterministic index bytes")
		}
		module, err := yimecore.BuildIndexEntries(mode, aliases, filepath.Join(base.source, "admitted-records.json"), filepath.Join(base.source, filepath.FromSlash(moduleRelative)))
		if err != nil {
			t.Fatal(err)
		}
		generation.Modes[mode] = yimebroker.BundleModeSpec{Core: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: coreRelative, ExpectedSHA256: core.IndexSHA256}, Modules: []yimebroker.BundleModuleSpec{{ID: speechruntime.ModuleID, Index: yimebroker.IndexSpec{Version: generation.Version, Mode: mode, Path: moduleRelative, ExpectedSHA256: module.IndexSHA256}}}}
		receipt.Modes[mode] = speechruntime.AdmissionMode{CoreSHA256: core.IndexSHA256, ModuleSHA256: module.IndexSHA256, CanonicalCount: 24, AliasCount: 24}
	}
	receiptHash := packageFixtureJSON(t, filepath.Join(base.source, "admission.json"), receipt)
	manifest := speechruntime.Manifest{SchemaVersion: speechruntime.Schema, ApprovedRecords: 24, Admission: speechruntime.FileRef{Path: "admission.json", SHA256: receiptHash}, ForwardSource: speechruntime.FileRef{Path: "forward-source.json", SHA256: forwardHash}, Generation: generation}
	packageFixtureJSON(t, filepath.Join(base.source, "bundle-off.json"), manifest)
	manifest.Enabled = true
	packageFixtureJSON(t, filepath.Join(base.source, "bundle-on.json"), manifest)
	packageFixtureJSON(t, filepath.Join(base.source, "prepare-outcome.json"), map[string]any{"schema_version": "yimecore-speech-prepare-v1", "passed": true, "records": 24, "mode_rows": 72, "rime_executed": false, "runtime_rule_inference": false, "installed_product_changed": false})
	var tools []exportSource
	for source, relative := range map[string]string{base.broker: "bin/YimeBroker-speech.exe", base.tool: "bin/YimeSpeechAdmission.exe"} {
		data, err := os.ReadFile(source)
		if err != nil {
			t.Fatal(err)
		}
		hash := packageFixtureWrite(t, filepath.Join(base.source, filepath.FromSlash(relative)), data)
		tools = append(tools, exportSource{relative, int64(len(data)), hash})
	}
	brokerHash, err := speechruntime.HashFile(filepath.Join(base.source, "bin", "YimeBroker-speech.exe"))
	if err != nil {
		t.Fatal(err)
	}
	var stages []map[string]any
	for index, name := range []string{"disabled-before", "enabled-train", "enabled-restart", "disabled-after", "reenabled", "invalid-generation-rejected", "valid-generation-recovery"} {
		generation := 6
		if index == 0 {
			generation = 0
		}
		stage := map[string]any{"name": name, "passed": true, "pid": index + 100, "exit_code": 0, "modes_passed": 3, "canonical_checks": 72, "alias_or_disabled_source_checks": 72, "learning_generation": generation}
		if index == 5 {
			stage["exit_code"] = 42
			stage["state_unchanged"] = true
		}
		if index == 6 {
			stage["canonical_checks"] = 3
			stage["learned_alias_checks"] = 3
		}
		stages = append(stages, stage)
	}
	packageFixtureJSON(t, filepath.Join(base.source, "process-outcome.json"), map[string]any{"schema_version": "yimecore-speech-process-acceptance-v1", "passed": true, "broker_sha256": brokerHash, "stages": stages, "rime_executed": false, "installed_broker_connected": false, "user_data_read": false, "windows_reboot_tested": false, "registered_or_live_host_tested": false})
	f.summary = map[string]any{"schema_version": "yimecore-speech-admission-isolated-v1", "stage": "complete", "module": speechruntime.ModuleID, "reviewed_records": 24, "mode_alias_rows": 72, "trial_root": base.source, "failure": nil, "environment_restore_failures": []string{}, "tools": tools, "dependencies": []map[string]any{{"import_path": "fmt", "cgo_files": 0}}}
	for _, key := range []string{"passed", "forward_source_passed", "admission_prepare_passed", "owned_process_acceptance_passed", "dependency_boundary_passed", "python_contracts_passed", "installed_baseline_unchanged", "locked_inputs_unchanged", "source_set_unchanged", "legacy_static_unchanged", "environment_restored", "synthetic_learning_data_used"} {
		f.summary[key] = true
	}
	for _, key := range []string{"real_rime_executed", "registered_hosts_executed", "frozen_targets_executed", "default_input_method_changed", "new_package_installed", "daily_broker_connected", "user_text_read", "live_learning_data_read", "live_config_read", "product_or_registry_mutated", "local_product_ready", "public_release_ready"} {
		f.summary[key] = false
	}
	var tests []map[string]any
	for _, pkg := range []string{"./input_methods/yime/connectedspeech", "./input_methods/yime/layoutdesigner", "./input_methods/yime/yimecore", "./input_methods/yime/yimebroker", "./input_methods/yime/speechruntime", "./cmd/yimebroker", "./cmd/yimecore-speech-admission"} {
		tests = append(tests, map[string]any{"package": pkg, "selector": "^TestSyntheticOnly$", "passed": true, "passed_count": 1, "failed_count": 0, "skipped_count": 0, "skipped_tests": []string{}})
	}
	f.summary["directed_tests"] = tests
	f.refreshSources(t)
	f.refreshArtifacts(t)
	f.sealSummary(t)
	return f
}

func (f *exportFixture) refreshSources(t *testing.T) {
	t.Helper()
	paths, err := exportSourcePaths(f.config.repo, f.forward)
	if err != nil {
		t.Fatal(err)
	}
	var records []exportSource
	for path := range paths {
		item, err := describePackageFile("", path, filepath.Join(f.config.repo, filepath.FromSlash(path)))
		if err != nil {
			t.Fatal(err)
		}
		records = append(records, exportSource{path, item.Size, item.SHA256})
	}
	data, err := json.Marshal(records)
	if err != nil {
		t.Fatal(err)
	}
	f.config.inventorySHA = packageFixtureWrite(t, filepath.Join(f.config.root, "source-hashes-after.json"), data)
	packageFixtureWrite(t, filepath.Join(f.config.root, "source-hashes-before.json"), data)
	f.summary["source_inventory"] = exportSource{"source-hashes-after.json", int64(len(data)), f.config.inventorySHA}
	f.summary["source_inventory_before"] = exportSource{"source-hashes-before.json", int64(len(data)), f.config.inventorySHA}
}

func (f *exportFixture) refreshArtifacts(t *testing.T) {
	t.Helper()
	var artifacts []exportSource
	for path := range exportArtifactPaths() {
		item, err := describePackageFile("", path, filepath.Join(f.config.root, filepath.FromSlash(path)))
		if err != nil {
			t.Fatal(err)
		}
		artifacts = append(artifacts, exportSource{path, item.Size, item.SHA256})
	}
	f.summary["admission_artifacts"] = artifacts
}
func (f *exportFixture) sealSummary(t *testing.T) {
	t.Helper()
	f.config.summarySHA = packageFixtureJSON(t, filepath.Join(f.config.root, "summary.json"), f.summary)
}

func TestSpeechProductExportExactElevenPreservesBytesAndIndependentCore(t *testing.T) {
	f := newProductExportFixture(t)
	if err := exportProduct(f.config); err != nil {
		t.Fatal(err)
	}
	var report productExportReceipt
	if err := readJSON(f.config.receipt, &report); err != nil {
		t.Fatal(err)
	}
	if !report.Passed || !report.ProductVerified || !report.InputsUnchanged || report.PayloadFiles != 11 || len(report.Files) != 11 || report.DefaultEnabled || report.RuntimeExecuted || report.Installed {
		t.Fatal("export result overclaims or incomplete")
	}
	for source, target := range exportCopies {
		original, err := os.ReadFile(filepath.Join(f.config.root, filepath.FromSlash(source)))
		if err != nil {
			t.Fatal(err)
		}
		copied, err := os.ReadFile(filepath.Join(f.config.output, filepath.FromSlash(target)))
		if err != nil || !bytes.Equal(original, copied) {
			t.Fatal("export changed admitted bytes")
		}
	}
	if err := verifyProductExport(f.config.output, f.config.indexes, f.config.data, report); err != nil {
		t.Fatal(err)
	}
	if err := exportProduct(f.config); err == nil {
		t.Fatal("existing output overwritten")
	}
	packageFixtureWrite(t, filepath.Join(f.config.output, "speech", "unexpected.py"), []byte("not allowed"))
	if err := verifyProductExport(f.config.output, f.config.indexes, f.config.data, report); err == nil {
		t.Fatal("unknown payload accepted")
	}
}

func TestSpeechProductExportRejectsPinnedEvidenceAndInputs(t *testing.T) {
	for _, kind := range []string{"summary_hash", "inventory_pin", "missing_inventory_binding", "source_modified", "canonical_dictionary_modified", "target_lock_modified", "new_go_source", "missing_source_row", "source_duplicate", "artifact_modified", "artifact_missing", "artifact_duplicate", "tool_modified", "wrong_architecture", "wrong_stage", "failed_gate", "missing_false", "failed_test", "skip_count", "missing_failed_count", "missing_dependency_cgo", "missing_process_stage", "normal_core", "normal_layout", "bad_records", "unknown_review", "output_overlap", "receipt_overlap", "ads_mapping"} {
		t.Run(kind, func(t *testing.T) {
			f := newProductExportFixture(t)
			switch kind {
			case "summary_hash":
				f.config.summarySHA = strings.Repeat("0", 64)
			case "inventory_pin":
				f.config.inventorySHA = strings.Repeat("0", 64)
			case "missing_inventory_binding":
				delete(f.summary, "source_inventory")
				f.sealSummary(t)
			case "source_modified":
				packageFixtureWrite(t, filepath.Join(f.config.repo, "AGENTS.md"), []byte("changed"))
			case "canonical_dictionary_modified":
				packageFixtureWrite(t, filepath.Join(f.config.repo, "go-backend", "input_methods", "yime", "data", "yime_full.dict.yaml"), []byte("changed after admission"))
			case "target_lock_modified":
				packageFixtureWrite(t, filepath.Join(f.config.repo, "tools", "lexicon", "data", "yime_core_target.lock.json"), []byte("{}"))
			case "new_go_source":
				packageFixtureWrite(t, filepath.Join(f.config.repo, "go-backend", "cmd", "new.go"), []byte("package fixture"))
			case "missing_source_row", "source_duplicate":
				var records []exportSource
				if err := readJSON(filepath.Join(f.config.root, "source-hashes-after.json"), &records); err != nil {
					t.Fatal(err)
				}
				if kind == "missing_source_row" {
					records = records[1:]
				} else {
					records[0] = records[1]
				}
				data, _ := json.Marshal(records)
				f.config.inventorySHA = hexDigest(data)
				for _, name := range []string{"source-hashes-after.json", "source-hashes-before.json"} {
					packageFixtureWrite(t, filepath.Join(f.config.root, name), data)
				}
				f.summary["source_inventory"] = exportSource{"source-hashes-after.json", int64(len(data)), f.config.inventorySHA}
				f.summary["source_inventory_before"] = exportSource{"source-hashes-before.json", int64(len(data)), f.config.inventorySHA}
				f.sealSummary(t)
			case "artifact_modified":
				packageFixtureWrite(t, filepath.Join(f.config.root, "process-outcome.json"), []byte("{}"))
			case "artifact_missing":
				f.summary["admission_artifacts"] = f.summary["admission_artifacts"].([]exportSource)[1:]
				f.sealSummary(t)
			case "artifact_duplicate":
				rows := f.summary["admission_artifacts"].([]exportSource)
				rows[0] = rows[1]
				f.sealSummary(t)
			case "tool_modified":
				packageFixtureWrite(t, filepath.Join(f.config.root, "bin", "YimeBroker-speech.exe"), []byte("changed"))
			case "wrong_architecture":
				path := "bin/YimeBroker-speech.exe"
				data := packageFixturePE(t, 0x014c)
				hash := packageFixtureWrite(t, filepath.Join(f.config.root, filepath.FromSlash(path)), data)
				for index, row := range f.summary["tools"].([]exportSource) {
					if row.Path == path {
						f.summary["tools"].([]exportSource)[index] = exportSource{path, int64(len(data)), hash}
					}
				}
				f.sealSummary(t)
			case "wrong_stage":
				f.summary["stage"] = "old-complete"
				f.sealSummary(t)
			case "failed_gate":
				f.summary["source_set_unchanged"] = false
				f.sealSummary(t)
			case "missing_false":
				delete(f.summary, "user_text_read")
				f.sealSummary(t)
			case "failed_test", "skip_count":
				tests := f.summary["directed_tests"].([]map[string]any)
				if kind == "failed_test" {
					tests[0]["failed_count"] = 1
				} else {
					tests[0]["skipped_count"] = 1
				}
				f.sealSummary(t)
			case "missing_failed_count":
				delete(f.summary["directed_tests"].([]map[string]any)[0], "failed_count")
				f.sealSummary(t)
			case "missing_dependency_cgo":
				delete(f.summary["dependencies"].([]map[string]any)[0], "cgo_files")
				f.sealSummary(t)
			case "missing_process_stage":
				var process map[string]any
				if err := readJSON(filepath.Join(f.config.root, "process-outcome.json"), &process); err != nil {
					t.Fatal(err)
				}
				process["stages"] = process["stages"].([]any)[:6]
				packageFixtureJSON(t, filepath.Join(f.config.root, "process-outcome.json"), process)
				f.refreshArtifacts(t)
				f.sealSummary(t)
			case "normal_core":
				packageFixtureWrite(t, filepath.Join(f.config.indexes, "full.yidx"), []byte("changed"))
			case "normal_layout":
				packageFixtureWrite(t, filepath.Join(f.config.data, "yime_yinyuan_layout.json"), []byte("changed"))
			case "bad_records":
				packageFixtureWrite(t, filepath.Join(f.config.root, "admitted-records.json"), []byte("{}"))
				var receipt speechruntime.AdmissionReceipt
				if err := readJSON(filepath.Join(f.config.root, "admission.json"), &receipt); err != nil {
					t.Fatal(err)
				}
				receipt.Records.SHA256 = hexDigest([]byte("{}"))
				receiptHash := packageFixtureJSON(t, filepath.Join(f.config.root, "admission.json"), receipt)
				for _, name := range []string{"bundle-off.json", "bundle-on.json"} {
					var manifest speechruntime.Manifest
					if err := readJSON(filepath.Join(f.config.root, name), &manifest); err != nil {
						t.Fatal(err)
					}
					manifest.Admission.SHA256 = receiptHash
					packageFixtureJSON(t, filepath.Join(f.config.root, name), manifest)
				}
				f.refreshArtifacts(t)
				f.sealSummary(t)
			case "unknown_review":
				path := "docs/project/connected_speech/third_tone_stage5b_review.tsv"
				digest := packageFixtureWrite(t, filepath.Join(f.config.repo, filepath.FromSlash(path)), []byte("unreviewed"))
				f.forward.InputSHA256[path] = digest
				for index := range f.forward.Inputs {
					if f.forward.Inputs[index].Path == path {
						f.forward.Inputs[index].SHA256 = digest
					}
				}
				packageFixtureJSON(t, filepath.Join(f.config.root, "forward-source.json"), f.forward)
				f.refreshSources(t)
				f.refreshArtifacts(t)
				f.sealSummary(t)
			case "output_overlap":
				f.config.output = filepath.Join(f.config.root, "speech-product-export-nested")
			case "receipt_overlap":
				f.config.receipt = filepath.Join(f.config.root, "speech-product-export-mapping.json")
			case "ads_mapping":
				f.config.receipt = filepath.Join(filepath.Dir(f.config.receipt), "speech-product-export-mapping:ads.json")
			}
			if err := exportProduct(f.config); err == nil {
				t.Fatal("invalid build-only export accepted")
			}
		})
	}
}

func TestSpeechProductExportSourceRecordRequiresExactJSONFields(t *testing.T) {
	for _, data := range []string{`{"path":"empty.py","sha256":"` + strings.Repeat("a", 64) + `"}`, `{"Path":"empty.py","bytes":0,"sha256":"` + strings.Repeat("a", 64) + `"}`, `{"path":"empty.py","bytes":null,"sha256":"` + strings.Repeat("a", 64) + `"}`, `{"path":"empty.py","bytes":0,"sha256":"` + strings.Repeat("a", 64) + `","unknown":true}`} {
		var source exportSource
		if err := exportStrictJSON([]byte(data), &source); err == nil {
			t.Fatal("noncanonical source record accepted")
		}
	}
}

func TestSpeechProductExportRetainsExplicitSkipEvidence(t *testing.T) {
	f := newProductExportFixture(t)
	tests := f.summary["directed_tests"].([]map[string]any)
	tests[0]["skipped_count"] = 1
	tests[0]["skipped_tests"] = []string{"TestSyntheticUnavailableSurface"}
	f.sealSummary(t)
	if err := exportProduct(f.config); err != nil {
		t.Fatal(err)
	}
	var receipt productExportReceipt
	if err := readJSON(f.config.receipt, &receipt); err != nil {
		t.Fatal(err)
	}
	if len(receipt.SkippedTests) != 1 || !strings.HasSuffix(receipt.SkippedTests[0], ":TestSyntheticUnavailableSurface") {
		t.Fatal("SKIP evidence suppressed")
	}
}

func TestSpeechProductExportRejectsIndirectSources(t *testing.T) {
	f := newProductExportFixture(t)
	target := filepath.Join(f.config.repo, "go-backend", "cmd", "indirect.go")
	if err := os.Symlink(filepath.Join(f.config.repo, "AGENTS.md"), target); err != nil {
		t.Skip("platform does not permit a synthetic symlink")
	}
	if err := exportProduct(f.config); err == nil {
		t.Fatal("indirect source accepted")
	}
}

func TestSpeechProductExportFixedCollectionContainsNoExecutableOrState(t *testing.T) {
	if len(exportCopies) != 9 || len(exportArtifactPaths()) != 13 {
		t.Fatal("fixed export closure changed")
	}
	for _, path := range exportCopies {
		for _, forbidden := range []string{".exe", ".py", "state", "journal", "sources/", "bundle-on"} {
			if strings.Contains(path, forbidden) {
				t.Fatal("forbidden export runtime dependency")
			}
		}
	}
}

func TestSpeechProductExportFixedSourcesIncludeMaintenanceConfigContract(t *testing.T) {
	wanted := "tools/yimecore/test-local-maintenance-config-data.ps1"
	for _, path := range exportFixedSources {
		if path == wanted {
			return
		}
	}
	t.Fatal("maintenance config contract is outside fixed product source evidence")
}
