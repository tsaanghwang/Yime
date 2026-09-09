package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
)

const localRuntimeContract = "yimecore-local-runtime-bundle-v1"
const localInstallableContract = "yimecore-local-product-package-v1"
const localMaintenanceHealthProtocol = "yimecore-maintenance-health-v1"

// Optional maintenance health is a fixed package-owned source set. The facts
// helper stays at the process observer's existing ../dual-product path; this
// refers only to this package, never an installed Rime/PIME product.
var requiredLocalMaintenanceHealthFiles = []string{
	"maintenance/local-product-runtime.ps1",
	"maintenance/native-maintenance-processes.psm1",
	"maintenance/native-maintenance-process-facts.cs",
	"dual-product/rime-pime-dp1u-native-facts.cs",
	"maintenance/native-maintenance-health.psm1",
	"maintenance/native-maintenance-health-client.cs",
}

type localMaintenanceHealthDescriptor struct {
	Protocol        string `json:"protocol"`
	RequiredOnStart *bool  `json:"required_on_start"`
}

var requiredLocalMaintenanceFiles = []string{
	"Install-YimeCore-Local.cmd",
	"Maintain-YimeCore-Local.cmd",
	"maintenance/Manage-YimeCoreTrial.ps1",
	"maintenance/manage-local-product.ps1",
	"maintenance/local-package-contract.ps1",
	"maintenance/local-product-runtime.ps1",
	"maintenance/local-runtime-launcher.cs",
	"maintenance/development-scope.ps1",
	"maintenance/development-scope.json",
	"maintenance/local-maintenance-safety.ps1",
	"maintenance/backup-local-trial-state.ps1",
	"maintenance/restore-local-trial-state.ps1",
	"maintenance/start-e6c-trial-runtime.ps1",
	"maintenance/stop-e6c-trial-runtime.ps1",
	"maintenance/verify-e6c-trial-runtime.ps1",
	"LOCAL-PRODUCT.md",
}

// This is deliberately distinct from the legacy multi-architecture E6-C gate.
// A runtime bundle is NOT an installable local product. L3 needs a new contract.
var requiredLocalRuntimeFiles = []string{
	"bin/YimeBroker.exe",
	"bin/YimeCoreExplain.exe",
	"bin/YimeCoreSentenceRegression.exe",
	"bin/YimeCoreIndependenceAudit.exe",
	"bin/YimeCoreTrialRuntime.exe",
	"bin/YimeCoreInputToolbar.exe",
	"bin/YimeCoreReverseLookup.exe",
	"bin/YimeCoreLexiconManager.exe",
	"bin/YimeCoreTrainer.exe",
	"bin/YimeCoreToolCenter.exe",
	"bin/YimeCoreLexiconCenter.exe",
	"bin/YimeCoreBlocklistManager.exe",
	"bin/YimeCoreSystemLexiconAudit.exe",
	"bin/YimeCoreLearningManager.exe",
	"bin/YimeCorePromotionScan.exe",
	"bin/YimeCoreProfessionalLexicon.exe",
	"bin/YimeCoreLayoutDesigner.exe",
	"bin/YimeCoreDiagnostics.exe",
	"bin/YimeCoreSettingsTool.exe",
	"bin/YimeCoreRecoveryProbe.exe",
	"x64/YimeTextServiceExperiment.dll",
	"x64/YimeTextServiceRegistration.exe",
	"x64/YimeRegisteredHostTests.exe",
	"x86/YimeTextServiceExperiment.dll",
	"x86/YimeTextServiceRegistration.exe",
	"x86/YimeRegisteredHostTests.exe",
	"data/yime_yinyuan_layout.json",
	"data/yime_pinyin_codes.tsv",
	"data/pinyin_normalized.json",
	"data/yime_pua_pinyin.json",
	"data/fonts/YinYuan-Regular.ttf",
	"data/yime_full.dict.yaml",
	"data/yime_variable.dict.yaml",
	"data/yime_shorthand.dict.yaml",
	"data/yime_lexicon_manifest.json",
	"data/yime_core_source_manifest.json",
	"data/yime_full.schema.yaml",
	"data/yime_variable.schema.yaml",
	"data/yime_shorthand.schema.yaml",
	"data/yime_syllable_decomposition.tsv",
	"data/trainer/foundation.json",
	"data/trainer/curriculum.json",
	"data/trainer/yinyuan_catalog.json",
	"data/trainer/yinyuan_groups.json",
	"data/dynamic_sentence_cases.json",
	"professional-lexicons/catalog.json",
	"profile-icon.ico",
	"help/README.html",
	"help/diagnostics.html",
	"help/settings-and-data.html",
	"help/trial-feedback.html",
	"indexes/full.yidx",
	"indexes/variable.yidx",
	"indexes/shorthand.yidx",
	"local-product.json",
	"build/source-manifest.json",
	"build/build-inputs.json",
	"build/go-runtime-dependencies.txt",
}

// Optional product resources have one fixed ownership set, never a descriptor-
// supplied directory allowlist. The original local.12 requirements stay intact.
var requiredLocalSpeechFiles = []string{
	"speech-capability.json",
	"speech/product.json",
	"speech/admission.json",
	"speech/forward-source.json",
	"speech/admitted-records.json",
	"speech/indexes/full-core.yidx",
	"speech/indexes/full-stage5c.yidx",
	"speech/indexes/variable-core.yidx",
	"speech/indexes/variable-stage5c.yidx",
	"speech/indexes/shorthand-core.yidx",
	"speech/indexes/shorthand-stage5c.yidx",
}

type localSpeechDescriptor struct {
	CapabilityPath string `json:"capability_path"`
	DefaultEnabled *bool  `json:"default_enabled"`
}

func requiredFilesForContract(manifest packageManifest) ([]string, error) {
	switch manifest.PackageContract {
	case "":
		if strings.HasPrefix(manifest.ToolVersion, "yimecore-local-") {
			return nil, errors.New("local package must declare an explicit contract")
		}
		return requiredPackageFiles, nil
	case localRuntimeContract:
		if manifest.ToolVersion != "yimecore-local-builder-v1" {
			return nil, errors.New("unexpected local builder identity")
		}
		return requiredLocalRuntimeFiles, nil
	case localInstallableContract:
		if manifest.ToolVersion != "yimecore-local-builder-v1" {
			return nil, errors.New("unexpected local builder identity")
		}
		return append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...), nil
	default:
		return nil, fmt.Errorf("unknown contract %q", manifest.PackageContract)
	}
}

func validateLocalRuntimeContract(root string, entries map[string]manifestFile) error {
	return validateLocalContract(root, entries, localRuntimeContract)
}

func validateLocalContract(root string, entries map[string]manifestFile, contract string) error {
	installable := contract == localInstallableContract
	if err := rejectIndirectPath(root, "local-product.json"); err != nil {
		return err
	}
	data, err := os.ReadFile(filepath.Join(root, "local-product.json"))
	if err != nil {
		return err
	}
	var descriptor struct {
		SchemaVersion   string `json:"schema_version"`
		PackageContract string `json:"package_contract"`
		Installable     *bool  `json:"installable"`
		Version         string `json:"version"`
		DisplayName     string `json:"display_name"`
		Scope           struct {
			ComputerName        string   `json:"computer_name"`
			ActiveArchitectures []string `json:"active_architectures"`
		} `json:"scope"`
		Identity struct {
			ProductKey     string `json:"product_key"`
			CLSID          string `json:"clsid"`
			Profile        string `json:"profile"`
			LegacyCLSID    string `json:"legacy_clsid"`
			LegacyProfile  string `json:"legacy_profile"`
			StateDirectory string `json:"state_directory"`
			Pipe           string `json:"pipe"`
			ModelSourceID  string `json:"model_source_id"`
		} `json:"identity"`
	}
	if err := json.Unmarshal(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf}), &descriptor); err != nil {
		return err
	}
	speech, err := decodeLocalSpeechDescriptor(data)
	if err != nil {
		return err
	}
	health, err := decodeLocalMaintenanceHealthDescriptor(data)
	if err != nil {
		return err
	}
	if health != nil && !installable {
		return errors.New("maintenance health requires the installable local product contract")
	}
	allowed := map[string]bool{}
	for _, path := range append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...) {
		allowed[strings.ToLower(path)] = true
	}
	if speech != nil {
		for _, path := range requiredLocalSpeechFiles {
			allowed[path] = true
		}
	}
	if health != nil {
		for _, path := range requiredLocalMaintenanceHealthFiles {
			allowed[path] = true
		}
	}
	for path := range entries {
		if strings.HasPrefix(path, "arm64/") {
			return errors.New("ARM64 payload is outside this current-machine runtime bundle; use a target-specific experimental bundle")
		}
		if !installable && (strings.HasSuffix(path, ".cmd") || strings.HasPrefix(path, "maintenance/")) {
			return errors.New("runtime-only bundle must not advertise installation/maintenance")
		}
		if (installable || speech != nil || isLocalSpeechPath(path)) && !allowed[path] {
			return fmt.Errorf("unexpected local product payload: %s", path)
		}
	}
	if descriptor.SchemaVersion != "yimecore-local-product-v1" || descriptor.PackageContract != contract ||
		descriptor.Installable == nil || *descriptor.Installable != installable || descriptor.Version == "" ||
		descriptor.Scope.ComputerName != "MYCOMPUTER" || len(descriptor.Scope.ActiveArchitectures) != 2 ||
		descriptor.Scope.ActiveArchitectures[0] != "x64" || descriptor.Scope.ActiveArchitectures[1] != "x86" {
		return errors.New("invalid local product schema, scope or installability")
	}
	if installable && descriptor.DisplayName != "音元拼音" {
		return errors.New("unexpected local product display name")
	}
	id := descriptor.Identity
	if id.ProductKey != "YimeCoreExperimentalTrial" ||
		id.CLSID != "{E40FA752-BB96-461D-A51D-F40EB437EC65}" ||
		id.Profile != "{126F54C6-E9B1-4E22-8652-03224CBD49F9}" ||
		id.LegacyCLSID != "{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}" ||
		id.LegacyProfile != "{607895A8-9504-4A2E-9BB1-2C159E3A1757}" ||
		id.StateDirectory != "YimeCore Experimental Trial" ||
		id.Pipe != `\\.\pipe\YimeBroker.YimeCoreTrial.v1` ||
		id.ModelSourceID != "yimecore-e6c-three-mode-trial-v1" {
		return errors.New("local product changes a stable compatibility identity")
	}
	if err := validateLocalMaintenanceHealthContract(root, entries, health); err != nil {
		return err
	}
	return validateLocalSpeechContract(root, entries, speech)
}

func decodeLocalMaintenanceHealthDescriptor(data []byte) (*localMaintenanceHealthDescriptor, error) {
	outer, err := localJSONObject(data)
	if err != nil {
		return nil, err
	}
	for name := range outer {
		if strings.EqualFold(name, "maintenance_health") && name != "maintenance_health" {
			return nil, errors.New("maintenance health declaration must use its canonical field name")
		}
	}
	raw := outer["maintenance_health"]
	if len(raw) == 0 {
		return nil, nil // Historical descriptors have no new prerequisite.
	}
	fields, err := localJSONObject(raw)
	if err != nil || len(fields) != 2 || fields["protocol"] == nil || fields["required_on_start"] == nil {
		return nil, errors.New("maintenance health requires exactly protocol and required_on_start")
	}
	var result localMaintenanceHealthDescriptor
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	if result.Protocol != localMaintenanceHealthProtocol || result.RequiredOnStart == nil || !*result.RequiredOnStart {
		return nil, errors.New("maintenance health requires its fixed protocol and literal required_on_start true")
	}
	return &result, nil
}

func validateLocalMaintenanceHealthContract(root string, entries map[string]manifestFile, descriptor *localMaintenanceHealthDescriptor) error {
	if descriptor == nil {
		return nil
	}
	for _, path := range requiredLocalMaintenanceHealthFiles {
		item, exists := entries[strings.ToLower(path)]
		if !exists || item.Path != path {
			return fmt.Errorf("maintenance health helper is missing from canonical manifest paths: %s", path)
		}
		if err := rejectIndirectPath(root, path); err != nil {
			return err
		}
		full := filepath.Join(root, filepath.FromSlash(path))
		info, err := os.Stat(full)
		if err != nil || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() != item.Bytes {
			return fmt.Errorf("maintenance health helper is absent, irregular or size-mismatched: %s", path)
		}
		digest, err := hashFile(full)
		if err != nil || !strings.EqualFold(digest, item.SHA256) {
			return fmt.Errorf("maintenance health helper manifest hash mismatch: %s", path)
		}
	}
	return nil
}

func isLocalSpeechPath(path string) bool {
	path = strings.ToLower(path)
	return path == "speech-capability.json" || path == "speech" || strings.HasPrefix(path, "speech/")
}

// Retain the descriptor's existing extension fields, but do not let duplicate
// JSON keys or a differently cased speech field create two interpretations.
func localJSONObject(data []byte) (map[string]json.RawMessage, error) {
	decoder := json.NewDecoder(bytes.NewReader(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf})))
	start, err := decoder.Token()
	if err != nil || start != json.Delim('{') {
		return nil, errors.New("local contract requires a JSON object")
	}
	fields := map[string]json.RawMessage{}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		name, ok := token.(string)
		if !ok || fields[name] != nil {
			return nil, errors.New("duplicate local contract JSON field")
		}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return nil, err
		}
		fields[name] = value
	}
	if _, err = decoder.Token(); err != nil {
		return nil, err
	}
	if _, err = decoder.Token(); err != io.EOF {
		return nil, errors.New("trailing local contract JSON")
	}
	return fields, nil
}

func localSpeechField(data []byte) (json.RawMessage, error) {
	fields, err := localJSONObject(data)
	if err != nil {
		return nil, err
	}
	for name := range fields {
		if strings.EqualFold(name, "speech") && name != "speech" {
			return nil, errors.New("speech declaration must use its canonical field name")
		}
	}
	return fields["speech"], nil
}

func decodeLocalSpeechDescriptor(data []byte) (*localSpeechDescriptor, error) {
	raw, err := localSpeechField(data)
	if err != nil || len(raw) == 0 {
		return nil, err
	}
	fields, err := localJSONObject(raw)
	if err != nil || len(fields) != 2 || fields["capability_path"] == nil || fields["default_enabled"] == nil {
		return nil, errors.New("speech declaration requires exactly capability_path and default_enabled")
	}
	var result localSpeechDescriptor
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	if result.CapabilityPath != speechruntime.CapabilityFilename || result.DefaultEnabled == nil || *result.DefaultEnabled {
		return nil, errors.New("only fixed default-off speech capability is allowed")
	}
	return &result, nil
}

func validateLocalSpeechContract(root string, entries map[string]manifestFile, descriptor *localSpeechDescriptor) error {
	if descriptor == nil {
		for _, name := range []string{speechruntime.CapabilityFilename, "speech"} {
			if _, err := os.Lstat(filepath.Join(root, name)); !errors.Is(err, os.ErrNotExist) {
				return errors.New("undeclared speech payload is not a core-only product")
			}
		}
		return nil
	}
	for _, path := range requiredLocalSpeechFiles {
		item, exists := entries[path]
		if !exists || item.Path != path {
			return errors.New("declared speech payload requires all eleven canonical manifest paths")
		}
		if err := rejectIndirectPath(root, path); err != nil {
			return err
		}
		full := filepath.Join(root, filepath.FromSlash(path))
		info, err := os.Stat(full)
		if err != nil || !info.Mode().IsRegular() || info.Size() != item.Bytes {
			return errors.New("speech manifest file is absent, irregular or size-mismatched")
		}
		digest, err := hashFile(full)
		if err != nil || !strings.EqualFold(digest, item.SHA256) {
			return errors.New("speech outer manifest hash mismatch")
		}
	}
	capability, err := speechruntime.LoadCapability(root)
	if err != nil || capability == nil {
		return errors.New("declared speech capability is missing or invalid")
	}
	product, err := speechruntime.OpenProduct(root, capability.Product.Path, capability.Product.SHA256)
	if err != nil {
		return fmt.Errorf("speech product receipt/index validation: %w", err)
	}
	defer product.Close()
	// This is package sealing, not the runtime's disabled-layout compatibility
	// path. A newly packaged core and layout must always match its speech assets.
	dataRoot := filepath.Join(root, "data")
	if err := product.ValidateIndexes(filepath.Join(root, "indexes"), dataRoot); err != nil {
		return err
	}
	admitted, err := candidateannotation.DecodeAdmittedRecords(product.AdmittedRecords())
	if err != nil {
		return errors.New("speech annotation receipt cannot be decoded")
	}
	if admitted.InputSHA256["layout"] != product.LayoutSHA256() {
		return errors.New("speech annotation receipt layout differs from product layout")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		resolver, err := candidateannotation.Load(dataRoot, mode)
		if err != nil {
			return fmt.Errorf("speech %s annotation resources: %w", mode, err)
		}
		if _, err := resolver.WithAdmittedRecords(admitted, true); err != nil {
			return fmt.Errorf("speech %s annotation binding: %w", mode, err)
		}
	}
	return validateLocalSpeechBuildBinding(root, capability)
}

func localSpeechDigest(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == 32 && len(value) == 64 && value == strings.ToLower(value)
}

func validateLocalSpeechBuildBinding(root string, capability *speechruntime.Capability) error {
	const path = "build/build-inputs.json"
	if err := rejectIndirectPath(root, path); err != nil {
		return err
	}
	data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path)))
	if err != nil {
		return err
	}
	raw, err := localSpeechField(data)
	if err != nil || len(raw) == 0 {
		return errors.New("speech build binding is missing")
	}
	fields, err := localJSONObject(raw)
	if err != nil || len(fields) != 6 {
		return errors.New("speech build binding field set mismatch")
	}
	var values map[string]string
	if err := json.Unmarshal(raw, &values); err != nil {
		return err
	}
	if values["schema_version"] != "yimecore-speech-build-binding-v1" {
		return errors.New("speech build binding schema mismatch")
	}
	for _, name := range []string{"admission_summary_sha256", "source_inventory_sha256", "export_receipt_sha256", "capability_sha256", "product_manifest_sha256"} {
		if !localSpeechDigest(values[name]) {
			return errors.New("speech build binding requires five pinned lowercase SHA-256 values")
		}
	}
	capabilityDigest, err := hashFile(filepath.Join(root, speechruntime.CapabilityFilename))
	if err != nil || values["capability_sha256"] != capabilityDigest || values["product_manifest_sha256"] != capability.Product.SHA256 {
		return errors.New("speech build binding does not identify packaged capability/product bytes")
	}
	// The other three digests pin archived build evidence. The auditor must not
	// turn that evidence into an installed dependency by following outside paths.
	return nil
}
