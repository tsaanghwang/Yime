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

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

const YiBuChainAuditToolVersion = "connected-speech-stage2-yi-bu-audit-v1"

var yiBuChainReportFiles = []string{
	"baseline_hashes_before.json",
	"baseline_hashes_after.json",
	"case_coverage.tsv",
	"summary.json",
}

var yiBuChainBaselineFiles = []string{
	"yime_pinyin_codes.tsv",
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
}

type YiBuChainAuditConfig struct {
	RepoRoot          string
	DataDir           string
	CasesPath         string
	OutputDir         string
	AllowedOutputRoot string
}

func DefaultYiBuChainAuditConfig(repoRoot string) YiBuChainAuditConfig {
	return YiBuChainAuditConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		CasesPath:         filepath.Join(repoRoot, "docs", "project", "connected_speech", "stage2_yi_bu_cases.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "connected-speech-stage2-yi-bu-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

type YiBuChainCase struct {
	CaseID               string
	Text                 string
	Classification       string
	RuntimePinyin        string
	TrialPinyin          string
	TrialRuntimeExpected bool
	Decision             string
	Reason               string
}

type YiBuChainAuditSummary struct {
	ToolVersion             string          `json:"tool_version"`
	CaseCount               int             `json:"case_count"`
	ExistingSurfaceCount    int             `json:"existing_surface_count"`
	MissingAliasCount       int             `json:"missing_alias_count"`
	ExcludedCount           int             `json:"excluded_count"`
	DeferredCount           int             `json:"deferred_count"`
	ThreeModeCheckCount     int             `json:"three_mode_check_count"`
	IssueCount              int             `json:"issue_count"`
	RuntimeAliasesGenerated int             `json:"runtime_aliases_generated"`
	BaselineHashesMatch     bool            `json:"baseline_hashes_match"`
	Gates                   map[string]bool `json:"gates"`
	Passed                  bool            `json:"passed"`
}

type YiBuChainAuditManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type YiBuChainAuditResult struct {
	Summary  YiBuChainAuditSummary
	Manifest YiBuChainAuditManifest
	Issues   []string
}

func RunYiBuChainAudit(config YiBuChainAuditConfig) (YiBuChainAuditResult, error) {
	if err := validateYiBuChainConfig(&config); err != nil {
		return YiBuChainAuditResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return YiBuChainAuditResult{}, err
	}

	baselinePaths := map[string]string{}
	for _, name := range yiBuChainBaselineFiles {
		baselinePaths[name] = filepath.Join(config.DataDir, name)
	}
	before, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_before.json"), before); err != nil {
		return YiBuChainAuditResult{}, err
	}

	cases, err := loadYiBuChainCases(config.CasesPath)
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	codeRows, err := loadCanonicalCodeRows(filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	indexes := map[string]map[string]bool{}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		path := filepath.Join(config.DataDir, "yime_"+mode+".dict.yaml")
		index, readErr := loadDictionaryTextCodeIndex(path)
		if readErr != nil {
			return YiBuChainAuditResult{}, readErr
		}
		indexes[mode] = index
	}

	rows := [][]string{{
		"case_id", "text", "classification", "mode", "runtime_pinyin", "runtime_code", "runtime_found",
		"trial_pinyin", "trial_code", "trial_runtime_expected", "trial_found", "status", "decision", "reason",
	}}
	issues := []string{}
	seen := map[string]bool{}
	counts := map[string]int{}
	threeModeChecks := 0
	for _, item := range cases {
		counts[item.Classification]++
		if item.CaseID == "" || seen[item.CaseID] {
			issues = append(issues, fmt.Sprintf("duplicate or empty case_id: %q", item.CaseID))
		}
		seen[item.CaseID] = true
		runtimeRecord, buildErr := buildPinyinRecord(item.RuntimePinyin, codeRows)
		if buildErr != nil {
			issues = append(issues, item.CaseID+": "+buildErr.Error())
			continue
		}
		var trialRecord codemode.Record
		if item.TrialPinyin != "" {
			trialRecord, buildErr = buildPinyinRecord(item.TrialPinyin, codeRows)
			if buildErr != nil {
				issues = append(issues, item.CaseID+": "+buildErr.Error())
				continue
			}
		}
		for _, mode := range []string{"full", "variable", "shorthand"} {
			runtimeCode := recordCode(runtimeRecord, mode)
			runtimeFound := indexes[mode][dictionaryKey(item.Text, runtimeCode)]
			trialCode := ""
			trialFound := false
			if item.TrialPinyin != "" {
				trialCode = recordCode(trialRecord, mode)
				trialFound = indexes[mode][dictionaryKey(item.Text, trialCode)]
			}
			status := "ok"
			if !runtimeFound {
				status = "runtime_reading_missing"
				issues = append(issues, fmt.Sprintf("%s:%s runtime reading %q is missing", item.CaseID, mode, item.RuntimePinyin))
			}
			if item.TrialPinyin != "" && trialFound != item.TrialRuntimeExpected {
				status = "trial_presence_mismatch"
				issues = append(issues, fmt.Sprintf("%s:%s trial reading %q found=%t want=%t", item.CaseID, mode, item.TrialPinyin, trialFound, item.TrialRuntimeExpected))
			}
			rows = append(rows, []string{
				item.CaseID, item.Text, item.Classification, mode, item.RuntimePinyin, runtimeCode,
				strconv.FormatBool(runtimeFound), item.TrialPinyin, trialCode, strconv.FormatBool(item.TrialRuntimeExpected),
				strconv.FormatBool(trialFound), status, item.Decision, item.Reason,
			})
			threeModeChecks++
		}
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "case_coverage.tsv"), rows); err != nil {
		return YiBuChainAuditResult{}, err
	}

	after, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_after.json"), after); err != nil {
		return YiBuChainAuditResult{}, err
	}
	baselineMatch := equalHashes(before, after)
	gates := map[string]bool{
		"case_ids_unique":                     !containsIssue(issues, "duplicate or empty case_id"),
		"current_runtime_readings_three_mode": !containsIssue(issues, "runtime reading"),
		"trial_runtime_presence_as_declared":  !containsIssue(issues, "trial reading"),
		"runtime_aliases_generated_zero":      true,
		"canonical_data_hashes_unchanged":     baselineMatch,
	}
	summary := YiBuChainAuditSummary{
		ToolVersion: YiBuChainAuditToolVersion, CaseCount: len(cases), ExistingSurfaceCount: counts["existing_surface"],
		MissingAliasCount: counts["missing_alias"], ExcludedCount: counts["excluded"], DeferredCount: counts["deferred"],
		ThreeModeCheckCount: threeModeChecks, IssueCount: len(issues), RuntimeAliasesGenerated: 0,
		BaselineHashesMatch: baselineMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates) && len(issues) == 0
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return YiBuChainAuditResult{}, err
	}

	inputHashes, err := hashNamedFiles(map[string]string{
		"cases":          config.CasesPath,
		"pinyin_codes":   filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
		"full_dict":      filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable_dict":  filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand_dict": filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	})
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	outputPaths := map[string]string{}
	for _, name := range yiBuChainReportFiles {
		outputPaths[name] = filepath.Join(config.OutputDir, name)
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return YiBuChainAuditResult{}, err
	}
	manifest := YiBuChainAuditManifest{
		ToolVersion: YiBuChainAuditToolVersion, InputSHA256: inputHashes, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic Stage 2A chain-audit files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return YiBuChainAuditResult{}, err
	}
	result := YiBuChainAuditResult{Summary: summary, Manifest: manifest, Issues: issues}
	if !summary.Passed {
		return result, fmt.Errorf("Stage 2A 一、不既有链路审计失败：issues=%d baseline_match=%t", len(issues), baselineMatch)
	}
	return result, nil
}

func loadYiBuChainCases(path string) ([]YiBuChainCase, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	reader.FieldsPerRecord = -1
	header, err := reader.Read()
	if err != nil {
		return nil, err
	}
	columns := map[string]int{}
	for index, name := range header {
		columns[strings.TrimSpace(strings.TrimPrefix(name, "\ufeff"))] = index
	}
	required := []string{"case_id", "text", "classification", "runtime_pinyin", "trial_pinyin", "trial_runtime_expected", "decision", "reason"}
	for _, name := range required {
		if _, ok := columns[name]; !ok {
			return nil, fmt.Errorf("Stage 2A case table is missing %s", name)
		}
	}
	validClasses := stringSet("existing_surface", "missing_alias", "excluded", "deferred")
	result := []YiBuChainCase{}
	for {
		row, readErr := reader.Read()
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return nil, readErr
		}
		value := func(name string) string {
			index := columns[name]
			if index >= len(row) {
				return ""
			}
			return strings.TrimSpace(row[index])
		}
		if value("case_id") == "" {
			continue
		}
		classification := value("classification")
		if !validClasses[classification] {
			return nil, fmt.Errorf("unknown Stage 2A classification %q", classification)
		}
		expected, parseErr := strconv.ParseBool(value("trial_runtime_expected"))
		if parseErr != nil {
			return nil, fmt.Errorf("%s trial_runtime_expected: %w", value("case_id"), parseErr)
		}
		result = append(result, YiBuChainCase{
			CaseID: value("case_id"), Text: value("text"), Classification: classification,
			RuntimePinyin: value("runtime_pinyin"), TrialPinyin: value("trial_pinyin"),
			TrialRuntimeExpected: expected, Decision: value("decision"), Reason: value("reason"),
		})
	}
	sort.Slice(result, func(i, j int) bool { return result[i].CaseID < result[j].CaseID })
	return result, nil
}

func buildPinyinRecord(pinyin string, codeRows map[string]string) (codemode.Record, error) {
	parts := strings.Fields(pinyin)
	if len(parts) == 0 {
		return codemode.Record{}, errors.New("empty numeric-tone pinyin")
	}
	codes := make([]string, 0, len(parts))
	for _, part := range parts {
		code := codeRows[canonicalNumericPinyin(part)]
		if code == "" {
			return codemode.Record{}, fmt.Errorf("unknown numeric-tone syllable %q", part)
		}
		codes = append(codes, code)
	}
	return codemode.BuildRecord(strings.Join(codes, " "))
}

func loadDictionaryTextCodeIndex(path string) (map[string]bool, error) {
	result := map[string]bool{}
	err := scanRimeDictionary(path, func(entry dictionaryEntry) {
		result[dictionaryKey(entry.Text, entry.Code)] = true
	})
	return result, err
}

func dictionaryKey(text, code string) string {
	return strings.TrimSpace(text) + "\x00" + strings.Join(strings.Fields(code), " ")
}

func recordCode(record codemode.Record, mode string) string {
	switch mode {
	case "full":
		return record.FullSpelling
	case "variable":
		return record.VariableSpelling
	case "shorthand":
		return record.ShorthandSpelling
	default:
		panic("unknown code mode: " + mode)
	}
}

func containsIssue(issues []string, fragment string) bool {
	for _, issue := range issues {
		if strings.Contains(issue, fragment) {
			return true
		}
	}
	return false
}

func validateYiBuChainConfig(config *YiBuChainAuditConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.CasesPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("RepoRoot, DataDir, CasesPath, OutputDir, and AllowedOutputRoot are required")
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
	if filepath.Base(output) != "connected-speech-stage2-yi-bu-audit" {
		return fmt.Errorf("Stage 2A output directory must be named connected-speech-stage2-yi-bu-audit: %s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}
