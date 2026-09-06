// Command yimecore-speech-admission prepares and exercises a private, Rime-free
// Stage5C bundle. It is not included in a local-product installation manifest.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func main() {
	action := flag.String("action", "", "prepare, exercise, package, verify-package, exercise-package or export-product")
	repo := flag.String("repo", "", "explicit repository input root")
	root := flag.String("root", "", "fresh speech-admission trial root")
	broker := flag.String("broker", "", "newly built isolated Broker")
	brokerSHA := flag.String("broker-sha256", "", "expected new Broker hash")
	outputRoot := flag.String("output-root", "", "new, nonoverlapping package or exercise output root")
	packageSHA := flag.String("package-sha256", "", "expected sealed package manifest hash")
	summarySHA := flag.String("summary-sha256", "", "expected fresh admission summary hash")
	inventorySHA := flag.String("source-inventory-sha256", "", "expected summary-bound admission source inventory hash")
	normalIndexes := flag.String("normal-index-root", "", "independently built normal core index root")
	normalData := flag.String("normal-data-root", "", "independently built normal product data root")
	exportReceipt := flag.String("export-receipt", "", "new package-external speech-product-export-mapping JSON path")
	flag.Parse()
	var err error
	switch *action {
	case "prepare":
		err = prepare(*repo, *root)
	case "exercise":
		err = exercise(*root, *broker, *brokerSHA)
	case "package":
		err = packageCandidate(*repo, *root, *outputRoot, *broker, *brokerSHA)
	case "verify-package":
		_, err = verifyPackage(*root, *packageSHA)
	case "exercise-package":
		err = exercisePackage(*root, *packageSHA, *outputRoot)
	case "export-product":
		err = exportProduct(productExportConfig{repo: *repo, root: *root, summarySHA: *summarySHA, inventorySHA: *inventorySHA, indexes: *normalIndexes, data: *normalData, output: *outputRoot, receipt: *exportReceipt})
	default:
		err = errors.New("explicit supported speech action required")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("PASS: isolated speech " + *action + " only; no installed or daily-use acceptance inferred.")
}

func writeNew(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, err = f.Write(append(data, '\n'))
	return errors.Join(err, f.Close())
}

func readJSON(path string, target any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}

func prepare(repo, root string) error {
	if repo == "" || !filepath.IsAbs(repo) {
		return errors.New("absolute repository input root required")
	}
	if err := speechruntime.IsTrialRoot(root); err != nil {
		return err
	}
	forwardPath, err := speechruntime.Child(root, "forward-source.json")
	if err != nil {
		return err
	}
	forward, err := speechruntime.ReadForward(forwardPath)
	if err != nil {
		return err
	}
	for relative, expected := range forward.InputSHA256 {
		p, err := speechruntime.Child(repo, relative)
		if err != nil {
			return err
		}
		hash, err := speechruntime.HashFile(p)
		if err != nil || hash != expected {
			return errors.New("forward-source input changed before preparation")
		}
	}
	dataRoot := filepath.Join(repo, "go-backend", "input_methods", "yime", "data")
	var lock struct {
		Artifacts []struct {
			Role, Path, SHA256 string
			Size               int64
		}
	}
	if err := readJSON(filepath.Join(repo, "tools", "lexicon", "data", "yime_core_target.lock.json"), &lock); err != nil {
		return err
	}
	locked := map[string]string{}
	for _, item := range lock.Artifacts {
		if item.Role == "third_tone_sandhi_layer" || item.Role == "canonical_layout_projection" || item.Role == "full_mode_dictionary" || item.Role == "variable_mode_dictionary" || item.Role == "shorthand_mode_dictionary" {
			if _, duplicate := locked[item.Role]; duplicate {
				return errors.New("duplicate lock role")
			}
			p, err := speechruntime.Child(repo, item.Path)
			if err != nil {
				return err
			}
			hash, err := speechruntime.HashFile(p)
			if err != nil || hash != item.SHA256 {
				return errors.New("locked input hash mismatch")
			}
			locked[item.Role] = item.SHA256
		}
	}
	if len(locked) != 5 {
		return errors.New("missing source lock roles")
	}
	var historical struct {
		InputSHA256 map[string]string `json:"input_sha256"`
	}
	if err := readJSON(filepath.Join(dataRoot, "yime_third_tone_stage5c_manifest.json"), &historical); err != nil {
		return err
	}
	if hash, err := speechruntime.HashFile(filepath.Join(dataRoot, "yime_third_tone_stage5c_manifest.json")); err != nil || hash != locked["third_tone_sandhi_layer"] {
		return errors.New("approved manifest not locked")
	}
	inventoryRelative := "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv"
	layoutRelative := "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"
	if forward.InputSHA256[layoutRelative] != locked["canonical_layout_projection"] {
		return errors.New("forward layout differs from target lock")
	}
	input := connectedspeech.AdmissionInput{
		ReviewPath:    filepath.Join(repo, "docs", "project", "connected_speech", "third_tone_stage5b_review.tsv"),
		DecisionsPath: filepath.Join(repo, "docs", "project", "connected_speech", "third_tone_stage5b_decisions.tsv"),
		SourcesPath:   filepath.Join(repo, "docs", "project", "connected_speech", "third_tone_stage5b_sources.tsv"),
		InventoryPath: filepath.Join(repo, filepath.FromSlash(inventoryRelative)), LayoutPath: filepath.Join(repo, filepath.FromSlash(layoutRelative)),
		ExpectedSHA256: map[string]string{"review": historical.InputSHA256["review"], "decisions": historical.InputSHA256["decisions"], "sources": historical.InputSHA256["sources"], "inventory": forward.InputSHA256[inventoryRelative], "layout": locked["canonical_layout_projection"]},
	}
	admitted, err := connectedspeech.AdmitStage5C(input)
	if err != nil {
		return err
	}
	recordPath, _ := speechruntime.Child(root, "admitted-records.json")
	if err := writeNew(recordPath, admitted); err != nil {
		return err
	}
	recordHash, err := speechruntime.HashFile(recordPath)
	if err != nil {
		return err
	}
	forwardHash, err := speechruntime.HashFile(forwardPath)
	if err != nil {
		return err
	}
	indexRoot, _ := speechruntime.Child(root, "indexes")
	if err := os.Mkdir(indexRoot, 0700); err != nil {
		return err
	}
	gen := yimebroker.BundleGenerationSpec{Version: "stage5c-enabled-v1", Modes: map[string]yimebroker.BundleModeSpec{}}
	receipt := speechruntime.AdmissionReceipt{SchemaVersion: "yimecore-speech-admission-receipt-v1", Passed: true, RecordCount: 24, ForwardSHA256: forwardHash,
		Records: speechruntime.FileRef{Path: "admitted-records.json", SHA256: recordHash}, Checks: map[string]bool{"forward_source": true, "four_positions": true, "nonlengthening": true, "canonical_membership": true, "canonical_weights_consistent": true}, Modes: map[string]speechruntime.AdmissionMode{}}
	weights := map[string]int64{}
	builds := map[string][]yimecore.IndexBuildResult{}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		coreRelative, moduleRelative := "indexes/"+mode+"-core.yidx", "indexes/"+mode+"-stage5c.yidx"
		corePath, _ := speechruntime.Child(root, coreRelative)
		modulePath, _ := speechruntime.Child(root, moduleRelative)
		coreSource := filepath.Join(dataRoot, "yime_"+mode+".dict.yaml")
		coreHash, err := speechruntime.HashFile(coreSource)
		if err != nil || coreHash != locked[mode+"_mode_dictionary"] {
			return errors.New("core source differs from lock")
		}
		coreBuild, err := yimecore.BuildIndexFile(mode, coreSource, corePath)
		if err != nil {
			return err
		}
		if coreBuild.SourceSHA256 != coreHash {
			return errors.New("core changed during index build")
		}
		core, err := yimecore.OpenFileIndex(corePath)
		if err != nil {
			return err
		}
		wanted := map[string]connectedspeech.AdmissionRecord{}
		entries := make([]yimecore.Entry, 0, 24)
		for _, record := range admitted.Records {
			wanted[record.Codes[mode].Canonical+"\x00"+record.Text] = record
			entries = append(entries, yimecore.Entry{Text: record.Text, Code: record.Codes[mode].Alias, Weight: 1})
		}
		found := map[string]bool{}
		err = core.VisitEntries(func(entry yimecore.Entry) bool {
			if record, ok := wanted[entry.Code+"\x00"+entry.Text]; ok {
				found[record.ReviewID] = true
				if previous, exists := weights[record.ReviewID]; exists && previous != entry.Weight {
					receipt.Checks["canonical_weights_consistent"] = false
				}
				weights[record.ReviewID] = entry.Weight
			}
			return true
		})
		closeErr := core.Close()
		if err != nil {
			return err
		}
		if closeErr != nil {
			return closeErr
		}
		if len(found) != 24 || !receipt.Checks["canonical_weights_consistent"] {
			return errors.New("canonical membership or mode weight consistency failed")
		}
		moduleBuild, err := yimecore.BuildIndexEntries(mode, entries, recordPath, modulePath)
		if err != nil {
			return err
		}
		if moduleBuild.IndexedRecords != 24 || moduleBuild.DuplicateRecords != 0 {
			return errors.New("incomplete or duplicate admitted aliases")
		}
		gen.Modes[mode] = yimebroker.BundleModeSpec{Core: yimebroker.IndexSpec{Version: gen.Version, Mode: mode, Path: coreRelative, ExpectedSHA256: coreBuild.IndexSHA256}, Modules: []yimebroker.BundleModuleSpec{{ID: speechruntime.ModuleID, Index: yimebroker.IndexSpec{Version: gen.Version, Mode: mode, Path: moduleRelative, ExpectedSHA256: moduleBuild.IndexSHA256}}}}
		receipt.Modes[mode] = speechruntime.AdmissionMode{CoreSHA256: coreBuild.IndexSHA256, ModuleSHA256: moduleBuild.IndexSHA256, CanonicalCount: 24, AliasCount: 24}
		builds[mode] = []yimecore.IndexBuildResult{coreBuild, moduleBuild}
	}
	receiptPath, _ := speechruntime.Child(root, "admission.json")
	if err := writeNew(receiptPath, receipt); err != nil {
		return err
	}
	receiptHash, err := speechruntime.HashFile(receiptPath)
	if err != nil {
		return err
	}
	manifest := speechruntime.Manifest{SchemaVersion: speechruntime.Schema, Enabled: false, ApprovedRecords: 24, Admission: speechruntime.FileRef{Path: "admission.json", SHA256: receiptHash}, ForwardSource: speechruntime.FileRef{Path: "forward-source.json", SHA256: forwardHash}, Generation: gen}
	for _, enabled := range []bool{false, true} {
		name := "bundle-off.json"
		if enabled {
			name = "bundle-on.json"
		}
		manifest.Enabled = enabled
		if err := writeNew(filepath.Join(root, name), manifest); err != nil {
			return err
		}
	}
	return writeNew(filepath.Join(root, "prepare-outcome.json"), map[string]any{"schema_version": "yimecore-speech-prepare-v1", "passed": true, "records": 24, "mode_rows": 72, "builds": builds, "rime_executed": false, "runtime_rule_inference": false, "installed_product_changed": false})
}
