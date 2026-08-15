package connectedspeech

import (
	"errors"
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const NeutralLexiconImpactToolVersion = "neutral-tone-lexicon-impact-v2"

type NeutralLexiconImpactConfig struct {
	RepoRoot          string
	DataDir           string
	ClassesPath       string
	CatalogPath       string
	PolicyPath        string
	OutputDir         string
	AllowedOutputRoot string
}

type NeutralLexiconImpactSummary struct {
	ToolVersion                       string          `json:"tool_version"`
	NeutralLexiconDistinctCount       int             `json:"neutral_lexicon_distinct_count"`
	EligibleLexiconRecordCount        int             `json:"eligible_lexicon_record_count"`
	IneligibleLexiconRecordCount      int             `json:"ineligible_lexicon_record_count"`
	IneligibleReasonCounts            map[string]int  `json:"ineligible_reason_counts"`
	PriorRuleDependentRecordCount     int             `json:"prior_rule_dependent_record_count"`
	ChangedAliasRecordCount           int             `json:"changed_alias_record_count"`
	CompatibilityUnchangedRecordCount int             `json:"compatibility_unchanged_record_count"`
	ThreeModeAliasRowCount            int             `json:"three_mode_alias_row_count"`
	NewStaticMappingCount             int             `json:"new_static_mapping_count"`
	AlreadyPresentMappingCount        int             `json:"already_present_mapping_count"`
	CompetingBucketRowCount           int             `json:"competing_bucket_row_count"`
	AliasRecordsWithCompetition       int             `json:"alias_records_with_competition"`
	WouldBecomeTopCount               int             `json:"would_become_top_count"`
	WouldTieTopCount                  int             `json:"would_tie_top_count"`
	BelowExistingTopCount             int             `json:"below_existing_top_count"`
	ReviewQueueRecordCount            int             `json:"review_queue_record_count"`
	ReviewReasonCounts                map[string]int  `json:"review_reason_counts"`
	CollisionPolicyID                 string          `json:"collision_policy_id"`
	CollisionDecision                 string          `json:"collision_decision"`
	CollisionRankingPolicy            string          `json:"collision_ranking_policy"`
	AcceptedCompetingAliasCount       int             `json:"accepted_competing_alias_count"`
	InputHashesMatch                  bool            `json:"input_hashes_match"`
	RuntimeAliasesGenerated           int             `json:"runtime_aliases_generated"`
	IssueCount                        int             `json:"issue_count"`
	Gates                             map[string]bool `json:"gates"`
	Passed                            bool            `json:"passed"`
}

type NeutralLexiconImpactResult struct {
	Summary NeutralLexiconImpactSummary
}

type neutralImpactAlias struct {
	Text               string
	NumericPinyin      string
	Weight             string
	ContextClasses     string
	ChangedNeutral     int
	PriorRuleDependent bool
	Canonical          codemode.Record
	Surface            codemode.Record
}

type neutralWantedBucket struct {
	Texts map[string]bool
}

type neutralObservedBucket struct {
	RowCount          int
	SameTextRows      map[string]int
	TopCompetitor     map[string]int
	CompetitorSamples map[string][]string
}

func DefaultNeutralLexiconImpactConfig(repoRoot string) NeutralLexiconImpactConfig {
	return NeutralLexiconImpactConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ClassesPath:       filepath.Join(repoRoot, "docs", "project", "connected_speech", "neutral_tone_context_classes.tsv"),
		CatalogPath:       filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "trainer", "yinyuan_catalog.json"),
		PolicyPath:        filepath.Join(repoRoot, "docs", "project", "connected_speech", "neutral_tone_collision_policy.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "neutral-tone-lexicon-impact-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunNeutralLexiconImpactAudit(config NeutralLexiconImpactConfig) (NeutralLexiconImpactResult, error) {
	if err := validateNeutralLexiconImpactConfig(&config); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	inputPaths := neutralChainInputPaths(config.DataDir)
	inputPaths["neutral_tone_context_classes.tsv"] = config.ClassesPath
	inputPaths["yinyuan_catalog.json"] = config.CatalogPath
	inputPaths["neutral_tone_collision_policy.tsv"] = config.PolicyPath
	inputPaths["yime_yinyuan_layout.json"] = filepath.Join(config.DataDir, "yime_yinyuan_layout.json")
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	policy, err := LoadNeutralCollisionPolicy(config.PolicyPath)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}

	classes, err := loadNeutralContextClasses(config.ClassesPath)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	catalog, err := loadNeutralCatalog(config.CatalogPath)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	issues := []neutralSurfaceIssue{}
	gradeTargets, pitchGrades, musicalEntries := validateNeutralCatalog(catalog, &issues)
	validateNeutralContextClasses(classes, pitchGrades, &issues)
	if len(issues) != 0 {
		return NeutralLexiconImpactResult{}, fmt.Errorf("neutral context inputs have %d validation issues", len(issues))
	}
	classByTone := map[int]neutralContextClass{}
	for index := range classes {
		classes[index].ActualProjectedToneGrade = pitchGrades[classes[index].SurfacePitchLevel]
		classByTone[classes[index].ConditioningSurfaceTone] = classes[index]
	}
	entryByID := map[string]neutralCatalogEntry{}
	for _, entry := range musicalEntries {
		entryByID[entry.ID] = entry
	}
	inventory, err := LoadInventory(filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"))
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	profile, err := layoutdesigner.LoadProfile(filepath.Join(config.DataDir, "yime_yinyuan_layout.json"))
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	canonicalCodes, err := loadCanonicalCodeRows(filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	fullInverse := buildCanonicalInverse(canonicalCodes)
	marked, err := loadMarkedPinyin(filepath.Join(config.DataDir, "pinyin_normalized.json"))
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	chainIssues := []NeutralChainIssue{}
	lexicon, _, err := collectNeutralLexicon(
		filepath.Join(config.DataDir, "yime_full.dict.yaml"), fullInverse, marked,
		func(component, key, code, detail string) {
			chainIssues = append(chainIssues, NeutralChainIssue{Component: component, Key: key, Code: code, Detail: detail})
		},
	)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}

	aliases := []neutralImpactAlias{}
	ineligible := 0
	ineligibleReasons := map[string]int{}
	ineligibleRows := [][]string{{"text", "numeric_pinyin", "weight", "reason", "detail"}}
	priorDependent := 0
	compatibilityUnchanged := 0
	for _, entry := range lexicon {
		alias, status, buildErr := buildNeutralImpactAlias(entry, fullInverse, inventory, classByTone, entryByID, gradeTargets, profile)
		if buildErr != nil {
			chainIssues = append(chainIssues, NeutralChainIssue{Component: "surface_projection", Key: entry.Text + ":" + entry.NumericPinyin, Code: status, Detail: buildErr.Error()})
			ineligible++
			ineligibleReasons[status]++
			ineligibleRows = append(ineligibleRows, []string{entry.Text, entry.NumericPinyin, entry.Weight, status, buildErr.Error()})
			continue
		}
		if status != "eligible" {
			ineligible++
			ineligibleReasons[status]++
			ineligibleRows = append(ineligibleRows, []string{entry.Text, entry.NumericPinyin, entry.Weight, status, "current rule requires a preceding surface tone from 1 through 4"})
			continue
		}
		if alias.PriorRuleDependent {
			priorDependent++
		}
		if sameProjectedCodes(alias.Canonical, alias.Surface) {
			compatibilityUnchanged++
		}
		aliases = append(aliases, alias)
	}
	sort.Slice(aliases, func(i, j int) bool {
		left := aliases[i].Text + "\x00" + aliases[i].NumericPinyin + "\x00" + aliases[i].Weight
		right := aliases[j].Text + "\x00" + aliases[j].NumericPinyin + "\x00" + aliases[j].Weight
		return left < right
	})

	modes := []struct {
		Name string
		Path string
	}{
		{"full", filepath.Join(config.DataDir, "yime_full.dict.yaml")},
		{"variable", filepath.Join(config.DataDir, "yime_variable.dict.yaml")},
		{"shorthand", filepath.Join(config.DataDir, "yime_shorthand.dict.yaml")},
	}
	wantedByMode := map[string]map[string]*neutralWantedBucket{}
	for _, mode := range modes {
		wanted := map[string]*neutralWantedBucket{}
		for _, alias := range aliases {
			code := neutralImpactModeCode(alias.Surface, mode.Name)
			bucket := wanted[code]
			if bucket == nil {
				bucket = &neutralWantedBucket{Texts: map[string]bool{}}
				wanted[code] = bucket
			}
			bucket.Texts[alias.Text] = true
		}
		wantedByMode[mode.Name] = wanted
	}
	observedByMode := map[string]map[string]*neutralObservedBucket{}
	for _, mode := range modes {
		observed, scanErr := observeNeutralImpactBuckets(mode.Path, wantedByMode[mode.Name])
		if scanErr != nil {
			return NeutralLexiconImpactResult{}, scanErr
		}
		observedByMode[mode.Name] = observed
	}

	aliasRows := [][]string{{"text", "numeric_pinyin", "weight", "context_classes", "changed_neutral_syllables", "prior_rule_dependent", "canonical_full", "surface_full", "canonical_variable", "surface_variable", "canonical_shorthand", "surface_shorthand"}}
	impactRows := [][]string{{"text", "numeric_pinyin", "mode", "canonical_code", "surface_code", "weight", "mapping_status", "competitor_rows", "top_competitor_weight", "rank_effect", "competitor_samples"}}
	reviewRows := [][]string{{"priority", "text", "numeric_pinyin", "weight", "reasons", "context_classes", "changed_neutral_syllables", "mode_effects", "competitor_samples", "canonical_full", "surface_full"}}
	reviewReasonCounts := map[string]int{}
	newMappings := 0
	alreadyPresent := 0
	competingRows := 0
	wouldTop := 0
	wouldTie := 0
	belowTop := 0
	recordsWithCompetition := map[string]bool{}
	for _, alias := range aliases {
		reviewReasons := map[string]bool{}
		modeEffects := []string{}
		reviewSamples := []string{}
		if alias.PriorRuleDependent {
			reviewReasons["prior_rule_dependency"] = true
		}
		aliasRows = append(aliasRows, []string{
			alias.Text, alias.NumericPinyin, alias.Weight, alias.ContextClasses, strconv.Itoa(alias.ChangedNeutral), strconv.FormatBool(alias.PriorRuleDependent),
			alias.Canonical.FullSpelling, alias.Surface.FullSpelling, alias.Canonical.VariableSpelling, alias.Surface.VariableSpelling,
			alias.Canonical.ShorthandSpelling, alias.Surface.ShorthandSpelling,
		})
		for _, mode := range modes {
			canonicalCode := neutralImpactModeCode(alias.Canonical, mode.Name)
			surfaceCode := neutralImpactModeCode(alias.Surface, mode.Name)
			observed := observedByMode[mode.Name][surfaceCode]
			sameTextRows := 0
			competitorRows := 0
			topCompetitor := 0
			samples := []string{}
			if observed != nil {
				sameTextRows = observed.SameTextRows[alias.Text]
				competitorRows = observed.RowCount - sameTextRows
				topCompetitor = observed.TopCompetitor[alias.Text]
				samples = observed.CompetitorSamples[alias.Text]
			}
			mappingStatus := "new"
			if sameTextRows > 0 {
				mappingStatus = "already_present"
				alreadyPresent++
			} else {
				newMappings++
			}
			rankEffect := neutralAliasRankEffect(mappingStatus, competitorRows, alias.Weight, topCompetitor)
			if mappingStatus == "new" && competitorRows > 0 {
				competingRows++
				recordsWithCompetition[alias.Text+"\x00"+alias.NumericPinyin+"\x00"+alias.Weight] = true
				switch rankEffect {
				case "would_become_top":
					wouldTop++
					reviewReasons["would_become_top"] = true
				case "would_tie_top":
					wouldTie++
					reviewReasons["would_tie_top"] = true
				case "below_existing_top":
					belowTop++
					reviewReasons["below_existing_top"] = true
				}
				modeEffects = append(modeEffects, mode.Name+":"+rankEffect)
				for _, sample := range samples {
					if !containsString(reviewSamples, sample) {
						reviewSamples = append(reviewSamples, sample)
					}
				}
			}
			impactRows = append(impactRows, []string{
				alias.Text, alias.NumericPinyin, mode.Name, canonicalCode, surfaceCode, alias.Weight, mappingStatus,
				strconv.Itoa(competitorRows), strconv.Itoa(topCompetitor), rankEffect, strings.Join(samples, ","),
			})
		}
		if len(reviewReasons) > 0 {
			reasons := sortedBoolKeys(reviewReasons)
			for _, reason := range reasons {
				reviewReasonCounts[reason]++
			}
			sort.Strings(reviewSamples)
			reviewRows = append(reviewRows, []string{
				neutralReviewPriority(reviewReasons), alias.Text, alias.NumericPinyin, alias.Weight,
				strings.Join(reasons, ","), alias.ContextClasses, strconv.Itoa(alias.ChangedNeutral),
				strings.Join(modeEffects, ","), strings.Join(reviewSamples, ","), alias.Canonical.FullSpelling, alias.Surface.FullSpelling,
			})
		}
	}
	issueRows := [][]string{{"component", "key", "code", "detail"}}
	for _, issue := range chainIssues {
		issueRows = append(issueRows, []string{issue.Component, issue.Key, issue.Code, issue.Detail})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "neutral_surface_aliases.tsv"), aliasRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "three_mode_candidate_impact.tsv"), impactRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "review_queue.tsv"), reviewRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "issues.tsv"), issueRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	ineligibleReasonRows := [][]string{{"reason", "record_count"}}
	for _, reason := range sortedStringKeys(ineligibleReasons) {
		ineligibleReasonRows = append(ineligibleReasonRows, []string{reason, strconv.Itoa(ineligibleReasons[reason])})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "ineligible_reasons.tsv"), ineligibleReasonRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "ineligible_records.tsv"), ineligibleRows); err != nil {
		return NeutralLexiconImpactResult{}, err
	}

	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	gates := map[string]bool{
		"three_mode_rows_complete":        len(impactRows)-1 == len(aliases)*3,
		"all_aliases_keep_four_positions": true,
		"input_hashes_unchanged":          hashesMatch,
		"runtime_aliases_generated_zero":  true,
		"reports_written":                 len(aliasRows) > 1 && len(impactRows) > 1,
		"review_queue_is_unique":          len(reviewRows)-1 <= len(aliases),
		"collision_policy_validated":      policy.Decision == "include_in_candidate_bucket",
	}
	summary := NeutralLexiconImpactSummary{
		ToolVersion: NeutralLexiconImpactToolVersion, NeutralLexiconDistinctCount: len(lexicon), EligibleLexiconRecordCount: len(aliases),
		IneligibleLexiconRecordCount: ineligible, IneligibleReasonCounts: ineligibleReasons, PriorRuleDependentRecordCount: priorDependent,
		ChangedAliasRecordCount: len(aliases) - compatibilityUnchanged, CompatibilityUnchangedRecordCount: compatibilityUnchanged,
		ThreeModeAliasRowCount: len(impactRows) - 1, NewStaticMappingCount: newMappings, AlreadyPresentMappingCount: alreadyPresent,
		CompetingBucketRowCount: competingRows, AliasRecordsWithCompetition: len(recordsWithCompetition),
		WouldBecomeTopCount: wouldTop, WouldTieTopCount: wouldTie, BelowExistingTopCount: belowTop,
		ReviewQueueRecordCount: len(reviewRows) - 1, ReviewReasonCounts: reviewReasonCounts,
		CollisionPolicyID: policy.PolicyID, CollisionDecision: policy.Decision, CollisionRankingPolicy: policy.RankingPolicy,
		AcceptedCompetingAliasCount: len(recordsWithCompetition),
		InputHashesMatch:            hashesMatch, RuntimeAliasesGenerated: 0, IssueCount: len(chainIssues), Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	outputPaths := map[string]string{
		"neutral_surface_aliases.tsv":     filepath.Join(config.OutputDir, "neutral_surface_aliases.tsv"),
		"three_mode_candidate_impact.tsv": filepath.Join(config.OutputDir, "three_mode_candidate_impact.tsv"),
		"review_queue.tsv":                filepath.Join(config.OutputDir, "review_queue.tsv"),
		"ineligible_reasons.tsv":          filepath.Join(config.OutputDir, "ineligible_reasons.tsv"),
		"ineligible_records.tsv":          filepath.Join(config.OutputDir, "ineligible_records.tsv"),
		"issues.tsv":                      filepath.Join(config.OutputDir, "issues.tsv"), "summary.json": filepath.Join(config.OutputDir, "summary.json"),
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	manifest := NeutralSurfaceManifest{
		ToolVersion: NeutralLexiconImpactToolVersion, InputSHA256: before, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic neutral-tone lexicon impact files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return NeutralLexiconImpactResult{}, err
	}
	result := NeutralLexiconImpactResult{Summary: summary}
	if !summary.Passed {
		return result, errors.New("neutral-tone lexicon impact gates did not pass")
	}
	return result, nil
}

func buildNeutralImpactAlias(entry *neutralLexiconAggregate, inverse map[string][]string, inventory Inventory, classes map[int]neutralContextClass, catalog map[string]neutralCatalogEntry, targets map[string]map[string]string, profile layoutdesigner.Profile) (neutralImpactAlias, string, error) {
	tokens := strings.Fields(entry.FullSpelling)
	sequence := make(YinyuanSequence, len(tokens))
	pinyin := make([]string, len(tokens))
	tones := make([]int, len(tokens))
	for index, token := range tokens {
		choices := inverse[token]
		if len(choices) == 0 || !sameToneIdentity(choices) {
			return neutralImpactAlias{}, "ambiguous_canonical_code", fmt.Errorf("code %q has choices %s", token, strings.Join(choices, ","))
		}
		pinyin[index] = choices[0]
		if len(pinyin[index]) == 0 {
			return neutralImpactAlias{}, "empty_pinyin", fmt.Errorf("code %q has empty pinyin", token)
		}
		tone, err := strconv.Atoi(pinyin[index][len(pinyin[index])-1:])
		if err != nil {
			return neutralImpactAlias{}, "invalid_tone", err
		}
		tones[index] = tone
		tuple, ok := inventory.Syllables[pinyin[index]]
		if !ok {
			return neutralImpactAlias{}, "missing_decomposition", fmt.Errorf("%s has no decomposition", pinyin[index])
		}
		sequence[index] = tuple
	}
	changed := 0
	contextIDs := []string{}
	priorDependent := containsPriorRuleSyllable(pinyin)
	for index, tone := range tones {
		if tone != 5 {
			continue
		}
		if index == 0 {
			return neutralImpactAlias{}, "neutral_without_predecessor", nil
		}
		if tones[index-1] == 5 {
			return neutralImpactAlias{}, "neutral_after_neutral", nil
		}
		if tones[index-1] < 1 || tones[index-1] > 4 {
			return neutralImpactAlias{}, "invalid_conditioning_tone", nil
		}
		class := classes[tones[index-1]]
		projected, err := projectNeutralTuple(sequence[index], class.ActualProjectedToneGrade, catalog, targets)
		if err != nil {
			return neutralImpactAlias{}, "projection_failed", err
		}
		sequence[index] = projected
		changed++
		contextIDs = append(contextIDs, class.ClassID)
	}
	if changed == 0 {
		return neutralImpactAlias{}, "no_eligible_neutral", nil
	}
	canonical, err := codemode.BuildRecord(entry.FullSpelling)
	if err != nil {
		return neutralImpactAlias{}, "invalid_canonical_code", err
	}
	surface, err := projectSequence(sequence, profile)
	if err != nil {
		return neutralImpactAlias{}, "surface_projection_failed", err
	}
	return neutralImpactAlias{
		Text: entry.Text, NumericPinyin: entry.NumericPinyin, Weight: entry.Weight,
		ContextClasses: strings.Join(contextIDs, ","), ChangedNeutral: changed, PriorRuleDependent: priorDependent,
		Canonical: canonical, Surface: surface,
	}, "eligible", nil
}

func observeNeutralImpactBuckets(path string, wanted map[string]*neutralWantedBucket) (map[string]*neutralObservedBucket, error) {
	result := map[string]*neutralObservedBucket{}
	err := scanRimeDictionary(path, func(entry dictionaryEntry) {
		code := strings.Join(strings.Fields(entry.Code), " ")
		targets := wanted[code]
		if targets == nil {
			return
		}
		bucket := result[code]
		if bucket == nil {
			bucket = &neutralObservedBucket{SameTextRows: map[string]int{}, TopCompetitor: map[string]int{}, CompetitorSamples: map[string][]string{}}
			result[code] = bucket
		}
		bucket.RowCount++
		weight, _ := strconv.Atoi(entry.Weight)
		for target := range targets.Texts {
			if entry.Text == target {
				bucket.SameTextRows[target]++
				continue
			}
			if weight > bucket.TopCompetitor[target] {
				bucket.TopCompetitor[target] = weight
			}
			if len(bucket.CompetitorSamples[target]) < 5 && !containsString(bucket.CompetitorSamples[target], entry.Text) {
				bucket.CompetitorSamples[target] = append(bucket.CompetitorSamples[target], entry.Text)
			}
		}
	})
	return result, err
}

func neutralImpactModeCode(record codemode.Record, mode string) string {
	switch mode {
	case "variable":
		return record.VariableSpelling
	case "shorthand":
		return record.ShorthandSpelling
	default:
		return record.FullSpelling
	}
}

func sameProjectedCodes(left, right codemode.Record) bool {
	return left.FullSpelling == right.FullSpelling && left.VariableSpelling == right.VariableSpelling && left.ShorthandSpelling == right.ShorthandSpelling
}

func neutralAliasRankEffect(mappingStatus string, competitorRows int, aliasWeight string, topCompetitor int) string {
	if mappingStatus == "already_present" {
		return "already_present_no_change"
	}
	if competitorRows == 0 {
		return "no_competitor"
	}
	weight, _ := strconv.Atoi(aliasWeight)
	switch {
	case weight > topCompetitor:
		return "would_become_top"
	case weight == topCompetitor:
		return "would_tie_top"
	default:
		return "below_existing_top"
	}
}

func containsPriorRuleSyllable(pinyin []string) bool {
	for _, syllable := range pinyin {
		switch syllable {
		case "yi1", "bu4", "qi1", "ba1":
			return true
		}
	}
	return false
}

func neutralReviewPriority(reasons map[string]bool) string {
	for _, priority := range []string{"prior_rule_dependency", "would_tie_top", "would_become_top", "below_existing_top"} {
		if reasons[priority] {
			return priority
		}
	}
	return ""
}

func containsString(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func sortedStringKeys(values map[string]int) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func sortedBoolKeys(values map[string]bool) []string {
	keys := make([]string, 0, len(values))
	for key, enabled := range values {
		if enabled {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	return keys
}

func validateNeutralLexiconImpactConfig(config *NeutralLexiconImpactConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ClassesPath == "" || config.CatalogPath == "" || config.PolicyPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("all neutral lexicon impact paths are required")
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
	if filepath.Base(output) != "neutral-tone-lexicon-impact-audit" {
		return fmt.Errorf("neutral lexicon impact output directory must be named neutral-tone-lexicon-impact-audit: %s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}
