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

const ParticleAStage6BToolVersion = "connected-speech-particle-a-stage6b-projection-v2"

type ParticleAStage6BConfig struct {
	RepoRoot          string
	DataDir           string
	ScopePath         string
	ProjectionPath    string
	OutputDir         string
	AllowedOutputRoot string
}

type ParticleAStage6BSummary struct {
	ToolVersion               string          `json:"tool_version"`
	ProjectionClassCount      int             `json:"projection_class_count"`
	ExplicitParticleACount    int             `json:"explicit_particle_a_count"`
	ProjectableCandidateCount int             `json:"projectable_candidate_count"`
	BlockedLongerCount        int             `json:"blocked_longer_count"`
	ThreeModeProjectionRows   int             `json:"three_mode_projection_rows"`
	CollisionMappings         int             `json:"collision_mappings"`
	AlreadyPresentAllModes    int             `json:"already_present_all_modes"`
	UnresolvedCount           int             `json:"unresolved_count"`
	RuntimeAliasesGenerated   int             `json:"runtime_aliases_generated"`
	ClassCounts               map[string]int  `json:"class_counts"`
	BlockedLongerByClass      map[string]int  `json:"blocked_longer_by_class"`
	InputHashesMatch          bool            `json:"input_hashes_match"`
	Gates                     map[string]bool `json:"gates"`
	Passed                    bool            `json:"passed"`
}

type ParticleAStage6BManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type ParticleAStage6BResult struct {
	Summary  ParticleAStage6BSummary
	Manifest ParticleAStage6BManifest
}

type particleAProjectionClass struct {
	ClassID            string
	SurfacePinyin      string
	TupleStrategy      string
	TargetShouyinID    string
	SourceScope        string
	AdjudicationStatus string
	RuntimeEligible    bool
	Note               string
}

type particleAStage6BCandidate struct {
	ID              string
	Text            string
	CanonicalPinyin string
	SurfacePinyin   string
	ClassID         string
	TargetShouyinID string
	TargetTuple     YinyuanTuple
	Weight          string
	Canonical       codemode.Record
	Surface         codemode.Record
	BlockedByLength bool
}

type particleAStage6BObservation struct {
	CanonicalWeight  string
	SurfaceSameText  bool
	ExistingRows     int
	ExistingRivals   int
	TopRivalWeight   int
	CompetitorSample []string
}

func DefaultParticleAStage6BConfig(repoRoot string) ParticleAStage6BConfig {
	return ParticleAStage6BConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ScopePath:         filepath.Join(repoRoot, "docs", "project", "connected_speech", "particle_a_stage6a_scope.tsv"),
		ProjectionPath:    filepath.Join(repoRoot, "docs", "project", "connected_speech", "particle_a_stage6b_projection.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "particle-a-stage6b-projection"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunParticleAStage6BProjection(config ParticleAStage6BConfig) (ParticleAStage6BResult, error) {
	if err := validateParticleAStage6BConfig(&config); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ParticleAStage6BResult{}, err
	}
	inputPaths := map[string]string{
		"scope": config.ScopePath, "projection_policy": config.ProjectionPath,
		"pinyin_codes":  filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
		"decomposition": filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"),
		"layout":        filepath.Join(config.DataDir, "yime_yinyuan_layout.json"),
		"full":          filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable":      filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand":     filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	scope, err := loadParticleAScope(config.ScopePath)
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := validateParticleAScope(scope); err != nil {
		return ParticleAStage6BResult{}, err
	}
	policy, err := loadParticleAStage6BPolicy(config.ProjectionPath)
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := validateParticleAStage6BPolicy(policy); err != nil {
		return ParticleAStage6BResult{}, err
	}
	policyByClass := map[string]particleAProjectionClass{}
	for _, item := range policy {
		policyByClass[item.ClassID] = item
	}
	codes, err := loadCanonicalCodeRows(inputPaths["pinyin_codes"])
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	inverse := buildCanonicalInverse(codes)
	inventory, err := LoadInventory(inputPaths["decomposition"])
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	decomposition, err := loadParticleADecomposition(inputPaths["decomposition"])
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	profile, err := layoutdesigner.LoadProfile(inputPaths["layout"])
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	a5Code := strings.TrimSpace(codes["a5"])
	if a5Code == "" {
		return ParticleAStage6BResult{}, errors.New("规范码表缺少 a5")
	}

	candidates := []particleAStage6BCandidate{}
	unresolved := [][]string{{"text", "full_code", "weight", "reason", "detail"}}
	err = scanRimeDictionary(inputPaths["full"], func(entry dictionaryEntry) {
		parts := strings.Fields(entry.Code)
		if !strings.HasSuffix(entry.Text, "啊") || len(parts) < 2 || parts[len(parts)-1] != a5Code {
			return
		}
		sequence := make(YinyuanSequence, len(parts))
		pinyinParts := make([]string, len(parts))
		for index, code := range parts {
			choices := inverse[code]
			if len(choices) == 0 || !sameToneIdentity(choices) {
				unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "ambiguous_or_unknown_code", code + "=" + strings.Join(choices, "|")})
				return
			}
			tuple, tupleErr := uniqueTupleForChoices(choices, inventory)
			if tupleErr != nil {
				unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "ambiguous_tuple", tupleErr.Error()})
				return
			}
			sequence[index] = tuple
			pinyinParts[index] = pinyinChoiceLabel(choices)
		}
		previousChoices := inverse[parts[len(parts)-2]]
		classID, _, classErr := classifyParticleAPrevious(previousChoices, decomposition)
		if classErr != nil {
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "previous_final_unresolved", classErr.Error()})
			return
		}
		class := policyByClass[classID]
		target, targetErr := particleAStage6BTargetTuple(class, inventory)
		if targetErr != nil {
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "target_tuple_unresolved", targetErr.Error()})
			return
		}
		canonical, projectErr := projectSequence(sequence, profile)
		if projectErr != nil || canonical.FullSpelling != strings.Join(parts, " ") {
			detail := fmt.Sprintf("project=%v got=%q want=%q", projectErr, canonical.FullSpelling, strings.Join(parts, " "))
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "canonical_projection_mismatch", detail})
			return
		}
		surfaceSequence := append(YinyuanSequence(nil), sequence...)
		surfaceSequence[len(surfaceSequence)-1] = target
		surface, projectErr := projectSequence(surfaceSequence, profile)
		if projectErr != nil || !modeLengthProjectionValid(canonical, surface) {
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "surface_projection_invalid", fmt.Sprint(projectErr)})
			return
		}
		blocked := codeLength(surface.FullSpelling) > codeLength(canonical.FullSpelling) ||
			codeLength(surface.VariableSpelling) > codeLength(canonical.VariableSpelling) ||
			codeLength(surface.ShorthandSpelling) > codeLength(canonical.ShorthandSpelling)
		surfacePinyinParts := append([]string(nil), pinyinParts...)
		surfacePinyinParts[len(surfacePinyinParts)-1] = class.SurfacePinyin
		candidates = append(candidates, particleAStage6BCandidate{
			Text: entry.Text, CanonicalPinyin: strings.Join(pinyinParts, " "), SurfacePinyin: strings.Join(surfacePinyinParts, " "),
			ClassID: classID, TargetShouyinID: class.TargetShouyinID, TargetTuple: target, Weight: entry.Weight,
			Canonical: canonical, Surface: surface, BlockedByLength: blocked,
		})
	})
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].ClassID+"\x00"+candidates[i].Text+"\x00"+candidates[i].Canonical.FullSpelling < candidates[j].ClassID+"\x00"+candidates[j].Text+"\x00"+candidates[j].Canonical.FullSpelling
	})
	for index := range candidates {
		candidates[index].ID = fmt.Sprintf("PA-6B-%05d", index+1)
	}

	modes := []struct{ Name, File string }{{"full", "full"}, {"variable", "variable"}, {"shorthand", "shorthand"}}
	observations := map[string]map[string]*particleAStage6BObservation{}
	canonicalWanted := map[string]map[string][]string{}
	surfaceWanted := map[string]map[string]map[string][]string{}
	for _, mode := range modes {
		canonicalWanted[mode.Name] = map[string][]string{}
		surfaceWanted[mode.Name] = map[string]map[string][]string{}
		for _, candidate := range candidates {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode.Name)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode.Name)
			canonicalWanted[mode.Name][dictionaryKey(candidate.Text, canonicalCode)] = append(canonicalWanted[mode.Name][dictionaryKey(candidate.Text, canonicalCode)], candidate.ID)
			if surfaceWanted[mode.Name][surfaceCode] == nil {
				surfaceWanted[mode.Name][surfaceCode] = map[string][]string{}
			}
			surfaceWanted[mode.Name][surfaceCode][candidate.Text] = append(surfaceWanted[mode.Name][surfaceCode][candidate.Text], candidate.ID)
			if observations[candidate.ID] == nil {
				observations[candidate.ID] = map[string]*particleAStage6BObservation{}
			}
			observations[candidate.ID][mode.Name] = &particleAStage6BObservation{}
		}
		if err := observeParticleAStage6BMode(inputPaths[mode.File], mode.Name, canonicalWanted[mode.Name], surfaceWanted[mode.Name], observations); err != nil {
			return ParticleAStage6BResult{}, err
		}
	}

	classCounts, blockedByClass := map[string]int{}, map[string]int{}
	candidateRows := [][]string{{"record_id", "text", "canonical_pinyin", "surface_pinyin", "class_id", "target_shouyin_id", "target_yinyuan_ids", "weight", "canonical_full", "surface_full", "length_policy", "candidate_text_policy", "adjudication_status", "runtime_enabled"}}
	projectionRows := [][]string{{"record_id", "text", "class_id", "mode", "canonical_code", "surface_code", "canonical_length", "surface_length", "length_delta", "canonical_weight_match", "surface_same_text_present", "existing_bucket_rows", "predicted_bucket_rows", "existing_competitors", "top_competitor_weight", "competitor_samples", "runtime_status"}}
	blockedCount, collisions, alreadyAll := 0, 0, 0
	allCanonicalWeightsMatch := true
	for _, candidate := range candidates {
		classCounts[candidate.ClassID]++
		lengthPolicy := "not_longer_all_modes"
		if candidate.BlockedByLength {
			lengthPolicy = "blocked_surface_longer"
			blockedCount++
			blockedByClass[candidate.ClassID]++
		}
		ids := candidate.TargetTuple[:]
		candidateRows = append(candidateRows, []string{candidate.ID, candidate.Text, candidate.CanonicalPinyin, candidate.SurfacePinyin, candidate.ClassID, candidate.TargetShouyinID, strings.Join(ids, " "), candidate.Weight, candidate.Canonical.FullSpelling, candidate.Surface.FullSpelling, lengthPolicy, "preserve", "research_only", "false"})
		allPresent := true
		for _, mode := range modes {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode.Name)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode.Name)
			observation := observations[candidate.ID][mode.Name]
			if observation.CanonicalWeight != candidate.Weight {
				allCanonicalWeightsMatch = false
			}
			predicted := observation.ExistingRows
			if !observation.SurfaceSameText {
				predicted++
				allPresent = false
			}
			if predicted > 1 {
				collisions++
			}
			status := "research_only_not_generated"
			if candidate.BlockedByLength {
				status = "blocked_surface_longer"
			}
			projectionRows = append(projectionRows, []string{candidate.ID, candidate.Text, candidate.ClassID, mode.Name, canonicalCode, surfaceCode, strconv.Itoa(codeLength(canonicalCode)), strconv.Itoa(codeLength(surfaceCode)), strconv.Itoa(codeLength(surfaceCode) - codeLength(canonicalCode)), strconv.FormatBool(observation.CanonicalWeight == candidate.Weight), strconv.FormatBool(observation.SurfaceSameText), strconv.Itoa(observation.ExistingRows), strconv.Itoa(predicted), strconv.Itoa(observation.ExistingRivals), strconv.Itoa(observation.TopRivalWeight), strings.Join(observation.CompetitorSample, ","), status})
		}
		if allPresent {
			alreadyAll++
		}
	}
	classRows := [][]string{{"class_id", "surface_pinyin", "tuple_strategy", "target_shouyin_id", "layout_key", "candidate_count", "blocked_longer_count", "source_scope", "adjudication_status", "runtime_eligible", "note"}}
	for _, class := range policy {
		classRows = append(classRows, []string{class.ClassID, class.SurfacePinyin, class.TupleStrategy, class.TargetShouyinID, profile.Projection[class.TargetShouyinID], strconv.Itoa(classCounts[class.ClassID]), strconv.Itoa(blockedByClass[class.ClassID]), class.SourceScope, class.AdjudicationStatus, strconv.FormatBool(class.RuntimeEligible), class.Note})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "candidate_inventory.tsv"), candidateRows); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "three_mode_projection.tsv"), projectionRows); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "class_summary.tsv"), classRows); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "unresolved.tsv"), unresolved); err != nil {
		return ParticleAStage6BResult{}, err
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	gates := map[string]bool{
		"six_projection_classes_complete":   len(policy) == 6 && len(classCounts) == 6,
		"all_target_ids_are_projected":      particleAStage6BTargetsProjected(policy, profile),
		"all_explicit_rows_projected":       len(unresolved) == 1,
		"three_mode_projection_complete":    len(projectionRows)-1 == len(candidates)*3,
		"canonical_weights_match_all_modes": allCanonicalWeightsMatch,
		"longer_routes_are_blocked":         true,
		"candidate_text_is_preserved":       true,
		"runtime_aliases_remain_zero":       true,
		"inputs_are_read_only":              equalHashes(before, after),
	}
	summary := ParticleAStage6BSummary{
		ToolVersion: ParticleAStage6BToolVersion, ProjectionClassCount: len(policy), ExplicitParticleACount: len(candidates) + len(unresolved) - 1,
		ProjectableCandidateCount: len(candidates), BlockedLongerCount: blockedCount, ThreeModeProjectionRows: len(projectionRows) - 1,
		CollisionMappings: collisions, AlreadyPresentAllModes: alreadyAll, UnresolvedCount: len(unresolved) - 1,
		RuntimeAliasesGenerated: 0, ClassCounts: classCounts, BlockedLongerByClass: blockedByClass,
		InputHashesMatch: equalHashes(before, after), Gates: gates, Passed: allGatesPass(gates),
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ParticleAStage6BResult{}, err
	}
	if err := writeParticleAStage6BReport(filepath.Join(config.OutputDir, "REPORT.md"), summary); err != nil {
		return ParticleAStage6BResult{}, err
	}
	outputPaths := map[string]string{}
	for _, name := range []string{"REPORT.md", "candidate_inventory.tsv", "class_summary.tsv", "input_hashes_after.json", "input_hashes_before.json", "summary.json", "three_mode_projection.tsv", "unresolved.tsv"} {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ParticleAStage6BResult{}, err
	}
	manifest := ParticleAStage6BManifest{ToolVersion: ParticleAStage6BToolVersion, InputSHA256: before, OutputSHA256: outputHashes, OutputHashScope: "all deterministic Stage 6B reports except manifest.json"}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return ParticleAStage6BResult{}, err
	}
	result := ParticleAStage6BResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("阶段 6B 语气词‘啊’离线投影门禁未通过")
	}
	return result, nil
}

func loadParticleAStage6BPolicy(path string) ([]particleAProjectionClass, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	if !scanner.Scan() {
		return nil, errors.New("阶段 6B 投影表为空")
	}
	wantHeader := "class_id\tsurface_pinyin\ttuple_strategy\ttarget_shouyin_id\tsource_scope\tadjudication_status\truntime_eligible\tnote"
	if strings.TrimPrefix(strings.TrimSuffix(scanner.Text(), "\r"), "\ufeff") != wantHeader {
		return nil, errors.New("阶段 6B 投影表表头错误")
	}
	result := []particleAProjectionClass{}
	for scanner.Scan() {
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 8 {
			return nil, fmt.Errorf("阶段 6B 投影表列数错误：%s", line)
		}
		runtime, err := strconv.ParseBool(fields[6])
		if err != nil {
			return nil, err
		}
		result = append(result, particleAProjectionClass{fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], runtime, fields[7]})
	}
	return result, scanner.Err()
}

func validateParticleAStage6BPolicy(policy []particleAProjectionClass) error {
	want := map[string]struct{ pinyin, strategy, onset string }{
		"PA-U": {"wa5", "replace_a5_shouyin", "N24"}, "PA-N": {"na5", "replace_a5_shouyin", "N08"},
		"PA-NG": {"nga5", "replace_a5_shouyin", "N26"}, "PA-APICAL-FRONT": {"ɹa5", "replace_a5_shouyin", "N27"},
		"PA-RETROFLEX": {"ra5", "replace_a5_shouyin", "N19"}, "PA-VOWEL-IY": {"ya5", "replace_a5_shouyin", "N23"},
	}
	seen := map[string]bool{}
	for _, item := range policy {
		expected, ok := want[item.ClassID]
		if !ok || seen[item.ClassID] {
			return fmt.Errorf("阶段 6B 类别未知或重复：%s", item.ClassID)
		}
		if item.SurfacePinyin != expected.pinyin || item.TupleStrategy != expected.strategy || item.TargetShouyinID != expected.onset {
			return fmt.Errorf("阶段 6B 类别 %s 的目标投影不一致", item.ClassID)
		}
		if item.RuntimeEligible || item.AdjudicationStatus != "research_only" || item.SourceScope == "" || item.Note == "" {
			return fmt.Errorf("阶段 6B 类别 %s 越过离线边界", item.ClassID)
		}
		seen[item.ClassID] = true
	}
	if len(seen) != len(want) {
		return fmt.Errorf("阶段 6B 必须恰有六类，实际 %d", len(seen))
	}
	return nil
}

func particleAStage6BTargetTuple(class particleAProjectionClass, inventory Inventory) (YinyuanTuple, error) {
	if class.TupleStrategy != "replace_a5_shouyin" {
		return YinyuanTuple{}, fmt.Errorf("不支持的语气词投影策略 %s", class.TupleStrategy)
	}
	base, ok := inventory.Syllables["a5"]
	if !ok {
		return YinyuanTuple{}, errors.New("音节表缺少 a5")
	}
	base[0] = class.TargetShouyinID
	return base, nil
}

func particleAStage6BTargetsProjected(policy []particleAProjectionClass, profile layoutdesigner.Profile) bool {
	for _, item := range policy {
		if profile.Projection[item.TargetShouyinID] == "" {
			return false
		}
	}
	return true
}

func observeParticleAStage6BMode(path, mode string, canonical map[string][]string, surface map[string]map[string][]string, observations map[string]map[string]*particleAStage6BObservation) error {
	return scanRimeDictionary(path, func(entry dictionaryEntry) {
		code := strings.Join(strings.Fields(entry.Code), " ")
		for _, id := range canonical[dictionaryKey(entry.Text, code)] {
			observations[id][mode].CanonicalWeight = entry.Weight
		}
		texts := surface[code]
		if texts == nil {
			return
		}
		weight, _ := strconv.Atoi(entry.Weight)
		for text, ids := range texts {
			for _, id := range ids {
				observation := observations[id][mode]
				observation.ExistingRows++
				if entry.Text == text {
					observation.SurfaceSameText = true
					continue
				}
				observation.ExistingRivals++
				if weight > observation.TopRivalWeight {
					observation.TopRivalWeight = weight
				}
				if len(observation.CompetitorSample) < 5 && !containsString(observation.CompetitorSample, entry.Text) {
					observation.CompetitorSample = append(observation.CompetitorSample, entry.Text)
				}
			}
		}
	})
}

func validateParticleAStage6BConfig(config *ParticleAStage6BConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ScopePath == "" || config.ProjectionPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("阶段 6B 所有路径均不能为空")
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
		return fmt.Errorf("阶段 6B 输出必须严格位于临时目录 %s 内", allowed)
	}
	if filepath.Base(output) != "particle-a-stage6b-projection" {
		return fmt.Errorf("阶段 6B 输出目录必须名为 particle-a-stage6b-projection：%s", output)
	}
	config.OutputDir, config.AllowedOutputRoot = output, allowed
	return nil
}

func writeParticleAStage6BReport(path string, summary ParticleAStage6BSummary) error {
	text := fmt.Sprintf(`# 阶段 6B：语气词“啊”离线三模式投影

- 显式“啊/a5”记录：%d
- 可完成语义投影：%d；未决：%d
- 三模式投影行：%d
- 因任一模式比规范路径更长而阻断：%d
- 预测落入重码桶的模式映射：%d
- 三模式均已有同文路径：%d
- 运行时别名：0
- 输入哈希保持：%t
- 审计通过：%t

本阶段只验证“六类末音 → 目标首音 ID → 三模式编码”的中间链路。候选文字始终保持“啊”，不改写为“呀、哇、哪”；没有显式构式来源复核、码长放宽决策和真实 Rime 宿主门禁前，不生成或接入运行时候选。
`, summary.ExplicitParticleACount, summary.ProjectableCandidateCount, summary.UnresolvedCount, summary.ThreeModeProjectionRows, summary.BlockedLongerCount, summary.CollisionMappings, summary.AlreadyPresentAllModes, summary.InputHashesMatch, summary.Passed)
	return os.WriteFile(path, []byte(text), 0o644)
}
