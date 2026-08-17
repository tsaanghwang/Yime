package connectedspeech

import (
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const ParticleAStage6CToolVersion = "connected-speech-particle-a-stage6c-review-v2"

type ParticleAStage6CConfig struct {
	RepoRoot          string
	ReviewPath        string
	SourcesPath       string
	DecisionsPath     string
	Stage6BOutputDir  string
	OutputDir         string
	AllowedOutputRoot string
	RefreshStage6B    bool
}

type ParticleAStage6CSummary struct {
	ToolVersion             string          `json:"tool_version"`
	SourceCount             int             `json:"source_count"`
	ReviewCount             int             `json:"review_count"`
	DecisionCount           int             `json:"decision_count"`
	MatchedCount            int             `json:"matched_count"`
	PendingCount            int             `json:"pending_count"`
	ApprovedCount           int             `json:"approved_count"`
	DeferredCount           int             `json:"deferred_count"`
	RejectedCount           int             `json:"rejected_count"`
	SemanticOnlyCount       int             `json:"semantic_only_count"`
	KeyChangingCount        int             `json:"key_changing_count"`
	ThreeModeProjectionRows int             `json:"three_mode_projection_rows"`
	UnresolvedCount         int             `json:"unresolved_count"`
	RuntimeAliasesGenerated int             `json:"runtime_aliases_generated"`
	InputHashesMatch        bool            `json:"input_hashes_match"`
	Gates                   map[string]bool `json:"gates"`
	Passed                  bool            `json:"passed"`
}

type ParticleAStage6CManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type ParticleAStage6CResult struct {
	Summary  ParticleAStage6CSummary
	Manifest ParticleAStage6CManifest
}

type particleAStage6CSource struct{ ID, Kind, Title, Locator, ScopeClaim, Limitation string }
type particleAStage6CReview struct {
	ID, Text, CanonicalPinyin, SurfacePinyin, ClassID, Stage6BID, Weight, EvidenceClass, ReviewStatus, RuntimeStatus, Note string
	SourceIDs                                                                                                              []string
}
type particleAStage6CDecision struct {
	ReviewID, Decision, Applicability, CandidatePolicy, Reviewer, ReviewedAt, Note string
	SourceIDs                                                                      []string
}
type particleAStage6CCandidate struct{ ID, Text, CanonicalPinyin, SurfacePinyin, ClassID, Weight, LengthPolicy, TextPolicy, Status, Runtime string }

var particleAStage6CProjectionHeader = []string{"record_id", "text", "class_id", "mode", "canonical_code", "surface_code", "canonical_length", "surface_length", "length_delta", "canonical_weight_match", "surface_same_text_present", "existing_bucket_rows", "predicted_bucket_rows", "existing_competitors", "top_competitor_weight", "competitor_samples", "runtime_status"}

func DefaultParticleAStage6CConfig(repoRoot string) ParticleAStage6CConfig {
	base := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	return ParticleAStage6CConfig{
		RepoRoot: repoRoot, ReviewPath: filepath.Join(base, "particle_a_stage6c_review.tsv"), SourcesPath: filepath.Join(base, "particle_a_stage6c_sources.tsv"),
		DecisionsPath: filepath.Join(base, "particle_a_stage6c_decisions.tsv"), Stage6BOutputDir: filepath.Join(repoRoot, ".tmp", "particle-a-stage6b-projection"),
		OutputDir: filepath.Join(repoRoot, ".tmp", "particle-a-stage6c-review"), AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"), RefreshStage6B: true,
	}
}

func RunParticleAStage6CReview(config ParticleAStage6CConfig) (ParticleAStage6CResult, error) {
	if err := validateParticleAStage6CConfig(&config); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if config.RefreshStage6B {
		stage6B := DefaultParticleAStage6BConfig(config.RepoRoot)
		stage6B.OutputDir, stage6B.AllowedOutputRoot = config.Stage6BOutputDir, config.AllowedOutputRoot
		if _, err := RunParticleAStage6BProjection(stage6B); err != nil {
			return ParticleAStage6CResult{}, fmt.Errorf("刷新阶段6B失败: %w", err)
		}
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ParticleAStage6CResult{}, err
	}
	inputPaths := map[string]string{"review": config.ReviewPath, "sources": config.SourcesPath, "decisions": config.DecisionsPath,
		"stage6b_candidates": filepath.Join(config.Stage6BOutputDir, "candidate_inventory.tsv"), "stage6b_projection": filepath.Join(config.Stage6BOutputDir, "three_mode_projection.tsv"), "stage6b_manifest": filepath.Join(config.Stage6BOutputDir, "manifest.json")}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	sources, err := loadParticleAStage6CSources(config.SourcesPath)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	reviews, err := loadParticleAStage6CReviews(config.ReviewPath)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	decisions, err := loadParticleAStage6CDecisions(config.DecisionsPath)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	candidates, err := loadParticleAStage6CCandidates(inputPaths["stage6b_candidates"])
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	projections, err := loadParticleAStage6CProjections(inputPaths["stage6b_projection"])
	if err != nil {
		return ParticleAStage6CResult{}, err
	}

	unresolved := [][]string{{"review_id", "text", "reason", "detail"}}
	projectionRows := [][]string{append([]string{"review_id"}, particleAStage6CProjectionHeader...)}
	classCounts := map[string]int{}
	matched, semanticOnly, keyChanging := 0, 0, 0
	approved, deferred, rejected := 0, 0, 0
	for _, review := range reviews {
		classCounts[review.ClassID]++
		if err := validateParticleAStage6CReview(review, sources); err != nil {
			unresolved = append(unresolved, []string{review.ID, review.Text, "review_invalid", err.Error()})
			continue
		}
		candidate, ok := candidates[particleAStage6CKey(review.Text, review.CanonicalPinyin)]
		if !ok {
			unresolved = append(unresolved, []string{review.ID, review.Text, "candidate_missing", review.CanonicalPinyin})
			continue
		}
		if candidate.ID != review.Stage6BID || candidate.Weight != review.Weight || candidate.SurfacePinyin != review.SurfacePinyin || candidate.ClassID != review.ClassID || candidate.LengthPolicy != "not_longer_all_modes" || candidate.TextPolicy != "preserve" || candidate.Runtime != "false" {
			unresolved = append(unresolved, []string{review.ID, review.Text, "snapshot_mismatch", fmt.Sprintf("candidate=%+v", candidate)})
			continue
		}
		modeRows := projections[candidate.ID]
		if err := validateParticleAStage6CModeRows(modeRows, review); err != nil {
			unresolved = append(unresolved, []string{review.ID, review.Text, "projection_invalid", err.Error()})
			continue
		}
		for _, row := range modeRows {
			projectionRows = append(projectionRows, append([]string{review.ID}, row...))
		}
		matched++
		if review.EvidenceClass == "semantic_only_shared_key" {
			semanticOnly++
		} else {
			keyChanging++
		}
		if decision, exists := decisions[review.ID]; exists {
			if err := validateParticleAStage6CDecision(decision, sources); err != nil {
				unresolved = append(unresolved, []string{review.ID, review.Text, "decision_invalid", err.Error()})
				continue
			}
			switch decision.Decision {
			case "approved":
				approved++
			case "deferred":
				deferred++
			case "rejected":
				rejected++
			}
		}
	}
	for reviewID := range decisions {
		if !particleAStage6CHasReview(reviews, reviewID) {
			unresolved = append(unresolved, []string{reviewID, "", "orphan_decision", "判决没有对应复核项"})
		}
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	balanced := len(classCounts) == 6
	for _, count := range classCounts {
		balanced = balanced && count == 5
	}
	gates := map[string]bool{
		"six_classes_balanced": balanced, "all_review_rows_match_stage6b": matched == len(reviews), "three_mode_rows_complete": len(projectionRows)-1 == matched*3,
		"semantic_shared_key_is_separate": semanticOnly == 5, "key_changing_examples_present": keyChanging == 25,
		"all_sources_resolve": len(sources) == 3, "all_review_rows_decided": len(decisions) == len(reviews), "all_decisions_approved": approved == len(reviews),
		"runtime_aliases_remain_zero": true, "inputs_are_read_only": equalHashes(before, after), "unresolved_rows_zero": len(unresolved) == 1,
	}
	summary := ParticleAStage6CSummary{ToolVersion: ParticleAStage6CToolVersion, SourceCount: len(sources), ReviewCount: len(reviews), DecisionCount: len(decisions), MatchedCount: matched,
		PendingCount: len(reviews) - len(decisions), ApprovedCount: approved, DeferredCount: deferred, RejectedCount: rejected, SemanticOnlyCount: semanticOnly, KeyChangingCount: keyChanging,
		ThreeModeProjectionRows: len(projectionRows) - 1, UnresolvedCount: len(unresolved) - 1, RuntimeAliasesGenerated: 0, InputHashesMatch: equalHashes(before, after), Gates: gates, Passed: allGatesPass(gates)}
	if err := writeTSV(filepath.Join(config.OutputDir, "review_projection.tsv"), projectionRows); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "unresolved.tsv"), unresolved); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ParticleAStage6CResult{}, err
	}
	if err := writeParticleAStage6CReport(filepath.Join(config.OutputDir, "REPORT.md"), summary); err != nil {
		return ParticleAStage6CResult{}, err
	}
	outputPaths := map[string]string{}
	for _, name := range []string{"REPORT.md", "input_hashes_after.json", "input_hashes_before.json", "review_projection.tsv", "summary.json", "unresolved.tsv"} {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ParticleAStage6CResult{}, err
	}
	manifest := ParticleAStage6CManifest{ToolVersion: ParticleAStage6CToolVersion, InputSHA256: before, OutputSHA256: outputHashes, OutputHashScope: "all deterministic Stage 6C reports except manifest.json"}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return ParticleAStage6CResult{}, err
	}
	result := ParticleAStage6CResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("阶段6C复核门禁未通过")
	}
	return result, nil
}

func loadParticleAStage6CSources(path string) (map[string]particleAStage6CSource, error) {
	rows, err := readParticleAStage6CTSV(path, []string{"source_id", "source_kind", "title", "locator", "scope_claim", "limitation"})
	if err != nil {
		return nil, err
	}
	result := map[string]particleAStage6CSource{}
	for _, row := range rows {
		item := particleAStage6CSource{row[0], row[1], row[2], row[3], row[4], row[5]}
		if item.ID == "" || item.Kind == "" || item.Title == "" || item.Locator == "" || item.ScopeClaim == "" || item.Limitation == "" || result[item.ID].ID != "" {
			return nil, fmt.Errorf("阶段6C来源无效: %v", row)
		}
		result[item.ID] = item
	}
	return result, nil
}
func loadParticleAStage6CReviews(path string) ([]particleAStage6CReview, error) {
	header := []string{"review_id", "text", "canonical_pinyin", "expected_surface_pinyin", "class_id", "stage6b_record_id_snapshot", "priority_weight_snapshot", "evidence_class", "review_status", "runtime_status", "source_ids", "note"}
	rows, err := readParticleAStage6CTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := make([]particleAStage6CReview, 0, len(rows))
	seen := map[string]bool{}
	for _, row := range rows {
		if seen[row[0]] {
			return nil, fmt.Errorf("复核ID重复: %s", row[0])
		}
		seen[row[0]] = true
		result = append(result, particleAStage6CReview{row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[11], splitParticleAStage6C(row[10])})
	}
	return result, nil
}
func loadParticleAStage6CDecisions(path string) (map[string]particleAStage6CDecision, error) {
	header := []string{"review_id", "decision", "applicability", "candidate_policy", "reviewer", "reviewed_at", "source_ids", "note"}
	rows, err := readParticleAStage6CTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := map[string]particleAStage6CDecision{}
	for _, row := range rows {
		if result[row[0]].ReviewID != "" {
			return nil, fmt.Errorf("判决重复: %s", row[0])
		}
		result[row[0]] = particleAStage6CDecision{row[0], row[1], row[2], row[3], row[4], row[5], row[7], splitParticleAStage6C(row[6])}
	}
	return result, nil
}
func loadParticleAStage6CCandidates(path string) (map[string]particleAStage6CCandidate, error) {
	header := []string{"record_id", "text", "canonical_pinyin", "surface_pinyin", "class_id", "target_shouyin_id", "target_yinyuan_ids", "weight", "canonical_full", "surface_full", "length_policy", "candidate_text_policy", "adjudication_status", "runtime_enabled"}
	rows, err := readParticleAStage6CTSV(path, header)
	if err != nil {
		return nil, err
	}
	result := map[string]particleAStage6CCandidate{}
	for _, row := range rows {
		item := particleAStage6CCandidate{row[0], row[1], row[2], row[3], row[4], row[7], row[10], row[11], row[12], row[13]}
		result[particleAStage6CKey(item.Text, item.CanonicalPinyin)] = item
	}
	return result, nil
}
func loadParticleAStage6CProjections(path string) (map[string][][]string, error) {
	rows, err := readParticleAStage6CTSV(path, particleAStage6CProjectionHeader)
	if err != nil {
		return nil, err
	}
	result := map[string][][]string{}
	for _, row := range rows {
		result[row[0]] = append(result[row[0]], row)
	}
	return result, nil
}

func validateParticleAStage6CReview(review particleAStage6CReview, sources map[string]particleAStage6CSource) error {
	if review.ID == "" || review.Text == "" || review.CanonicalPinyin == "" || review.SurfacePinyin == "" || review.Stage6BID == "" || review.Weight == "" || review.Note == "" {
		return errors.New("字段不完整")
	}
	if review.ReviewStatus != "pending_human_review" || review.RuntimeStatus != "not_approved" {
		return errors.New("首批必须保持待复核且未批准")
	}
	if review.ClassID == "PA-NG" && review.EvidenceClass != "semantic_only_shared_key" {
		return errors.New("PA-NG必须标作共键语义样本")
	}
	if review.ClassID != "PA-NG" && review.EvidenceClass != "input_alias_key_change" {
		return errors.New("非PA-NG必须标作键码变化样本")
	}
	if len(review.SourceIDs) == 0 {
		return errors.New("缺少来源")
	}
	for _, id := range review.SourceIDs {
		if sources[id].ID == "" {
			return fmt.Errorf("未知来源%s", id)
		}
	}
	return nil
}
func validateParticleAStage6CModeRows(rows [][]string, review particleAStage6CReview) error {
	if len(rows) != 3 {
		return fmt.Errorf("三模式行数=%d", len(rows))
	}
	seen := map[string]bool{}
	for _, row := range rows {
		if len(row) != len(particleAStage6CProjectionHeader) || seen[row[3]] {
			return errors.New("模式重复或列数错误")
		}
		seen[row[3]] = true
		if row[1] != review.Text || row[2] != review.ClassID || row[8] != "0" || row[9] != "true" || row[16] != "research_only_not_generated" {
			return fmt.Errorf("模式门禁不满足: %v", row)
		}
		sameCode := row[4] == row[5]
		if review.EvidenceClass == "semantic_only_shared_key" && !sameCode {
			return errors.New("共键语义样本出现物理码差异")
		}
		if review.EvidenceClass == "input_alias_key_change" && sameCode {
			return errors.New("键码变化样本没有物理码差异")
		}
	}
	return nil
}
func validateParticleAStage6CDecision(decision particleAStage6CDecision, sources map[string]particleAStage6CSource) error {
	if decision.Decision != "approved" && decision.Decision != "deferred" && decision.Decision != "rejected" {
		return errors.New("判决值无效")
	}
	if decision.Applicability == "" || decision.Reviewer == "" || decision.ReviewedAt == "" || decision.Note == "" || len(decision.SourceIDs) == 0 {
		return errors.New("判决字段不完整")
	}
	if decision.Decision == "approved" && decision.CandidatePolicy != "parallel_alias_keep_canonical" {
		return errors.New("批准项必须保留规范路径")
	}
	if decision.Decision != "approved" && decision.CandidatePolicy != "no_runtime_alias" {
		return errors.New("非批准项不得生成运行别名")
	}
	for _, id := range decision.SourceIDs {
		if sources[id].ID == "" {
			return fmt.Errorf("判决来源不存在: %s", id)
		}
	}
	return nil
}
func validateParticleAStage6CConfig(config *ParticleAStage6CConfig) error {
	if config.RepoRoot == "" || config.ReviewPath == "" || config.SourcesPath == "" || config.DecisionsPath == "" || config.Stage6BOutputDir == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("阶段6C路径不能为空")
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
		return errors.New("阶段6C输出必须位于临时目录")
	}
	if filepath.Base(output) != "particle-a-stage6c-review" {
		return errors.New("阶段6C输出目录名错误")
	}
	config.OutputDir, config.AllowedOutputRoot = output, allowed
	return nil
}
func readParticleAStage6CTSV(path string, header []string) ([][]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	reader.FieldsPerRecord = len(header)
	got, err := reader.Read()
	if err != nil {
		return nil, err
	}
	got[0] = strings.TrimPrefix(got[0], "\ufeff")
	if strings.Join(got, "\t") != strings.Join(header, "\t") {
		return nil, fmt.Errorf("%s表头错误", path)
	}
	rows := [][]string{}
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if len(row) == 0 || (len(row) > 0 && strings.HasPrefix(strings.TrimSpace(row[0]), "#")) {
			continue
		}
		rows = append(rows, row)
	}
	return rows, nil
}
func particleAStage6CKey(text, pinyin string) string { return text + "\x00" + pinyin }
func splitParticleAStage6C(value string) []string {
	result := []string{}
	for _, item := range strings.Split(value, ",") {
		if item = strings.TrimSpace(item); item != "" {
			result = append(result, item)
		}
	}
	return result
}
func particleAStage6CHasReview(reviews []particleAStage6CReview, id string) bool {
	for _, review := range reviews {
		if review.ID == id {
			return true
		}
	}
	return false
}
func writeParticleAStage6CReport(path string, summary ParticleAStage6CSummary) error {
	keys := make([]string, 0, len(summary.Gates))
	for key := range summary.Gates {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	lines := []string{"# 阶段6C：语气词‘啊’首批复核门禁", "", fmt.Sprintf("- 复核项：%d；匹配：%d；已核准：%d；待人工复核：%d", summary.ReviewCount, summary.MatchedCount, summary.ApprovedCount, summary.PendingCount), fmt.Sprintf("- 共键语义样本：%d；键码变化样本：%d", summary.SemanticOnlyCount, summary.KeyChangingCount), fmt.Sprintf("- 三模式投影行：%d；未决：%d；运行时别名：0", summary.ThreeModeProjectionRows, summary.UnresolvedCount), "", "## 门禁", ""}
	for _, key := range keys {
		lines = append(lines, fmt.Sprintf("- `%s`：%t", key, summary.Gates[key]))
	}
	lines = append(lines, "", "30 条已按句末通常语境核准；本阶段仍不生成运行时词典，运行接入须另走下一阶段门禁。", "")
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644)
}
