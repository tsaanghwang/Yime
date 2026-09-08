package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type productExportConfig struct {
	repo, root, summarySHA, inventorySHA, indexes, data, output, receipt string
}

type exportSource struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

type exportMapping struct {
	SourcePath  string `json:"source_path,omitempty"`
	ProductPath string `json:"product_path"`
	SHA256      string `json:"sha256"`
	Bytes       int64  `json:"bytes"`
	Generated   bool   `json:"generated"`
}

type productExportReceipt struct {
	SchemaVersion         string          `json:"schema_version"`
	Passed                bool            `json:"passed"`
	DefaultEnabled        bool            `json:"default_enabled"`
	PayloadFiles          int             `json:"payload_files"`
	Summary               exportSource    `json:"admission_summary"`
	SourceInventory       exportSource    `json:"source_inventory"`
	SourceInventoryBefore exportSource    `json:"source_inventory_before"`
	SourceFiles           int             `json:"source_files"`
	ForwardFiles          int             `json:"forward_source_files"`
	AdmissionArtifacts    []exportSource  `json:"admission_artifacts"`
	Tools                 []exportSource  `json:"admission_tools"`
	SkippedTests          []string        `json:"skipped_tests"`
	LayoutSHA256          string          `json:"layout_sha256"`
	ProductSHA256         string          `json:"product_sha256"`
	Files                 []exportMapping `json:"files"`
	InputsUnchanged       bool            `json:"inputs_unchanged"`
	ProductVerified       bool            `json:"product_verified"`
	RuntimeExecuted       bool            `json:"runtime_executed"`
	Installed             bool            `json:"installed"`
}

var exportCopies = map[string]string{
	"admission.json":                 "speech/admission.json",
	"forward-source.json":            "speech/forward-source.json",
	"admitted-records.json":          "speech/admitted-records.json",
	"indexes/full-core.yidx":         "speech/indexes/full-core.yidx",
	"indexes/full-stage5c.yidx":      "speech/indexes/full-stage5c.yidx",
	"indexes/variable-core.yidx":     "speech/indexes/variable-core.yidx",
	"indexes/variable-stage5c.yidx":  "speech/indexes/variable-stage5c.yidx",
	"indexes/shorthand-core.yidx":    "speech/indexes/shorthand-core.yidx",
	"indexes/shorthand-stage5c.yidx": "speech/indexes/shorthand-stage5c.yidx",
}

func exportArtifactPaths() map[string]bool {
	paths := map[string]bool{"bundle-off.json": true, "bundle-on.json": true, "prepare-outcome.json": true, "process-outcome.json": true}
	for path := range exportCopies {
		paths[path] = true
	}
	return paths
}

// This fixed set is independent of the runner's serialized inventory. The five
// code trees add newly created source files as well as detecting removed files.
var exportFixedSources = []string{
	"AGENTS.md", "go-backend/go.mod", "docs/project/MANDARIN_CONNECTED_SPEECH_PLAN.md",
	"tools/yimecore/development-scope.json", "tools/yimecore/development-scope.ps1", "tools/yimecore/local-maintenance-safety.ps1",
	"tools/yimecore/get-l5-daily-use-baseline.ps1", "tools/yimecore/run-connected-speech-reconnect.ps1",
	"tools/yimecore/run-connected-speech-admission.ps1", "tools/yimecore/run-connected-speech-package.ps1", "tools/yimecore/test-connected-speech-package.ps1",
	"tools/lexicon/validate_connected_speech_forward.py", "tools/lexicon/tests/test_validate_connected_speech_forward.py",
	"docs/testing/connected-speech/2026-09-05-isolated-reconnect.json",
	"tools/yimecore/local-product.json", "tools/yimecore/local-product-build-common.ps1", "tools/yimecore/build-local-product.ps1",
	"tools/yimecore/local-product-speech-build.ps1", "tools/yimecore/test-local-product-speech-build.ps1", "tools/yimecore/test-speech-maintenance-data.ps1",
	"tools/yimecore/test-local-maintenance-config-data.ps1",
	"tools/yimecore/run-connected-speech-product-package.ps1", "tools/yimecore/speech-product-contract.json",
	"go-backend/input_methods/yime/data/yime_full.dict.yaml", "go-backend/input_methods/yime/data/yime_variable.dict.yaml",
	"go-backend/input_methods/yime/data/yime_shorthand.dict.yaml", "tools/lexicon/data/yime_core_target.lock.json",
	"tools/yimecore/run-connected-speech-product-source.ps1",
	"tools/yimecore/test-speech-symlink-evidence.ps1",
}

func hexDigest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }

func exportSourcePaths(repo string, forward speechruntime.ForwardReceipt) (map[string]bool, error) {
	paths := map[string]bool{}
	for _, path := range exportFixedSources {
		paths[path] = true
	}
	for _, input := range forward.Inputs {
		paths[input.Path] = true
	}
	for _, tree := range []string{"go-backend/input_methods/yime", "go-backend/cmd", "go-backend/internal", "syllable", "yime"} {
		root, err := packageChild(repo, tree)
		if err != nil {
			return nil, err
		}
		if err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if err := packagePlainPath(path); err != nil {
				return err
			}
			if entry.IsDir() {
				return nil
			}
			extension := filepath.Ext(entry.Name())
			if extension != ".go" && extension != ".py" {
				return nil
			}
			relative, err := filepath.Rel(repo, path)
			if err != nil {
				return err
			}
			paths[filepath.ToSlash(relative)] = true
			return nil
		}); err != nil {
			return nil, err
		}
	}
	return paths, nil
}

func exportRead(root, path, hash string, limit int64, target any) (exportSource, error) {
	var empty exportSource
	p, err := packageChild(root, path)
	if err != nil {
		return empty, err
	}
	item, err := describePackageFile("", path, p)
	if err != nil {
		return empty, err
	}
	if !packageDigest(hash) || item.SHA256 != hash || item.Size < 0 || item.Size > limit {
		return empty, errors.New("export evidence hash/size mismatch")
	}
	data, err := os.ReadFile(p)
	if err != nil {
		return empty, err
	}
	// Bind the parsed bytes too, not merely a preceding path hash.
	if hexDigest(data) != hash {
		return empty, errors.New("export evidence changed during read")
	}
	if err = exportStrictJSON(data, target); err != nil {
		return empty, err
	}
	return exportSource{path, item.Size, hash}, nil
}

func exportField(raw map[string]json.RawMessage, key string, value any) error {
	data, ok := raw[key]
	if !ok || bytes.Equal(data, []byte("null")) {
		return fmt.Errorf("required export evidence field missing: %s", key)
	}
	return exportStrictJSON(data, value)
}

func exportStrictJSON(data []byte, target any) error {
	if err := strictPackageJSON(data, target); err != nil {
		return err
	}
	var rows []map[string]json.RawMessage
	switch target.(type) {
	case *exportSource:
		var row map[string]json.RawMessage
		if err := json.Unmarshal(data, &row); err != nil {
			return err
		}
		rows = append(rows, row)
	case *[]exportSource:
		if err := json.Unmarshal(data, &rows); err != nil {
			return err
		}
	default:
		return nil
	}
	for _, row := range rows {
		if len(row) != 3 {
			return errors.New("source record field set mismatch")
		}
		for _, name := range []string{"path", "bytes", "sha256"} {
			if len(row[name]) == 0 || bytes.Equal(row[name], []byte("null")) {
				return errors.New("missing source record field")
			}
		}
	}
	return nil
}

func exportRequire(raw map[string]json.RawMessage, key string, want any) error {
	var value any
	if err := exportField(raw, key, &value); err != nil {
		return err
	}
	if !reflect.DeepEqual(value, want) {
		return fmt.Errorf("export evidence field rejected: %s", key)
	}
	return nil
}

func exportCheckSources(root string, records []exportSource, wanted map[string]bool) error {
	if len(records) != len(wanted) {
		return errors.New("export evidence source set incomplete")
	}
	seen := map[string]bool{}
	for _, record := range records {
		if !wanted[record.Path] || seen[record.Path] || record.Bytes < 0 || !packageDigest(record.SHA256) {
			return errors.New("export evidence unknown/duplicate/invalid source")
		}
		seen[record.Path] = true
		p, err := packageChild(root, record.Path)
		if err != nil {
			return err
		}
		actual, err := describePackageFile("", record.Path, p)
		if err != nil || actual.Size != record.Bytes || actual.SHA256 != record.SHA256 {
			return errors.New("export evidence source changed")
		}
	}
	return nil
}

func exportValidateSummary(config productExportConfig) (productExportReceipt, error) {
	result := productExportReceipt{SchemaVersion: "yimecore-speech-product-export-v1", PayloadFiles: 11, ForwardFiles: 56}
	var summary map[string]json.RawMessage
	var err error
	result.Summary, err = exportRead(config.root, "summary.json", config.summarySHA, 2*1024*1024, &summary)
	if err != nil {
		return result, err
	}
	for key, value := range map[string]any{"schema_version": "yimecore-speech-admission-isolated-v1", "stage": "complete", "module": speechruntime.ModuleID, "reviewed_records": float64(24), "mode_alias_rows": float64(72)} {
		if err = exportRequire(summary, key, value); err != nil {
			return result, err
		}
	}
	for _, key := range []string{"passed", "forward_source_passed", "admission_prepare_passed", "owned_process_acceptance_passed", "dependency_boundary_passed", "python_contracts_passed", "installed_baseline_unchanged", "locked_inputs_unchanged", "source_set_unchanged", "legacy_static_unchanged", "environment_restored", "synthetic_learning_data_used"} {
		if err = exportRequire(summary, key, true); err != nil {
			return result, err
		}
	}
	for _, key := range []string{"real_rime_executed", "registered_hosts_executed", "frozen_targets_executed", "default_input_method_changed", "new_package_installed", "daily_broker_connected", "user_text_read", "live_learning_data_read", "live_config_read", "product_or_registry_mutated", "local_product_ready", "public_release_ready"} {
		if err = exportRequire(summary, key, false); err != nil {
			return result, err
		}
	}
	if string(summary["failure"]) != "null" {
		return result, errors.New("export admission reports a failure or omits failure state")
	}
	var trialRoot string
	if err = exportField(summary, "trial_root", &trialRoot); err != nil || !strings.EqualFold(filepath.Clean(trialRoot), filepath.Clean(config.root)) {
		return result, errors.New("export summary belongs to another admission root")
	}
	var restoreFailures []json.RawMessage
	if err = exportField(summary, "environment_restore_failures", &restoreFailures); err != nil || len(restoreFailures) != 0 {
		return result, errors.New("admission environment restoration incomplete")
	}
	if err = exportField(summary, "source_inventory", &result.SourceInventory); err != nil {
		return result, err
	}
	if err = exportField(summary, "source_inventory_before", &result.SourceInventoryBefore); err != nil {
		return result, err
	}
	if result.SourceInventory.Path != "source-hashes-after.json" || result.SourceInventoryBefore.Path != "source-hashes-before.json" || result.SourceInventory.SHA256 != config.inventorySHA || result.SourceInventoryBefore.SHA256 != config.inventorySHA || result.SourceInventory.Bytes != result.SourceInventoryBefore.Bytes {
		return result, errors.New("source inventory is not bound before/after to the fixed admission summary")
	}
	var sources, before []exportSource
	actual, err := exportRead(config.root, result.SourceInventory.Path, config.inventorySHA, 4*1024*1024, &sources)
	if err != nil || actual != result.SourceInventory {
		return result, errors.New("after source inventory hash/size mismatch")
	}
	actual, err = exportRead(config.root, result.SourceInventoryBefore.Path, config.inventorySHA, 4*1024*1024, &before)
	if err != nil || actual != result.SourceInventoryBefore || !reflect.DeepEqual(sources, before) {
		return result, errors.New("before source inventory mismatch")
	}
	if err = exportField(summary, "admission_artifacts", &result.AdmissionArtifacts); err != nil {
		return result, err
	}
	if err = exportCheckSources(config.root, result.AdmissionArtifacts, exportArtifactPaths()); err != nil {
		return result, err
	}
	if err = exportField(summary, "tools", &result.Tools); err != nil {
		return result, err
	}
	if err = exportCheckSources(config.root, result.Tools, map[string]bool{"bin/YimeBroker-speech.exe": true, "bin/YimeSpeechAdmission.exe": true}); err != nil {
		return result, err
	}
	for _, tool := range result.Tools {
		if err = requireAMD64Executable(filepath.Join(config.root, filepath.FromSlash(tool.Path))); err != nil {
			return result, err
		}
	}
	forward, err := speechruntime.ReadForward(filepath.Join(config.root, "forward-source.json"))
	if err != nil {
		return result, err
	}
	wanted, err := exportSourcePaths(config.repo, forward)
	if err != nil {
		return result, err
	}
	if err = exportCheckSources(config.repo, sources, wanted); err != nil {
		return result, err
	}
	result.SourceFiles = len(sources)
	for _, input := range forward.Inputs {
		path, err := packageChild(config.repo, input.Path)
		if err != nil {
			return result, err
		}
		hash, err := speechruntime.HashFile(path)
		if err != nil || hash != input.SHA256 {
			return result, errors.New("actual forward source differs from admission receipt")
		}
	}
	for path, expected := range map[string]string{
		"docs/project/connected_speech/third_tone_stage5b_review.tsv":    "484f37fe78a1b6144c0abf5addd55245e1d0517eee21a142e9f735e495aa931b",
		"docs/project/connected_speech/third_tone_stage5b_decisions.tsv": "575bd0ed7794c46c8aee53c1560bb0020f9397c06a20bda9ee7e6ad714adb0c8",
		"docs/project/connected_speech/third_tone_stage5b_sources.tsv":   "dbba5cc8dc25fcbb70185b70aa3296503100e480c49fd462db76842f21338579",
	} {
		if forward.InputSHA256[path] != expected {
			return result, errors.New("export is not the fixed reviewed Stage5C batch")
		}
	}
	result.LayoutSHA256 = forward.InputSHA256["go-backend/input_methods/yime/data/yime_yinyuan_layout.json"]
	if err = exportValidateTests(summary, &result); err != nil {
		return result, err
	}
	return result, exportValidateProcess(config.root, result.AdmissionArtifacts, result.Tools)
}

func exportValidateTests(summary map[string]json.RawMessage, result *productExportReceipt) error {
	for field, keys := range map[string][]string{"directed_tests": {"package", "selector", "passed_count", "failed_count", "skipped_count", "skipped_tests", "passed"}, "dependencies": {"import_path", "cgo_files"}} {
		var rows []map[string]json.RawMessage
		if err := exportField(summary, field, &rows); err != nil {
			return err
		}
		for _, row := range rows {
			if len(row) != len(keys) {
				return errors.New("admission test/dependency field set incomplete")
			}
			for _, key := range keys {
				if len(row[key]) == 0 || bytes.Equal(row[key], []byte("null")) {
					return errors.New("admission test/dependency required field missing")
				}
			}
		}
	}
	var tests []struct {
		Package      string   `json:"package"`
		Selector     string   `json:"selector"`
		PassedCount  int      `json:"passed_count"`
		FailedCount  int      `json:"failed_count"`
		SkippedCount int      `json:"skipped_count"`
		SkippedTests []string `json:"skipped_tests"`
		Passed       bool     `json:"passed"`
	}
	if err := exportField(summary, "directed_tests", &tests); err != nil {
		return err
	}
	wanted := map[string]bool{"./input_methods/yime/connectedspeech": true, "./input_methods/yime/layoutdesigner": true, "./input_methods/yime/yimecore": true, "./input_methods/yime/yimebroker": true, "./input_methods/yime/speechruntime": true, "./cmd/yimebroker": true, "./cmd/yimecore-speech-admission": true}
	if len(tests) != len(wanted) {
		return errors.New("admission directed test matrix missing")
	}
	for _, test := range tests {
		if !wanted[test.Package] || !test.Passed || test.PassedCount < 1 || test.FailedCount != 0 || test.SkippedCount != len(test.SkippedTests) || test.Selector == "" {
			return errors.New("admission directed test failure/incomplete evidence")
		}
		delete(wanted, test.Package)
		for _, name := range test.SkippedTests {
			if name == "" {
				return errors.New("empty admission SKIP evidence")
			}
			result.SkippedTests = append(result.SkippedTests, test.Package+":"+name)
		}
	}
	var dependencies []struct {
		Path string `json:"import_path"`
		CGO  int    `json:"cgo_files"`
	}
	if err := exportField(summary, "dependencies", &dependencies); err != nil {
		return err
	}
	if len(dependencies) == 0 {
		return errors.New("admission dependency evidence absent")
	}
	for _, dependency := range dependencies {
		if dependency.Path == "" || dependency.CGO != 0 || dependency.Path == "runtime/cgo" || dependency.Path == "github.com/tsaanghwang/Yime/go-backend/input_methods/yime" {
			return errors.New("admission dependency boundary invalid")
		}
		for _, part := range strings.Split(strings.ToLower(dependency.Path), "/") {
			if part == "rime" || part == "librime" || part == "pime" {
				return errors.New("admission depends on another runtime")
			}
		}
	}
	return nil
}

func exportValidateProcess(root string, artifacts, tools []exportSource) error {
	hashes := map[string]string{}
	for _, record := range append(append([]exportSource{}, artifacts...), tools...) {
		hashes[record.Path] = record.SHA256
	}
	var prepare map[string]json.RawMessage
	if _, err := exportRead(root, "prepare-outcome.json", hashes["prepare-outcome.json"], 256*1024, &prepare); err != nil {
		return err
	}
	for key, value := range map[string]any{"schema_version": "yimecore-speech-prepare-v1", "passed": true, "records": float64(24), "mode_rows": float64(72), "rime_executed": false, "runtime_rule_inference": false, "installed_product_changed": false} {
		if err := exportRequire(prepare, key, value); err != nil {
			return err
		}
	}
	var process map[string]json.RawMessage
	if _, err := exportRead(root, "process-outcome.json", hashes["process-outcome.json"], 256*1024, &process); err != nil {
		return err
	}
	for key, value := range map[string]any{"schema_version": "yimecore-speech-process-acceptance-v1", "passed": true, "broker_sha256": hashes["bin/YimeBroker-speech.exe"], "rime_executed": false, "installed_broker_connected": false, "user_data_read": false, "windows_reboot_tested": false, "registered_or_live_host_tested": false} {
		if err := exportRequire(process, key, value); err != nil {
			return err
		}
	}
	var stages []map[string]json.RawMessage
	if err := exportField(process, "stages", &stages); err != nil {
		return err
	}
	names := []string{"disabled-before", "enabled-train", "enabled-restart", "disabled-after", "reenabled", "invalid-generation-rejected", "valid-generation-recovery"}
	if len(stages) != len(names) {
		return errors.New("admission process lifecycle incomplete")
	}
	pids := map[int]bool{}
	for index, stage := range stages {
		if err := exportRequire(stage, "name", names[index]); err != nil {
			return err
		}
		if err := exportRequire(stage, "passed", true); err != nil {
			return err
		}
		var pid int
		if err := exportField(stage, "pid", &pid); err != nil || pid <= 0 || pids[pid] {
			return errors.New("admission process identity incomplete")
		}
		pids[pid] = true
		if index == 5 {
			if err := exportRequire(stage, "exit_code", float64(42)); err != nil {
				return err
			}
			if err := exportRequire(stage, "state_unchanged", true); err != nil {
				return err
			}
			continue
		}
		generation := 6
		if index == 0 {
			generation = 0
		}
		checks := 72
		if index == 6 {
			checks = 3
		}
		for key, value := range map[string]any{"modes_passed": float64(3), "canonical_checks": float64(checks), "learning_generation": float64(generation), "exit_code": float64(0)} {
			if err := exportRequire(stage, key, value); err != nil {
				return err
			}
		}
		key := "alias_or_disabled_source_checks"
		if index == 6 {
			key = "learned_alias_checks"
		}
		if err := exportRequire(stage, key, float64(checks)); err != nil {
			return err
		}
	}
	return nil
}

func exportProduct(config productExportConfig) (resultErr error) {
	for _, root := range []string{config.repo, config.root, config.indexes, config.data} {
		if !filepath.IsAbs(root) {
			return errors.New("explicit absolute export inputs required")
		}
		if err := packagePlainPath(root); err != nil {
			return err
		}
	}
	if err := packageRoot(config.root, "speech-admission-"); err != nil {
		return err
	}
	if err := packageNewRoot(config.output, "speech-product-export-", config.root, config.indexes, config.data); err != nil {
		return err
	}
	if !filepath.IsAbs(config.receipt) || strings.Contains(strings.TrimPrefix(config.receipt, filepath.VolumeName(config.receipt)), ":") || !strings.HasPrefix(filepath.Base(config.receipt), "speech-product-export-mapping") || filepath.Ext(config.receipt) != ".json" {
		return errors.New("new explicit package-external mapping receipt required")
	}
	if err := packagePlainPath(config.receipt); err != nil {
		return err
	}
	for _, protected := range []string{config.root, config.output, config.indexes, config.data} {
		if rootsOverlap(config.receipt, protected) {
			return errors.New("export receipt overlaps protected payload/input root")
		}
	}
	if _, err := os.Lstat(config.receipt); !os.IsNotExist(err) {
		return errors.New("export mapping receipt must not exist")
	}
	if info, err := os.Stat(filepath.Dir(config.receipt)); err != nil || !info.IsDir() {
		return errors.New("export receipt parent must already exist")
	}
	report, err := exportValidateSummary(config)
	if err != nil {
		return err
	}
	if err = verifyPackageRuntime(config.root); err != nil {
		return err
	}
	var manifest speechruntime.Manifest
	if err = readJSON(filepath.Join(config.root, "bundle-off.json"), &manifest); err != nil {
		return err
	}
	disabled := false
	product := speechruntime.ProductManifest{SchemaVersion: speechruntime.ProductSchema, ModuleID: speechruntime.ModuleID, ApprovedRecords: 24, DefaultEnabled: &disabled, LayoutSHA256: report.LayoutSHA256, Admission: manifest.Admission, ForwardSource: manifest.ForwardSource, Generation: manifest.Generation}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path, err := packageChild(config.indexes, mode+".yidx")
		if err != nil {
			return err
		}
		hash, err := speechruntime.HashFile(path)
		if err != nil || hash != product.Generation.Modes[mode].Core.ExpectedSHA256 {
			return errors.New("normal independently built core differs from admitted generation")
		}
	}
	path, err := packageChild(config.data, "yime_yinyuan_layout.json")
	if err != nil {
		return err
	}
	layout, err := speechruntime.HashFile(path)
	if err != nil || layout != report.LayoutSHA256 {
		return errors.New("normal product layout differs from admitted generation")
	}
	if err = os.Mkdir(config.output, 0700); err != nil {
		return err
	}
	// Failure preserves the isolated output and a truthful package-external receipt.
	defer func() {
		after, verifyErr := exportValidateSummary(config)
		report.InputsUnchanged = verifyErr == nil && reflect.DeepEqual(after.AdmissionArtifacts, report.AdmissionArtifacts) && after.Summary == report.Summary
		if !report.InputsUnchanged && verifyErr == nil {
			verifyErr = errors.New("export input evidence changed")
		}
		var productErr error
		if report.ProductVerified {
			productErr = verifyProductExport(config.output, config.indexes, config.data, report)
			report.ProductVerified = productErr == nil
		}
		report.Passed = resultErr == nil && verifyErr == nil && report.ProductVerified
		resultErr = errors.Join(resultErr, verifyErr, productErr, writeNew(config.receipt, report))
	}()
	for sourceRelative, targetRelative := range exportCopies {
		source, err := packageChild(config.root, sourceRelative)
		if err != nil {
			return err
		}
		item, err := describePackageFile("", targetRelative, source)
		if err != nil {
			return err
		}
		if err = copyPackageFile(source, config.output, item); err != nil {
			return err
		}
		report.Files = append(report.Files, exportMapping{SourcePath: sourceRelative, ProductPath: targetRelative, SHA256: item.SHA256, Bytes: item.Size})
	}
	if err = writeNew(filepath.Join(config.output, filepath.FromSlash(speechruntime.ProductManifestPath)), product); err != nil {
		return err
	}
	productSHA, err := speechruntime.HashFile(filepath.Join(config.output, filepath.FromSlash(speechruntime.ProductManifestPath)))
	if err != nil {
		return err
	}
	report.ProductSHA256 = productSHA
	capability := speechruntime.Capability{SchemaVersion: speechruntime.CapabilitySchema, DefaultEnabled: &disabled, Product: speechruntime.FileRef{Path: speechruntime.ProductManifestPath, SHA256: productSHA}}
	if err = writeNew(filepath.Join(config.output, speechruntime.CapabilityFilename), capability); err != nil {
		return err
	}
	for _, relative := range []string{speechruntime.ProductManifestPath, speechruntime.CapabilityFilename} {
		item, err := describePackageFile("", relative, filepath.Join(config.output, filepath.FromSlash(relative)))
		if err != nil {
			return err
		}
		report.Files = append(report.Files, exportMapping{ProductPath: relative, SHA256: item.SHA256, Bytes: item.Size, Generated: true})
	}
	sort.Slice(report.Files, func(i, j int) bool { return report.Files[i].ProductPath < report.Files[j].ProductPath })
	if err = verifyProductExport(config.output, config.indexes, config.data, report); err != nil {
		return err
	}
	report.ProductVerified = true
	return nil
}

func verifyProductExport(root, indexes, data string, report productExportReceipt) error {
	wanted := map[string]bool{speechruntime.CapabilityFilename: true, speechruntime.ProductManifestPath: true}
	for _, path := range exportCopies {
		wanted[path] = true
	}
	var records []exportSource
	for _, item := range report.Files {
		records = append(records, exportSource{item.ProductPath, item.Bytes, item.SHA256})
	}
	if err := exportCheckSources(root, records, wanted); err != nil {
		return err
	}
	if err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := packagePlainPath(path); err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		relative = filepath.ToSlash(relative)
		if entry.IsDir() {
			if relative != "." && relative != "speech" && relative != "speech/indexes" {
				return errors.New("unknown export directory")
			}
			return nil
		}
		if !wanted[relative] {
			return errors.New("unknown export file")
		}
		return nil
	}); err != nil {
		return err
	}
	capability, err := speechruntime.LoadCapability(root)
	if err != nil || capability == nil || capability.Product.SHA256 != report.ProductSHA256 {
		return errors.New("export capability failed verification")
	}
	product, err := speechruntime.OpenProduct(root, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return err
	}
	defer product.Close()
	if err = product.ValidateIndexes(indexes, data); err != nil {
		return err
	}
	admitted, err := candidateannotation.DecodeAdmittedRecords(product.AdmittedRecords())
	if err != nil {
		return err
	}
	if admitted.InputSHA256["layout"] != product.LayoutSHA256() {
		return errors.New("export annotation evidence layout differs")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		resolver, err := candidateannotation.Load(data, mode)
		if err != nil {
			return err
		}
		if _, err = resolver.WithAdmittedRecords(admitted, true); err != nil {
			return err
		}
		// Validate exact admitted payload membership without generating aliases.
		core, err := yimecore.OpenResidentFileIndex(filepath.Join(root, "speech", "indexes", mode+"-core.yidx"))
		if err != nil {
			return err
		}
		module, err := yimecore.OpenResidentFileIndex(filepath.Join(root, "speech", "indexes", mode+"-stage5c.yidx"))
		if err != nil {
			core.Close()
			return err
		}
		canonical, aliases := map[string]bool{}, map[string]bool{}
		for _, record := range admitted.Records {
			canonical[record.Text+"\x00"+record.Codes[mode].Canonical] = true
			aliases[record.Text+"\x00"+record.Codes[mode].Alias] = true
		}
		err = core.VisitEntries(func(entry yimecore.Entry) bool { delete(canonical, entry.Text+"\x00"+entry.Code); return true })
		valid := true
		if err == nil {
			err = module.VisitEntries(func(entry yimecore.Entry) bool {
				key := entry.Text + "\x00" + entry.Code
				if !aliases[key] || entry.Weight != 1 {
					valid = false
				}
				delete(aliases, key)
				return true
			})
		}
		closeErr := errors.Join(core.Close(), module.Close())
		if err != nil || closeErr != nil || !valid || len(canonical) != 0 || len(aliases) != 0 {
			return errors.New("export indexes do not contain exactly the admitted aliases and canonical members")
		}
	}
	return nil
}
