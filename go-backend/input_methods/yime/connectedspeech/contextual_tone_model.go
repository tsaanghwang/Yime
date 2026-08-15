package connectedspeech

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const (
	ContextualToneModelToolVersion = "contextual-tone-quality-model-audit-v1"
	contextualToneModelID          = "yime-contextual-tone-quality-hypothesis-v1"
)

var contextualToneReportFiles = []string{
	"input_hashes_before.json",
	"input_hashes_after.json",
	"rule_order.tsv",
	"conflict_report.tsv",
	"validation_issues.tsv",
	"summary.json",
	"REPORT.md",
}

type ContextualToneModel struct {
	SchemaVersion       int                        `json:"schema_version"`
	ModelID             string                     `json:"model_id"`
	Revision            int                        `json:"revision"`
	Status              string                     `json:"status"`
	Claim               string                     `json:"claim"`
	EvaluationStrategy  string                     `json:"evaluation_strategy"`
	RuntimeEnabled      bool                       `json:"runtime_enabled"`
	MaximumGlobalPasses int                        `json:"maximum_global_passes"`
	Layers              []ContextualToneLayer      `json:"layers"`
	Rules               []ContextualToneRule       `json:"rules"`
	Dependencies        []ContextualToneDependency `json:"dependencies"`
}

type ContextualToneLayer struct {
	LayerID string `json:"layer_id"`
	Order   int    `json:"order"`
	Name    string `json:"name"`
	Output  string `json:"output"`
}

type ContextualToneRule struct {
	RuleID                         string   `json:"rule_id"`
	Name                           string   `json:"name"`
	Phenomenon                     string   `json:"phenomenon"`
	LayerID                        string   `json:"layer_id"`
	Activation                     string   `json:"activation"`
	Scope                          string   `json:"scope"`
	Reads                          []string `json:"reads"`
	Writes                         []string `json:"writes"`
	RequiresProsodicDomain         bool     `json:"requires_prosodic_domain"`
	MaximumApplicationsPerSyllable int      `json:"maximum_applications_per_syllable"`
	Recursive                      bool     `json:"recursive"`
	EvidenceClass                  string   `json:"evidence_class"`
	Note                           string   `json:"note"`
}

type ContextualToneDependency struct {
	FromRule  string `json:"from_rule"`
	ToRule    string `json:"to_rule"`
	Relation  string `json:"relation"`
	Condition string `json:"condition"`
}

type ContextualToneConflict struct {
	ConflictID       string
	LeftRule         string
	RightRule        string
	OverlapCondition string
	Relation         string
	Resolution       string
	Status           string
	Note             string
}

type ContextualToneModelIssue struct {
	ObjectID string `json:"object_id"`
	Field    string `json:"field"`
	Code     string `json:"code"`
	Detail   string `json:"detail"`
}

type ContextualToneModelAuditConfig struct {
	RepoRoot          string
	ModelPath         string
	ConflictsPath     string
	OutputDir         string
	AllowedOutputRoot string
}

type ContextualToneModelAuditSummary struct {
	ToolVersion             string          `json:"tool_version"`
	SchemaVersion           int             `json:"schema_version"`
	ModelID                 string          `json:"model_id"`
	LayerCount              int             `json:"layer_count"`
	RuleCount               int             `json:"rule_count"`
	DependencyCount         int             `json:"dependency_count"`
	ConflictCount           int             `json:"conflict_count"`
	DeferredRuleCount       int             `json:"deferred_rule_count"`
	DeferredConflictCount   int             `json:"deferred_conflict_count"`
	ValidationIssueCount    int             `json:"validation_issue_count"`
	RuntimeAliasesGenerated int             `json:"runtime_aliases_generated"`
	InputHashesMatch        bool            `json:"input_hashes_match"`
	Gates                   map[string]bool `json:"gates"`
	Passed                  bool            `json:"passed"`
}

type ContextualToneModelAuditResult struct {
	Summary ContextualToneModelAuditSummary
	Issues  []ContextualToneModelIssue
}

func DefaultContextualToneModelAuditConfig(repoRoot string) ContextualToneModelAuditConfig {
	base := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	return ContextualToneModelAuditConfig{
		RepoRoot:          repoRoot,
		ModelPath:         filepath.Join(base, "contextual_tone_rule_model.json"),
		ConflictsPath:     filepath.Join(base, "contextual_tone_rule_conflicts.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "contextual-tone-model-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func LoadContextualToneModel(path string) (ContextualToneModel, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return ContextualToneModel{}, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var model ContextualToneModel
	if err := decoder.Decode(&model); err != nil {
		return ContextualToneModel{}, fmt.Errorf("解析语境调层模型: %w", err)
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return ContextualToneModel{}, err
	}
	return model, nil
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("JSON 文档包含多余值")
		}
		return err
	}
	return nil
}

func LoadContextualToneConflicts(path string) ([]ContextualToneConflict, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	reader.FieldsPerRecord = -1
	rows, err := reader.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("解析语境调层冲突表: %w", err)
	}
	wantHeader := []string{"conflict_id", "left_rule", "right_rule", "overlap_condition", "relation", "resolution", "status", "note"}
	if len(rows) == 0 || !stringSlicesEqual(rows[0], wantHeader) {
		return nil, fmt.Errorf("语境调层冲突表表头必须为 %s", strings.Join(wantHeader, "\\t"))
	}
	conflicts := make([]ContextualToneConflict, 0, len(rows)-1)
	for index, row := range rows[1:] {
		if len(row) != len(wantHeader) {
			return nil, fmt.Errorf("语境调层冲突表第 %d 行字段数=%d，预期=%d", index+2, len(row), len(wantHeader))
		}
		conflicts = append(conflicts, ContextualToneConflict{
			ConflictID: row[0], LeftRule: row[1], RightRule: row[2], OverlapCondition: row[3],
			Relation: row[4], Resolution: row[5], Status: row[6], Note: row[7],
		})
	}
	return conflicts, nil
}

func ValidateContextualToneModel(model ContextualToneModel, conflicts []ContextualToneConflict) []ContextualToneModelIssue {
	issues := []ContextualToneModelIssue{}
	add := func(id, field, code, detail string) {
		issues = append(issues, ContextualToneModelIssue{ObjectID: id, Field: field, Code: code, Detail: detail})
	}
	if model.SchemaVersion != 1 {
		add(model.ModelID, "schema_version", "unsupported", "当前只接受 schema_version=1")
	}
	if model.ModelID != contextualToneModelID {
		add(model.ModelID, "model_id", "unexpected", "模型 ID 必须显式标识第一版工程假设")
	}
	if model.Status != "research_only" {
		add(model.ModelID, "status", "unsafe", "统一模型在评审前只能是 research_only")
	}
	if strings.TrimSpace(model.Claim) == "" {
		add(model.ModelID, "claim", "missing", "必须声明模型是可证伪、可替换的工程假设")
	}
	if model.EvaluationStrategy != "bounded_non_recursive_partial_order" {
		add(model.ModelID, "evaluation_strategy", "unsafe", "只能采用有界、非递归的偏序求值")
	}
	if model.RuntimeEnabled {
		add(model.ModelID, "runtime_enabled", "runtime_forbidden", "假设模型不得接入运行时")
	}
	if model.MaximumGlobalPasses != 1 {
		add(model.ModelID, "maximum_global_passes", "recursive_risk", "全局求值必须严格限制为一轮")
	}

	layerByID := map[string]ContextualToneLayer{}
	orders := map[int]string{}
	for _, layer := range model.Layers {
		if layer.LayerID == "" || layer.Name == "" || layer.Output == "" {
			add(layer.LayerID, "layers", "incomplete", "层 ID、名称和输出均不能为空")
		}
		if _, exists := layerByID[layer.LayerID]; exists {
			add(layer.LayerID, "layer_id", "duplicate", "层 ID 重复")
		}
		if previous, exists := orders[layer.Order]; exists {
			add(layer.LayerID, "order", "duplicate", "层顺序与 "+previous+" 重复")
		}
		layerByID[layer.LayerID] = layer
		orders[layer.Order] = layer.LayerID
	}

	ruleByID := map[string]ContextualToneRule{}
	allowedActivation := map[string]bool{"research_only": true, "deferred": true, "approved_engineering_boundary": true}
	for _, rule := range model.Rules {
		if rule.RuleID == "" {
			add("<empty-rule>", "rule_id", "missing", "规则 ID 不能为空")
		}
		if _, exists := ruleByID[rule.RuleID]; exists {
			add(rule.RuleID, "rule_id", "duplicate", "规则 ID 重复")
		}
		ruleByID[rule.RuleID] = rule
		if _, exists := layerByID[rule.LayerID]; !exists {
			add(rule.RuleID, "layer_id", "unknown", "引用了不存在的层 "+rule.LayerID)
		}
		if !allowedActivation[rule.Activation] {
			add(rule.RuleID, "activation", "unsafe", "规则不得处于可运行状态")
		}
		if rule.Recursive || rule.MaximumApplicationsPerSyllable != 1 {
			add(rule.RuleID, "recursive", "recursive_risk", "每个音节每条规则只能应用一次且不得递归")
		}
		if rule.Name == "" || rule.Phenomenon == "" || rule.Scope == "" || rule.EvidenceClass == "" || len(rule.Reads) == 0 || len(rule.Writes) == 0 {
			add(rule.RuleID, "rule", "incomplete", "名称、现象、范围、证据类、读集和写集均不能为空")
		}
	}

	adjacency := map[string][]string{}
	seenDependencies := map[string]bool{}
	for _, dependency := range model.Dependencies {
		key := dependency.FromRule + "\x00" + dependency.ToRule + "\x00" + dependency.Relation
		if seenDependencies[key] {
			add(dependency.FromRule, "dependencies", "duplicate", "依赖边重复")
		}
		seenDependencies[key] = true
		if _, exists := ruleByID[dependency.FromRule]; !exists {
			add(dependency.FromRule, "from_rule", "unknown", "依赖起点规则不存在")
		}
		if _, exists := ruleByID[dependency.ToRule]; !exists {
			add(dependency.ToRule, "to_rule", "unknown", "依赖终点规则不存在")
		}
		if dependency.FromRule == dependency.ToRule {
			add(dependency.FromRule, "dependencies", "self_cycle", "规则不得依赖自身")
		}
		if dependency.Relation != "precedes" && dependency.Relation != "requires" {
			add(dependency.FromRule, "relation", "unknown", "依赖关系只能是 precedes 或 requires")
		}
		if dependency.Condition == "" {
			add(dependency.FromRule, "condition", "missing", "依赖边必须说明适用条件")
		}
		adjacency[dependency.FromRule] = append(adjacency[dependency.FromRule], dependency.ToRule)
	}
	if cycle := dependencyCycle(ruleByID, adjacency); len(cycle) > 0 {
		add(model.ModelID, "dependencies", "cycle", "规则依赖图存在环: "+strings.Join(cycle, " -> "))
	}

	seenConflicts := map[string]bool{}
	allowedConflictRelation := map[string]bool{"blocks": true, "exclusive_with": true, "requires": true}
	allowedConflictStatus := map[string]bool{"research_only": true, "deferred": true, "approved_engineering_boundary": true}
	for _, conflict := range conflicts {
		if conflict.ConflictID == "" || seenConflicts[conflict.ConflictID] {
			add(conflict.ConflictID, "conflict_id", "duplicate_or_missing", "冲突 ID 必须唯一且非空")
		}
		seenConflicts[conflict.ConflictID] = true
		if _, exists := ruleByID[conflict.LeftRule]; !exists {
			add(conflict.ConflictID, "left_rule", "unknown", "左侧规则不存在")
		}
		if _, exists := ruleByID[conflict.RightRule]; !exists {
			add(conflict.ConflictID, "right_rule", "unknown", "右侧规则不存在")
		}
		if conflict.LeftRule == conflict.RightRule {
			add(conflict.ConflictID, "rules", "self_conflict", "冲突两端不得是同一规则")
		}
		if !allowedConflictRelation[conflict.Relation] || !allowedConflictStatus[conflict.Status] {
			add(conflict.ConflictID, "relation_or_status", "unknown", "冲突关系或状态不受支持")
		}
		if conflict.OverlapCondition == "" || conflict.Resolution == "" || conflict.Note == "" {
			add(conflict.ConflictID, "conflict", "incomplete", "重叠条件、裁决和备注均不能为空")
		}
	}

	for _, required := range []string{
		"CTC-001", "CTC-002", "CTC-003", "CTC-004", "CTC-005", "CTC-006", "CTC-007",
		"CTC-008", "CTC-009", "CTC-010", "CTC-011", "CTC-012", "CTC-013", "CTC-014",
	} {
		if !seenConflicts[required] {
			add(required, "conflict_id", "required_missing", "已知高风险交叠必须在冲突表中明示")
		}
	}
	sort.Slice(issues, func(i, j int) bool {
		return issues[i].ObjectID+"\x00"+issues[i].Field+"\x00"+issues[i].Code < issues[j].ObjectID+"\x00"+issues[j].Field+"\x00"+issues[j].Code
	})
	return issues
}

func dependencyCycle(rules map[string]ContextualToneRule, adjacency map[string][]string) []string {
	state := map[string]int{}
	stack := []string{}
	var visit func(string) []string
	visit = func(node string) []string {
		state[node] = 1
		stack = append(stack, node)
		for _, next := range adjacency[node] {
			if state[next] == 0 {
				if cycle := visit(next); len(cycle) > 0 {
					return cycle
				}
			} else if state[next] == 1 {
				for index, value := range stack {
					if value == next {
						return append(append([]string(nil), stack[index:]...), next)
					}
				}
			}
		}
		stack = stack[:len(stack)-1]
		state[node] = 2
		return nil
	}
	ids := make([]string, 0, len(rules))
	for id := range rules {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if state[id] == 0 {
			if cycle := visit(id); len(cycle) > 0 {
				return cycle
			}
		}
	}
	return nil
}

func RunContextualToneModelAudit(config ContextualToneModelAuditConfig) (ContextualToneModelAuditResult, error) {
	if err := validateContextualToneModelAuditConfig(&config); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	before, err := hashNamedFiles(map[string]string{"model": config.ModelPath, "conflicts": config.ConflictsPath})
	if err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	model, err := LoadContextualToneModel(config.ModelPath)
	if err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	conflicts, err := LoadContextualToneConflicts(config.ConflictsPath)
	if err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	issues := ValidateContextualToneModel(model, conflicts)
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_before.json"), before); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "rule_order.tsv"), contextualToneRuleRows(model)); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "conflict_report.tsv"), contextualToneConflictRows(conflicts)); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "validation_issues.tsv"), contextualToneIssueRows(issues)); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	after, err := hashNamedFiles(map[string]string{"model": config.ModelPath, "conflicts": config.ConflictsPath})
	if err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "input_hashes_after.json"), after); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	deferredRules, deferredConflicts := 0, 0
	for _, rule := range model.Rules {
		if rule.Activation == "deferred" {
			deferredRules++
		}
	}
	for _, conflict := range conflicts {
		if conflict.Status == "deferred" {
			deferredConflicts++
		}
	}
	hashesMatch := equalHashes(before, after)
	summary := ContextualToneModelAuditSummary{
		ToolVersion: ContextualToneModelToolVersion, SchemaVersion: model.SchemaVersion, ModelID: model.ModelID,
		LayerCount: len(model.Layers), RuleCount: len(model.Rules), DependencyCount: len(model.Dependencies),
		ConflictCount: len(conflicts), DeferredRuleCount: deferredRules, DeferredConflictCount: deferredConflicts,
		ValidationIssueCount: len(issues), RuntimeAliasesGenerated: 0, InputHashesMatch: hashesMatch,
		Gates: map[string]bool{
			"model_structure_valid":    len(issues) == 0,
			"dependency_graph_acyclic": len(dependencyCycle(ruleMap(model.Rules), dependencyAdjacency(model.Dependencies))) == 0,
			"bounded_non_recursive":    model.MaximumGlobalPasses == 1 && allRulesNonRecursive(model.Rules),
			"known_conflicts_explicit": len(conflicts) >= 14,
			"runtime_output_zero":      true,
			"source_files_unchanged":   hashesMatch,
		},
	}
	summary.Passed = allGatesPass(summary.Gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	if err := os.WriteFile(filepath.Join(config.OutputDir, "REPORT.md"), []byte(contextualToneReport(model, summary)), 0o644); err != nil {
		return ContextualToneModelAuditResult{}, err
	}
	result := ContextualToneModelAuditResult{Summary: summary, Issues: issues}
	if !summary.Passed {
		return result, fmt.Errorf("统一语境调层—质层假设模型审计未通过：%d 个问题", len(issues))
	}
	return result, nil
}

func validateContextualToneModelAuditConfig(config *ContextualToneModelAuditConfig) error {
	if config.RepoRoot == "" || config.ModelPath == "" || config.ConflictsPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("RepoRoot、ModelPath、ConflictsPath、OutputDir 和 AllowedOutputRoot 均不能为空")
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
	if filepath.Base(output) != "contextual-tone-model-audit" {
		return fmt.Errorf("统一模型输出目录名必须是 contextual-tone-model-audit：%s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}

func contextualToneRuleRows(model ContextualToneModel) [][]string {
	layers := map[string]ContextualToneLayer{}
	for _, layer := range model.Layers {
		layers[layer.LayerID] = layer
	}
	rules := append([]ContextualToneRule(nil), model.Rules...)
	sort.Slice(rules, func(i, j int) bool {
		left, right := layers[rules[i].LayerID], layers[rules[j].LayerID]
		if left.Order != right.Order {
			return left.Order < right.Order
		}
		return rules[i].RuleID < rules[j].RuleID
	})
	rows := [][]string{{"layer_order", "layer_id", "rule_id", "name", "activation", "scope", "recursive", "maximum_applications_per_syllable", "reads", "writes"}}
	for _, rule := range rules {
		rows = append(rows, []string{strconv.Itoa(layers[rule.LayerID].Order), rule.LayerID, rule.RuleID, rule.Name, rule.Activation, rule.Scope, strconv.FormatBool(rule.Recursive), strconv.Itoa(rule.MaximumApplicationsPerSyllable), strings.Join(rule.Reads, ","), strings.Join(rule.Writes, ",")})
	}
	return rows
}

func contextualToneConflictRows(conflicts []ContextualToneConflict) [][]string {
	items := append([]ContextualToneConflict(nil), conflicts...)
	sort.Slice(items, func(i, j int) bool { return items[i].ConflictID < items[j].ConflictID })
	rows := [][]string{{"conflict_id", "left_rule", "right_rule", "overlap_condition", "relation", "resolution", "status", "note", "validation"}}
	for _, item := range items {
		rows = append(rows, []string{item.ConflictID, item.LeftRule, item.RightRule, item.OverlapCondition, item.Relation, item.Resolution, item.Status, item.Note, "checked"})
	}
	return rows
}

func contextualToneIssueRows(issues []ContextualToneModelIssue) [][]string {
	rows := [][]string{{"object_id", "field", "code", "detail"}}
	for _, issue := range issues {
		rows = append(rows, []string{issue.ObjectID, issue.Field, issue.Code, issue.Detail})
	}
	return rows
}

func contextualToneReport(model ContextualToneModel, summary ContextualToneModelAuditSummary) string {
	return fmt.Sprintf(`# 统一语境调层—质层假设模型审计报告

> 本模型是可证伪、可替换、可逐步修订的工程假设，不是对普通话全部语流事实的定论。

- 模型：%s（revision %d）
- 求值：%s；全局最多 %d 轮
- 规则：%d；依赖边：%d；显式冲突：%d
- 暂缓规则：%d；暂缓冲突：%d
- 结构问题：%d
- 运行时候选：%d
- 输入文件前后哈希一致：%t
- 审计通过：%t

当前报告只验证离线模型的结构、偏序、冲突覆盖和只读边界；不生成词典，不访问或修改 PIME/Rime，不证明规则符合全部语言事实。
`, model.ModelID, model.Revision, model.EvaluationStrategy, model.MaximumGlobalPasses, summary.RuleCount, summary.DependencyCount, summary.ConflictCount, summary.DeferredRuleCount, summary.DeferredConflictCount, summary.ValidationIssueCount, summary.RuntimeAliasesGenerated, summary.InputHashesMatch, summary.Passed)
}

func ruleMap(rules []ContextualToneRule) map[string]ContextualToneRule {
	result := make(map[string]ContextualToneRule, len(rules))
	for _, rule := range rules {
		result[rule.RuleID] = rule
	}
	return result
}

func dependencyAdjacency(dependencies []ContextualToneDependency) map[string][]string {
	result := map[string][]string{}
	for _, dependency := range dependencies {
		result[dependency.FromRule] = append(result[dependency.FromRule], dependency.ToRule)
	}
	return result
}

func allRulesNonRecursive(rules []ContextualToneRule) bool {
	for _, rule := range rules {
		if rule.Recursive || rule.MaximumApplicationsPerSyllable != 1 {
			return false
		}
	}
	return true
}

func stringSlicesEqual(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
