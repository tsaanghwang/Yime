package connectedspeech

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const ThirdToneStage5AToolVersion = "connected-speech-third-tone-stage5a-audit-v1"

type ThirdToneStage5AConfig struct {
	RepoRoot          string
	DataDir           string
	ScopePath         string
	CatalogPath       string
	OutputDir         string
	AllowedOutputRoot string
}

type ThirdToneStage5ASummary struct {
	ToolVersion                      string          `json:"tool_version"`
	ScopeClassCount                  int             `json:"scope_class_count"`
	LexiconRowCount                  int             `json:"lexicon_row_count"`
	DisyllabicDoubleThirdCount       int             `json:"disyllabic_double_third_count"`
	ProjectableCandidateCount        int             `json:"projectable_candidate_count"`
	SynthesizedSurfaceCandidateCount int             `json:"synthesized_surface_candidate_count"`
	BlockedLongerCandidateCount      int             `json:"blocked_longer_candidate_count"`
	AlreadyPresentThreeModeCount     int             `json:"already_present_three_mode_count"`
	PredictedCollisionMappingCount   int             `json:"predicted_collision_mapping_count"`
	LongerEntryWithPairCount         int             `json:"longer_entry_with_pair_count"`
	ThreePlusChainCount              int             `json:"three_plus_chain_count"`
	ThreeModeProjectionRowCount      int             `json:"three_mode_projection_row_count"`
	UnresolvedRowCount               int             `json:"unresolved_row_count"`
	RuntimeAliasesGenerated          int             `json:"runtime_aliases_generated"`
	InputHashesMatch                 bool            `json:"input_hashes_match"`
	Gates                            map[string]bool `json:"gates"`
	Passed                           bool            `json:"passed"`
}

type ThirdToneStage5AResult struct {
	Summary  ThirdToneStage5ASummary
	Manifest ThirdToneStage5AManifest
}

type ThirdToneStage5AManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type thirdToneScopeClass struct {
	ClassID            string
	CanonicalPattern   string
	SurfacePattern     string
	BoundaryEvidence   string
	AdjudicationStatus string
	RuntimeEligible    bool
	Note               string
}

type thirdToneCandidate struct {
	ID                       string
	Text                     string
	Weight                   string
	CanonicalPinyin          string
	SurfacePinyin            string
	Canonical                codemode.Record
	Surface                  codemode.Record
	BlockedByLength          bool
	AmbiguousSources         bool
	SurfaceInventoryAttested bool
}

type thirdToneModeObservation struct {
	CanonicalFoundWeight string
	SurfaceSameText      bool
	ExistingBucketRows   int
	ExistingCompetitors  int
	TopCompetitorWeight  int
	CompetitorSamples    []string
}

type thirdToneWantedMode struct {
	Canonical map[string][]string
	Surface   map[string]map[string][]string
}

func DefaultThirdToneStage5AConfig(repoRoot string) ThirdToneStage5AConfig {
	return ThirdToneStage5AConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ScopePath:         filepath.Join(repoRoot, "docs", "project", "connected_speech", "third_tone_sandhi_scope.tsv"),
		CatalogPath:       filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "trainer", "yinyuan_catalog.json"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "third-tone-stage5a-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunThirdToneStage5AAudit(config ThirdToneStage5AConfig) (ThirdToneStage5AResult, error) {
	if err := validateThirdToneStage5AConfig(&config); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	inputPaths := map[string]string{
		"scope":         config.ScopePath,
		"pinyin_codes":  filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
		"decomposition": filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"),
		"layout":        filepath.Join(config.DataDir, "yime_yinyuan_layout.json"),
		"catalog":       config.CatalogPath,
		"full_lexicon":  filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable":      filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand":     filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	scope, err := loadThirdToneScope(config.ScopePath)
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := validateThirdToneScope(scope); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	codes, err := loadCanonicalCodeRows(filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	inverse := buildCanonicalInverse(codes)
	inventory, err := LoadInventory(filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"))
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	profile, err := layoutdesigner.LoadProfile(filepath.Join(config.DataDir, "yime_yinyuan_layout.json"))
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	catalog, err := loadNeutralCatalog(config.CatalogPath)
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	catalogIssues := []neutralSurfaceIssue{}
	gradeTargets, _, musicalEntries := validateNeutralCatalog(catalog, &catalogIssues)
	if len(catalogIssues) != 0 {
		return ThirdToneStage5AResult{}, fmt.Errorf("音元目录存在 %d 个问题", len(catalogIssues))
	}
	catalogByID := map[string]neutralCatalogEntry{}
	for _, entry := range musicalEntries {
		catalogByID[entry.ID] = entry
	}

	candidates := []thirdToneCandidate{}
	unresolvedRows := [][]string{{"text", "full_code", "weight", "reason", "detail"}}
	longerRows := [][]string{{"text", "full_code", "weight", "tone_pattern", "classification"}}
	lexiconRows, longerPairs, chains := 0, 0, 0
	err = scanRimeDictionary(filepath.Join(config.DataDir, "yime_full.dict.yaml"), func(entry dictionaryEntry) {
		lexiconRows++
		parts := strings.Fields(entry.Code)
		tones, ok := thirdTonePattern(parts, inverse)
		if !ok {
			return
		}
		pair := containsAdjacentThirdTones(tones)
		chain := containsThirdToneRun(tones, 3)
		if len(parts) != 2 {
			if pair {
				longerPairs++
				classification := "pair_in_longer_deferred"
				if chain {
					chains++
					classification = "three_plus_chain_deferred"
				}
				longerRows = append(longerRows, []string{entry.Text, entry.Code, entry.Weight, joinTones(tones), classification})
			}
			return
		}
		if tones[0] != 3 || tones[1] != 3 {
			return
		}
		candidate, reason, buildErr := buildThirdToneCandidate(entry, len(candidates)+1, inverse, inventory, profile, catalogByID, gradeTargets)
		if buildErr != nil {
			unresolvedRows = append(unresolvedRows, []string{entry.Text, entry.Code, entry.Weight, reason, buildErr.Error()})
			return
		}
		candidates = append(candidates, candidate)
	})
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].Text+"\x00"+candidates[i].Canonical.FullSpelling < candidates[j].Text+"\x00"+candidates[j].Canonical.FullSpelling
	})
	for index := range candidates {
		candidates[index].ID = fmt.Sprintf("T3-5A-%05d", index+1)
	}

	modes := []struct{ Name, File string }{
		{"full", "yime_full.dict.yaml"},
		{"variable", "yime_variable.dict.yaml"},
		{"shorthand", "yime_shorthand.dict.yaml"},
	}
	observations := map[string]map[string]*thirdToneModeObservation{}
	wanted := map[string]thirdToneWantedMode{}
	for _, mode := range modes {
		modeWanted := thirdToneWantedMode{Canonical: map[string][]string{}, Surface: map[string]map[string][]string{}}
		for _, candidate := range candidates {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode.Name)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode.Name)
			modeWanted.Canonical[dictionaryKey(candidate.Text, canonicalCode)] = append(modeWanted.Canonical[dictionaryKey(candidate.Text, canonicalCode)], candidate.ID)
			if modeWanted.Surface[surfaceCode] == nil {
				modeWanted.Surface[surfaceCode] = map[string][]string{}
			}
			modeWanted.Surface[surfaceCode][candidate.Text] = append(modeWanted.Surface[surfaceCode][candidate.Text], candidate.ID)
			if observations[candidate.ID] == nil {
				observations[candidate.ID] = map[string]*thirdToneModeObservation{}
			}
			observations[candidate.ID][mode.Name] = &thirdToneModeObservation{}
		}
		wanted[mode.Name] = modeWanted
		if err := observeThirdToneMode(filepath.Join(config.DataDir, mode.File), mode.Name, modeWanted, observations); err != nil {
			return ThirdToneStage5AResult{}, err
		}
	}

	candidateRows := [][]string{{"record_id", "text", "canonical_pinyin", "surface_pinyin", "weight", "canonical_full", "surface_full", "source_code_ambiguous", "surface_syllable_attested_in_inventory", "length_policy", "adjudication_status"}}
	projectionRows := [][]string{{"record_id", "text", "mode", "canonical_code", "surface_code", "canonical_length", "surface_length", "length_delta", "canonical_weight_found", "canonical_weight_match", "surface_same_text_present", "existing_bucket_rows", "predicted_bucket_rows", "existing_competitors", "top_competitor_weight", "competitor_samples", "runtime_status"}}
	blockedLonger, synthesizedSurface, alreadyPresentAll, collisionMappings := 0, 0, 0, 0
	for _, candidate := range candidates {
		lengthPolicy := "not_longer_all_modes"
		if candidate.BlockedByLength {
			blockedLonger++
			lengthPolicy = "blocked_surface_longer"
		}
		if !candidate.SurfaceInventoryAttested {
			synthesizedSurface++
		}
		candidateRows = append(candidateRows, []string{candidate.ID, candidate.Text, candidate.CanonicalPinyin, candidate.SurfacePinyin, candidate.Weight, candidate.Canonical.FullSpelling, candidate.Surface.FullSpelling, strconv.FormatBool(candidate.AmbiguousSources), strconv.FormatBool(candidate.SurfaceInventoryAttested), lengthPolicy, "research_only"})
		allPresent := true
		for _, mode := range modes {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode.Name)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode.Name)
			observation := observations[candidate.ID][mode.Name]
			predictedRows := observation.ExistingBucketRows
			if !observation.SurfaceSameText {
				predictedRows++
			}
			if predictedRows > 1 {
				collisionMappings++
			}
			if !observation.SurfaceSameText {
				allPresent = false
			}
			runtimeStatus := "research_only_not_generated"
			if candidate.BlockedByLength {
				runtimeStatus = "blocked_surface_longer"
			}
			projectionRows = append(projectionRows, []string{
				candidate.ID, candidate.Text, mode.Name, canonicalCode, surfaceCode,
				strconv.Itoa(codeLength(canonicalCode)), strconv.Itoa(codeLength(surfaceCode)), strconv.Itoa(codeLength(surfaceCode) - codeLength(canonicalCode)),
				observation.CanonicalFoundWeight, strconv.FormatBool(observation.CanonicalFoundWeight == candidate.Weight), strconv.FormatBool(observation.SurfaceSameText),
				strconv.Itoa(observation.ExistingBucketRows), strconv.Itoa(predictedRows), strconv.Itoa(observation.ExistingCompetitors), strconv.Itoa(observation.TopCompetitorWeight),
				strings.Join(observation.CompetitorSamples, ","), runtimeStatus,
			})
		}
		if allPresent {
			alreadyPresentAll++
		}
	}

	if err := writeTSV(filepath.Join(config.OutputDir, "candidate_inventory.tsv"), candidateRows); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "three_mode_projection.tsv"), projectionRows); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "deferred_longer_sequences.tsv"), longerRows); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "unresolved.tsv"), unresolvedRows); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	allCanonicalWeightsMatch := true
	for _, candidate := range candidates {
		for _, mode := range modes {
			if observations[candidate.ID][mode.Name].CanonicalFoundWeight != candidate.Weight {
				allCanonicalWeightsMatch = false
			}
		}
	}
	gates := map[string]bool{
		"scope_policy_complete":               len(scope) == 3,
		"disyllabic_scope_only":               true,
		"longer_sequences_deferred":           true,
		"three_mode_projection_complete":      len(projectionRows)-1 == len(candidates)*3,
		"canonical_weights_match_all_modes":   allCanonicalWeightsMatch,
		"longer_aliases_not_runtime_eligible": true,
		"runtime_aliases_generated_zero":      true,
		"input_hashes_unchanged":              hashesMatch,
		"unresolved_projection_rows_zero":     len(unresolvedRows) == 1,
	}
	summary := ThirdToneStage5ASummary{
		ToolVersion: ThirdToneStage5AToolVersion, ScopeClassCount: len(scope), LexiconRowCount: lexiconRows,
		DisyllabicDoubleThirdCount: len(candidates) + len(unresolvedRows) - 1, ProjectableCandidateCount: len(candidates),
		SynthesizedSurfaceCandidateCount: synthesizedSurface,
		BlockedLongerCandidateCount:      blockedLonger, AlreadyPresentThreeModeCount: alreadyPresentAll,
		PredictedCollisionMappingCount: collisionMappings, LongerEntryWithPairCount: longerPairs, ThreePlusChainCount: chains,
		ThreeModeProjectionRowCount: len(projectionRows) - 1, UnresolvedRowCount: len(unresolvedRows) - 1,
		RuntimeAliasesGenerated: 0, InputHashesMatch: hashesMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	report := fmt.Sprintf(`# 阶段 5A 上声变调离线审计

- 核心词典行：%d
- 两音节双上声候选：%d（可投影 %d；未决 %d）
- 因任一模式增码而阻断：%d
- 三模式中均已存在表层路径：%d
- 预测进入已有或新增重码桶的模式映射：%d
- 长词中含双上声：%d；其中三上声及以上连续链：%d
- 运行时别名：0
- 输入哈希保持：%t
- 审计通过：%t

本报告只把直接两音节词典条目视为词界候选，不把词典收录自动解释为韵律域证据。三音节以上条目、连续三上声及所有缺少显式韵律分组的记录继续暂缓；未生成、未安装任何运行时别名。
`, lexiconRows, summary.DisyllabicDoubleThirdCount, len(candidates), summary.UnresolvedRowCount, blockedLonger, alreadyPresentAll, collisionMappings, longerPairs, chains, hashesMatch, summary.Passed)
	if err := os.WriteFile(filepath.Join(config.OutputDir, "REPORT.md"), []byte(report), 0o644); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	outputPaths := map[string]string{}
	for _, name := range []string{
		"candidate_inventory.tsv", "three_mode_projection.tsv", "deferred_longer_sequences.tsv", "unresolved.tsv",
		"input_hashes_before.json", "input_hashes_after.json", "summary.json", "REPORT.md",
	} {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ThirdToneStage5AResult{}, err
	}
	manifest := ThirdToneStage5AManifest{
		ToolVersion: ThirdToneStage5AToolVersion, InputSHA256: before, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic Stage 5A files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return ThirdToneStage5AResult{}, err
	}
	result := ThirdToneStage5AResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("阶段 5A 上声变调离线审计门禁未通过")
	}
	return result, nil
}

func buildThirdToneCandidate(entry dictionaryEntry, ordinal int, inverse map[string][]string, inventory Inventory, profile layoutdesigner.Profile, catalog map[string]neutralCatalogEntry, targets map[string]map[string]string) (thirdToneCandidate, string, error) {
	parts := strings.Fields(entry.Code)
	if len(parts) != 2 {
		return thirdToneCandidate{}, "not_disyllabic", errors.New("需要恰好两个音节")
	}
	canonicalSequence := make(YinyuanSequence, 2)
	surfaceSequence := make(YinyuanSequence, 2)
	canonicalLabels := make([]string, 2)
	surfaceLabels := make([]string, 2)
	ambiguous := false
	surfaceAttested := true
	for index, code := range parts {
		choices := inverse[code]
		if len(choices) == 0 || !sameToneIdentity(choices) || toneSuffix(choices[0]) != '3' {
			return thirdToneCandidate{}, "ambiguous_or_non_third_code", fmt.Errorf("%q -> %s", code, strings.Join(choices, ","))
		}
		if len(choices) > 1 {
			ambiguous = true
		}
		canonicalTuple, err := uniqueTupleForChoices(choices, inventory)
		if err != nil {
			return thirdToneCandidate{}, "ambiguous_canonical_tuple", err
		}
		canonicalSequence[index] = canonicalTuple
		surfaceSequence[index] = canonicalTuple
		canonicalLabels[index] = pinyinChoiceLabel(choices)
		surfaceLabels[index] = canonicalLabels[index]
		if index == 0 {
			surfaceChoices := make([]string, 0, len(choices))
			for _, choice := range choices {
				surfaceChoices = append(surfaceChoices, replaceToneSuffix(choice, '2'))
			}
			surfaceTuple, err := projectThirdToneTupleToSecond(canonicalTuple, catalog, targets)
			if err != nil {
				return thirdToneCandidate{}, "surface_tuple_derivation_failed", err
			}
			for _, choice := range surfaceChoices {
				attested, ok := inventory.Syllables[choice]
				if !ok {
					surfaceAttested = false
					continue
				}
				if attested != surfaceTuple {
					return thirdToneCandidate{}, "surface_tuple_mismatch", fmt.Errorf("%s 的既有四音元与条件调值派生不一致", choice)
				}
			}
			surfaceSequence[index] = surfaceTuple
			surfaceLabels[index] = pinyinChoiceLabel(surfaceChoices)
		}
	}
	canonical, err := projectSequence(canonicalSequence, profile)
	if err != nil {
		return thirdToneCandidate{}, "canonical_projection_failed", err
	}
	if canonical.FullSpelling != strings.Join(parts, " ") {
		return thirdToneCandidate{}, "canonical_projection_mismatch", fmt.Errorf("%q != %q", canonical.FullSpelling, entry.Code)
	}
	surface, err := projectSequence(surfaceSequence, profile)
	if err != nil {
		return thirdToneCandidate{}, "surface_projection_failed", err
	}
	if !modeLengthProjectionValid(canonical, surface) {
		return thirdToneCandidate{}, "invalid_mode_projection", errors.New("三模式逐音节码长不满足 2..4")
	}
	blocked := codeLength(surface.FullSpelling) > codeLength(canonical.FullSpelling) ||
		codeLength(surface.VariableSpelling) > codeLength(canonical.VariableSpelling) ||
		codeLength(surface.ShorthandSpelling) > codeLength(canonical.ShorthandSpelling)
	return thirdToneCandidate{
		ID: fmt.Sprintf("T3-5A-%05d", ordinal), Text: entry.Text, Weight: entry.Weight,
		CanonicalPinyin: strings.Join(canonicalLabels, " "), SurfacePinyin: strings.Join(surfaceLabels, " "),
		Canonical: canonical, Surface: surface, BlockedByLength: blocked, AmbiguousSources: ambiguous, SurfaceInventoryAttested: surfaceAttested,
	}, "eligible", nil
}

func observeThirdToneMode(path, mode string, wanted thirdToneWantedMode, observations map[string]map[string]*thirdToneModeObservation) error {
	return scanRimeDictionary(path, func(entry dictionaryEntry) {
		code := strings.Join(strings.Fields(entry.Code), " ")
		for _, id := range wanted.Canonical[dictionaryKey(entry.Text, code)] {
			observations[id][mode].CanonicalFoundWeight = entry.Weight
		}
		texts := wanted.Surface[code]
		if texts == nil {
			return
		}
		weight, _ := strconv.Atoi(entry.Weight)
		for target, ids := range texts {
			for _, id := range ids {
				observation := observations[id][mode]
				observation.ExistingBucketRows++
				if entry.Text == target {
					observation.SurfaceSameText = true
					continue
				}
				observation.ExistingCompetitors++
				if weight > observation.TopCompetitorWeight {
					observation.TopCompetitorWeight = weight
				}
				if len(observation.CompetitorSamples) < 5 && !containsString(observation.CompetitorSamples, entry.Text) {
					observation.CompetitorSamples = append(observation.CompetitorSamples, entry.Text)
				}
			}
		}
	})
}

func loadThirdToneScope(path string) ([]thirdToneScopeClass, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	result := []thirdToneScopeClass{}
	line := 0
	for scanner.Scan() {
		line++
		text := strings.TrimSuffix(scanner.Text(), "\r")
		if line == 1 {
			if text != "class_id\tcanonical_pattern\tsurface_pattern\tboundary_evidence\tadjudication_status\truntime_eligible\tnote" {
				return nil, fmt.Errorf("%s: unexpected header", path)
			}
			continue
		}
		if strings.TrimSpace(text) == "" || strings.HasPrefix(strings.TrimSpace(text), "#") {
			continue
		}
		fields := strings.Split(text, "\t")
		if len(fields) != 7 {
			return nil, fmt.Errorf("%s:%d: expected 7 fields, got %d", path, line, len(fields))
		}
		runtimeEligible, err := strconv.ParseBool(fields[5])
		if err != nil {
			return nil, fmt.Errorf("%s:%d: invalid runtime_eligible", path, line)
		}
		result = append(result, thirdToneScopeClass{fields[0], fields[1], fields[2], fields[3], fields[4], runtimeEligible, fields[6]})
	}
	return result, scanner.Err()
}

func validateThirdToneScope(scope []thirdToneScopeClass) error {
	want := map[string]string{
		"T3-DISYLLABLE-LEXICON": "research_only",
		"T3-PAIR-IN-LONGER":     "deferred",
		"T3-CHAIN-THREE-PLUS":   "deferred",
	}
	seen := map[string]bool{}
	for _, class := range scope {
		if seen[class.ClassID] || want[class.ClassID] == "" {
			return fmt.Errorf("无效或重复的上声范围类别 %q", class.ClassID)
		}
		seen[class.ClassID] = true
		if class.AdjudicationStatus != want[class.ClassID] || class.RuntimeEligible || class.BoundaryEvidence == "" || class.Note == "" {
			return fmt.Errorf("上声范围类别 %q 违反只离线边界", class.ClassID)
		}
	}
	if len(seen) != len(want) {
		return fmt.Errorf("上声范围类别不完整：got %d want %d", len(seen), len(want))
	}
	return nil
}

func validateThirdToneStage5AConfig(config *ThirdToneStage5AConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ScopePath == "" || config.CatalogPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("阶段 5A 所有路径均不能为空")
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
		return fmt.Errorf("阶段 5A 输出必须严格位于临时目录 %s 内", allowed)
	}
	if filepath.Base(output) != "third-tone-stage5a-audit" {
		return fmt.Errorf("阶段 5A 输出目录必须名为 third-tone-stage5a-audit：%s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}

func thirdTonePattern(parts []string, inverse map[string][]string) ([]int, bool) {
	result := make([]int, len(parts))
	for index, code := range parts {
		choices := inverse[code]
		if len(choices) == 0 || !sameToneIdentity(choices) {
			return nil, false
		}
		result[index] = int(toneSuffix(choices[0]) - '0')
	}
	return result, true
}

func uniqueTupleForChoices(choices []string, inventory Inventory) (YinyuanTuple, error) {
	var result YinyuanTuple
	set := false
	for _, choice := range choices {
		tuple, ok := inventory.Syllables[choice]
		if !ok {
			return YinyuanTuple{}, fmt.Errorf("音节 %s 缺少四音元分解", choice)
		}
		if !set {
			result, set = tuple, true
			continue
		}
		if result != tuple {
			return YinyuanTuple{}, fmt.Errorf("同码来源不能归入唯一四音元：%s", strings.Join(choices, ","))
		}
	}
	if !set {
		return YinyuanTuple{}, errors.New("音节选择为空")
	}
	return result, nil
}

func projectThirdToneTupleToSecond(tuple YinyuanTuple, catalog map[string]neutralCatalogEntry, targets map[string]map[string]string) (YinyuanTuple, error) {
	result := tuple
	for index, grade := range []string{"low", "mid", "high"} {
		position := index + 1
		entry, ok := catalog[tuple[position]]
		if !ok {
			return YinyuanTuple{}, fmt.Errorf("未知乐音音元 %s", tuple[position])
		}
		target := targets[entry.QualityGroup][grade]
		if target == "" {
			return YinyuanTuple{}, fmt.Errorf("音质组 %s 缺少 %s 调级", entry.QualityGroup, grade)
		}
		result[position] = target
	}
	return result, nil
}

func containsAdjacentThirdTones(tones []int) bool {
	for index := 1; index < len(tones); index++ {
		if tones[index-1] == 3 && tones[index] == 3 {
			return true
		}
	}
	return false
}

func containsThirdToneRun(tones []int, minimum int) bool {
	run := 0
	for _, tone := range tones {
		if tone == 3 {
			run++
			if run >= minimum {
				return true
			}
		} else {
			run = 0
		}
	}
	return false
}

func joinTones(tones []int) string {
	parts := make([]string, len(tones))
	for index, tone := range tones {
		parts[index] = strconv.Itoa(tone)
	}
	return strings.Join(parts, " ")
}

func replaceToneSuffix(pinyin string, tone byte) string {
	pinyin = canonicalNumericPinyin(pinyin)
	if pinyin == "" || toneSuffix(pinyin) == 0 {
		return pinyin
	}
	return pinyin[:len(pinyin)-1] + string(tone)
}

func pinyinChoiceLabel(choices []string) string {
	if len(choices) == 1 {
		return choices[0]
	}
	return "{" + strings.Join(choices, "|") + "}"
}

func thirdToneModeCode(record codemode.Record, mode string) string {
	switch mode {
	case "variable":
		return record.VariableSpelling
	case "shorthand":
		return record.ShorthandSpelling
	default:
		return record.FullSpelling
	}
}
