package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const localRuntimeContract = "yimecore-local-runtime-bundle-v1"
const localInstallableContract = "yimecore-local-product-package-v1"

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
	allowed := map[string]bool{}
	for _, path := range append(append([]string(nil), requiredLocalRuntimeFiles...), requiredLocalMaintenanceFiles...) {
		allowed[strings.ToLower(path)] = true
	}
	for path := range entries {
		if strings.HasPrefix(path, "x86/") || strings.HasPrefix(path, "arm64/") {
			return errors.New("frozen-architecture payload in x64-only runtime bundle")
		}
		if !installable && (strings.HasSuffix(path, ".cmd") || strings.HasPrefix(path, "maintenance/")) {
			return errors.New("runtime-only bundle must not advertise installation/maintenance")
		}
		if installable && !allowed[path] {
			return fmt.Errorf("unexpected local product payload: %s", path)
		}
	}
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
			StateDirectory string `json:"state_directory"`
			Pipe           string `json:"pipe"`
			ModelSourceID  string `json:"model_source_id"`
		} `json:"identity"`
	}
	if err := json.Unmarshal(bytes.TrimPrefix(data, []byte{0xef, 0xbb, 0xbf}), &descriptor); err != nil {
		return err
	}
	if descriptor.SchemaVersion != "yimecore-local-product-v1" || descriptor.PackageContract != contract ||
		descriptor.Installable == nil || *descriptor.Installable != installable || descriptor.Version == "" ||
		descriptor.Scope.ComputerName != "MYCOMPUTER" || len(descriptor.Scope.ActiveArchitectures) != 1 ||
		descriptor.Scope.ActiveArchitectures[0] != "x64" {
		return errors.New("invalid local product schema, scope or installability")
	}
	if installable && descriptor.DisplayName != "Yime 独立开发版" {
		return errors.New("unexpected local product display name")
	}
	id := descriptor.Identity
	if id.ProductKey != "YimeCoreExperimentalTrial" ||
		id.CLSID != "{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}" ||
		id.Profile != "{607895A8-9504-4A2E-9BB1-2C159E3A1757}" ||
		id.StateDirectory != "YimeCore Experimental Trial" ||
		id.Pipe != `\\.\pipe\YimeBroker.YimeCoreTrial.v1` ||
		id.ModelSourceID != "yimecore-e6c-three-mode-trial-v1" {
		return errors.New("local product changes a stable compatibility identity")
	}
	return nil
}
