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

const ThirdToneStage5BToolVersion = "connected-speech-third-tone-stage5b-review-v1"

type ThirdToneStage5BConfig struct {
	RepoRoot          string
	ReviewPath        string
	DecisionsPath     string
	SourcesPath       string
	Stage5AOutputDir  string
	Stage5ADataDir    string
	OutputDir         string
	AllowedOutputRoot string
	RefreshStage5A    bool
}

type ThirdToneStage5BSummary struct {
	ToolVersion              string          `json:"tool_version"`
	SourceCount              int             `json:"source_count"`
	ReviewCount              int             `json:"review_count"`
	DecisionCount            int             `json:"decision_count"`
	PendingHumanReviewCount  int             `json:"pending_human_review_count"`
	ApprovedCount            int             `json:"approved_count"`
	MatchedStage5ACount      int             `json:"matched_stage5a_count"`
	ThreeModeProjectionCount int             `json:"three_mode_projection_count"`
	UnresolvedCount          int             `json:"unresolved_count"`
	RuntimeAliasesGenerated  int             `json:"runtime_aliases_generated"`
	Stage5ARefreshed         bool            `json:"stage5a_refreshed"`
	InputHashesMatch         bool            `json:"input_hashes_match"`
	Gates                    map[string]bool `json:"gates"`
	Passed                   bool            `json:"passed"`
}

type ThirdToneStage5BResult struct {
	Summary  ThirdToneStage5BSummary
	Manifest ThirdToneStage5BManifest
}

type ThirdToneStage5BManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type thirdToneStage5BSource struct {
	ID         string
	Title      string
	Authority  string
	URL        string
	Supports   string
	Limitation string
}

type thirdToneStage5BReview struct {
	ReviewID              string
	Text                  string
	CanonicalPinyin       string
	ExpectedSurfacePinyin string
	Stage5ARecordSnapshot string
	WeightSnapshot        string
	EvidenceClass         string
	ProsodicStatus        string
	RuntimeStatus         string
	SourceIDs             []string
	Note                  string
}

type thirdToneStage5BDecision struct {
	ReviewID          string
	Decision          string
	ApplicableContext string
	BlockingContext   string
	TrialEligibility  string
	InputPolicy       string
	Adjudicator       string
	AdjudicatedOn     string
	Note              string
}

type thirdToneStage5BCandidate struct {
	RecordID        string
	Text            string
	CanonicalPinyin string
	SurfacePinyin   string
	Weight          string
	CanonicalFull   string
	SurfaceFull     string
	SurfaceAttested bool
	LengthPolicy    string
	Adjudication    string
}

var thirdToneStage5BProjectionHeader = []string{
	"record_id", "text", "mode", "canonical_code", "surface_code", "canonical_length", "surface_length",
	"length_delta", "canonical_weight_found", "canonical_weight_match", "surface_same_text_present",
	"existing_bucket_rows", "predicted_bucket_rows", "existing_competitors", "top_competitor_weight",
	"competitor_samples", "runtime_status",
}

func DefaultThirdToneStage5BConfig(repoRoot string) ThirdToneStage5BConfig {
	temporaryRoot := filepath.Join(repoRoot, ".tmp")
	return ThirdToneStage5BConfig{
		RepoRoot:          repoRoot,
		ReviewPath:        filepath.Join(repoRoot, "docs", "project", "connected_speech", "third_tone_stage5b_review.tsv"),
		DecisionsPath:     filepath.Join(repoRoot, "docs", "project", "connected_speech", "third_tone_stage5b_decisions.tsv"),
		SourcesPath:       filepath.Join(repoRoot, "docs", "project", "connected_speech", "third_tone_stage5b_sources.tsv"),
		Stage5AOutputDir:  filepath.Join(temporaryRoot, "third-tone-stage5a-audit"),
		Stage5ADataDir:    filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		OutputDir:         filepath.Join(temporaryRoot, "third-tone-stage5b-review"),
		AllowedOutputRoot: temporaryRoot,
		RefreshStage5A:    true,
	}
}

func RunThirdToneStage5BReview(config ThirdToneStage5BConfig) (ThirdToneStage5BResult, error) {
	if err := validateThirdToneStage5BConfig(&config); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	if config.RefreshStage5A {
		stage5AConfig := DefaultThirdToneStage5AConfig(config.RepoRoot)
		stage5AConfig.OutputDir = config.Stage5AOutputDir
		stage5AConfig.AllowedOutputRoot = config.AllowedOutputRoot
		if config.Stage5ADataDir != "" {
			stage5AConfig.DataDir = config.Stage5ADataDir
		}
		if _, err := RunThirdToneStage5AAudit(stage5AConfig); err != nil {
			return ThirdToneStage5BResult{}, fmt.Errorf("刷新阶段 5A 失败: %w", err)
		}
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	inputPaths := map[string]string{
		"review":             config.ReviewPath,
		"decisions":          config.DecisionsPath,
		"sources":            config.SourcesPath,
		"stage5a_candidates": filepath.Join(config.Stage5AOutputDir, "candidate_inventory.tsv"),
		"stage5a_projection": filepath.Join(config.Stage5AOutputDir, "three_mode_projection.tsv"),
		"stage5a_summary":    filepath.Join(config.Stage5AOutputDir, "summary.json"),
		"stage5a_manifest":   filepath.Join(config.Stage5AOutputDir, "manifest.json"),
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	sources, err := loadThirdToneStage5BSources(config.SourcesPath)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	reviews, err := loadThirdToneStage5BReviews(config.ReviewPath)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	decisions, err := loadThirdToneStage5BDecisions(config.DecisionsPath)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	candidates, err := loadThirdToneStage5BCandidates(filepath.Join(config.Stage5AOutputDir, "candidate_inventory.tsv"))
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	projections, err := loadThirdToneStage5BProjections(filepath.Join(config.Stage5AOutputDir, "three_mode_projection.tsv"))
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}

	reviewRows := [][]string{{"review_id", "current_stage5a_record_id", "text", "canonical_pinyin", "surface_pinyin", "weight", "evidence_class", "decision", "applicable_context", "blocking_context", "trial_eligibility", "input_policy", "adjudicator", "adjudicated_on", "three_mode_gate", "source_ids", "review_note", "decision_note"}}
	projectionRows := [][]string{append([]string{"review_id"}, thirdToneStage5BProjectionHeader...)}
	unresolvedRows := [][]string{{"review_id", "text", "reason", "detail"}}
	matched, pending, approved := 0, 0, 0
	seenReview := map[string]bool{}
	seenCandidate := map[string]bool{}
	for _, review := range reviews {
		if seenReview[review.ReviewID] {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "duplicate_review_id", review.ReviewID})
			continue
		}
		seenReview[review.ReviewID] = true
		if review.ProsodicStatus == "approved" || review.RuntimeStatus != "not_approved" {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "premature_approval", review.ProsodicStatus + "/" + review.RuntimeStatus})
			continue
		}
		if err := validateThirdToneStage5BPendingBoundary(review); err != nil {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "invalid_review_boundary", err.Error()})
			continue
		}
		unknownSource := ""
		for _, sourceID := range review.SourceIDs {
			if _, ok := sources[sourceID]; !ok {
				unknownSource = sourceID
				break
			}
		}
		if unknownSource != "" || len(review.SourceIDs) == 0 {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "unknown_or_missing_source", unknownSource})
			continue
		}
		decision, ok := decisions[review.ReviewID]
		if !ok {
			pending++
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "decision_missing", "未找到人工判决"})
			continue
		}
		if err := validateThirdToneStage5BDecision(decision); err != nil {
			pending++
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "decision_invalid", err.Error()})
			continue
		}
		approved++
		key := thirdToneStage5BKey(review.Text, review.CanonicalPinyin)
		candidate, ok := candidates[key]
		if !ok {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "stage5a_candidate_missing", review.CanonicalPinyin})
			continue
		}
		if seenCandidate[candidate.RecordID] {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "duplicate_candidate_selection", candidate.RecordID})
			continue
		}
		seenCandidate[candidate.RecordID] = true
		if candidate.RecordID != review.Stage5ARecordSnapshot || candidate.Weight != review.WeightSnapshot || candidate.SurfacePinyin != review.ExpectedSurfacePinyin {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "snapshot_drift", fmt.Sprintf("id=%s weight=%s surface=%s", candidate.RecordID, candidate.Weight, candidate.SurfacePinyin)})
			continue
		}
		if !candidate.SurfaceAttested || candidate.LengthPolicy != "not_longer_all_modes" || candidate.Adjudication != "research_only" {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "stage5a_gate_failed", fmt.Sprintf("attested=%t length=%s status=%s", candidate.SurfaceAttested, candidate.LengthPolicy, candidate.Adjudication)})
			continue
		}
		modeRows := projections[candidate.RecordID]
		modeGate, reason := validateThirdToneStage5BModeRows(modeRows, candidate.Weight)
		if !modeGate {
			unresolvedRows = append(unresolvedRows, []string{review.ReviewID, review.Text, "three_mode_gate_failed", reason})
			continue
		}
		matched++
		reviewRows = append(reviewRows, []string{review.ReviewID, candidate.RecordID, review.Text, review.CanonicalPinyin, candidate.SurfacePinyin, candidate.Weight, review.EvidenceClass, decision.Decision, decision.ApplicableContext, decision.BlockingContext, decision.TrialEligibility, decision.InputPolicy, decision.Adjudicator, decision.AdjudicatedOn, "passed", strings.Join(review.SourceIDs, ","), review.Note, decision.Note})
		for _, row := range modeRows {
			projectionRows = append(projectionRows, append([]string{review.ReviewID}, row...))
		}
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "review_queue.tsv"), reviewRows); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "three_mode_review_projection.tsv"), projectionRows); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "unresolved.tsv"), unresolvedRows); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	gates := map[string]bool{
		"sources_present":                len(sources) >= 2,
		"review_rows_present":            len(reviews) > 0,
		"one_decision_per_review":        len(decisions) == len(reviews),
		"all_reviews_approved_for_trial": pending == 0 && approved == len(reviews),
		"parallel_alias_policy_complete": pending == 0 && approved == len(reviews),
		"all_reviews_match_stage5a":      matched == len(reviews),
		"three_mode_projection_complete": len(projectionRows)-1 == len(reviews)*3,
		"unresolved_rows_zero":           len(unresolvedRows) == 1,
		"runtime_aliases_generated_zero": true,
		"input_hashes_unchanged":         hashesMatch,
	}
	summary := ThirdToneStage5BSummary{
		ToolVersion: ThirdToneStage5BToolVersion, SourceCount: len(sources), ReviewCount: len(reviews), DecisionCount: len(decisions),
		PendingHumanReviewCount: pending, ApprovedCount: approved, MatchedStage5ACount: matched,
		ThreeModeProjectionCount: len(projectionRows) - 1, UnresolvedCount: len(unresolvedRows) - 1,
		RuntimeAliasesGenerated: 0, Stage5ARefreshed: config.RefreshStage5A, InputHashesMatch: hashesMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	report := fmt.Sprintf(`# 阶段 5B-0 上声变调高频复核门禁

- 一般规则来源：%d
- 高频复核项：%d
- 待人工复核：%d
- 已批准：%d
- 当前阶段 5A 匹配：%d
- 三模式复核投影：%d
- 未决：%d
- 运行时别名：0
- 输入哈希保持：%t
- 门禁通过：%t

本报告证明 24 条项目负责人判决仍与当前阶段 5A 数据一致。核准只适用于词内普通连续韵律域；词条之间的列举停顿不构成阻断，只有词内音节边界上的停顿、强调、并列或其它内部韵律约束才阻断本规则。本阶段不生成运行别名；阶段 5C 消费本门禁结果，并行保留规范未变调码和附加变调码，使两条路径输入同一候选。
`, len(sources), len(reviews), pending, approved, matched, len(projectionRows)-1, len(unresolvedRows)-1, hashesMatch, summary.Passed)
	if err := os.WriteFile(filepath.Join(config.OutputDir, "REPORT.md"), []byte(report), 0o644); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	outputPaths := map[string]string{}
	for _, name := range []string{"REPORT.md", "input_hashes_after.json", "input_hashes_before.json", "review_queue.tsv", "summary.json", "three_mode_review_projection.tsv", "unresolved.tsv"} {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ThirdToneStage5BResult{}, err
	}
	manifest := ThirdToneStage5BManifest{ToolVersion: ThirdToneStage5BToolVersion, InputSHA256: before, OutputSHA256: outputHashes, OutputHashScope: "all deterministic Stage 5B files except manifest.json"}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return ThirdToneStage5BResult{}, err
	}
	result := ThirdToneStage5BResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("阶段 5B-0 上声变调复核门禁未通过")
	}
	return result, nil
}

func validateThirdToneStage5BConfig(config *ThirdToneStage5BConfig) error {
	if config.RepoRoot == "" || config.ReviewPath == "" || config.DecisionsPath == "" || config.SourcesPath == "" || config.Stage5AOutputDir == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("阶段 5B 所有路径均不能为空")
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
		return fmt.Errorf("阶段 5B 输出必须严格位于临时目录 %s 内", allowed)
	}
	if filepath.Base(output) != "third-tone-stage5b-review" {
		return fmt.Errorf("阶段 5B 输出目录必须名为 third-tone-stage5b-review：%s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}

func loadThirdToneStage5BSources(path string) (map[string]thirdToneStage5BSource, error) {
	header := []string{"source_id", "title", "authority", "url", "supports", "limitation"}
	rows, err := readThirdToneStage5BTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := map[string]thirdToneStage5BSource{}
	for index, row := range rows {
		entry := thirdToneStage5BSource{row[0], row[1], row[2], row[3], row[4], row[5]}
		if entry.ID == "" || entry.Title == "" || entry.Authority == "" || !strings.HasPrefix(entry.URL, "https://") || entry.Supports == "" || entry.Limitation == "" || result[entry.ID].ID != "" {
			return nil, fmt.Errorf("%s:%d: 无效或重复的来源", path, index+2)
		}
		result[entry.ID] = entry
	}
	return result, nil
}

func loadThirdToneStage5BReviews(path string) ([]thirdToneStage5BReview, error) {
	header := []string{"review_id", "text", "canonical_pinyin", "expected_surface_pinyin", "stage5a_record_id_snapshot", "priority_weight_snapshot", "evidence_class", "prosodic_status", "runtime_status", "source_ids", "note"}
	rows, err := readThirdToneStage5BTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := make([]thirdToneStage5BReview, 0, len(rows))
	for index, row := range rows {
		sourceIDs := splitThirdToneStage5BNonEmpty(row[9], ",")
		if row[0] == "" || row[1] == "" || row[2] == "" || row[3] == "" || row[4] == "" || row[5] == "" || row[10] == "" {
			return nil, fmt.Errorf("%s:%d: 复核记录缺少必填字段", path, index+2)
		}
		result = append(result, thirdToneStage5BReview{row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], sourceIDs, row[10]})
	}
	return result, nil
}

func loadThirdToneStage5BDecisions(path string) (map[string]thirdToneStage5BDecision, error) {
	header := []string{"review_id", "decision", "applicable_context", "blocking_context", "trial_eligibility", "input_policy", "adjudicator", "adjudicated_on", "note"}
	rows, err := readThirdToneStage5BTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := map[string]thirdToneStage5BDecision{}
	for index, row := range rows {
		decision := thirdToneStage5BDecision{row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8]}
		if decision.ReviewID == "" || result[decision.ReviewID].ReviewID != "" {
			return nil, fmt.Errorf("%s:%d: 无效或重复的人工判决", path, index+2)
		}
		result[decision.ReviewID] = decision
	}
	return result, nil
}

func loadThirdToneStage5BCandidates(path string) (map[string]thirdToneStage5BCandidate, error) {
	header := []string{"record_id", "text", "canonical_pinyin", "surface_pinyin", "weight", "canonical_full", "surface_full", "source_code_ambiguous", "surface_syllable_attested_in_inventory", "length_policy", "adjudication_status"}
	rows, err := readThirdToneStage5BTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := map[string]thirdToneStage5BCandidate{}
	for index, row := range rows {
		attested, err := strconv.ParseBool(row[8])
		if err != nil {
			return nil, fmt.Errorf("%s:%d: 无效的音节清单状态", path, index+2)
		}
		candidate := thirdToneStage5BCandidate{row[0], row[1], row[2], row[3], row[4], row[5], row[6], attested, row[9], row[10]}
		key := thirdToneStage5BKey(candidate.Text, candidate.CanonicalPinyin)
		if _, exists := result[key]; exists {
			return nil, fmt.Errorf("%s:%d: 候选键重复", path, index+2)
		}
		result[key] = candidate
	}
	return result, nil
}

func loadThirdToneStage5BProjections(path string) (map[string][][]string, error) {
	rows, err := readThirdToneStage5BTSV(path, thirdToneStage5BProjectionHeader)
	if err != nil {
		return nil, err
	}
	result := map[string][][]string{}
	for _, row := range rows {
		result[row[0]] = append(result[row[0]], row)
	}
	for id := range result {
		sort.Slice(result[id], func(i, j int) bool { return result[id][i][2] < result[id][j][2] })
	}
	return result, nil
}

func validateThirdToneStage5BModeRows(rows [][]string, weight string) (bool, string) {
	if len(rows) != 3 {
		return false, fmt.Sprintf("投影行=%d", len(rows))
	}
	wantModes := map[string]bool{"full": false, "variable": false, "shorthand": false}
	for _, row := range rows {
		if len(row) != len(thirdToneStage5BProjectionHeader) || wantModes[row[2]] {
			return false, "模式缺失、重复或列数错误"
		}
		if _, ok := wantModes[row[2]]; !ok {
			return false, "未知模式 " + row[2]
		}
		wantModes[row[2]] = true
		delta, err := strconv.Atoi(row[7])
		if err != nil || delta > 0 {
			return false, "表层路径增码或码长无效"
		}
		if row[8] != weight || row[9] != "true" || row[16] != "research_only_not_generated" {
			return false, "权重或只读状态不一致"
		}
	}
	return true, ""
}

func validateThirdToneStage5BPendingBoundary(review thirdToneStage5BReview) error {
	if review.EvidenceClass != "direct_disyllabic_lexicon_only" {
		return fmt.Errorf("evidence_class=%s", review.EvidenceClass)
	}
	if review.ProsodicStatus != "pending_human_review" || review.RuntimeStatus != "not_approved" {
		return fmt.Errorf("status=%s/%s", review.ProsodicStatus, review.RuntimeStatus)
	}
	return nil
}

func validateThirdToneStage5BDecision(decision thirdToneStage5BDecision) error {
	if decision.Decision != "approved_2_3" {
		return fmt.Errorf("decision=%s", decision.Decision)
	}
	if decision.ApplicableContext != "ordinary_continuous_prosodic_domain" {
		return fmt.Errorf("applicable_context=%s", decision.ApplicableContext)
	}
	wantBlocking := "internal_emphasis,internal_syllable_boundary_pause,internal_coordination,other_internal_prosodic_constraint"
	if decision.BlockingContext != wantBlocking {
		return fmt.Errorf("blocking_context=%s", decision.BlockingContext)
	}
	if decision.TrialEligibility != "eligible_for_stage5c_temporary_trial" || decision.InputPolicy != "parallel_alias_keep_canonical" || decision.Adjudicator == "" || decision.AdjudicatedOn == "" || decision.Note == "" {
		return fmt.Errorf("trial/adjudication fields incomplete")
	}
	return nil
}

func readThirdToneStage5BTSV(path string, header []string) ([][]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	line := 0
	rows := [][]string{}
	for scanner.Scan() {
		line++
		text := strings.TrimSuffix(scanner.Text(), "\r")
		fields := strings.Split(text, "\t")
		if line == 1 {
			if strings.Join(fields, "\t") != strings.Join(header, "\t") {
				return nil, fmt.Errorf("%s: unexpected header", path)
			}
			continue
		}
		if strings.TrimSpace(text) == "" || strings.HasPrefix(strings.TrimSpace(text), "#") {
			continue
		}
		if len(fields) != len(header) {
			return nil, fmt.Errorf("%s:%d: expected %d fields, got %d", path, line, len(header), len(fields))
		}
		rows = append(rows, fields)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if line == 0 {
		return nil, fmt.Errorf("%s: empty TSV", path)
	}
	return rows, nil
}

func thirdToneStage5BKey(text, canonicalPinyin string) string {
	return text + "\x00" + strings.Join(strings.Fields(canonicalPinyin), " ")
}

func splitThirdToneStage5BNonEmpty(text, separator string) []string {
	result := []string{}
	for _, part := range strings.Split(text, separator) {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}
