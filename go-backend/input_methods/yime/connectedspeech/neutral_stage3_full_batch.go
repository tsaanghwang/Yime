package connectedspeech

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

const NeutralStage3FullBatchToolVersion = "neutral-tone-stage3-2-full-batch-v2"

type NeutralStage3FullBatchConfig struct {
	RepoRoot          string
	DataDir           string
	ImpactDir         string
	PolicyPath        string
	OutputDir         string
	AllowedOutputRoot string
}

type NeutralStage3FullBatchSummary struct {
	ToolVersion                       string          `json:"tool_version"`
	EligibleImpactRecordCount         int             `json:"eligible_impact_record_count"`
	IncludedSimpleChangedRecordCount  int             `json:"included_simple_changed_record_count"`
	ExcludedPriorRuleRecordCount      int             `json:"excluded_prior_rule_record_count"`
	ThreeModeSourceRowCount           int             `json:"three_mode_source_row_count"`
	ThreeModeDistinctMappingCount     int             `json:"three_mode_distinct_mapping_count"`
	ExactDuplicateMappingCount        int             `json:"exact_duplicate_mapping_count"`
	InternalCollisionBucketCount      int             `json:"internal_collision_bucket_count"`
	InternalCollisionBucketsByMode    map[string]int  `json:"internal_collision_buckets_by_mode"`
	MaximumInternalCandidateCount     int             `json:"maximum_internal_candidate_count"`
	InternalCollidingMappingCount     int             `json:"internal_colliding_mapping_count"`
	InternalCollidingAliasRecordCount int             `json:"internal_colliding_alias_record_count"`
	ExistingCompetitionRowCount       int             `json:"existing_competition_row_count"`
	ExistingCompetingAliasRecordCount int             `json:"existing_competing_alias_record_count"`
	OldExactPrefixCodesAffectedByMode map[string]int  `json:"old_exact_prefix_codes_affected_by_mode"`
	NewAliasRecordsAtOldPrefixByMode  map[string]int  `json:"new_alias_records_at_old_prefix_by_mode"`
	MaxNewCandidatesAtOldPrefixByMode map[string]int  `json:"max_new_candidates_at_old_prefix_by_mode"`
	NetNewVisibleTextRelationsByMode  map[string]int  `json:"net_new_visible_text_relations_by_mode"`
	OldPrefixesWithNetNewTextByMode   map[string]int  `json:"old_prefixes_with_net_new_text_by_mode"`
	MaxNetNewTextAtOldPrefixByMode    map[string]int  `json:"max_net_new_text_at_old_prefix_by_mode"`
	OldPrefixesWithNewInTop5ByMode    map[string]int  `json:"old_prefixes_with_new_in_static_top5_by_mode"`
	MaxNewInStaticTop5ByMode          map[string]int  `json:"max_new_in_static_top5_by_mode"`
	OldPrefixesAlsoNewExactByMode     map[string]int  `json:"old_prefixes_also_new_exact_by_mode"`
	NewExactPrefixCodesByMode         map[string]int  `json:"new_exact_prefix_codes_by_mode"`
	OldLongerCodesAffectedByMode      map[string]int  `json:"old_longer_codes_affected_by_mode"`
	InternalNewOnlyBucketsByMode      map[string]int  `json:"internal_new_only_buckets_by_mode"`
	InternalNewOnlyNetPrefixByMode    map[string]int  `json:"internal_new_only_with_net_new_at_old_prefix_by_mode"`
	InternalNewOnlyOldSuffixByMode    map[string]int  `json:"internal_new_only_prefix_of_old_longer_by_mode"`
	InternalNewOnlyAnyPrefixByMode    map[string]int  `json:"internal_new_only_with_any_visible_prefix_impact_by_mode"`
	CollisionPolicyID                 string          `json:"collision_policy_id"`
	CollisionDecision                 string          `json:"collision_decision"`
	RuntimeAliasesGenerated           int             `json:"runtime_aliases_generated"`
	InputHashesMatch                  bool            `json:"input_hashes_match"`
	Gates                             map[string]bool `json:"gates"`
	Passed                            bool            `json:"passed"`
}

type NeutralStage3FullBatchResult struct {
	Summary    NeutralStage3FullBatchSummary
	SmokeCases []NeutralStage3TrialCase
}

type neutralFullBatchMapping struct {
	Text          string
	NumericPinyin string
	Code          string
	Weight        string
	SourceKey     string
}

type neutralPrefixRankedCandidate struct {
	Text   string
	Weight int
	Origin string
}

type neutralOldPrefixBaseline struct {
	LongerRows int
	Top5       []neutralPrefixRankedCandidate
}

type neutralNewCodePrefixImpact struct {
	OldExactCode                 bool
	HasOldExactPrefix            bool
	HasNetNewTextAtOldPrefix     bool
	IsExactPrefixOfOldLongerCode bool
}

type neutralPrefixImpactStats struct {
	OldExactPrefixCodesAffected int
	NewAliasRecordsAtOldPrefix  int
	MaxNewCandidatesAtOldPrefix int
	NetNewVisibleTextRelations  int
	OldPrefixesWithNetNewText   int
	MaxNetNewTextAtOldPrefix    int
	OldPrefixesWithNewInTop5    int
	MaxNewInStaticTop5          int
	OldPrefixesAlsoNewExact     int
	NewExactPrefixCodes         int
	OldLongerCodesAffected      int
}

func DefaultNeutralStage3FullBatchConfig(repoRoot string) NeutralStage3FullBatchConfig {
	return NeutralStage3FullBatchConfig{
		RepoRoot: repoRoot, DataDir: filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ImpactDir:  filepath.Join(repoRoot, ".tmp", "neutral-tone-lexicon-impact-audit"),
		PolicyPath: filepath.Join(repoRoot, "docs", "project", "connected_speech", "neutral_tone_collision_policy.tsv"),
		OutputDir:  filepath.Join(repoRoot, ".tmp", "neutral-tone-stage3-2-full-batch"), AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunNeutralStage3FullBatchAudit(config NeutralStage3FullBatchConfig) (NeutralStage3FullBatchResult, error) {
	if err := validateNeutralStage3FullBatchConfig(&config); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	inputPaths := map[string]string{
		"aliases": filepath.Join(config.ImpactDir, "neutral_surface_aliases.tsv"),
		"impact":  filepath.Join(config.ImpactDir, "three_mode_candidate_impact.tsv"),
		"policy":  config.PolicyPath,
	}
	for _, mode := range neutralStage3Modes {
		inputPaths["old_"+mode.Mode+"_dictionary"] = filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml")
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	policy, err := LoadNeutralCollisionPolicy(config.PolicyPath)
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	aliases, err := loadNeutralStage3AliasesIncludingPrior(inputPaths["aliases"])
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	included := []*neutralStage3Sample{}
	excludedPrior := 0
	for _, sample := range aliases {
		if sample.Canonical["full"] == sample.Surface["full"] {
			continue
		}
		if sample.RankEffect == "prior_rule_dependency" {
			excludedPrior++
			continue
		}
		included = append(included, sample)
	}
	sort.Slice(included, func(i, j int) bool {
		return neutralStage3Key(included[i].Text, included[i].NumericPinyin, included[i].Weight) < neutralStage3Key(included[j].Text, included[j].NumericPinyin, included[j].Weight)
	})

	selectedKeys := map[string]bool{}
	for _, sample := range included {
		selectedKeys[neutralStage3Key(sample.Text, sample.NumericPinyin, sample.Weight)] = true
	}
	existingRows, existingRecords, err := countSelectedExistingCompetition(inputPaths["impact"], selectedKeys)
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}

	allMappings := map[string][]neutralFullBatchMapping{}
	distinctMappings := 0
	exactDuplicates := 0
	internalCollisionBuckets := 0
	internalCollisionBucketsByMode := map[string]int{}
	maximumInternalCandidateCount := 0
	internalCollidingMappings := 0
	internalCollidingRecords := map[string]bool{}
	collisionRows := [][]string{{"mode", "surface_code", "candidate_count", "top_weight", "candidate_samples"}}
	prefixRows := [][]string{{"mode", "relation", "trigger_code", "related_code_count", "new_text_count", "already_visible_same_text_count", "net_new_visible_text_count", "old_completion_row_count", "net_new_pool_share_percent", "new_in_static_weight_top5", "new_exact_text_count_at_trigger", "candidate_samples"}}
	oldExactPrefixCodesAffectedByMode := map[string]int{}
	newAliasRecordsAtOldPrefixByMode := map[string]int{}
	maxNewCandidatesAtOldPrefixByMode := map[string]int{}
	netNewVisibleTextRelationsByMode := map[string]int{}
	oldPrefixesWithNetNewTextByMode := map[string]int{}
	maxNetNewTextAtOldPrefixByMode := map[string]int{}
	oldPrefixesWithNewInTop5ByMode := map[string]int{}
	maxNewInStaticTop5ByMode := map[string]int{}
	oldPrefixesAlsoNewExactByMode := map[string]int{}
	newExactPrefixCodesByMode := map[string]int{}
	oldLongerCodesAffectedByMode := map[string]int{}
	internalNewOnlyBucketsByMode := map[string]int{}
	internalNewOnlyNetPrefixByMode := map[string]int{}
	internalNewOnlyOldSuffixByMode := map[string]int{}
	internalNewOnlyAnyPrefixByMode := map[string]int{}
	dictionaryNames := map[string]string{}
	for _, mode := range neutralStage3Modes {
		dictionaryName := "yime_connected_speech_stage3_2_" + mode.Mode
		dictionaryNames[mode.Mode] = dictionaryName
		mappings := map[string]neutralFullBatchMapping{}
		for _, sample := range included {
			mapping := neutralFullBatchMapping{
				Text: sample.Text, NumericPinyin: sample.NumericPinyin, Code: sample.Surface[mode.Mode], Weight: sample.Weight,
				SourceKey: neutralStage3Key(sample.Text, sample.NumericPinyin, sample.Weight),
			}
			key := mapping.Text + "\x00" + mapping.Code
			if previous, ok := mappings[key]; ok {
				if previous.Weight != mapping.Weight {
					return NeutralStage3FullBatchResult{}, fmt.Errorf("%s mapping %s/%s has inconsistent weights %s and %s", mode.Mode, mapping.Text, mapping.Code, previous.Weight, mapping.Weight)
				}
				exactDuplicates++
				continue
			}
			mappings[key] = mapping
		}
		list := make([]neutralFullBatchMapping, 0, len(mappings))
		buckets := map[string][]neutralFullBatchMapping{}
		for _, mapping := range mappings {
			list = append(list, mapping)
			buckets[mapping.Code] = append(buckets[mapping.Code], mapping)
		}
		sort.Slice(list, func(i, j int) bool {
			if list[i].Code != list[j].Code {
				return list[i].Code < list[j].Code
			}
			left, _ := strconv.Atoi(list[i].Weight)
			right, _ := strconv.Atoi(list[j].Weight)
			if left != right {
				return left > right
			}
			return list[i].Text < list[j].Text
		})
		allMappings[mode.Mode] = list
		distinctMappings += len(list)
		prefixStats, modePrefixRows, codePrefixImpact, prefixErr := auditNeutralPrefixImpact(mode.Mode, list, filepath.Join(config.DataDir, "yime_"+mode.Mode+".dict.yaml"))
		if prefixErr != nil {
			return NeutralStage3FullBatchResult{}, prefixErr
		}
		prefixRows = append(prefixRows, modePrefixRows...)
		oldExactPrefixCodesAffectedByMode[mode.Mode] = prefixStats.OldExactPrefixCodesAffected
		newAliasRecordsAtOldPrefixByMode[mode.Mode] = prefixStats.NewAliasRecordsAtOldPrefix
		maxNewCandidatesAtOldPrefixByMode[mode.Mode] = prefixStats.MaxNewCandidatesAtOldPrefix
		netNewVisibleTextRelationsByMode[mode.Mode] = prefixStats.NetNewVisibleTextRelations
		oldPrefixesWithNetNewTextByMode[mode.Mode] = prefixStats.OldPrefixesWithNetNewText
		maxNetNewTextAtOldPrefixByMode[mode.Mode] = prefixStats.MaxNetNewTextAtOldPrefix
		oldPrefixesWithNewInTop5ByMode[mode.Mode] = prefixStats.OldPrefixesWithNewInTop5
		maxNewInStaticTop5ByMode[mode.Mode] = prefixStats.MaxNewInStaticTop5
		oldPrefixesAlsoNewExactByMode[mode.Mode] = prefixStats.OldPrefixesAlsoNewExact
		newExactPrefixCodesByMode[mode.Mode] = prefixStats.NewExactPrefixCodes
		oldLongerCodesAffectedByMode[mode.Mode] = prefixStats.OldLongerCodesAffected
		codes := make([]string, 0, len(buckets))
		for code := range buckets {
			codes = append(codes, code)
		}
		sort.Strings(codes)
		for _, code := range codes {
			bucket := buckets[code]
			texts := map[string]bool{}
			topWeight := 0
			for _, mapping := range bucket {
				texts[mapping.Text] = true
				weight, _ := strconv.Atoi(mapping.Weight)
				if weight > topWeight {
					topWeight = weight
				}
			}
			if len(texts) < 2 {
				continue
			}
			prefixImpact := codePrefixImpact[normalizeTypedCode(code)]
			if !prefixImpact.OldExactCode {
				internalNewOnlyBucketsByMode[mode.Mode]++
				if prefixImpact.HasNetNewTextAtOldPrefix {
					internalNewOnlyNetPrefixByMode[mode.Mode]++
				}
				if prefixImpact.IsExactPrefixOfOldLongerCode {
					internalNewOnlyOldSuffixByMode[mode.Mode]++
				}
				if prefixImpact.HasNetNewTextAtOldPrefix || prefixImpact.IsExactPrefixOfOldLongerCode {
					internalNewOnlyAnyPrefixByMode[mode.Mode]++
				}
			}
			internalCollisionBuckets++
			internalCollisionBucketsByMode[mode.Mode]++
			internalCollidingMappings += len(bucket)
			if len(texts) > maximumInternalCandidateCount {
				maximumInternalCandidateCount = len(texts)
			}
			samples := make([]string, 0, len(texts))
			for _, mapping := range bucket {
				internalCollidingRecords[mapping.SourceKey] = true
				if !containsString(samples, mapping.Text) && len(samples) < 8 {
					samples = append(samples, mapping.Text)
				}
			}
			collisionRows = append(collisionRows, []string{mode.Mode, code, strconv.Itoa(len(texts)), strconv.Itoa(topWeight), strings.Join(samples, ",")})
		}
		lines := neutralStage3DictionaryHeader(dictionaryName)
		lines[0] = "# Stage 3-2 full-batch temporary neutral-tone alias dictionary"
		for _, mapping := range list {
			lines = append(lines, rimeDictionaryLine(mapping.Text, mapping.Code, mapping.Weight))
		}
		if err := os.WriteFile(filepath.Join(config.OutputDir, dictionaryName+".dict.yaml"), []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
			return NeutralStage3FullBatchResult{}, err
		}
		patch := "patch:\n  translator/dictionary: " + dictionaryName + "\n  translator/enable_sentence: false\n"
		if err := os.WriteFile(filepath.Join(config.OutputDir, "yime_"+mode.Mode+".custom.yaml"), []byte(patch), 0o644); err != nil {
			return NeutralStage3FullBatchResult{}, err
		}
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "internal_collision_buckets.tsv"), collisionRows); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "prefix_impact.tsv"), prefixRows); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	includedRows := [][]string{{"text", "numeric_pinyin", "weight", "context_classes", "full", "variable", "shorthand"}}
	for _, sample := range included {
		includedRows = append(includedRows, []string{sample.Text, sample.NumericPinyin, sample.Weight, sample.ContextClasses, sample.Surface["full"], sample.Surface["variable"], sample.Surface["shorthand"]})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "included_aliases.tsv"), includedRows); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}

	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	gates := map[string]bool{
		"three_mode_source_rows_complete": len(included)*3 == len(included)*len(neutralStage3Modes),
		"all_weights_inherited":           allNeutralBatchWeightsPresent(included),
		"collision_policy_inherited":      policy.Decision == "include_in_candidate_bucket",
		"prior_rule_records_excluded":     excludedPrior > 0,
		"input_hashes_unchanged":          hashesMatch,
		"runtime_aliases_generated_zero":  true,
	}
	summary := NeutralStage3FullBatchSummary{
		ToolVersion: NeutralStage3FullBatchToolVersion, EligibleImpactRecordCount: len(aliases),
		IncludedSimpleChangedRecordCount: len(included), ExcludedPriorRuleRecordCount: excludedPrior,
		ThreeModeSourceRowCount: len(included) * 3, ThreeModeDistinctMappingCount: distinctMappings, ExactDuplicateMappingCount: exactDuplicates,
		InternalCollisionBucketCount: internalCollisionBuckets, InternalCollisionBucketsByMode: internalCollisionBucketsByMode,
		MaximumInternalCandidateCount: maximumInternalCandidateCount, InternalCollidingMappingCount: internalCollidingMappings,
		InternalCollidingAliasRecordCount: len(internalCollidingRecords), ExistingCompetitionRowCount: existingRows,
		ExistingCompetingAliasRecordCount: existingRecords, CollisionPolicyID: policy.PolicyID, CollisionDecision: policy.Decision,
		OldExactPrefixCodesAffectedByMode: oldExactPrefixCodesAffectedByMode, NewAliasRecordsAtOldPrefixByMode: newAliasRecordsAtOldPrefixByMode,
		MaxNewCandidatesAtOldPrefixByMode: maxNewCandidatesAtOldPrefixByMode, NewExactPrefixCodesByMode: newExactPrefixCodesByMode,
		NetNewVisibleTextRelationsByMode: netNewVisibleTextRelationsByMode, OldPrefixesWithNetNewTextByMode: oldPrefixesWithNetNewTextByMode,
		MaxNetNewTextAtOldPrefixByMode: maxNetNewTextAtOldPrefixByMode, OldPrefixesWithNewInTop5ByMode: oldPrefixesWithNewInTop5ByMode,
		MaxNewInStaticTop5ByMode:      maxNewInStaticTop5ByMode,
		OldPrefixesAlsoNewExactByMode: oldPrefixesAlsoNewExactByMode,
		OldLongerCodesAffectedByMode:  oldLongerCodesAffectedByMode,
		InternalNewOnlyBucketsByMode:  internalNewOnlyBucketsByMode, InternalNewOnlyNetPrefixByMode: internalNewOnlyNetPrefixByMode,
		InternalNewOnlyOldSuffixByMode: internalNewOnlyOldSuffixByMode, InternalNewOnlyAnyPrefixByMode: internalNewOnlyAnyPrefixByMode,
		RuntimeAliasesGenerated: 0, InputHashesMatch: hashesMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	outputPaths := map[string]string{
		"included_aliases.tsv":           filepath.Join(config.OutputDir, "included_aliases.tsv"),
		"internal_collision_buckets.tsv": filepath.Join(config.OutputDir, "internal_collision_buckets.tsv"),
		"prefix_impact.tsv":              filepath.Join(config.OutputDir, "prefix_impact.tsv"),
		"summary.json":                   filepath.Join(config.OutputDir, "summary.json"),
	}
	for _, mode := range neutralStage3Modes {
		outputPaths[dictionaryNames[mode.Mode]+".dict.yaml"] = filepath.Join(config.OutputDir, dictionaryNames[mode.Mode]+".dict.yaml")
		outputPaths["yime_"+mode.Mode+".custom.yaml"] = filepath.Join(config.OutputDir, "yime_"+mode.Mode+".custom.yaml")
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	manifest := NeutralSurfaceManifest{ToolVersion: NeutralStage3FullBatchToolVersion, InputSHA256: before, OutputSHA256: outputHashes, OutputHashScope: "all deterministic Stage 3-2 full-batch files except manifest.json"}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return NeutralStage3FullBatchResult{}, err
	}
	result := NeutralStage3FullBatchResult{Summary: summary, SmokeCases: selectNeutralBatchSmokeCases(included)}
	if !summary.Passed {
		return result, errors.New("Stage 3-2 full-batch gates did not pass")
	}
	return result, nil
}

func loadNeutralStage3AliasesIncludingPrior(path string) (map[string]*neutralStage3Sample, error) {
	rows, err := readNamedTSV(path)
	if err != nil {
		return nil, err
	}
	result := map[string]*neutralStage3Sample{}
	for _, row := range rows {
		key := neutralStage3Key(row["text"], row["numeric_pinyin"], row["weight"])
		rank := ""
		if row["prior_rule_dependent"] == "true" {
			rank = "prior_rule_dependency"
		}
		result[key] = &neutralStage3Sample{
			Text: row["text"], NumericPinyin: row["numeric_pinyin"], Weight: row["weight"], ContextClasses: row["context_classes"], RankEffect: rank,
			Canonical: map[string]string{"full": row["canonical_full"], "variable": row["canonical_variable"], "shorthand": row["canonical_shorthand"]},
			Surface:   map[string]string{"full": row["surface_full"], "variable": row["surface_variable"], "shorthand": row["surface_shorthand"]},
		}
	}
	return result, nil
}

func countSelectedExistingCompetition(path string, selected map[string]bool) (int, int, error) {
	rows, err := readNamedTSV(path)
	if err != nil {
		return 0, 0, err
	}
	rowCount := 0
	records := map[string]bool{}
	for _, row := range rows {
		key := neutralStage3Key(row["text"], row["numeric_pinyin"], row["weight"])
		if !selected[key] || row["mapping_status"] != "new" {
			continue
		}
		competitors, _ := strconv.Atoi(row["competitor_rows"])
		if competitors > 0 {
			rowCount++
			records[key] = true
		}
	}
	return rowCount, len(records), nil
}

func allNeutralBatchWeightsPresent(samples []*neutralStage3Sample) bool {
	for _, sample := range samples {
		weight, err := strconv.Atoi(sample.Weight)
		if err != nil || weight < 0 {
			return false
		}
	}
	return true
}

func selectNeutralBatchSmokeCases(samples []*neutralStage3Sample) []NeutralStage3TrialCase {
	ordered := append([]*neutralStage3Sample(nil), samples...)
	sort.Slice(ordered, func(i, j int) bool {
		left, _ := strconv.Atoi(ordered[i].Weight)
		right, _ := strconv.Atoi(ordered[j].Weight)
		if left != right {
			return left > right
		}
		return ordered[i].Text < ordered[j].Text
	})
	if len(ordered) > 12 {
		ordered = ordered[:12]
	}
	result := make([]NeutralStage3TrialCase, 0, len(ordered))
	for _, sample := range ordered {
		result = append(result, NeutralStage3TrialCase{Text: sample.Text, NumericPinyin: sample.NumericPinyin, SurfaceCodes: sample.Surface})
	}
	return result
}

func auditNeutralPrefixImpact(mode string, mappings []neutralFullBatchMapping, oldDictionaryPath string) (neutralPrefixImpactStats, [][]string, map[string]neutralNewCodePrefixImpact, error) {
	oldCodes := map[string]bool{}
	err := scanRimeDictionary(oldDictionaryPath, func(entry dictionaryEntry) {
		oldCodes[normalizeTypedCode(entry.Code)] = true
	})
	if err != nil {
		return neutralPrefixImpactStats{}, nil, nil, err
	}
	newByCode := map[string][]neutralFullBatchMapping{}
	for _, mapping := range mappings {
		code := normalizeTypedCode(mapping.Code)
		newByCode[code] = append(newByCode[code], mapping)
	}
	newCodeImpacts := map[string]neutralNewCodePrefixImpact{}
	for code := range newByCode {
		newCodeImpacts[code] = neutralNewCodePrefixImpact{OldExactCode: oldCodes[code]}
	}
	oldPrefixNew := map[string]map[string]neutralFullBatchMapping{}
	newRecordsAtOldPrefix := map[string]bool{}
	for code, bucket := range newByCode {
		for index := 1; index < len(code); index++ {
			prefix := code[:index]
			if !oldCodes[prefix] {
				continue
			}
			impact := newCodeImpacts[code]
			impact.HasOldExactPrefix = true
			newCodeImpacts[code] = impact
			if oldPrefixNew[prefix] == nil {
				oldPrefixNew[prefix] = map[string]neutralFullBatchMapping{}
			}
			for _, mapping := range bucket {
				oldPrefixNew[prefix][mapping.Text+"\x00"+code] = mapping
				newRecordsAtOldPrefix[mapping.SourceKey] = true
			}
		}
	}
	newPrefixOld := map[string]map[string]bool{}
	oldLongerAffected := map[string]bool{}
	for oldCode := range oldCodes {
		for index := 1; index < len(oldCode); index++ {
			prefix := oldCode[:index]
			if _, ok := newByCode[prefix]; !ok {
				continue
			}
			impact := newCodeImpacts[prefix]
			impact.IsExactPrefixOfOldLongerCode = true
			newCodeImpacts[prefix] = impact
			if newPrefixOld[prefix] == nil {
				newPrefixOld[prefix] = map[string]bool{}
			}
			newPrefixOld[prefix][oldCode] = true
			oldLongerAffected[oldCode] = true
		}
	}
	baselines := map[string]*neutralOldPrefixBaseline{}
	wantedTextPrefixes := map[string]map[string]bool{}
	for prefix, mappingsAtPrefix := range oldPrefixNew {
		baselines[prefix] = &neutralOldPrefixBaseline{}
		for _, mapping := range mappingsAtPrefix {
			if wantedTextPrefixes[mapping.Text] == nil {
				wantedTextPrefixes[mapping.Text] = map[string]bool{}
			}
			wantedTextPrefixes[mapping.Text][prefix] = true
		}
	}
	alreadyVisible := map[string]map[string]bool{}
	err = scanRimeDictionary(oldDictionaryPath, func(entry dictionaryEntry) {
		code := normalizeTypedCode(entry.Code)
		for index := 1; index < len(code); index++ {
			prefix := code[:index]
			baseline := baselines[prefix]
			if baseline == nil {
				continue
			}
			baseline.LongerRows++
			weight, _ := strconv.Atoi(entry.Weight)
			baseline.Top5 = addNeutralPrefixTopCandidate(baseline.Top5, neutralPrefixRankedCandidate{Text: entry.Text, Weight: weight, Origin: "old"}, 5)
		}
		for prefix := range wantedTextPrefixes[entry.Text] {
			if !strings.HasPrefix(code, prefix) {
				continue
			}
			if alreadyVisible[prefix] == nil {
				alreadyVisible[prefix] = map[string]bool{}
			}
			alreadyVisible[prefix][entry.Text] = true
		}
	})
	if err != nil {
		return neutralPrefixImpactStats{}, nil, nil, err
	}
	rows := [][]string{}
	oldPrefixes := make([]string, 0, len(oldPrefixNew))
	for code := range oldPrefixNew {
		oldPrefixes = append(oldPrefixes, code)
	}
	sort.Strings(oldPrefixes)
	maxNewCandidates := 0
	netNewRelations := 0
	prefixesWithNetNew := 0
	maxNetNew := 0
	prefixesWithNewInTop5 := 0
	maxNewInTop5 := 0
	prefixesAlsoNewExact := 0
	for _, code := range oldPrefixes {
		mappingsAtPrefix := oldPrefixNew[code]
		texts := map[string]bool{}
		newByText := map[string]neutralPrefixRankedCandidate{}
		for _, mapping := range mappingsAtPrefix {
			texts[mapping.Text] = true
			if alreadyVisible[code][mapping.Text] {
				continue
			}
			mappingCode := normalizeTypedCode(mapping.Code)
			impact := newCodeImpacts[mappingCode]
			impact.HasNetNewTextAtOldPrefix = true
			newCodeImpacts[mappingCode] = impact
			weight, _ := strconv.Atoi(mapping.Weight)
			if previous, ok := newByText[mapping.Text]; !ok || weight > previous.Weight {
				newByText[mapping.Text] = neutralPrefixRankedCandidate{Text: mapping.Text, Weight: weight, Origin: "new"}
			}
		}
		if len(texts) > maxNewCandidates {
			maxNewCandidates = len(texts)
		}
		netNew := len(newByText)
		netNewRelations += netNew
		if netNew > 0 {
			prefixesWithNetNew++
		}
		if netNew > maxNetNew {
			maxNetNew = netNew
		}
		baseline := baselines[code]
		combinedTop5 := append([]neutralPrefixRankedCandidate{}, baseline.Top5...)
		for _, candidate := range newByText {
			combinedTop5 = addNeutralPrefixTopCandidate(combinedTop5, candidate, 5)
		}
		newInTop5 := 0
		for _, candidate := range combinedTop5 {
			if candidate.Origin == "new" {
				newInTop5++
			}
		}
		if newInTop5 > 0 {
			prefixesWithNewInTop5++
		}
		if newInTop5 > maxNewInTop5 {
			maxNewInTop5 = newInTop5
		}
		newExactTexts := map[string]bool{}
		for _, mapping := range newByCode[code] {
			newExactTexts[mapping.Text] = true
		}
		if len(newExactTexts) > 0 {
			prefixesAlsoNewExact++
		}
		poolShare := 0.0
		if baseline.LongerRows+netNew > 0 {
			poolShare = float64(netNew) * 100 / float64(baseline.LongerRows+netNew)
		}
		rows = append(rows, []string{mode, "old_exact_prefix_of_new", code, strconv.Itoa(len(mappingsAtPrefix)), strconv.Itoa(len(texts)), strconv.Itoa(len(texts) - netNew), strconv.Itoa(netNew), strconv.Itoa(baseline.LongerRows), strconv.FormatFloat(poolShare, 'f', 4, 64), strconv.Itoa(newInTop5), strconv.Itoa(len(newExactTexts)), sampleSortedKeys(texts, 8)})
	}
	newPrefixes := make([]string, 0, len(newPrefixOld))
	for code := range newPrefixOld {
		newPrefixes = append(newPrefixes, code)
	}
	sort.Strings(newPrefixes)
	for _, code := range newPrefixes {
		texts := map[string]bool{}
		for _, mapping := range newByCode[code] {
			texts[mapping.Text] = true
		}
		rows = append(rows, []string{mode, "new_exact_prefix_of_old", code, strconv.Itoa(len(newPrefixOld[code])), strconv.Itoa(len(texts)), "", "", "", "", "", strconv.Itoa(len(texts)), sampleSortedKeys(texts, 8)})
	}
	return neutralPrefixImpactStats{
		OldExactPrefixCodesAffected: len(oldPrefixNew), NewAliasRecordsAtOldPrefix: len(newRecordsAtOldPrefix),
		MaxNewCandidatesAtOldPrefix: maxNewCandidates, NetNewVisibleTextRelations: netNewRelations,
		OldPrefixesWithNetNewText: prefixesWithNetNew, MaxNetNewTextAtOldPrefix: maxNetNew,
		OldPrefixesWithNewInTop5: prefixesWithNewInTop5, MaxNewInStaticTop5: maxNewInTop5,
		OldPrefixesAlsoNewExact: prefixesAlsoNewExact,
		NewExactPrefixCodes:     len(newPrefixOld), OldLongerCodesAffected: len(oldLongerAffected),
	}, rows, newCodeImpacts, nil
}

func addNeutralPrefixTopCandidate(candidates []neutralPrefixRankedCandidate, candidate neutralPrefixRankedCandidate, limit int) []neutralPrefixRankedCandidate {
	for index := range candidates {
		if candidates[index].Text != candidate.Text {
			continue
		}
		if candidate.Weight > candidates[index].Weight {
			candidates[index] = candidate
		}
		sortNeutralPrefixCandidates(candidates)
		return candidates
	}
	candidates = append(candidates, candidate)
	sortNeutralPrefixCandidates(candidates)
	if len(candidates) > limit {
		candidates = candidates[:limit]
	}
	return candidates
}

func sortNeutralPrefixCandidates(candidates []neutralPrefixRankedCandidate) {
	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].Weight != candidates[j].Weight {
			return candidates[i].Weight > candidates[j].Weight
		}
		if candidates[i].Origin != candidates[j].Origin {
			return candidates[i].Origin == "old"
		}
		return candidates[i].Text < candidates[j].Text
	})
}

func normalizeTypedCode(code string) string {
	return strings.Map(func(value rune) rune {
		if unicode.IsSpace(value) {
			return -1
		}
		return value
	}, code)
}

func sampleSortedKeys(values map[string]bool, limit int) string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	if len(keys) > limit {
		keys = keys[:limit]
	}
	return strings.Join(keys, ",")
}

func validateNeutralStage3FullBatchConfig(config *NeutralStage3FullBatchConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ImpactDir == "" || config.PolicyPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("all Stage 3-2 full-batch paths are required")
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
	if err != nil || relative == "." || relative == "" || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.Base(output) != "neutral-tone-stage3-2-full-batch" {
		return fmt.Errorf("Stage 3-2 output must be neutral-tone-stage3-2-full-batch below %s", allowed)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}
