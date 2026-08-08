package connectedspeech

import (
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

var baselineDataFiles = []string{
	"yime_pinyin_codes.tsv",
	"yime_syllable_decomposition.tsv",
	"yime_yinyuan_layout.json",
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
	"yime_full.schema.yaml",
	"yime_variable.schema.yaml",
	"yime_shorthand.schema.yaml",
	"yime_lexicon_manifest.json",
	"yime_runtime_profile.json",
}

var deterministicReportFiles = []string{
	"baseline_hashes_before.json",
	"baseline_hashes_after.json",
	"summary.json",
	"source_coverage.tsv",
	"rewrite_review.tsv",
	"three_mode_coverage.tsv",
	"code_length.tsv",
	"collisions.tsv",
	"ranking_impact.tsv",
	"rejected_records.tsv",
}

type Config struct {
	RepoRoot          string
	RecordsPath       string
	SchemaPath        string
	DataDir           string
	DecompositionPath string
	LayoutPath        string
	OutputDir         string
	AllowedOutputRoot string
	Switches          Switches
}

func DefaultConfig(repoRoot, recordsPath string) Config {
	dataDir := filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data")
	return Config{
		RepoRoot:          repoRoot,
		RecordsPath:       recordsPath,
		SchemaPath:        filepath.Join(repoRoot, "docs", "project", "connected_speech", "connected_speech_record.schema.json"),
		DataDir:           dataDir,
		DecompositionPath: filepath.Join(dataDir, "yime_syllable_decomposition.tsv"),
		LayoutPath:        filepath.Join(dataDir, "yime_yinyuan_layout.json"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "connected-speech-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

type Summary struct {
	ToolVersion           string          `json:"tool_version"`
	SchemaVersion         int             `json:"schema_version"`
	RulesetVersion        string          `json:"ruleset_version,omitempty"`
	RecordCount           int             `json:"record_count"`
	ValidationIssueCount  int             `json:"validation_issue_count"`
	TrialRecordCount      int             `json:"trial_record_count"`
	TrialAliasCount       int             `json:"trial_alias_count"`
	IsolatedRecordCount   int             `json:"isolated_record_count"`
	CollisionCount        int             `json:"collision_count"`
	PotentialRankingCount int             `json:"potential_ranking_impact_count"`
	ActualRankingChanges  int             `json:"actual_ranking_changes"`
	BaselineHashesMatch   bool            `json:"baseline_hashes_match"`
	Passed                bool            `json:"passed"`
	Gates                 map[string]bool `json:"gates"`
}

type Manifest struct {
	ToolVersion          string            `json:"tool_version"`
	SchemaVersion        int               `json:"schema_version"`
	RulesetVersion       string            `json:"ruleset_version,omitempty"`
	LayoutDigest         string            `json:"layout_digest"`
	ModeTransformVersion string            `json:"mode_transform_version"`
	Switches             Switches          `json:"switches"`
	InputSHA256          map[string]string `json:"input_sha256"`
	OutputSHA256         map[string]string `json:"output_sha256"`
	OutputHashScope      string            `json:"output_hash_scope"`
}

type AuditResult struct {
	Summary  Summary
	Manifest Manifest
	Issues   []Issue
}

type trialProjection struct {
	RecordID        string
	Text            string
	Phenomenon      string
	PathKind        string
	Canonical       codemode.Record
	Trial           codemode.Record
	IsAlias         bool
	CandidatePolicy string
}

type dictionaryCandidate struct {
	Text   string `json:"text"`
	Weight int    `json:"weight"`
}

func RunAudit(config Config) (AuditResult, error) {
	if err := validateConfig(&config); err != nil {
		return AuditResult{}, err
	}
	if err := ValidateSchemaDocument(config.SchemaPath); err != nil {
		return AuditResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return AuditResult{}, err
	}

	before, err := hashBaseline(config.DataDir)
	if err != nil {
		return AuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_before.json"), before); err != nil {
		return AuditResult{}, err
	}

	records, err := LoadRecords(config.RecordsPath)
	if err != nil {
		return AuditResult{}, err
	}
	inventory, err := LoadInventory(config.DecompositionPath)
	if err != nil {
		return AuditResult{}, err
	}
	profile, err := layoutdesigner.LoadProfile(config.LayoutPath)
	if err != nil {
		return AuditResult{}, fmt.Errorf("读取音元布局: %w", err)
	}
	issues := ValidateRecords(records, inventory)
	issuesByRecord := map[string]bool{}
	for _, issue := range issues {
		issuesByRecord[issue.RecordID] = true
	}

	projections := make([]trialProjection, 0, len(records))
	rejectedRows := [][]string{{"record_id", "adjudication_status", "reason", "detail"}}
	isolatedCount := 0
	trialAliasCount := 0
	lengthProjectionOK := true
	for _, record := range records {
		if issuesByRecord[record.RecordID] {
			rejectedRows = append(rejectedRows, []string{record.RecordID, record.AdjudicationStatus, "validation_failed", "结构或语义校验失败"})
			continue
		}
		sequence, pathKind, reason := selectTrialSequence(record, config.Switches)
		if reason != "" {
			if isolatedStatuses[record.AdjudicationStatus] {
				isolatedCount++
			}
			rejectedRows = append(rejectedRows, []string{record.RecordID, record.AdjudicationStatus, reason, trialReasonDetail(reason)})
			continue
		}
		canonical, err := projectSequence(record.CanonicalYinyuanIDs, profile)
		if err != nil {
			issues = append(issues, Issue{RecordID: record.RecordID, Field: "canonical_yinyuan_ids", Code: "projection_failed", Detail: err.Error()})
			rejectedRows = append(rejectedRows, []string{record.RecordID, record.AdjudicationStatus, "projection_failed", err.Error()})
			continue
		}
		trial, err := projectSequence(sequence, profile)
		if err != nil {
			issues = append(issues, Issue{RecordID: record.RecordID, Field: pathKind + "_yinyuan_ids", Code: "projection_failed", Detail: err.Error()})
			rejectedRows = append(rejectedRows, []string{record.RecordID, record.AdjudicationStatus, "projection_failed", err.Error()})
			continue
		}
		projectionOK := modeLengthProjectionValid(canonical, trial)
		lengthProjectionOK = lengthProjectionOK && projectionOK
		isAlias := canonical.FullSpelling != trial.FullSpelling || canonical.VariableSpelling != trial.VariableSpelling || canonical.ShorthandSpelling != trial.ShorthandSpelling
		if isAlias {
			trialAliasCount++
		}
		projections = append(projections, trialProjection{
			RecordID: record.RecordID, Text: record.Text, Phenomenon: record.Phenomenon,
			PathKind: pathKind, Canonical: canonical, Trial: trial, IsAlias: isAlias,
			CandidatePolicy: record.CandidateTextPolicy,
		})
	}
	sort.Slice(projections, func(i, j int) bool { return projections[i].RecordID < projections[j].RecordID })
	sort.Slice(rejectedRows[1:], func(i, j int) bool {
		return rejectedRows[i+1][0]+rejectedRows[i+1][2] < rejectedRows[j+1][0]+rejectedRows[j+1][2]
	})

	coverageRows := buildCoverageRows(projections)
	lengthRows := buildLengthRows(projections)
	sourceRows := buildSourceRows(records)
	rewriteRows := buildRewriteRows(records)
	collisionRows, rankingRows, collisionCount, potentialRankingCount, err := analyzeDictionaries(config.DataDir, projections)
	if err != nil {
		return AuditResult{}, err
	}

	if err := writeTSV(filepath.Join(config.OutputDir, "source_coverage.tsv"), sourceRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "rewrite_review.tsv"), rewriteRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "three_mode_coverage.tsv"), coverageRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "code_length.tsv"), lengthRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "collisions.tsv"), collisionRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "ranking_impact.tsv"), rankingRows); err != nil {
		return AuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "rejected_records.tsv"), rejectedRows); err != nil {
		return AuditResult{}, err
	}

	after, err := hashBaseline(config.DataDir)
	if err != nil {
		return AuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_after.json"), after); err != nil {
		return AuditResult{}, err
	}
	baselineMatch := equalHashes(before, after)
	rulesetVersion := ""
	if len(records) > 0 {
		rulesetVersion = records[0].RulesetVersion
	}
	summary := Summary{
		ToolVersion: ToolVersion, SchemaVersion: SchemaVersion, RulesetVersion: rulesetVersion,
		RecordCount: len(records), ValidationIssueCount: len(issues), TrialRecordCount: len(projections),
		TrialAliasCount: trialAliasCount, IsolatedRecordCount: isolatedCount, CollisionCount: collisionCount,
		PotentialRankingCount: potentialRankingCount, ActualRankingChanges: 0, BaselineHashesMatch: baselineMatch,
		Gates: map[string]bool{
			"structure_valid":              len(issues) == 0,
			"three_mode_coverage_complete": len(coverageRows)-1 == len(projections)*3,
			"mode_length_projection_valid": lengthProjectionOK,
			"isolated_runtime_output_zero": true,
			"actual_ranking_unchanged":     true,
			"baseline_hashes_match":        baselineMatch,
		},
	}
	summary.Passed = allGatesPass(summary.Gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return AuditResult{}, err
	}

	layoutDigest, err := profile.Digest()
	if err != nil {
		return AuditResult{}, err
	}
	inputHashes, err := hashNamedFiles(map[string]string{
		"records":                config.RecordsPath,
		"schema":                 config.SchemaPath,
		"syllable_decomposition": config.DecompositionPath,
		"layout":                 config.LayoutPath,
	})
	if err != nil {
		return AuditResult{}, err
	}
	outputHashes, err := hashReportFiles(config.OutputDir)
	if err != nil {
		return AuditResult{}, err
	}
	manifest := Manifest{
		ToolVersion: ToolVersion, SchemaVersion: SchemaVersion, RulesetVersion: rulesetVersion,
		LayoutDigest: layoutDigest, ModeTransformVersion: codemode.LayoutVersion, Switches: config.Switches,
		InputSHA256: inputHashes, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic report files except manifest.json (self-hash excluded)",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return AuditResult{}, err
	}
	result := AuditResult{Summary: summary, Manifest: manifest, Issues: issues}
	if !summary.Passed {
		return result, fmt.Errorf("语流音变离线审计未通过：结构问题 %d，基线一致=%t，三模式投影有效=%t", len(issues), baselineMatch, lengthProjectionOK)
	}
	return result, nil
}

func validateConfig(config *Config) error {
	if config.RepoRoot == "" || config.RecordsPath == "" || config.DataDir == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("RepoRoot、RecordsPath、DataDir、OutputDir 和 AllowedOutputRoot 均不能为空")
	}
	if config.DecompositionPath == "" {
		config.DecompositionPath = filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv")
	}
	if config.LayoutPath == "" {
		config.LayoutPath = filepath.Join(config.DataDir, "yime_yinyuan_layout.json")
	}
	if config.SchemaPath == "" {
		return errors.New("SchemaPath 不能为空")
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
		return fmt.Errorf("输出目录必须严格位于允许的临时根目录内：%s", allowed)
	}
	if filepath.Base(output) != "connected-speech-audit" {
		return fmt.Errorf("阶段 0 输出目录名必须是 connected-speech-audit：%s", output)
	}
	config.AllowedOutputRoot = allowed
	config.OutputDir = output
	return nil
}

func prepareOutputDir(path string) error {
	if err := os.RemoveAll(path); err != nil {
		return fmt.Errorf("清理旧离线报告 %s: %w", path, err)
	}
	return os.MkdirAll(path, 0o755)
}

func selectTrialSequence(record Record, switches Switches) (YinyuanSequence, string, string) {
	if isolatedStatuses[record.AdjudicationStatus] {
		return nil, "", "isolated_status"
	}
	if !switches.Enabled {
		return nil, "", "all_modules_disabled"
	}
	if !record.RuntimeEnabled {
		return nil, "", "record_disabled"
	}
	if !moduleEnabled(record, switches) {
		return nil, "", "phenomenon_module_disabled"
	}
	switch record.AdjudicationStatus {
	case "approved_compatibility":
		if record.CompatibilityYinyuanIDs == nil {
			return nil, "", "missing_trial_path"
		}
		return *record.CompatibilityYinyuanIDs, "compatibility", ""
	case "approved_surface", "experimental":
		if record.SurfaceYinyuanIDs != nil {
			return *record.SurfaceYinyuanIDs, "surface", ""
		}
		if record.CompatibilityYinyuanIDs != nil {
			return *record.CompatibilityYinyuanIDs, "compatibility", ""
		}
		return nil, "", "missing_trial_path"
	default:
		return nil, "", "status_not_trialable"
	}
}

func moduleEnabled(record Record, switches Switches) bool {
	switch record.Phenomenon {
	case "tone_sandhi":
		return switches.ToneSandhi
	case "neutral_tone":
		return switches.NeutralToneSurface
	case "erhua":
		if record.ErhuaStatus == "fused" {
			return switches.ErhuaFused
		}
		return switches.ErhuaSuffixCompatibility
	case "particle_allomorphy":
		return switches.ParticleAllomorphy
	case "assimilation":
		return switches.Assimilation
	case "dissimilation":
		return switches.Dissimilation
	default:
		return false
	}
}

func trialReasonDetail(reason string) string {
	details := map[string]string{
		"validation_failed":          "结构或语义校验失败，未进行试算",
		"isolated_status":            "research_only、deferred 或 rejected 必须隔离",
		"all_modules_disabled":       "总开关关闭",
		"record_disabled":            "记录自身未获试算启用",
		"phenomenon_module_disabled": "现象模块关闭",
		"missing_trial_path":         "没有经过审定的兼容或表层四音元路径",
		"status_not_trialable":       "审定状态不允许试算",
	}
	return details[reason]
}

func projectSequence(sequence YinyuanSequence, profile layoutdesigner.Profile) (codemode.Record, error) {
	ids := make([]string, 0, len(sequence)*4)
	for _, tuple := range sequence {
		ids = append(ids, tuple[:]...)
	}
	full, err := layoutdesigner.ProjectIDs(ids, profile)
	if err != nil {
		return codemode.Record{}, err
	}
	return layoutdesigner.ReencodeRecord(full, profile, profile)
}

func modeLengthProjectionValid(canonical, trial codemode.Record) bool {
	if err := codemode.ValidateContinuousInputRecord(canonical); err != nil {
		return false
	}
	if err := codemode.ValidateContinuousInputRecord(trial); err != nil {
		return false
	}
	canonicalFull := codeLength(canonical.FullSpelling)
	trialFull := codeLength(trial.FullSpelling)
	if canonicalFull == 0 || canonicalFull%codemode.SyllableCodeLength != 0 || trialFull != canonicalFull {
		return false
	}
	syllables := canonicalFull / codemode.SyllableCodeLength
	return fixedSyllableLengthsValid(canonical.FullSpelling, syllables) &&
		fixedSyllableLengthsValid(trial.FullSpelling, syllables) &&
		projectedSyllableLengthsValid(canonical.VariableSpelling, syllables) &&
		projectedSyllableLengthsValid(canonical.ShorthandSpelling, syllables) &&
		projectedSyllableLengthsValid(trial.VariableSpelling, syllables) &&
		projectedSyllableLengthsValid(trial.ShorthandSpelling, syllables)
}

func fixedSyllableLengthsValid(spelling string, wantSyllables int) bool {
	parts := strings.Fields(spelling)
	if len(parts) != wantSyllables {
		return false
	}
	for _, part := range parts {
		if utf8.RuneCountInString(part) != codemode.SyllableCodeLength {
			return false
		}
	}
	return true
}

func projectedSyllableLengthsValid(spelling string, wantSyllables int) bool {
	parts := strings.Fields(spelling)
	if len(parts) != wantSyllables {
		return false
	}
	for _, part := range parts {
		length := utf8.RuneCountInString(part)
		if length < 2 || length > codemode.SyllableCodeLength {
			return false
		}
	}
	return true
}

func codeLength(code string) int {
	return utf8.RuneCountInString(strings.ReplaceAll(code, " ", ""))
}

func buildCoverageRows(projections []trialProjection) [][]string {
	rows := [][]string{{"record_id", "text", "phenomenon", "path_kind", "mode", "canonical_code", "trial_code", "is_alias"}}
	for _, projection := range projections {
		for _, mode := range []struct{ name, canonical, trial string }{
			{"full", projection.Canonical.FullSpelling, projection.Trial.FullSpelling},
			{"variable", projection.Canonical.VariableSpelling, projection.Trial.VariableSpelling},
			{"shorthand", projection.Canonical.ShorthandSpelling, projection.Trial.ShorthandSpelling},
		} {
			rows = append(rows, []string{projection.RecordID, projection.Text, projection.Phenomenon, projection.PathKind, mode.name, mode.canonical, mode.trial, fmt.Sprint(mode.canonical != mode.trial)})
		}
	}
	return rows
}

func buildLengthRows(projections []trialProjection) [][]string {
	rows := [][]string{{"record_id", "mode", "canonical_length", "trial_length", "canonical_syllable_lengths", "trial_syllable_lengths", "delta", "relation", "projection_valid"}}
	for _, projection := range projections {
		fullLength := codeLength(projection.Canonical.FullSpelling)
		syllables := fullLength / codemode.SyllableCodeLength
		for _, mode := range []struct{ name, canonical, trial string }{
			{"full", projection.Canonical.FullSpelling, projection.Trial.FullSpelling},
			{"variable", projection.Canonical.VariableSpelling, projection.Trial.VariableSpelling},
			{"shorthand", projection.Canonical.ShorthandSpelling, projection.Trial.ShorthandSpelling},
		} {
			canonicalLength, trialLength := codeLength(mode.canonical), codeLength(mode.trial)
			delta := trialLength - canonicalLength
			relation := "unchanged"
			if delta > 0 {
				relation = "increased"
			} else if delta < 0 {
				relation = "decreased"
			}
			valid := fixedSyllableLengthsValid(mode.trial, syllables)
			if mode.name != "full" {
				valid = projectedSyllableLengthsValid(mode.trial, syllables)
			}
			rows = append(rows, []string{
				projection.RecordID, mode.name, fmt.Sprint(canonicalLength), fmt.Sprint(trialLength),
				syllableLengths(mode.canonical), syllableLengths(mode.trial), fmt.Sprint(delta), relation, fmt.Sprint(valid),
			})
		}
	}
	return rows
}

func syllableLengths(spelling string) string {
	parts := strings.Fields(spelling)
	lengths := make([]string, 0, len(parts))
	for _, part := range parts {
		lengths = append(lengths, fmt.Sprint(utf8.RuneCountInString(part)))
	}
	return strings.Join(lengths, ",")
}

func buildSourceRows(records []Record) [][]string {
	rows := [][]string{{"record_id", "observation_id", "source_policy", "source_locator", "source_sha256", "transcription_status"}}
	for _, record := range records {
		for _, observation := range record.SourceObservations {
			rows = append(rows, []string{record.RecordID, observation.ObservationID, observation.SourcePolicy, observation.SourceLocator, observation.SourceSHA256, observation.TranscriptionStatus})
		}
	}
	sort.Slice(rows[1:], func(i, j int) bool { return rows[i+1][1] < rows[j+1][1] })
	return rows
}

func buildRewriteRows(records []Record) [][]string {
	rows := [][]string{{"record_id", "rule_id", "syllable_index", "position", "from_id", "to_id", "attributes"}}
	for _, record := range records {
		for _, rewrite := range record.Rewrites {
			attributes := append([]string(nil), rewrite.Attributes...)
			sort.Strings(attributes)
			rows = append(rows, []string{record.RecordID, record.RuleID, fmt.Sprint(rewrite.SyllableIndex), rewrite.Position, rewrite.FromID, rewrite.ToID, strings.Join(attributes, ",")})
		}
	}
	sort.Slice(rows[1:], func(i, j int) bool { return strings.Join(rows[i+1][:4], "\x00") < strings.Join(rows[j+1][:4], "\x00") })
	return rows
}

func analyzeDictionaries(dataDir string, projections []trialProjection) ([][]string, [][]string, int, int, error) {
	collisionRows := [][]string{{"record_id", "mode", "trial_code", "alias_candidate", "existing_candidates", "old_top", "trial_top"}}
	rankingRows := [][]string{{"record_id", "mode", "trial_code", "old_top", "trial_top", "potential_preference_change", "actual_change"}}
	collisionCount, potentialCount := 0, 0
	for _, mode := range []string{"full", "variable", "shorthand"} {
		codes := map[string]bool{}
		for _, projection := range projections {
			if projection.IsAlias {
				codes[projectionModeCode(projection, mode)] = true
			}
		}
		found := map[string][]dictionaryCandidate{}
		if len(codes) > 0 {
			path := filepath.Join(dataDir, "yime_"+mode+".dict.yaml")
			if err := systemlexicon.VisitDictFile(path, func(entry systemlexicon.Entry) error {
				if codes[entry.Code] {
					found[entry.Code] = append(found[entry.Code], dictionaryCandidate{Text: entry.Text, Weight: entry.Weight})
				}
				return nil
			}); err != nil {
				return nil, nil, 0, 0, err
			}
		}
		for _, projection := range projections {
			if !projection.IsAlias {
				continue
			}
			code := projectionModeCode(projection, mode)
			candidates := found[code]
			oldTop := ""
			if len(candidates) > 0 {
				oldTop = candidates[0].Text
			}
			trialTop := oldTop
			if trialTop == "" {
				trialTop = projection.Text
			}
			potential := oldTop != "" && oldTop != projection.Text
			if potential {
				potentialCount++
			}
			encoded, _ := json.Marshal(candidates)
			if len(candidates) > 0 {
				collisionCount++
				collisionRows = append(collisionRows, []string{projection.RecordID, mode, code, projection.Text, string(encoded), oldTop, trialTop})
			}
			rankingRows = append(rankingRows, []string{projection.RecordID, mode, code, oldTop, trialTop, fmt.Sprint(potential), "false"})
		}
	}
	sort.Slice(collisionRows[1:], func(i, j int) bool {
		return strings.Join(collisionRows[i+1][:3], "\x00") < strings.Join(collisionRows[j+1][:3], "\x00")
	})
	sort.Slice(rankingRows[1:], func(i, j int) bool {
		return strings.Join(rankingRows[i+1][:3], "\x00") < strings.Join(rankingRows[j+1][:3], "\x00")
	})
	return collisionRows, rankingRows, collisionCount, potentialCount, nil
}

func projectionModeCode(projection trialProjection, mode string) string {
	switch mode {
	case "variable":
		return projection.Trial.VariableSpelling
	case "shorthand":
		return projection.Trial.ShorthandSpelling
	default:
		return projection.Trial.FullSpelling
	}
}

func hashBaseline(dataDir string) (map[string]string, error) {
	paths := make(map[string]string, len(baselineDataFiles))
	for _, name := range baselineDataFiles {
		paths[name] = filepath.Join(dataDir, name)
	}
	return hashNamedFiles(paths)
}

func hashNamedFiles(paths map[string]string) (map[string]string, error) {
	result := make(map[string]string, len(paths))
	for name, path := range paths {
		hash, err := hashFile(path)
		if err != nil {
			return nil, fmt.Errorf("计算 %s 的 SHA-256: %w", path, err)
		}
		result[name] = hash
	}
	return result, nil
}

func hashReportFiles(outputDir string) (map[string]string, error) {
	paths := make(map[string]string, len(deterministicReportFiles))
	for _, name := range deterministicReportFiles {
		paths[name] = filepath.Join(outputDir, name)
	}
	return hashNamedFiles(paths)
}

func hashFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}

func equalHashes(left, right map[string]string) bool {
	if len(left) != len(right) {
		return false
	}
	for name, hash := range left {
		if right[name] != hash {
			return false
		}
	}
	return true
}

func allGatesPass(gates map[string]bool) bool {
	for _, passed := range gates {
		if !passed {
			return false
		}
	}
	return true
}

func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func writeTSV(path string, rows [][]string) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	writer := csv.NewWriter(file)
	writer.Comma = '\t'
	writer.UseCRLF = false
	for _, row := range rows {
		if err := writer.Write(row); err != nil {
			file.Close()
			return err
		}
	}
	writer.Flush()
	if err := writer.Error(); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}
