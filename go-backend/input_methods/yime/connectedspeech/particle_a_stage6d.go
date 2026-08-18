package connectedspeech

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const (
	ParticleAStage6DToolVersion       = "connected-speech-particle-a-stage6d-runtime-v2"
	particleAStage6DWeight            = 1
	particleAStage6DExpectedExcluded  = 42
	particleAStage6DExpectedMedialXAX = 29
)

type ParticleAStage6DConfig struct {
	RepoRoot         string
	DataDir          string
	OutputDir        string
	ScopePath        string
	ProjectionPath   string
	RuntimeScopePath string
	ExclusionPath    string
}

type ParticleAStage6DSummary struct {
	ToolVersion                  string          `json:"tool_version"`
	ExcludedCandidateCount       int             `json:"excluded_candidate_count"`
	EligibleCandidateCount       int             `json:"eligible_candidate_count"`
	EligibleOccurrenceCount      int             `json:"eligible_occurrence_count"`
	RetainedMedialCandidateCount int             `json:"retained_medial_candidate_count"`
	FinalCandidateCount          int             `json:"final_candidate_count"`
	KeyChangingCandidateCount    int             `json:"key_changing_candidate_count"`
	SharedKeyCandidateCount      int             `json:"shared_key_candidate_count"`
	MaterializedCandidateCount   int             `json:"materialized_candidate_count"`
	ModeRowCounts                map[string]int  `json:"mode_row_counts"`
	ThreeModeRowCount            int             `json:"three_mode_row_count"`
	FixedRuntimeWeight           int             `json:"fixed_runtime_weight"`
	CanonicalRoutesPreserved     bool            `json:"canonical_routes_preserved"`
	ClassOccurrenceCounts        map[string]int  `json:"class_occurrence_counts"`
	Gates                        map[string]bool `json:"gates"`
	Passed                       bool            `json:"passed"`
}

type ParticleAStage6DManifest struct {
	ToolVersion  string                  `json:"tool_version"`
	InputSHA256  map[string]string       `json:"input_sha256"`
	OutputSHA256 map[string]string       `json:"output_sha256"`
	Summary      ParticleAStage6DSummary `json:"summary"`
}

type particleAStage6DCandidate struct {
	ID              string
	Text            string
	Weight          string
	Canonical       codemode.Record
	Surface         codemode.Record
	OccurrenceCount int
	HasMedial       bool
	HasFinal        bool
}

type particleAStage6DEntry struct {
	RecordID string
	Text     string
	Code     string
}

func DefaultParticleAStage6DConfig(repoRoot string) ParticleAStage6DConfig {
	dataDir := filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data")
	base := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	return ParticleAStage6DConfig{
		RepoRoot: repoRoot, DataDir: dataDir, OutputDir: dataDir,
		ScopePath:        filepath.Join(base, "particle_a_stage6a_scope.tsv"),
		ProjectionPath:   filepath.Join(base, "particle_a_stage6b_projection.tsv"),
		RuntimeScopePath: filepath.Join(base, "particle_a_stage6d_runtime_scope.tsv"),
		ExclusionPath:    filepath.Join(dataDir, "yime_system_candidate_exclusions.tsv"),
	}
}

// RunParticleAStage6DRuntime derives parallel surface-pronunciation routes for
// every explicit a5 occurrence that survives the source gate. Final a5 is in
// scope; medial a5 is admitted only in an immediate X-a-X reduplication. The
// 42 untraceable medial fragments are excluded as whole candidate texts.
func RunParticleAStage6DRuntime(config ParticleAStage6DConfig) (ParticleAStage6DManifest, error) {
	if config.RepoRoot == "" || config.DataDir == "" || config.OutputDir == "" || config.ScopePath == "" || config.ProjectionPath == "" || config.RuntimeScopePath == "" || config.ExclusionPath == "" {
		return ParticleAStage6DManifest{}, errors.New("阶段 6D 所有路径均不能为空")
	}
	if err := validateParticleAStage6DRuntimeScope(config.RuntimeScopePath); err != nil {
		return ParticleAStage6DManifest{}, err
	}
	scope, err := loadParticleAScope(config.ScopePath)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	if err := validateParticleAScope(scope); err != nil {
		return ParticleAStage6DManifest{}, err
	}
	projection, err := loadParticleAStage6BPolicy(config.ProjectionPath)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	if err := validateParticleAStage6BPolicy(projection); err != nil {
		return ParticleAStage6DManifest{}, err
	}
	projectionByClass := map[string]particleAProjectionClass{}
	for _, item := range projection {
		projectionByClass[item.ClassID] = item
	}
	exclusions, err := loadParticleAStage6DExclusions(config.ExclusionPath)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	if len(exclusions) != particleAStage6DExpectedExcluded {
		return ParticleAStage6DManifest{}, fmt.Errorf("阶段 6D 来源排除项=%d，预期 %d", len(exclusions), particleAStage6DExpectedExcluded)
	}

	inputPaths := map[string]string{
		"scope": config.ScopePath, "projection_policy": config.ProjectionPath,
		"runtime_scope": config.RuntimeScopePath, "candidate_exclusions": config.ExclusionPath,
		"pinyin_codes":  filepath.Join(config.DataDir, "yime_pinyin_codes.tsv"),
		"decomposition": filepath.Join(config.DataDir, "yime_syllable_decomposition.tsv"),
		"layout":        filepath.Join(config.DataDir, "yime_yinyuan_layout.json"),
		"full":          filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable":      filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand":     filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	codes, err := loadCanonicalCodeRows(inputPaths["pinyin_codes"])
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	inverse := buildCanonicalInverse(codes)
	inventory, err := LoadInventory(inputPaths["decomposition"])
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	decomposition, err := loadParticleADecomposition(inputPaths["decomposition"])
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	profile, err := layoutdesigner.LoadProfile(inputPaths["layout"])
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	a5Code := strings.TrimSpace(codes["a5"])
	if a5Code == "" {
		return ParticleAStage6DManifest{}, errors.New("规范码表缺少 a5")
	}

	candidates := []particleAStage6DCandidate{}
	seenCanonicalKeys := map[string]bool{}
	exclusionSeen := map[string]bool{}
	unresolved := []string{}
	classOccurrences := map[string]int{}
	err = scanRimeDictionary(inputPaths["full"], func(entry dictionaryEntry) {
		parts := strings.Fields(entry.Code)
		characters := []rune(entry.Text)
		if !strings.ContainsRune(entry.Text, '啊') {
			return
		}
		if len(characters) != len(parts) {
			unresolved = append(unresolved, fmt.Sprintf("%s(text=%d,syllables=%d)", entry.Text, len(characters), len(parts)))
			return
		}
		if exclusions[entry.Text] {
			for index, character := range characters {
				if character == '啊' && index > 0 && index < len(characters)-1 && parts[index] == a5Code {
					exclusionSeen[entry.Text] = true
				}
			}
			return
		}
		positions := []int{}
		hasMedial, hasFinal := false, false
		for index, character := range characters {
			if character != '啊' || index == 0 || parts[index] != a5Code {
				continue
			}
			if index < len(characters)-1 {
				if characters[index-1] != characters[index+1] {
					unresolved = append(unresolved, entry.Text)
					continue
				}
				hasMedial = true
			} else {
				hasFinal = true
			}
			positions = append(positions, index)
		}
		if len(positions) == 0 {
			return
		}
		canonicalKey := dictionaryKey(entry.Text, strings.Join(parts, " "))
		if seenCanonicalKeys[canonicalKey] {
			return
		}
		seenCanonicalKeys[canonicalKey] = true

		sequence := make(YinyuanSequence, len(parts))
		for index, code := range parts {
			choices := inverse[code]
			if len(choices) == 0 || !sameToneIdentity(choices) {
				unresolved = append(unresolved, entry.Text+":ambiguous="+code)
				return
			}
			tuple, tupleErr := uniqueTupleForChoices(choices, inventory)
			if tupleErr != nil {
				unresolved = append(unresolved, entry.Text+":"+tupleErr.Error())
				return
			}
			sequence[index] = tuple
		}
		canonical, projectErr := projectSequence(sequence, profile)
		if projectErr != nil || canonical.FullSpelling != strings.Join(parts, " ") {
			unresolved = append(unresolved, entry.Text+":canonical_projection")
			return
		}
		surfaceSequence := append(YinyuanSequence(nil), sequence...)
		for _, index := range positions {
			previousChoices := inverse[parts[index-1]]
			classID, _, classErr := classifyParticleAPrevious(previousChoices, decomposition)
			if classErr != nil {
				unresolved = append(unresolved, entry.Text+":"+classErr.Error())
				return
			}
			class, ok := projectionByClass[classID]
			if !ok {
				unresolved = append(unresolved, entry.Text+":missing_class="+classID)
				return
			}
			target, targetErr := particleAStage6BTargetTuple(class, inventory)
			if targetErr != nil {
				unresolved = append(unresolved, entry.Text+":"+targetErr.Error())
				return
			}
			surfaceSequence[index] = target
			classOccurrences[classID]++
		}
		surface, projectErr := projectSequence(surfaceSequence, profile)
		if projectErr != nil || !modeLengthProjectionValid(canonical, surface) {
			unresolved = append(unresolved, entry.Text+":surface_projection")
			return
		}
		if codeLength(surface.FullSpelling) > codeLength(canonical.FullSpelling) || codeLength(surface.VariableSpelling) > codeLength(canonical.VariableSpelling) || codeLength(surface.ShorthandSpelling) > codeLength(canonical.ShorthandSpelling) {
			unresolved = append(unresolved, entry.Text+":surface_longer")
			return
		}
		candidates = append(candidates, particleAStage6DCandidate{
			Text: entry.Text, Weight: entry.Weight, Canonical: canonical, Surface: surface,
			OccurrenceCount: len(positions), HasMedial: hasMedial, HasFinal: hasFinal,
		})
	})
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	if len(unresolved) > 0 {
		sort.Strings(unresolved)
		if len(unresolved) > 10 {
			unresolved = unresolved[:10]
		}
		return ParticleAStage6DManifest{}, fmt.Errorf("阶段 6D 出现未审定或无法投影的啊记录: %s", strings.Join(unresolved, ", "))
	}
	if len(exclusionSeen) != len(exclusions) {
		missing := []string{}
		for text := range exclusions {
			if !exclusionSeen[text] {
				missing = append(missing, text)
			}
		}
		sort.Strings(missing)
		return ParticleAStage6DManifest{}, fmt.Errorf("阶段 6D 排除表有 %d 条未匹配当前词典: %s", len(missing), strings.Join(missing, ","))
	}
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].Text+"\x00"+candidates[i].Canonical.FullSpelling < candidates[j].Text+"\x00"+candidates[j].Canonical.FullSpelling
	})
	for index := range candidates {
		candidates[index].ID = fmt.Sprintf("PA-6D-%05d", index+1)
	}

	modes := []string{"full", "variable", "shorthand"}
	canonicalWanted := map[string]map[string]string{}
	surfaceWanted := map[string]map[string]bool{}
	canonicalSeen := map[string]map[string]bool{}
	surfaceSeen := map[string]map[string]bool{}
	for _, mode := range modes {
		canonicalWanted[mode], surfaceWanted[mode] = map[string]string{}, map[string]bool{}
		canonicalSeen[mode], surfaceSeen[mode] = map[string]bool{}, map[string]bool{}
		for _, candidate := range candidates {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode)
			canonicalWanted[mode][dictionaryKey(candidate.Text, canonicalCode)] = candidate.Weight
			surfaceWanted[mode][dictionaryKey(candidate.Text, surfaceCode)] = true
		}
		if err := scanRimeDictionary(inputPaths[mode], func(entry dictionaryEntry) {
			key := dictionaryKey(entry.Text, strings.Join(strings.Fields(entry.Code), " "))
			if expected, ok := canonicalWanted[mode][key]; ok && entry.Weight == expected {
				canonicalSeen[mode][key] = true
			}
			if surfaceWanted[mode][key] {
				surfaceSeen[mode][key] = true
			}
		}); err != nil {
			return ParticleAStage6DManifest{}, err
		}
		if len(canonicalSeen[mode]) != len(canonicalWanted[mode]) {
			return ParticleAStage6DManifest{}, fmt.Errorf("阶段 6D %s 规范路线匹配=%d/%d", mode, len(canonicalSeen[mode]), len(canonicalWanted[mode]))
		}
	}

	entriesByMode := map[string][]particleAStage6DEntry{"full": {}, "variable": {}, "shorthand": {}}
	emittedByMode := map[string]map[string]bool{"full": {}, "variable": {}, "shorthand": {}}
	keyChanging, sharedKey, materialized := 0, 0, 0
	medialCount, finalCount, occurrenceCount := 0, 0, 0
	for _, candidate := range candidates {
		if candidate.HasMedial {
			medialCount++
		}
		if candidate.HasFinal {
			finalCount++
		}
		occurrenceCount += candidate.OccurrenceCount
		changed, wrote := false, false
		for _, mode := range modes {
			canonicalCode := thirdToneModeCode(candidate.Canonical, mode)
			surfaceCode := thirdToneModeCode(candidate.Surface, mode)
			if surfaceCode == canonicalCode {
				continue
			}
			changed = true
			key := dictionaryKey(candidate.Text, surfaceCode)
			if surfaceSeen[mode][key] || emittedByMode[mode][key] {
				continue
			}
			emittedByMode[mode][key] = true
			entriesByMode[mode] = append(entriesByMode[mode], particleAStage6DEntry{RecordID: candidate.ID, Text: candidate.Text, Code: surfaceCode})
			wrote = true
		}
		if changed {
			keyChanging++
		} else {
			sharedKey++
		}
		if wrote {
			materialized++
		}
	}
	if medialCount != particleAStage6DExpectedMedialXAX {
		return ParticleAStage6DManifest{}, fmt.Errorf("阶段 6D 保留句中 X啊X=%d，预期 %d", medialCount, particleAStage6DExpectedMedialXAX)
	}

	if err := os.MkdirAll(config.OutputDir, 0o755); err != nil {
		return ParticleAStage6DManifest{}, err
	}
	outputs := map[string]string{}
	modeRowCounts, totalRows := map[string]int{}, 0
	for _, mode := range modes {
		sort.Slice(entriesByMode[mode], func(i, j int) bool {
			return entriesByMode[mode][i].RecordID+"\x00"+entriesByMode[mode][i].Code < entriesByMode[mode][j].RecordID+"\x00"+entriesByMode[mode][j].Code
		})
		name := "yime_particle_a_stage6d_" + mode + ".dict.yaml"
		path := filepath.Join(config.OutputDir, name)
		if err := writeParticleAStage6DDictionary(path, mode, entriesByMode[mode]); err != nil {
			return ParticleAStage6DManifest{}, err
		}
		outputs[name] = path
		modeRowCounts[mode] = len(entriesByMode[mode])
		totalRows += len(entriesByMode[mode])
	}
	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	outputHashes, err := hashNamedFiles(outputs)
	if err != nil {
		return ParticleAStage6DManifest{}, err
	}
	gates := map[string]bool{
		"source_exclusion_scope_exact":       len(exclusionSeen) == particleAStage6DExpectedExcluded,
		"medial_scope_is_reviewed_x_a_x":     medialCount == particleAStage6DExpectedMedialXAX,
		"all_eligible_occurrences_projected": occurrenceCount >= len(candidates),
		"all_six_classes_represented":        len(classOccurrences) == 6,
		"three_modes_derived":                len(modeRowCounts) == 3,
		"fixed_low_initial_weight":           particleAStage6DWeight == 1,
		"canonical_routes_preserved":         true,
		"candidate_text_unchanged":           true,
		"inputs_are_read_only":               equalHashes(before, after),
	}
	summary := ParticleAStage6DSummary{
		ToolVersion: ParticleAStage6DToolVersion, ExcludedCandidateCount: len(exclusionSeen), EligibleCandidateCount: len(candidates),
		EligibleOccurrenceCount: occurrenceCount, RetainedMedialCandidateCount: medialCount, FinalCandidateCount: finalCount,
		KeyChangingCandidateCount: keyChanging, SharedKeyCandidateCount: sharedKey, MaterializedCandidateCount: materialized,
		ModeRowCounts: modeRowCounts, ThreeModeRowCount: totalRows, FixedRuntimeWeight: particleAStage6DWeight,
		CanonicalRoutesPreserved: true, ClassOccurrenceCounts: classOccurrences, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	manifest := ParticleAStage6DManifest{ToolVersion: ParticleAStage6DToolVersion, InputSHA256: before, OutputSHA256: outputHashes, Summary: summary}
	if err := writeJSON(filepath.Join(config.OutputDir, "yime_particle_a_stage6d_manifest.json"), manifest); err != nil {
		return ParticleAStage6DManifest{}, err
	}
	if !summary.Passed {
		return manifest, errors.New("阶段 6D 全量运行别名门禁未通过")
	}
	return manifest, nil
}

func validateParticleAStage6DRuntimeScope(path string) error {
	rows, err := readParticleAStage6CTSV(path, []string{"scope_id", "condition", "treatment", "candidate_policy", "runtime_enabled", "note"})
	if err != nil {
		return err
	}
	want := map[string]struct{ treatment, policy, enabled string }{
		"FINAL_WITH_HOST_A5":                {"apply_previous_final_assimilation", "parallel_alias_keep_canonical", "true"},
		"MEDIAL_IMMEDIATE_REDUPLICATION_A5": {"apply_previous_final_assimilation", "parallel_alias_keep_canonical", "true"},
		"MEDIAL_UNVERIFIABLE_FRAGMENT":      {"exclude_visible_candidate", "system_candidate_exclusion_gate", "false"},
		"INITIAL_NO_HOST":                   {"keep_canonical_no_assimilation", "canonical_only", "false"},
		"NON_A5":                            {"keep_canonical_no_assimilation", "canonical_only", "false"},
	}
	seen := map[string]bool{}
	for _, row := range rows {
		expected, ok := want[row[0]]
		if !ok || seen[row[0]] || row[1] == "" || row[2] != expected.treatment || row[3] != expected.policy || row[4] != expected.enabled || row[5] == "" {
			return fmt.Errorf("阶段 6D 运行范围无效: %v", row)
		}
		seen[row[0]] = true
	}
	if len(seen) != len(want) {
		return fmt.Errorf("阶段 6D 运行范围=%d，预期 %d", len(seen), len(want))
	}
	return nil
}

func loadParticleAStage6DExclusions(path string) (map[string]bool, error) {
	rows, err := readParticleAStage6CTSV(path, []string{"text", "category", "source_snapshot", "decision", "note"})
	if err != nil {
		return nil, err
	}
	result := map[string]bool{}
	for _, row := range rows {
		if row[0] == "" || row[1] != "unverifiable_particle_a_fragment" || row[2] != "wanxiang" || row[3] != "exclude_runtime_candidate" || row[4] == "" || result[row[0]] {
			return nil, fmt.Errorf("阶段 6D 来源排除行无效: %v", row)
		}
		characters := []rune(row[0])
		if len(characters) != 3 || characters[1] != '啊' || characters[0] == characters[2] {
			return nil, fmt.Errorf("阶段 6D 排除项不是非重叠句中啊截片: %s", row[0])
		}
		result[row[0]] = true
	}
	return result, nil
}

func writeParticleAStage6DDictionary(path, mode string, entries []particleAStage6DEntry) error {
	lines := []string{
		"# Rime dictionary",
		"# GENERATED FILE - all source-screened particle-a surface aliases; canonical a5 routes remain available.",
		"---", "name: yime_particle_a_stage6d_" + mode, "version: \"particle-a-stage6d-v2\"",
		"sort: by_weight", "use_preset_vocabulary: false", "...",
	}
	for _, entry := range entries {
		if entry.Text == "" || entry.Code == "" || len(strings.Fields(entry.Code)) != utf8.RuneCountInString(entry.Text) {
			return fmt.Errorf("阶段 6D %s 输出音节边界无效: %+v", mode, entry)
		}
		lines = append(lines, fmt.Sprintf("%s\t%s\t%d", entry.Text, entry.Code, particleAStage6DWeight))
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
