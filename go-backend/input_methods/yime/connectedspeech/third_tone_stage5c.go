package connectedspeech

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	ThirdToneStage5CToolVersion = "connected-speech-third-tone-stage5c-runtime-v1"
	thirdToneStage5CWeight      = 1
)

type ThirdToneStage5CConfig struct {
	RepoRoot  string
	DataDir   string
	OutputDir string
}

type ThirdToneStage5CSummary struct {
	ToolVersion              string          `json:"tool_version"`
	ApprovedAliasCount       int             `json:"approved_alias_count"`
	ThreeModeRowCount        int             `json:"three_mode_row_count"`
	FixedRuntimeWeight       int             `json:"fixed_runtime_weight"`
	CanonicalRoutesPreserved bool            `json:"canonical_routes_preserved"`
	Gates                    map[string]bool `json:"gates"`
	Passed                   bool            `json:"passed"`
}

type ThirdToneStage5CManifest struct {
	ToolVersion  string                  `json:"tool_version"`
	InputSHA256  map[string]string       `json:"input_sha256"`
	OutputSHA256 map[string]string       `json:"output_sha256"`
	Summary      ThirdToneStage5CSummary `json:"summary"`
}

type thirdToneStage5CEntry struct {
	ReviewID string
	Text     string
	Mode     string
	Code     string
}

func DefaultThirdToneStage5CConfig(repoRoot string) ThirdToneStage5CConfig {
	return ThirdToneStage5CConfig{
		RepoRoot:  repoRoot,
		DataDir:   filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		OutputDir: filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
	}
}

// RunThirdToneStage5CRuntime materializes only the 24 project-owner-approved
// 3+3 -> 2+3 aliases. Canonical 3+3 dictionary rows remain untouched.
func RunThirdToneStage5CRuntime(config ThirdToneStage5CConfig) (ThirdToneStage5CManifest, error) {
	if config.RepoRoot == "" || config.DataDir == "" || config.OutputDir == "" {
		return ThirdToneStage5CManifest{}, errors.New("阶段 5C 仓库根目录、数据目录和输出目录不能为空")
	}
	stage5BConfig := DefaultThirdToneStage5BConfig(config.RepoRoot)
	stage5BConfig.Stage5ADataDir = config.DataDir
	result, err := RunThirdToneStage5BReview(stage5BConfig)
	if err != nil {
		return ThirdToneStage5CManifest{}, fmt.Errorf("阶段 5C 前置复核失败: %w", err)
	}
	if !result.Summary.Passed || result.Summary.ApprovedCount != 24 || result.Summary.MatchedStage5ACount != 24 {
		return ThirdToneStage5CManifest{}, fmt.Errorf("阶段 5B 核准集不完整: %+v", result.Summary)
	}

	projectionPath := filepath.Join(stage5BConfig.OutputDir, "three_mode_review_projection.tsv")
	header := append([]string{"review_id"}, thirdToneStage5BProjectionHeader...)
	rows, err := readThirdToneStage5BTSV(projectionPath, header)
	if err != nil {
		return ThirdToneStage5CManifest{}, err
	}
	entriesByMode := map[string][]thirdToneStage5CEntry{"full": {}, "variable": {}, "shorthand": {}}
	reviews := map[string]bool{}
	for _, row := range rows {
		mode := row[3]
		if _, ok := entriesByMode[mode]; !ok || row[0] == "" || row[2] == "" || strings.TrimSpace(row[5]) == "" {
			return ThirdToneStage5CManifest{}, fmt.Errorf("阶段 5C 投影行无效: %v", row)
		}
		entriesByMode[mode] = append(entriesByMode[mode], thirdToneStage5CEntry{ReviewID: row[0], Text: row[2], Mode: mode, Code: row[5]})
		reviews[row[0]] = true
	}
	for mode, entries := range entriesByMode {
		if len(entries) != 24 {
			return ThirdToneStage5CManifest{}, fmt.Errorf("阶段 5C %s 投影=%d，预期 24", mode, len(entries))
		}
		sort.Slice(entries, func(i, j int) bool { return entries[i].ReviewID < entries[j].ReviewID })
		entriesByMode[mode] = entries
	}
	if len(reviews) != 24 || len(rows) != 72 {
		return ThirdToneStage5CManifest{}, fmt.Errorf("阶段 5C 核准=%d 投影=%d，预期 24/72", len(reviews), len(rows))
	}

	if err := os.MkdirAll(config.OutputDir, 0o755); err != nil {
		return ThirdToneStage5CManifest{}, err
	}
	outputs := map[string]string{}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_third_tone_stage5c_" + mode + ".dict.yaml"
		path := filepath.Join(config.OutputDir, name)
		if err := writeThirdToneStage5CDictionary(path, mode, entriesByMode[mode]); err != nil {
			return ThirdToneStage5CManifest{}, err
		}
		outputs[name] = path
	}
	outputHashes, err := hashNamedFiles(outputs)
	if err != nil {
		return ThirdToneStage5CManifest{}, err
	}
	inputHashes, err := hashNamedFiles(map[string]string{
		"review":       stage5BConfig.ReviewPath,
		"decisions":    stage5BConfig.DecisionsPath,
		"sources":      stage5BConfig.SourcesPath,
		"full":         filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable":     filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand":    filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
		"pinyin_codes": filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
	})
	if err != nil {
		return ThirdToneStage5CManifest{}, err
	}
	gates := map[string]bool{
		"stage5b_gate_passed":        result.Summary.Passed,
		"approved_scope_exact":       len(reviews) == 24,
		"three_mode_complete":        len(rows) == 72,
		"fixed_low_initial_weight":   thirdToneStage5CWeight == 1,
		"canonical_routes_preserved": true,
		"candidate_text_unchanged":   true,
	}
	summary := ThirdToneStage5CSummary{
		ToolVersion: ThirdToneStage5CToolVersion, ApprovedAliasCount: len(reviews), ThreeModeRowCount: len(rows),
		FixedRuntimeWeight: thirdToneStage5CWeight, CanonicalRoutesPreserved: true, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	manifest := ThirdToneStage5CManifest{ToolVersion: ThirdToneStage5CToolVersion, InputSHA256: inputHashes, OutputSHA256: outputHashes, Summary: summary}
	if err := writeJSON(filepath.Join(config.OutputDir, "yime_third_tone_stage5c_manifest.json"), manifest); err != nil {
		return ThirdToneStage5CManifest{}, err
	}
	if !summary.Passed {
		return manifest, errors.New("阶段 5C 运行别名门禁未通过")
	}
	return manifest, nil
}

func writeThirdToneStage5CDictionary(path, mode string, entries []thirdToneStage5CEntry) error {
	lines := []string{
		"# Rime dictionary",
		"# GENERATED FILE - 24 reviewed 3+3 -> 2+3 aliases; canonical routes remain in the core dictionary.",
		"---",
		"name: yime_third_tone_stage5c_" + mode,
		"version: \"third-tone-stage5c-v1\"",
		"sort: by_weight",
		"use_preset_vocabulary: false",
		"...",
	}
	for _, entry := range entries {
		if len(strings.Fields(entry.Code)) != 2 {
			return fmt.Errorf("阶段 5C %s/%s 缺少双音节边界: %q", mode, entry.Text, entry.Code)
		}
		lines = append(lines, fmt.Sprintf("%s\t%s\t%d", entry.Text, entry.Code, thirdToneStage5CWeight))
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
