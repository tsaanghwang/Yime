package connectedspeech

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const NeutralStage3TrialToolVersion = "neutral-tone-stage3-1-rime-trial-v1"

type NeutralStage3TrialConfig struct {
	RepoRoot          string
	DataDir           string
	ImpactDir         string
	PolicyPath        string
	OutputDir         string
	AllowedOutputRoot string
	SamplesPerStratum int
}

type NeutralStage3TrialSummary struct {
	ToolVersion                string          `json:"tool_version"`
	SelectedAliasCount         int             `json:"selected_alias_count"`
	SelectionReasonCounts      map[string]int  `json:"selection_reason_counts"`
	ContextClassCounts         map[string]int  `json:"context_class_counts"`
	ThreeModeEntryCount        int             `json:"three_mode_entry_count"`
	ExistingBucketEntryCount   int             `json:"existing_bucket_entry_count"`
	DeferredConsecutiveNeutral int             `json:"deferred_consecutive_neutral"`
	CollisionPolicyID          string          `json:"collision_policy_id"`
	CollisionDecision          string          `json:"collision_decision"`
	RuntimeAliasesGenerated    int             `json:"runtime_aliases_generated"`
	InputHashesMatch           bool            `json:"input_hashes_match"`
	Gates                      map[string]bool `json:"gates"`
	Passed                     bool            `json:"passed"`
}

type NeutralStage3TrialResult struct {
	Summary NeutralStage3TrialSummary
	Cases   []NeutralStage3TrialCase
}

type NeutralStage3TrialCase struct {
	Text                string
	NumericPinyin       string
	CanonicalCodes      map[string]string
	SurfaceCodes        map[string]string
	ExpectedRankEffects map[string]string
}

type neutralStage3Sample struct {
	Text           string
	NumericPinyin  string
	Weight         string
	ContextClasses string
	Canonical      map[string]string
	Surface        map[string]string
	RankEffect     string
	ModeEffects    map[string]string
}

var neutralStage3Modes = []struct {
	Mode       string
	Dictionary string
	Baseline   string
	Patch      string
}{
	{"full", "yime_connected_speech_stage3_full.dict.yaml", "yime_connected_speech_stage3_baseline_full.dict.yaml", "yime_full.custom.yaml"},
	{"variable", "yime_connected_speech_stage3_variable.dict.yaml", "yime_connected_speech_stage3_baseline_variable.dict.yaml", "yime_variable.custom.yaml"},
	{"shorthand", "yime_connected_speech_stage3_shorthand.dict.yaml", "yime_connected_speech_stage3_baseline_shorthand.dict.yaml", "yime_shorthand.custom.yaml"},
}

func DefaultNeutralStage3TrialConfig(repoRoot string) NeutralStage3TrialConfig {
	return NeutralStage3TrialConfig{
		RepoRoot: repoRoot, DataDir: filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ImpactDir:  filepath.Join(repoRoot, ".tmp", "neutral-tone-lexicon-impact-audit"),
		PolicyPath: filepath.Join(repoRoot, "docs", "project", "connected_speech", "neutral_tone_collision_policy.tsv"),
		OutputDir:  filepath.Join(repoRoot, ".tmp", "neutral-tone-stage3-1-rime"), AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
		SamplesPerStratum: 2,
	}
}

func RunNeutralStage3RimeTrial(config NeutralStage3TrialConfig) (NeutralStage3TrialResult, error) {
	if err := validateNeutralStage3TrialConfig(&config); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	inputPaths := map[string]string{
		"aliases":    filepath.Join(config.ImpactDir, "neutral_surface_aliases.tsv"),
		"impact":     filepath.Join(config.ImpactDir, "three_mode_candidate_impact.tsv"),
		"ineligible": filepath.Join(config.ImpactDir, "ineligible_records.tsv"),
		"policy":     config.PolicyPath,
	}
	for _, mode := range neutralStage3Modes {
		inputPaths[mode.Mode+"_dictionary"] = filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml")
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}
	policy, err := LoadNeutralCollisionPolicy(config.PolicyPath)
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}

	aliases, err := loadNeutralStage3Aliases(inputPaths["aliases"])
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}
	if err := loadNeutralStage3Effects(inputPaths["impact"], aliases); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	selected := selectNeutralStage3Samples(aliases, config.SamplesPerStratum)
	if len(selected) == 0 {
		return NeutralStage3TrialResult{}, errors.New("Stage 3-1 sample selection produced no aliases")
	}

	selectionCounts := map[string]int{}
	contextCounts := map[string]int{}
	for _, sample := range selected {
		selectionCounts[sample.RankEffect]++
		for _, classID := range splitNonEmpty(sample.ContextClasses) {
			contextCounts[classID]++
		}
	}
	entryRows := [][]string{{"text", "numeric_pinyin", "weight", "context_classes", "selection_reason", "mode", "canonical_code", "surface_code", "expected_rank_effect"}}
	existingBucketEntries := 0
	for _, mode := range neutralStage3Modes {
		wanted := map[string]bool{}
		for _, sample := range selected {
			wanted[sample.Surface[mode.Mode]] = true
		}
		baseLines := map[string]bool{}
		err := scanRimeDictionary(filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml"), func(entry dictionaryEntry) {
			code := strings.Join(strings.Fields(entry.Code), " ")
			if wanted[code] {
				baseLines[rimeDictionaryLine(entry.Text, code, entry.Weight)] = true
			}
		})
		if err != nil {
			return NeutralStage3TrialResult{}, err
		}
		existingBucketEntries += len(baseLines)
		baselineLines := neutralStage3DictionaryHeader(strings.TrimSuffix(mode.Baseline, ".dict.yaml"))
		trialLines := neutralStage3DictionaryHeader(strings.TrimSuffix(mode.Dictionary, ".dict.yaml"))
		for _, line := range sortedBoolKeys(baseLines) {
			baselineLines = append(baselineLines, line)
			trialLines = append(trialLines, line)
		}
		for _, sample := range selected {
			canonicalLine := rimeDictionaryLine(sample.Text, sample.Canonical[mode.Mode], sample.Weight)
			aliasLine := rimeDictionaryLine(sample.Text, sample.Surface[mode.Mode], sample.Weight)
			baselineLines = appendUniqueLine(baselineLines, canonicalLine)
			trialLines = appendUniqueLine(trialLines, canonicalLine)
			trialLines = appendUniqueLine(trialLines, aliasLine)
			entryRows = append(entryRows, []string{
				sample.Text, sample.NumericPinyin, sample.Weight, sample.ContextClasses, sample.RankEffect, mode.Mode,
				sample.Canonical[mode.Mode], sample.Surface[mode.Mode], sample.ModeEffects[mode.Mode],
			})
		}
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.Dictionary), []byte(strings.Join(trialLines, "\n")+"\n"), 0o644); err != nil {
			return NeutralStage3TrialResult{}, err
		}
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.Baseline), []byte(strings.Join(baselineLines, "\n")+"\n"), 0o644); err != nil {
			return NeutralStage3TrialResult{}, err
		}
		patch := "patch:\n  translator/dictionary: " + strings.TrimSuffix(mode.Dictionary, ".dict.yaml") + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(config.OutputDir, mode.Patch), []byte(patch), 0o644); err != nil {
			return NeutralStage3TrialResult{}, err
		}
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "stage3_1_samples.tsv"), entryRows); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	deferredRows, err := filterTSVRows(inputPaths["ineligible"], "reason", "neutral_after_neutral")
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "deferred_consecutive_neutral.tsv"), deferredRows); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	gates := map[string]bool{
		"all_four_context_classes_sampled": len(contextCounts) == 4,
		"all_four_risk_strata_sampled":     len(selectionCounts) == 4,
		"three_mode_rows_complete":         len(entryRows)-1 == len(selected)*3,
		"consecutive_neutral_deferred":     len(deferredRows)-1 > 0,
		"input_hashes_unchanged":           hashesMatch,
		"runtime_aliases_generated_zero":   true,
		"collision_policy_inherited":       policy.Decision == "include_in_candidate_bucket",
	}
	summary := NeutralStage3TrialSummary{
		ToolVersion: NeutralStage3TrialToolVersion, SelectedAliasCount: len(selected), SelectionReasonCounts: selectionCounts,
		ContextClassCounts: contextCounts, ThreeModeEntryCount: len(entryRows) - 1, ExistingBucketEntryCount: existingBucketEntries,
		DeferredConsecutiveNeutral: len(deferredRows) - 1, CollisionPolicyID: policy.PolicyID, CollisionDecision: policy.Decision,
		RuntimeAliasesGenerated: 0, InputHashesMatch: hashesMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	outputPaths := map[string]string{
		"stage3_1_samples.tsv":             filepath.Join(config.OutputDir, "stage3_1_samples.tsv"),
		"deferred_consecutive_neutral.tsv": filepath.Join(config.OutputDir, "deferred_consecutive_neutral.tsv"),
		"summary.json":                     filepath.Join(config.OutputDir, "summary.json"),
	}
	for _, mode := range neutralStage3Modes {
		outputPaths[mode.Dictionary] = filepath.Join(config.OutputDir, mode.Dictionary)
		outputPaths[mode.Baseline] = filepath.Join(config.OutputDir, mode.Baseline)
		outputPaths[mode.Patch] = filepath.Join(config.OutputDir, mode.Patch)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return NeutralStage3TrialResult{}, err
	}
	manifest := NeutralSurfaceManifest{
		ToolVersion: NeutralStage3TrialToolVersion, InputSHA256: before, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic Stage 3-1 temporary Rime files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return NeutralStage3TrialResult{}, err
	}
	cases := make([]NeutralStage3TrialCase, 0, len(selected))
	for _, sample := range selected {
		cases = append(cases, NeutralStage3TrialCase{
			Text: sample.Text, NumericPinyin: sample.NumericPinyin,
			CanonicalCodes: sample.Canonical, SurfaceCodes: sample.Surface, ExpectedRankEffects: sample.ModeEffects,
		})
	}
	result := NeutralStage3TrialResult{Summary: summary, Cases: cases}
	if !summary.Passed {
		return result, errors.New("Stage 3-1 temporary Rime trial gates did not pass")
	}
	return result, nil
}

func loadNeutralStage3Aliases(path string) (map[string]*neutralStage3Sample, error) {
	rows, err := readNamedTSV(path)
	if err != nil {
		return nil, err
	}
	result := map[string]*neutralStage3Sample{}
	for _, row := range rows {
		if row["prior_rule_dependent"] == "true" || row["canonical_full"] == row["surface_full"] {
			continue
		}
		key := neutralStage3Key(row["text"], row["numeric_pinyin"], row["weight"])
		result[key] = &neutralStage3Sample{
			Text: row["text"], NumericPinyin: row["numeric_pinyin"], Weight: row["weight"], ContextClasses: row["context_classes"],
			Canonical:   map[string]string{"full": row["canonical_full"], "variable": row["canonical_variable"], "shorthand": row["canonical_shorthand"]},
			Surface:     map[string]string{"full": row["surface_full"], "variable": row["surface_variable"], "shorthand": row["surface_shorthand"]},
			ModeEffects: map[string]string{},
		}
	}
	return result, nil
}

func loadNeutralStage3Effects(path string, aliases map[string]*neutralStage3Sample) error {
	rows, err := readNamedTSV(path)
	if err != nil {
		return err
	}
	for _, row := range rows {
		if row["mapping_status"] != "new" {
			continue
		}
		key := neutralStage3Key(row["text"], row["numeric_pinyin"], row["weight"])
		sample := aliases[key]
		if sample == nil {
			continue
		}
		effect := row["rank_effect"]
		sample.ModeEffects[row["mode"]] = effect
		if sample.RankEffect == "" || neutralRankOrder(effect) < neutralRankOrder(sample.RankEffect) {
			sample.RankEffect = effect
		}
	}
	return nil
}

func selectNeutralStage3Samples(aliases map[string]*neutralStage3Sample, perStratum int) []*neutralStage3Sample {
	all := make([]*neutralStage3Sample, 0, len(aliases))
	for _, sample := range aliases {
		if sample.RankEffect != "" && len(sample.ModeEffects) == 3 {
			all = append(all, sample)
		}
	}
	sort.Slice(all, func(i, j int) bool {
		left, _ := strconv.Atoi(all[i].Weight)
		right, _ := strconv.Atoi(all[j].Weight)
		if left != right {
			return left > right
		}
		return neutralStage3Key(all[i].Text, all[i].NumericPinyin, all[i].Weight) < neutralStage3Key(all[j].Text, all[j].NumericPinyin, all[j].Weight)
	})
	selected := map[string]*neutralStage3Sample{}
	for _, stratum := range []string{"no_competitor", "would_tie_top", "would_become_top", "below_existing_top"} {
		count := 0
		for _, sample := range all {
			if sample.RankEffect == stratum && count < perStratum {
				selected[neutralStage3Key(sample.Text, sample.NumericPinyin, sample.Weight)] = sample
				count++
			}
		}
	}
	for _, classID := range []string{"after_t1_level2", "after_t2_level3", "after_t3_level4", "after_t4_level1"} {
		for _, sample := range all {
			if containsString(splitNonEmpty(sample.ContextClasses), classID) {
				selected[neutralStage3Key(sample.Text, sample.NumericPinyin, sample.Weight)] = sample
				break
			}
		}
	}
	result := make([]*neutralStage3Sample, 0, len(selected))
	for _, sample := range selected {
		result = append(result, sample)
	}
	sort.Slice(result, func(i, j int) bool {
		return neutralStage3Key(result[i].Text, result[i].NumericPinyin, result[i].Weight) < neutralStage3Key(result[j].Text, result[j].NumericPinyin, result[j].Weight)
	})
	return result
}

func neutralRankOrder(effect string) int {
	for index, value := range []string{"would_tie_top", "would_become_top", "below_existing_top", "no_competitor"} {
		if value == effect {
			return index
		}
	}
	return 99
}

func neutralStage3DictionaryHeader(name string) []string {
	return []string{"# Stage 3-1 temporary neutral-tone trial dictionary", "# GENERATED IN .tmp - DO NOT INSTALL", "---", "name: " + name, "version: \"stage3-1-v1\"", "sort: by_weight", "use_preset_vocabulary: false", "..."}
}

func neutralStage3Key(text, pinyin, weight string) string {
	return text + "\x00" + pinyin + "\x00" + weight
}

func splitNonEmpty(value string) []string {
	result := []string{}
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" && !containsString(result, item) {
			result = append(result, item)
		}
	}
	return result
}

func appendUniqueLine(lines []string, value string) []string {
	if containsString(lines, value) {
		return lines
	}
	return append(lines, value)
}

func readNamedTSV(path string) ([]map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil {
		return nil, err
	}
	result := []map[string]string{}
	for {
		fields, readErr := reader.Read()
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return nil, readErr
		}
		row := map[string]string{}
		for index, name := range header {
			if index < len(fields) {
				row[name] = fields[index]
			}
		}
		result = append(result, row)
	}
	return result, nil
}

func filterTSVRows(path, field, wanted string) ([][]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil {
		return nil, err
	}
	fieldIndex := -1
	for index, name := range header {
		if name == field {
			fieldIndex = index
		}
	}
	if fieldIndex < 0 {
		return nil, fmt.Errorf("%s has no %s column", path, field)
	}
	result := [][]string{header}
	for {
		row, readErr := reader.Read()
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return nil, readErr
		}
		if fieldIndex < len(row) && row[fieldIndex] == wanted {
			result = append(result, row)
		}
	}
	return result, nil
}

func validateNeutralStage3TrialConfig(config *NeutralStage3TrialConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ImpactDir == "" || config.PolicyPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" || config.SamplesPerStratum < 1 {
		return errors.New("all Stage 3-1 paths and a positive sample count are required")
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
	if err != nil || relative == "." || relative == "" || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.Base(output) != "neutral-tone-stage3-1-rime" {
		return fmt.Errorf("Stage 3-1 output must be neutral-tone-stage3-1-rime below %s", allowed)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}
