package connectedspeech

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/userlexicon"
)

const NeutralChainAuditToolVersion = "neutral-tone-chain-audit-v1"

var neutralChainBaselineFiles = []string{
	"yime_pinyin_codes.tsv",
	"yime_syllable_decomposition.tsv",
	"pinyin_normalized.json",
	"yime_pinyin_reverse_source.tsv",
	"yime_full.dict.yaml",
	"yime_variable.dict.yaml",
	"yime_shorthand.dict.yaml",
}

var neutralChainReportFiles = []string{
	"baseline_hashes_before.json",
	"baseline_hashes_after.json",
	"summary.json",
	"neutral_syllables.tsv",
	"neutral_lexicon.tsv",
	"reverse_lookup.tsv",
	"code_ambiguities.tsv",
	"user_lexicon.tsv",
	"issues.tsv",
}

// NeutralChainAuditConfig deliberately has no installed-runtime or user-data
// path. Stage 1 reads checked-in data and writes reports only below .tmp.
type NeutralChainAuditConfig struct {
	RepoRoot          string
	DataDir           string
	OutputDir         string
	AllowedOutputRoot string
}

func DefaultNeutralChainAuditConfig(repoRoot string) NeutralChainAuditConfig {
	return NeutralChainAuditConfig{
		RepoRoot:          repoRoot,
		DataDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "neutral-tone-chain-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

type NeutralChainAuditSummary struct {
	ToolVersion                 string          `json:"tool_version"`
	NeutralSyllableCount        int             `json:"neutral_syllable_count"`
	NeutralLexiconEntryCount    int             `json:"neutral_lexicon_entry_count"`
	NeutralLexiconDistinctCount int             `json:"neutral_lexicon_distinct_count"`
	ReverseLookupCheckCount     int             `json:"reverse_lookup_check_count"`
	UserLexiconCheckCount       int             `json:"user_lexicon_check_count"`
	AmbiguousCodeGroupCount     int             `json:"ambiguous_code_group_count"`
	IssueCount                  int             `json:"issue_count"`
	BaselineHashesMatch         bool            `json:"baseline_hashes_match"`
	RuntimeAliasesGenerated     int             `json:"runtime_aliases_generated"`
	Passed                      bool            `json:"passed"`
	Gates                       map[string]bool `json:"gates"`
}

type NeutralChainAuditManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type NeutralChainAuditResult struct {
	Summary  NeutralChainAuditSummary
	Manifest NeutralChainAuditManifest
	Issues   []NeutralChainIssue
}

type NeutralChainIssue struct {
	Component string
	Key       string
	Code      string
	Detail    string
}

type neutralSyllable struct {
	Pinyin    string
	Marked    string
	Full      string
	Variable  string
	Shorthand string
	Tuple     YinyuanTuple
	Layout    string
}

type neutralLexiconAggregate struct {
	Text           string
	NumericPinyin  string
	MarkedPinyin   string
	Weight         string
	FullSpelling   string
	Variable       string
	Shorthand      string
	Count          int
	VariableFound  int
	ShorthandFound int
}

type dictionaryEntry struct {
	Text   string
	Code   string
	Weight string
}

func RunNeutralChainAudit(config NeutralChainAuditConfig) (NeutralChainAuditResult, error) {
	if err := validateNeutralChainConfig(&config); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return NeutralChainAuditResult{}, err
	}

	baselinePaths := neutralChainInputPaths(config.DataDir)
	before, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_before.json"), before); err != nil {
		return NeutralChainAuditResult{}, err
	}

	codeMap, err := reverselookup.LoadSharedCodeMap(config.DataDir)
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	canonicalCodes, err := loadCanonicalCodeRows(filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	decomposition, err := loadNeutralDecomposition(filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"))
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	marked, err := loadMarkedPinyin(filepath.Join(config.DataDir, "pinyin_normalized.json"))
	if err != nil {
		return NeutralChainAuditResult{}, err
	}

	issues := []NeutralChainIssue{}
	addIssue := func(component, key, code, detail string) {
		issues = append(issues, NeutralChainIssue{Component: component, Key: key, Code: code, Detail: detail})
	}
	neutralSyllables := make([]neutralSyllable, 0)
	for pinyin, full := range canonicalCodes {
		if !strings.HasSuffix(pinyin, "5") {
			continue
		}
		record, buildErr := codemode.BuildRecord(full)
		if buildErr != nil {
			addIssue("syllable", pinyin, "invalid_full_code", buildErr.Error())
			continue
		}
		row, ok := decomposition[pinyin]
		if !ok {
			addIssue("syllable", pinyin, "missing_decomposition", "neutral syllable is absent from yime_syllable_decomposition.tsv")
			continue
		}
		if row.Layout != record.Full {
			addIssue("syllable", pinyin, "layout_code_mismatch", fmt.Sprintf("decomposition=%q code_map=%q", row.Layout, record.Full))
		}
		for position := 1; position < len(row.Tuple); position++ {
			if !isMiddleGradeMusicalID(row.Tuple[position]) {
				addIssue("syllable", pinyin, "non_middle_grade_identity", fmt.Sprintf("position %d uses %s", position, row.Tuple[position]))
			}
		}
		markedValue := strings.TrimSpace(marked[pinyin])
		if markedValue == "" {
			addIssue("standard_pinyin", pinyin, "missing_marked_pinyin", "pinyin_normalized.json has no entry")
		} else if markedValue != strings.TrimSuffix(pinyin, "5") {
			addIssue("standard_pinyin", pinyin, "neutral_tone_marked", fmt.Sprintf("want unmarked %q, got %q", strings.TrimSuffix(pinyin, "5"), markedValue))
		}
		neutralSyllables = append(neutralSyllables, neutralSyllable{
			Pinyin: pinyin, Marked: markedValue, Full: record.Full,
			Variable: record.Variable, Shorthand: record.Shorthand,
			Tuple: row.Tuple, Layout: row.Layout,
		})
	}
	sort.Slice(neutralSyllables, func(i, j int) bool { return neutralSyllables[i].Pinyin < neutralSyllables[j].Pinyin })
	if len(neutralSyllables) == 0 {
		addIssue("syllable", "", "empty_neutral_inventory", "no canonical numeric-tone syllable ending in 5 was found")
	}

	reverseRows := [][]string{{"pinyin", "mode", "code", "decoded_pinyin", "status"}}
	reverseChecks := 0
	for _, syllable := range neutralSyllables {
		for _, mode := range []reverselookup.Mode{reverselookup.ModeVariable, reverselookup.ModeFull, reverselookup.ModeShorthand} {
			code, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, syllable.Pinyin, mode)
			status := "ok"
			decoded := ""
			if encodeErr != nil {
				status = "encode_failed"
				addIssue("reverse_lookup", syllable.Pinyin+":"+string(mode), status, encodeErr.Error())
			} else {
				var decodeOK bool
				decoded, decodeOK = reverselookup.DecodeCodeToNumericPinyin(code, codeMap, mode)
				if !decodeOK {
					status = "decode_failed"
					addIssue("reverse_lookup", syllable.Pinyin+":"+string(mode), status, fmt.Sprintf("code %q did not decode", code))
				} else if canonicalNumericPinyin(decoded) != canonicalNumericPinyin(syllable.Pinyin) {
					decodedCode, _, reencodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, decoded, mode)
					if reencodeErr == nil && decodedCode == code && strings.HasSuffix(canonicalNumericPinyin(decoded), "5") {
						status = "equivalent_neutral_code_collision"
					} else {
						status = "identity_mismatch"
						addIssue("reverse_lookup", syllable.Pinyin+":"+string(mode), status, fmt.Sprintf("code %q decoded as %q", code, decoded))
					}
				}
			}
			reverseRows = append(reverseRows, []string{syllable.Pinyin, string(mode), code, decoded, status})
			reverseChecks++
		}
	}

	fullInverse := buildCanonicalInverse(canonicalCodes)
	ambiguityRows, ambiguityCount, neutralCollisionsPreserveIdentity := buildCodeAmbiguityRows(canonicalCodes)
	lexicon, lexiconEntryCount, lexErr := collectNeutralLexicon(
		filepath.Join(config.DataDir, "yime_full.dict.yaml"), fullInverse, marked, addIssue,
	)
	if lexErr != nil {
		return NeutralChainAuditResult{}, lexErr
	}
	if err := markModeCoverage(filepath.Join(config.DataDir, "yime_variable.dict.yaml"), lexicon, "variable"); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := markModeCoverage(filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"), lexicon, "shorthand"); err != nil {
		return NeutralChainAuditResult{}, err
	}
	for _, entry := range lexicon {
		if entry.VariableFound != entry.Count {
			addIssue("system_lexicon", entry.Text+":"+entry.NumericPinyin, "variable_coverage_mismatch", fmt.Sprintf("want %d rows, found %d", entry.Count, entry.VariableFound))
		}
		if entry.ShorthandFound != entry.Count {
			addIssue("system_lexicon", entry.Text+":"+entry.NumericPinyin, "shorthand_coverage_mismatch", fmt.Sprintf("want %d rows, found %d", entry.Count, entry.ShorthandFound))
		}
	}

	userRows, userChecks, userSourceUnchanged := auditUserLexicon(config, codeMap, lexicon, addIssue)

	syllableRows := [][]string{{"pinyin", "standard_pinyin", "full", "variable", "shorthand", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id", "status"}}
	for _, syllable := range neutralSyllables {
		status := "ok"
		if hasIssueFor(issues, "syllable", syllable.Pinyin) || hasIssueFor(issues, "standard_pinyin", syllable.Pinyin) {
			status = "failed"
		}
		syllableRows = append(syllableRows, []string{
			syllable.Pinyin, syllable.Marked, syllable.Full, syllable.Variable, syllable.Shorthand,
			syllable.Tuple[0], syllable.Tuple[1], syllable.Tuple[2], syllable.Tuple[3], status,
		})
	}
	lexiconRows := [][]string{{"text", "numeric_pinyin", "standard_pinyin", "weight", "entry_count", "full", "variable", "variable_found", "shorthand", "shorthand_found", "status"}}
	for _, entry := range lexicon {
		status := "ok"
		if entry.VariableFound != entry.Count || entry.ShorthandFound != entry.Count {
			status = "failed"
		}
		lexiconRows = append(lexiconRows, []string{
			entry.Text, entry.NumericPinyin, entry.MarkedPinyin, entry.Weight, strconv.Itoa(entry.Count), entry.FullSpelling,
			entry.Variable, strconv.Itoa(entry.VariableFound), entry.Shorthand, strconv.Itoa(entry.ShorthandFound), status,
		})
	}
	issueRows := [][]string{{"component", "key", "code", "detail"}}
	sort.SliceStable(issues, func(i, j int) bool {
		left := issues[i].Component + "\x00" + issues[i].Key + "\x00" + issues[i].Code
		right := issues[j].Component + "\x00" + issues[j].Key + "\x00" + issues[j].Code
		return left < right
	})
	for _, issue := range issues {
		issueRows = append(issueRows, []string{issue.Component, issue.Key, issue.Code, issue.Detail})
	}

	if err := writeTSV(filepath.Join(config.OutputDir, "neutral_syllables.tsv"), syllableRows); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "neutral_lexicon.tsv"), lexiconRows); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "reverse_lookup.tsv"), reverseRows); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "code_ambiguities.tsv"), ambiguityRows); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "user_lexicon.tsv"), userRows); err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "issues.tsv"), issueRows); err != nil {
		return NeutralChainAuditResult{}, err
	}

	after, err := hashNamedFiles(baselinePaths)
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "baseline_hashes_after.json"), after); err != nil {
		return NeutralChainAuditResult{}, err
	}
	baselineMatch := equalHashes(before, after)
	gates := map[string]bool{
		"neutral_identity_complete":                 !hasIssueComponent(issues, "syllable"),
		"neutral_code_collisions_preserve_identity": neutralCollisionsPreserveIdentity,
		"standard_pinyin_unmarked":                  !hasIssueComponent(issues, "standard_pinyin"),
		"three_mode_lexicon_complete":               !hasIssueComponent(issues, "system_lexicon"),
		"reverse_lookup_roundtrip":                  !hasIssueComponent(issues, "reverse_lookup"),
		"user_lexicon_roundtrip":                    !hasIssueComponent(issues, "user_lexicon"),
		"user_lexicon_source_unchanged":             userSourceUnchanged,
		"runtime_aliases_generated_zero":            true,
		"canonical_data_hashes_unchanged":           baselineMatch,
	}
	summary := NeutralChainAuditSummary{
		ToolVersion: NeutralChainAuditToolVersion, NeutralSyllableCount: len(neutralSyllables),
		NeutralLexiconEntryCount: lexiconEntryCount, NeutralLexiconDistinctCount: len(lexicon),
		ReverseLookupCheckCount: reverseChecks, UserLexiconCheckCount: userChecks,
		AmbiguousCodeGroupCount: ambiguityCount,
		IssueCount:              len(issues), BaselineHashesMatch: baselineMatch, RuntimeAliasesGenerated: 0,
		Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return NeutralChainAuditResult{}, err
	}

	outputHashes, err := hashNeutralChainReports(config.OutputDir)
	if err != nil {
		return NeutralChainAuditResult{}, err
	}
	manifest := NeutralChainAuditManifest{
		ToolVersion: NeutralChainAuditToolVersion, InputSHA256: before, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic Stage 1 report files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return NeutralChainAuditResult{}, err
	}

	result := NeutralChainAuditResult{Summary: summary, Manifest: manifest, Issues: issues}
	if !summary.Passed {
		return result, fmt.Errorf("neutral-tone chain audit failed: issues=%d baseline_match=%t", len(issues), baselineMatch)
	}
	return result, nil
}

type decompositionRow struct {
	Tuple  YinyuanTuple
	Layout string
}

func loadCanonicalCodeRows(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	rows := map[string]string{}
	scanner := bufio.NewScanner(file)
	line := 0
	for scanner.Scan() {
		line++
		if line == 1 {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 || strings.TrimSpace(fields[0]) == "" {
			continue
		}
		rows[canonicalNumericPinyin(fields[0])] = strings.TrimSpace(fields[1])
	}
	return rows, scanner.Err()
}

func loadNeutralDecomposition(path string) (map[string]decompositionRow, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	if !scanner.Scan() {
		return nil, errors.New("empty syllable decomposition table")
	}
	header := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
	columns := map[string]int{}
	for index, name := range header {
		columns[strings.TrimSpace(name)] = index
	}
	required := []string{"pinyin_tone", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id", "layout_code"}
	for _, name := range required {
		if _, ok := columns[name]; !ok {
			return nil, fmt.Errorf("syllable decomposition table is missing %s", name)
		}
	}
	rows := map[string]decompositionRow{}
	for scanner.Scan() {
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < len(header) {
			continue
		}
		pinyin := canonicalNumericPinyin(fields[columns["pinyin_tone"]])
		rows[pinyin] = decompositionRow{
			Tuple: YinyuanTuple{
				strings.TrimSpace(fields[columns["shouyin_id"]]), strings.TrimSpace(fields[columns["huyin_id"]]),
				strings.TrimSpace(fields[columns["zhuyin_id"]]), strings.TrimSpace(fields[columns["moyin_id"]]),
			},
			Layout: strings.TrimSpace(fields[columns["layout_code"]]),
		}
	}
	return rows, scanner.Err()
}

func loadMarkedPinyin(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	raw := map[string]string{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	result := make(map[string]string, len(raw))
	for key, value := range raw {
		result[canonicalNumericPinyin(key)] = strings.TrimSpace(value)
	}
	return result, nil
}

func isMiddleGradeMusicalID(id string) bool {
	if len(id) != 3 || id[0] != 'M' {
		return false
	}
	number, err := strconv.Atoi(id[1:])
	return err == nil && number >= 1 && number <= 33 && (number-1)%3 == 1
}

func canonicalNumericPinyin(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "u:", "ü")
	value = strings.ReplaceAll(value, "v", "ü")
	return value
}

func buildCanonicalInverse(codes map[string]string) map[string][]string {
	result := map[string][]string{}
	for pinyin, code := range codes {
		code = strings.TrimSpace(code)
		result[code] = append(result[code], pinyin)
	}
	for code := range result {
		sort.Strings(result[code])
	}
	return result
}

func collectNeutralLexicon(path string, inverse map[string][]string, marked map[string]string, addIssue func(string, string, string, string)) ([]*neutralLexiconAggregate, int, error) {
	aggregates := map[string]*neutralLexiconAggregate{}
	unknownReported := map[string]bool{}
	total := 0
	err := scanRimeDictionary(path, func(entry dictionaryEntry) {
		parts := strings.Fields(entry.Code)
		pinyin := make([]string, 0, len(parts))
		containsNeutral := false
		markedParts := make([]string, 0, len(parts))
		for _, code := range parts {
			choices := inverse[code]
			if len(choices) == 0 || (len(choices) > 1 && !sameToneIdentity(choices)) {
				if !unknownReported[code] {
					issueCode := "unknown_full_code"
					if len(choices) > 1 {
						issueCode = "ambiguous_full_code"
					}
					addIssue("system_lexicon", code, issueCode, strings.Join(choices, ","))
					unknownReported[code] = true
				}
				return
			}
			if len(choices) == 1 {
				pinyin = append(pinyin, choices[0])
				markedParts = append(markedParts, marked[choices[0]])
			} else {
				pinyin = append(pinyin, "{"+strings.Join(choices, "|")+"}")
				markedChoices := make([]string, 0, len(choices))
				for _, choice := range choices {
					markedChoices = append(markedChoices, marked[choice])
				}
				markedParts = append(markedParts, "{"+strings.Join(markedChoices, "|")+"}")
			}
			containsNeutral = containsNeutral || strings.HasSuffix(choices[0], "5")
		}
		if !containsNeutral {
			return
		}
		record, buildErr := codemode.BuildRecord(entry.Code)
		if buildErr != nil {
			addIssue("system_lexicon", entry.Text, "invalid_full_entry", buildErr.Error())
			return
		}
		numeric := strings.Join(pinyin, " ")
		key := strings.Join([]string{entry.Text, numeric, entry.Weight, record.FullSpelling}, "\x00")
		aggregate := aggregates[key]
		if aggregate == nil {
			aggregate = &neutralLexiconAggregate{
				Text: entry.Text, NumericPinyin: numeric, MarkedPinyin: strings.Join(markedParts, " "), Weight: entry.Weight,
				FullSpelling: record.FullSpelling, Variable: record.VariableSpelling, Shorthand: record.ShorthandSpelling,
			}
			aggregates[key] = aggregate
		}
		aggregate.Count++
		total++
	})
	if err != nil {
		return nil, 0, err
	}
	result := make([]*neutralLexiconAggregate, 0, len(aggregates))
	for _, aggregate := range aggregates {
		result = append(result, aggregate)
	}
	sort.Slice(result, func(i, j int) bool {
		left := result[i].Text + "\x00" + result[i].NumericPinyin + "\x00" + result[i].Weight
		right := result[j].Text + "\x00" + result[j].NumericPinyin + "\x00" + result[j].Weight
		return left < right
	})
	return result, total, nil
}

func markModeCoverage(path string, entries []*neutralLexiconAggregate, mode string) error {
	wanted := map[string][]*neutralLexiconAggregate{}
	for _, entry := range entries {
		code := entry.Variable
		if mode == "shorthand" {
			code = entry.Shorthand
		}
		key := strings.Join([]string{entry.Text, code, entry.Weight}, "\x00")
		wanted[key] = append(wanted[key], entry)
	}
	return scanRimeDictionary(path, func(row dictionaryEntry) {
		key := strings.Join([]string{row.Text, strings.Join(strings.Fields(row.Code), " "), row.Weight}, "\x00")
		for _, entry := range wanted[key] {
			if mode == "variable" && entry.VariableFound < entry.Count {
				entry.VariableFound++
				return
			}
			if mode == "shorthand" && entry.ShorthandFound < entry.Count {
				entry.ShorthandFound++
				return
			}
		}
	})
}

func scanRimeDictionary(path string, visit func(dictionaryEntry)) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	inData := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !inData {
			inData = line == "..."
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 {
			continue
		}
		weight := ""
		if len(fields) >= 3 {
			weight = strings.TrimSpace(fields[2])
		}
		visit(dictionaryEntry{Text: strings.TrimSpace(fields[0]), Code: strings.TrimSpace(fields[1]), Weight: weight})
	}
	return scanner.Err()
}

func auditUserLexicon(config NeutralChainAuditConfig, codeMap map[string]reverselookup.CodeRecord, entries []*neutralLexiconAggregate, addIssue func(string, string, string, string)) ([][]string, int, bool) {
	rows := [][]string{{"text", "numeric_pinyin", "mode", "expected_code", "generated_code", "source_unchanged", "status"}}
	if len(entries) == 0 {
		addIssue("user_lexicon", "", "no_fixture", "system lexicon has no neutral-tone entry for the simulation")
		return rows, 0, false
	}
	representative := entries[0]
	for _, entry := range entries {
		if utf8.RuneCountInString(entry.Text) == len(strings.Fields(entry.NumericPinyin)) && reverselookup.ValidateNumericTonePinyin(entry.NumericPinyin) {
			representative = entry
			break
		}
	}
	simulationRoot, err := os.MkdirTemp(config.OutputDir, ".user-lexicon-simulation-")
	if err != nil {
		addIssue("user_lexicon", representative.Text, "simulation_setup_failed", err.Error())
		return rows, 0, false
	}
	defer os.RemoveAll(simulationRoot)
	sourceDir := filepath.Join(simulationRoot, "source")
	targetDir := filepath.Join(simulationRoot, "derived")
	if err := os.MkdirAll(sourceDir, 0o755); err != nil {
		addIssue("user_lexicon", representative.Text, "simulation_setup_failed", err.Error())
		return rows, 0, false
	}
	sourcePath := filepath.Join(sourceDir, userlexicon.SourceFileName)
	if err := userlexicon.WriteSourceEntries(sourcePath, []userlexicon.Entry{{Phrase: representative.Text, Pinyin: representative.NumericPinyin, Weight: "1000000"}}); err != nil {
		addIssue("user_lexicon", representative.Text, "source_write_failed", err.Error())
		return rows, 0, false
	}
	before, err := hashFile(sourcePath)
	if err != nil {
		addIssue("user_lexicon", representative.Text, "source_hash_failed", err.Error())
		return rows, 0, false
	}
	if err := userlexicon.RebuildAllRimeLexiconsTo(config.DataDir, sourceDir, targetDir); err != nil {
		addIssue("user_lexicon", representative.Text, "rebuild_failed", err.Error())
		return rows, 0, false
	}
	after, err := hashFile(sourcePath)
	if err != nil {
		addIssue("user_lexicon", representative.Text, "source_hash_failed", err.Error())
		return rows, 0, false
	}
	sourceUnchanged := before == after
	if !sourceUnchanged {
		addIssue("user_lexicon", representative.Text, "source_changed", "three-mode rebuild modified the numeric-tone source")
	}
	checks := 0
	for _, mode := range []reverselookup.Mode{reverselookup.ModeVariable, reverselookup.ModeFull, reverselookup.ModeShorthand} {
		expected, _, encodeErr := reverselookup.EncodeNumericTonePinyin(codeMap, representative.NumericPinyin, mode)
		generated := ""
		status := "ok"
		if encodeErr != nil {
			status = "encode_failed"
			addIssue("user_lexicon", representative.Text+":"+string(mode), status, encodeErr.Error())
		} else {
			readErr := scanRimeDictionaryLikeText(userlexicon.RimeLexiconPath(targetDir, string(mode)), func(row dictionaryEntry) {
				if row.Text == representative.Text {
					generated = strings.ReplaceAll(row.Code, " ", "")
				}
			})
			if readErr != nil {
				status = "read_failed"
				addIssue("user_lexicon", representative.Text+":"+string(mode), status, readErr.Error())
			} else if generated != expected {
				status = "generated_code_mismatch"
				addIssue("user_lexicon", representative.Text+":"+string(mode), status, fmt.Sprintf("want %q, got %q", expected, generated))
			}
		}
		rows = append(rows, []string{representative.Text, representative.NumericPinyin, string(mode), expected, generated, strconv.FormatBool(sourceUnchanged), status})
		checks++
	}
	return rows, checks, sourceUnchanged
}

func sameToneIdentity(choices []string) bool {
	if len(choices) == 0 {
		return false
	}
	want := toneSuffix(choices[0])
	if want == 0 {
		return false
	}
	for _, choice := range choices[1:] {
		if toneSuffix(choice) != want {
			return false
		}
	}
	return true
}

func toneSuffix(pinyin string) byte {
	pinyin = canonicalNumericPinyin(pinyin)
	if pinyin == "" {
		return 0
	}
	last := pinyin[len(pinyin)-1]
	if last < '1' || last > '5' {
		return 0
	}
	return last
}

func buildCodeAmbiguityRows(codes map[string]string) ([][]string, int, bool) {
	rows := [][]string{{"mode", "code", "pinyin_choices", "tone_identity_preserved", "neutral_identity"}}
	count := 0
	neutralIdentityPreserved := true
	for _, mode := range []string{"variable", "full", "shorthand"} {
		inverse := map[string][]string{}
		for pinyin, full := range codes {
			record, err := codemode.BuildRecord(full)
			if err != nil {
				continue
			}
			code := record.Variable
			if mode == "full" {
				code = record.Full
			} else if mode == "shorthand" {
				code = record.Shorthand
			}
			inverse[code] = append(inverse[code], pinyin)
		}
		modeRows := [][]string{}
		for code, choices := range inverse {
			if len(choices) < 2 {
				continue
			}
			sort.Strings(choices)
			preserved := sameToneIdentity(choices)
			neutral := preserved && toneSuffix(choices[0]) == '5'
			containsNeutral := false
			for _, choice := range choices {
				containsNeutral = containsNeutral || toneSuffix(choice) == '5'
			}
			if containsNeutral && !neutral {
				neutralIdentityPreserved = false
			}
			modeRows = append(modeRows, []string{mode, code, strings.Join(choices, ","), strconv.FormatBool(preserved), strconv.FormatBool(neutral)})
			count++
		}
		sort.Slice(modeRows, func(i, j int) bool { return modeRows[i][1] < modeRows[j][1] })
		rows = append(rows, modeRows...)
	}
	return rows, count, neutralIdentityPreserved
}

func scanRimeDictionaryLikeText(path string, visit func(dictionaryEntry)) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) < 2 {
			continue
		}
		weight := ""
		if len(fields) >= 3 {
			weight = strings.TrimSpace(fields[2])
		}
		visit(dictionaryEntry{Text: strings.TrimSpace(fields[0]), Code: strings.TrimSpace(fields[1]), Weight: weight})
	}
	return scanner.Err()
}

func validateNeutralChainConfig(config *NeutralChainAuditConfig) error {
	if config.RepoRoot == "" || config.DataDir == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("RepoRoot, DataDir, OutputDir, and AllowedOutputRoot are required")
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
	if filepath.Base(output) != "neutral-tone-chain-audit" {
		return fmt.Errorf("Stage 1 output directory must be named neutral-tone-chain-audit: %s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}

func neutralChainInputPaths(dataDir string) map[string]string {
	paths := make(map[string]string, len(neutralChainBaselineFiles))
	for _, name := range neutralChainBaselineFiles {
		paths[name] = filepath.Join(dataDir, name)
	}
	return paths
}

func hashNeutralChainReports(outputDir string) (map[string]string, error) {
	paths := make(map[string]string, len(neutralChainReportFiles))
	for _, name := range neutralChainReportFiles {
		paths[name] = filepath.Join(outputDir, name)
	}
	return hashNamedFiles(paths)
}

func hasIssueComponent(issues []NeutralChainIssue, component string) bool {
	for _, issue := range issues {
		if issue.Component == component {
			return true
		}
	}
	return false
}

func hasIssueFor(issues []NeutralChainIssue, component, key string) bool {
	for _, issue := range issues {
		if issue.Component == component && issue.Key == key {
			return true
		}
	}
	return false
}
