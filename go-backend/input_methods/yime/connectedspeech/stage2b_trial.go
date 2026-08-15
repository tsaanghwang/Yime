package connectedspeech

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const Stage2BTrialToolVersion = "connected-speech-stage2b-rime-trial-v1"

var stage2BTrialBaselineFiles = []string{
	"yime_pinyin_codes.tsv",
	"yime_syllable_decomposition.tsv",
	"yime_yinyuan_layout.json",
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
}

var stage2BTrialModes = []struct {
	Mode               string
	Dictionary         string
	BaselineDictionary string
	Patch              string
}{
	{"full", "yime_connected_speech_stage2b_full.dict.yaml", "yime_connected_speech_stage2b_baseline_full.dict.yaml", "yime_full.custom.yaml"},
	{"variable", "yime_connected_speech_stage2b_variable.dict.yaml", "yime_connected_speech_stage2b_baseline_variable.dict.yaml", "yime_variable.custom.yaml"},
	{"shorthand", "yime_connected_speech_stage2b_shorthand.dict.yaml", "yime_connected_speech_stage2b_baseline_shorthand.dict.yaml", "yime_shorthand.custom.yaml"},
}

type Stage2BTrialConfig struct {
	RepoRoot          string
	DataDir           string
	RecordsPath       string
	SchemaPath        string
	OutputDir         string
	AllowedOutputRoot string
}

func DefaultStage2BTrialConfig(repoRoot string) Stage2BTrialConfig {
	return Stage2BTrialConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		RecordsPath:       filepath.Join(repoRoot, "docs", "project", "connected_speech", "stage2_yi_bu_records.json"),
		SchemaPath:        filepath.Join(repoRoot, "docs", "project", "connected_speech", "connected_speech_record.schema.json"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "connected-speech-stage2b-rime"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

type Stage2BTrialSummary struct {
	ToolVersion             string          `json:"tool_version"`
	RecordCount             int             `json:"record_count"`
	TrialAliasCount         int             `json:"trial_alias_count"`
	StaticDictionaryAliases int             `json:"static_dictionary_aliases"`
	DynamicCandidateAliases int             `json:"dynamic_candidate_aliases"`
	ThreeModeEntryCount     int             `json:"three_mode_entry_count"`
	GrowingProjectionCount  int             `json:"growing_projection_count"`
	RuntimeAliasesGenerated int             `json:"runtime_aliases_generated"`
	BaselineHashesMatch     bool            `json:"baseline_hashes_match"`
	Gates                   map[string]bool `json:"gates"`
	Passed                  bool            `json:"passed"`
}

type Stage2BTrialManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type Stage2BTrialResult struct {
	Summary  Stage2BTrialSummary
	Manifest Stage2BTrialManifest
}

type stage2BTrialEntry struct {
	RecordID  string
	Text      string
	Reading   string
	Canonical codemode.Record
	Codes     codemode.Record
	Growth    map[string]int
}

type stage2BWeightPolicy struct {
	Kind   string
	Weight string
}

const (
	stage2BStaticWeight  = "inherit_static_dictionary_weight"
	stage2BDynamicWeight = "preserve_dynamic_rime_scoring"
)

func RunStage2BRimeTrial(config Stage2BTrialConfig) (Stage2BTrialResult, error) {
	if err := validateStage2BTrialConfig(&config); err != nil {
		return Stage2BTrialResult{}, err
	}
	if err := ValidateSchemaDocument(config.SchemaPath); err != nil {
		return Stage2BTrialResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return Stage2BTrialResult{}, err
	}

	baselinePaths := map[string]string{}
	for _, name := range stage2BTrialBaselineFiles {
		baselinePaths[name] = filepath.Join(config.DataDir, name)
	}
	before, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_before.json"), before); err != nil {
		return Stage2BTrialResult{}, err
	}

	records, err := LoadRecords(config.RecordsPath)
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	inventory, err := LoadInventory(filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"))
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	if issues := ValidateRecords(records, inventory); len(issues) != 0 {
		return Stage2BTrialResult{}, fmt.Errorf("Stage 2B records have %d validation issues: %s", len(issues), issues[0].Error())
	}
	profile, err := layoutdesigner.LoadProfile(filepath.Join(config.DataDir, "yime_yinyuan_layout.json"))
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	switches := Switches{Enabled: true, ToneSandhi: true}
	entries := []stage2BTrialEntry{}
	growing := 0
	for _, record := range records {
		sequence, _, reason := selectTrialSequence(record, switches)
		if reason != "" {
			continue
		}
		canonical, projectErr := projectSequence(record.CanonicalYinyuanIDs, profile)
		if projectErr != nil {
			return Stage2BTrialResult{}, projectErr
		}
		trial, projectErr := projectSequence(sequence, profile)
		if projectErr != nil {
			return Stage2BTrialResult{}, projectErr
		}
		if !modeLengthProjectionValid(canonical, trial) {
			return Stage2BTrialResult{}, fmt.Errorf("%s has an invalid per-syllable mode projection", record.RecordID)
		}
		if canonical.Full == trial.Full && canonical.Variable == trial.Variable && canonical.Shorthand == trial.Shorthand {
			continue
		}
		growth := map[string]int{
			"full":      codeLength(trial.FullSpelling) - codeLength(canonical.FullSpelling),
			"variable":  codeLength(trial.VariableSpelling) - codeLength(canonical.VariableSpelling),
			"shorthand": codeLength(trial.ShorthandSpelling) - codeLength(canonical.ShorthandSpelling),
		}
		for _, delta := range growth {
			if delta > 0 {
				growing++
			}
		}
		entries = append(entries, stage2BTrialEntry{
			RecordID: record.RecordID, Text: record.Text, Reading: valueOrEmpty(record.SurfaceReading), Canonical: canonical, Codes: trial, Growth: growth,
		})
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].RecordID < entries[j].RecordID })

	weightPolicies, err := resolveStage2BWeightPolicies(entries, config.DataDir)
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	staticAliases := 0
	dynamicAliases := 0
	for _, entry := range entries {
		if weightPolicies[entry.RecordID].Kind == stage2BStaticWeight {
			staticAliases++
		} else {
			dynamicAliases++
		}
	}
	entryRows := [][]string{{"record_id", "text", "surface_reading", "mode", "trial_code", "inherited_weight", "weight_policy", "length_delta"}}
	for _, mode := range stage2BTrialModes {
		dictionaryName := strings.TrimSuffix(mode.Dictionary, ".dict.yaml")
		baselineName := strings.TrimSuffix(mode.BaselineDictionary, ".dict.yaml")
		header := func(name string) []string {
			return []string{
				"# Stage 2B temporary connected-speech trial dictionary",
				"# GENERATED IN .tmp - DO NOT INSTALL",
				"---",
				"name: " + name,
				"version: \"stage2b-v1\"",
				"sort: by_weight",
				"use_preset_vocabulary: false",
				"...",
			}
		}
		lines := header(dictionaryName)
		baselineLines := header(baselineName)
		for _, entry := range entries {
			canonicalCode := recordCode(entry.Canonical, mode.Mode)
			code := recordCode(entry.Codes, mode.Mode)
			policy := weightPolicies[entry.RecordID]
			if policy.Kind == stage2BStaticWeight {
				lines = append(lines, rimeDictionaryLine(entry.Text, canonicalCode, policy.Weight))
				lines = append(lines, rimeDictionaryLine(entry.Text, code, policy.Weight))
				baselineLines = append(baselineLines, rimeDictionaryLine(entry.Text, canonicalCode, policy.Weight))
			}
			entryRows = append(entryRows, []string{
				entry.RecordID, entry.Text, entry.Reading, mode.Mode, code, policy.Weight, policy.Kind, fmt.Sprint(entry.Growth[mode.Mode]),
			})
		}
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.Dictionary), []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
			return Stage2BTrialResult{}, err
		}
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.BaselineDictionary), []byte(strings.Join(baselineLines, "\n")+"\n"), 0o644); err != nil {
			return Stage2BTrialResult{}, err
		}
		patch := "patch:\n  translator/dictionary: " + dictionaryName + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.Patch), []byte(patch), 0o644); err != nil {
			return Stage2BTrialResult{}, err
		}
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "stage2b_entries.tsv"), entryRows); err != nil {
		return Stage2BTrialResult{}, err
	}

	after, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_after.json"), after); err != nil {
		return Stage2BTrialResult{}, err
	}
	baselineMatch := equalHashes(before, after)
	gates := map[string]bool{
		"two_reviewed_aliases":            len(entries) == 2,
		"three_mode_entries_complete":     len(entryRows)-1 == len(entries)*3,
		"all_aliases_weight_classified":   staticAliases+dynamicAliases == len(entries),
		"per_syllable_code_lengths_valid": true,
		"canonical_data_hashes_unchanged": baselineMatch,
		"installed_pime_accessed_zero":    true,
		"runtime_aliases_generated_zero":  true,
	}
	summary := Stage2BTrialSummary{
		ToolVersion: Stage2BTrialToolVersion, RecordCount: len(records), TrialAliasCount: len(entries),
		StaticDictionaryAliases: staticAliases, DynamicCandidateAliases: dynamicAliases,
		ThreeModeEntryCount: len(entryRows) - 1, GrowingProjectionCount: growing, RuntimeAliasesGenerated: 0,
		BaselineHashesMatch: baselineMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return Stage2BTrialResult{}, err
	}

	inputHashes, err := hashNamedFiles(map[string]string{
		"records": config.RecordsPath, "schema": config.SchemaPath,
		"decomposition": filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"),
		"layout":        filepath.Join(config.DataDir, "yime_yinyuan_layout.json"),
	})
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	outputPaths := map[string]string{
		"baseline_hashes_before.json": filepath.Join(config.OutputDir, "baseline_hashes_before.json"),
		"baseline_hashes_after.json":  filepath.Join(config.OutputDir, "baseline_hashes_after.json"),
		"stage2b_entries.tsv":         filepath.Join(config.OutputDir, "stage2b_entries.tsv"),
		"summary.json":                filepath.Join(config.OutputDir, "summary.json"),
	}
	for _, mode := range stage2BTrialModes {
		outputPaths[mode.Dictionary] = filepath.Join(config.OutputDir, mode.Dictionary)
		outputPaths[mode.BaselineDictionary] = filepath.Join(config.OutputDir, mode.BaselineDictionary)
		outputPaths[mode.Patch] = filepath.Join(config.OutputDir, mode.Patch)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return Stage2BTrialResult{}, err
	}
	manifest := Stage2BTrialManifest{
		ToolVersion: Stage2BTrialToolVersion, InputSHA256: inputHashes, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic Stage 2B temporary Rime files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return Stage2BTrialResult{}, err
	}
	result := Stage2BTrialResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("Stage 2B temporary Rime trial gates did not pass")
	}
	return result, nil
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func loadDictionaryWeightIndex(path string) (map[string]string, error) {
	result := map[string]string{}
	err := scanRimeDictionary(path, func(entry dictionaryEntry) {
		result[dictionaryKey(entry.Text, entry.Code)] = entry.Weight
	})
	return result, err
}

func resolveStage2BWeightPolicies(entries []stage2BTrialEntry, dataDir string) (map[string]stage2BWeightPolicy, error) {
	indexes := map[string]map[string]string{}
	for _, mode := range stage2BTrialModes {
		index, err := loadDictionaryWeightIndex(filepath.Join(dataDir, "yime_"+mode.Mode+".dict.yaml"))
		if err != nil {
			return nil, err
		}
		indexes[mode.Mode] = index
	}
	result := make(map[string]stage2BWeightPolicy, len(entries))
	for _, entry := range entries {
		found := 0
		weight := ""
		for _, mode := range stage2BTrialModes {
			canonicalCode := recordCode(entry.Canonical, mode.Mode)
			current, exists := indexes[mode.Mode][dictionaryKey(entry.Text, canonicalCode)]
			if !exists {
				continue
			}
			found++
			if found == 1 {
				weight = current
				continue
			}
			if current != weight {
				return nil, fmt.Errorf("%s has inconsistent canonical weights across modes: %q vs %q", entry.RecordID, weight, current)
			}
		}
		switch found {
		case 0:
			result[entry.RecordID] = stage2BWeightPolicy{Kind: stage2BDynamicWeight}
		case len(stage2BTrialModes):
			result[entry.RecordID] = stage2BWeightPolicy{Kind: stage2BStaticWeight, Weight: weight}
		default:
			return nil, fmt.Errorf("%s has a partial canonical dictionary path in %d/%d modes", entry.RecordID, found, len(stage2BTrialModes))
		}
	}
	return result, nil
}

func rimeDictionaryLine(text, code, weight string) string {
	if weight == "" {
		return text + "\t" + code
	}
	return text + "\t" + code + "\t" + weight
}

func validateStage2BTrialConfig(config *Stage2BTrialConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.RecordsPath == "" || config.SchemaPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("all Stage 2B trial paths are required")
	}
	allowed, err := filepath.Abs(config.AllowedOutputRoot)
	if err != nil {
		return err
	}
	output, err := filepath.Abs(config.OutputDir)
	if err != nil {
		return err
	}
	relative, err := filepath.Rel(allowed, output)
	if err != nil || relative == "." || relative == "" || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("output must be strictly below the temporary root %s", allowed)
	}
	if filepath.Base(output) != "connected-speech-stage2b-rime" {
		return fmt.Errorf("Stage 2B output directory must be named connected-speech-stage2b-rime: %s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}
