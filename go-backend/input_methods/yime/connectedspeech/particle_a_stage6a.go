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
)

const ParticleAStage6AToolVersion = "connected-speech-particle-a-stage6a-audit-v1"

type ParticleAStage6AConfig struct {
	RepoRoot          string
	DataDir           string
	ScopePath         string
	OutputDir         string
	AllowedOutputRoot string
}

type ParticleAStage6ASummary struct {
	ToolVersion             string          `json:"tool_version"`
	ScopeClassCount         int             `json:"scope_class_count"`
	LexiconRowCount         int             `json:"lexicon_row_count"`
	ExplicitParticleACount  int             `json:"explicit_particle_a_count"`
	ClassifiedCount         int             `json:"classified_count"`
	UnresolvedCount         int             `json:"unresolved_count"`
	RuntimeAliasesGenerated int             `json:"runtime_aliases_generated"`
	ClassCounts             map[string]int  `json:"class_counts"`
	InputHashesMatch        bool            `json:"input_hashes_match"`
	Gates                   map[string]bool `json:"gates"`
	Passed                  bool            `json:"passed"`
}

type ParticleAStage6AManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type ParticleAStage6AResult struct {
	Summary  ParticleAStage6ASummary
	Manifest ParticleAStage6AManifest
}

type particleAScopeClass struct {
	ClassID            string
	Priority           int
	PreviousCondition  string
	SurfaceReading     string
	CommonWriting      string
	AdjudicationStatus string
	RuntimeEligible    bool
	Note               string
}

type particleADecomposition struct {
	Final string
	Tuple YinyuanTuple
}

type particleACandidate struct {
	ID              string
	Text            string
	CanonicalCode   string
	CanonicalPinyin string
	PreviousPinyin  string
	PreviousFinal   string
	ClassID         string
	SurfaceReading  string
	CommonWriting   string
	Weight          string
}

func DefaultParticleAStage6AConfig(repoRoot string) ParticleAStage6AConfig {
	return ParticleAStage6AConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		ScopePath:         filepath.Join(repoRoot, "docs", "project", "connected_speech", "particle_a_stage6a_scope.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "particle-a-stage6a-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunParticleAStage6AAudit(config ParticleAStage6AConfig) (ParticleAStage6AResult, error) {
	if err := validateParticleAStage6AConfig(&config); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ParticleAStage6AResult{}, err
	}
	inputPaths := map[string]string{
		"scope":         config.ScopePath,
		"pinyin_codes":  filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
		"decomposition": filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"),
		"full_lexicon":  filepath.Join(config.DataDir, "yime_full.dict.yaml"),
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	scope, err := loadParticleAScope(config.ScopePath)
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := validateParticleAScope(scope); err != nil {
		return ParticleAStage6AResult{}, err
	}
	scopeByID := map[string]particleAScopeClass{}
	for _, class := range scope {
		scopeByID[class.ClassID] = class
	}
	codes, err := loadCanonicalCodeRows(inputPaths["pinyin_codes"])
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	inverse := buildCanonicalInverse(codes)
	decomposition, err := loadParticleADecomposition(inputPaths["decomposition"])
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	a5Code := strings.TrimSpace(codes["a5"])
	if a5Code == "" {
		return ParticleAStage6AResult{}, errors.New("规范码表缺少语气词基础音节 a5")
	}

	lexiconRows := 0
	candidates := []particleACandidate{}
	unresolved := [][]string{{"text", "full_code", "weight", "reason", "detail"}}
	err = scanRimeDictionary(inputPaths["full_lexicon"], func(entry dictionaryEntry) {
		lexiconRows++
		parts := strings.Fields(entry.Code)
		if !strings.HasSuffix(entry.Text, "啊") || len(parts) < 2 || parts[len(parts)-1] != a5Code {
			return
		}
		pinyinParts := make([]string, len(parts))
		for index, code := range parts {
			choices := inverse[code]
			if len(choices) == 0 || !sameToneIdentity(choices) {
				unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "ambiguous_or_unknown_code", code + "=" + strings.Join(choices, "|")})
				return
			}
			pinyinParts[index] = choices[0]
		}
		previousChoices := inverse[parts[len(parts)-2]]
		classID, previousFinal, classErr := classifyParticleAPrevious(previousChoices, decomposition)
		if classErr != nil {
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "previous_final_unresolved", classErr.Error()})
			return
		}
		class, ok := scopeByID[classID]
		if !ok {
			unresolved = append(unresolved, []string{entry.Text, entry.Code, entry.Weight, "scope_class_missing", classID})
			return
		}
		candidates = append(candidates, particleACandidate{
			Text: entry.Text, CanonicalCode: entry.Code, CanonicalPinyin: strings.Join(pinyinParts, " "),
			PreviousPinyin: pinyinChoiceLabel(previousChoices), PreviousFinal: previousFinal, ClassID: classID,
			SurfaceReading: class.SurfaceReading, CommonWriting: class.CommonWriting, Weight: entry.Weight,
		})
	})
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].ClassID+"\x00"+candidates[i].Text+"\x00"+candidates[i].CanonicalCode < candidates[j].ClassID+"\x00"+candidates[j].Text+"\x00"+candidates[j].CanonicalCode
	})
	classCounts := map[string]int{}
	rows := [][]string{{"record_id", "text", "canonical_pinyin", "canonical_full_code", "previous_pinyin", "previous_final", "class_id", "surface_reading", "common_writing", "candidate_text_policy", "adjudication_status", "runtime_enabled", "weight"}}
	for index := range candidates {
		candidates[index].ID = fmt.Sprintf("PA-6A-%05d", index+1)
		candidate := candidates[index]
		classCounts[candidate.ClassID]++
		rows = append(rows, []string{candidate.ID, candidate.Text, candidate.CanonicalPinyin, candidate.CanonicalCode, candidate.PreviousPinyin, candidate.PreviousFinal, candidate.ClassID, candidate.SurfaceReading, candidate.CommonWriting, "preserve", scopeByID[candidate.ClassID].AdjudicationStatus, "false", candidate.Weight})
	}
	classRows := [][]string{{"class_id", "priority", "previous_final_condition", "surface_reading", "common_writing", "candidate_count", "adjudication_status", "runtime_eligible", "note"}}
	for _, class := range scope {
		classRows = append(classRows, []string{class.ClassID, strconv.Itoa(class.Priority), class.PreviousCondition, class.SurfaceReading, class.CommonWriting, strconv.Itoa(classCounts[class.ClassID]), class.AdjudicationStatus, strconv.FormatBool(class.RuntimeEligible), class.Note})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "candidate_inventory.tsv"), rows); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "class_summary.tsv"), classRows); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "unresolved.tsv"), unresolved); err != nil {
		return ParticleAStage6AResult{}, err
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	gates := map[string]bool{
		"scope_is_offline_only":        particleAScopeOffline(scope),
		"candidate_text_is_preserved":  true,
		"all_six_classes_represented":  len(classCounts) == 6,
		"all_explicit_rows_classified": len(unresolved) == 1,
		"runtime_aliases_remain_zero":  true,
		"inputs_are_read_only":         equalHashes(before, after),
	}
	summary := ParticleAStage6ASummary{
		ToolVersion: ParticleAStage6AToolVersion, ScopeClassCount: len(scope), LexiconRowCount: lexiconRows,
		ExplicitParticleACount: len(candidates) + len(unresolved) - 1, ClassifiedCount: len(candidates), UnresolvedCount: len(unresolved) - 1,
		RuntimeAliasesGenerated: 0, ClassCounts: classCounts, InputHashesMatch: equalHashes(before, after), Gates: gates, Passed: allGatesPass(gates),
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ParticleAStage6AResult{}, err
	}
	if err := writeParticleAStage6AReport(filepath.Join(config.OutputDir, "REPORT.md"), summary); err != nil {
		return ParticleAStage6AResult{}, err
	}
	outputNames := []string{"REPORT.md", "candidate_inventory.tsv", "class_summary.tsv", "input_hashes_after.json", "input_hashes_before.json", "summary.json", "unresolved.tsv"}
	outputPaths := map[string]string{}
	for _, name := range outputNames {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ParticleAStage6AResult{}, err
	}
	manifest := ParticleAStage6AManifest{ToolVersion: ParticleAStage6AToolVersion, InputSHA256: before, OutputSHA256: outputHashes, OutputHashScope: "all deterministic reports except manifest.json"}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return ParticleAStage6AResult{}, err
	}
	result := ParticleAStage6AResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, fmt.Errorf("particle-a Stage 6A audit failed: unresolved=%d", summary.UnresolvedCount)
	}
	return result, nil
}

func validateParticleAStage6AConfig(config *ParticleAStage6AConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.ScopePath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("阶段 6A 所有路径均不能为空")
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
		return fmt.Errorf("阶段 6A 输出必须严格位于临时目录 %s 内", allowed)
	}
	if filepath.Base(output) != "particle-a-stage6a-audit" {
		return fmt.Errorf("阶段 6A 输出目录必须名为 particle-a-stage6a-audit：%s", output)
	}
	config.OutputDir, config.AllowedOutputRoot = output, allowed
	return nil
}

func loadParticleAScope(path string) ([]particleAScopeClass, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	if !scanner.Scan() {
		return nil, errors.New("阶段 6A 范围表为空")
	}
	result := []particleAScopeClass{}
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) != 8 {
			return nil, fmt.Errorf("阶段 6A 范围表列数错误：%s", scanner.Text())
		}
		priority, err := strconv.Atoi(fields[1])
		if err != nil {
			return nil, fmt.Errorf("阶段 6A 优先级无效：%s", fields[1])
		}
		runtimeEligible, err := strconv.ParseBool(fields[6])
		if err != nil {
			return nil, fmt.Errorf("阶段 6A runtime_eligible 无效：%s", fields[6])
		}
		result = append(result, particleAScopeClass{fields[0], priority, fields[2], fields[3], fields[4], fields[5], runtimeEligible, fields[7]})
	}
	return result, scanner.Err()
}

func validateParticleAScope(scope []particleAScopeClass) error {
	wanted := map[string]bool{"PA-U": true, "PA-N": true, "PA-NG": true, "PA-APICAL-FRONT": true, "PA-RETROFLEX": true, "PA-VOWEL-IY": true}
	seen, priorities := map[string]bool{}, map[int]bool{}
	for _, class := range scope {
		if !wanted[class.ClassID] || seen[class.ClassID] {
			return fmt.Errorf("阶段 6A 类别缺失、重复或未知：%s", class.ClassID)
		}
		if priorities[class.Priority] {
			return fmt.Errorf("阶段 6A 优先级重复：%d", class.Priority)
		}
		if class.RuntimeEligible || class.AdjudicationStatus != "research_only" || class.SurfaceReading == "" || class.Note == "" {
			return fmt.Errorf("阶段 6A 类别不得进入运行时且必须完整：%s", class.ClassID)
		}
		seen[class.ClassID], priorities[class.Priority] = true, true
	}
	if len(seen) != len(wanted) {
		return fmt.Errorf("阶段 6A 必须恰有六类，实际 %d", len(seen))
	}
	return nil
}

func particleAScopeOffline(scope []particleAScopeClass) bool {
	for _, class := range scope {
		if class.RuntimeEligible {
			return false
		}
	}
	return true
}

func loadParticleADecomposition(path string) (map[string]particleADecomposition, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	if !scanner.Scan() {
		return nil, errors.New("音节分解表为空")
	}
	header := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
	columns := map[string]int{}
	for index, name := range header {
		columns[strings.TrimSpace(name)] = index
	}
	for _, name := range []string{"pinyin_tone", "ganyin_label", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
		if _, ok := columns[name]; !ok {
			return nil, fmt.Errorf("音节分解表缺少列 %s", name)
		}
	}
	rows := map[string]particleADecomposition{}
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < len(header) {
			continue
		}
		pinyin := canonicalNumericPinyin(fields[columns["pinyin_tone"]])
		final := strings.TrimSpace(fields[columns["ganyin_label"]])
		rows[pinyin] = particleADecomposition{Final: final, Tuple: YinyuanTuple{fields[columns["shouyin_id"]], fields[columns["huyin_id"]], fields[columns["zhuyin_id"]], fields[columns["moyin_id"]]}}
	}
	return rows, scanner.Err()
}

func classifyParticleAPrevious(choices []string, decomposition map[string]particleADecomposition) (string, string, error) {
	classID, finalLabel := "", ""
	for _, choice := range choices {
		row, ok := decomposition[canonicalNumericPinyin(choice)]
		if !ok {
			return "", "", fmt.Errorf("音节 %s 缺少分解", choice)
		}
		candidateClass := particleAFinalClass(choice, row.Final)
		if candidateClass == "" {
			return "", "", fmt.Errorf("音节 %s 的韵母 %s 不属于六类", choice, row.Final)
		}
		if classID != "" && classID != candidateClass {
			return "", "", fmt.Errorf("同码音节跨越类别：%s", strings.Join(choices, "|"))
		}
		classID = candidateClass
		if finalLabel == "" {
			finalLabel = stripToneDigit(row.Final)
		} else if finalLabel != stripToneDigit(row.Final) {
			finalLabel = "{" + finalLabel + "|" + stripToneDigit(row.Final) + "}"
		}
	}
	if classID == "" {
		return "", "", errors.New("前一音节没有可解码读音")
	}
	return classID, finalLabel, nil
}

func particleAFinalClass(pinyin, final string) string {
	base, finalBase := stripToneDigit(canonicalNumericPinyin(pinyin)), stripToneDigit(canonicalNumericPinyin(final))
	if strings.HasSuffix(finalBase, "ng") {
		return "PA-NG"
	}
	if strings.HasSuffix(finalBase, "n") {
		return "PA-N"
	}
	if finalBase == "_i" {
		if strings.HasPrefix(base, "zh") || strings.HasPrefix(base, "ch") || strings.HasPrefix(base, "sh") || strings.HasPrefix(base, "r") {
			return "PA-RETROFLEX"
		}
		return "PA-APICAL-FRONT"
	}
	if finalBase == "er" {
		return "PA-RETROFLEX"
	}
	if finalBase == "u" || finalBase == "ao" || finalBase == "iao" || finalBase == "ou" || finalBase == "iou" {
		return "PA-U"
	}
	if strings.ContainsAny(finalBase, "aoeêiü") {
		return "PA-VOWEL-IY"
	}
	return ""
}

func stripToneDigit(value string) string {
	value = strings.TrimSpace(value)
	if value != "" && value[len(value)-1] >= '1' && value[len(value)-1] <= '5' {
		return value[:len(value)-1]
	}
	return value
}

func writeParticleAStage6AReport(path string, summary ParticleAStage6ASummary) error {
	lines := []string{"# 阶段 6A：语气词“啊”离线末音分类审计", "", fmt.Sprintf("- 工具版本：`%s`", summary.ToolVersion), fmt.Sprintf("- 核心词典行数：%d", summary.LexiconRowCount), fmt.Sprintf("- 显式‘啊/a5’记录：%d", summary.ExplicitParticleACount), fmt.Sprintf("- 已分类：%d", summary.ClassifiedCount), fmt.Sprintf("- 未决：%d", summary.UnresolvedCount), "- 运行时别名：0", "- 候选文字策略：始终保留原字，不自动改写为‘呀、哇、哪’。", "", "## 六类分布", ""}
	keys := make([]string, 0, len(summary.ClassCounts))
	for key := range summary.ClassCounts {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		lines = append(lines, fmt.Sprintf("- `%s`：%d", key, summary.ClassCounts[key]))
	}
	lines = append(lines, "", "## 门禁", "")
	gateKeys := make([]string, 0, len(summary.Gates))
	for key := range summary.Gates {
		gateKeys = append(gateKeys, key)
	}
	sort.Strings(gateKeys)
	for _, key := range gateKeys {
		lines = append(lines, fmt.Sprintf("- `%s`：%t", key, summary.Gates[key]))
	}
	lines = append(lines, "", "本阶段不创建派生首音 ID、不投影三模式编码、不生成 Rime 候选。", "")
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644)
}
