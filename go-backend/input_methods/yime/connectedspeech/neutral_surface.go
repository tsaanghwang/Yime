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
)

const NeutralSurfaceAuditToolVersion = "neutral-tone-context-projection-v1"

type NeutralSurfaceAuditConfig struct {
	RepoRoot          string
	ClassesPath       string
	CatalogPath       string
	DecompositionPath string
	OutputDir         string
	AllowedOutputRoot string
}

type NeutralSurfaceSummary struct {
	ToolVersion                    string          `json:"tool_version"`
	ContextClassCount              int             `json:"context_class_count"`
	SurfacePitchLevelCount         int             `json:"surface_pitch_level_count"`
	ProjectedGradeCount            int             `json:"projected_grade_count"`
	ProjectionCollisionBucketCount int             `json:"projection_collision_bucket_count"`
	ContextualIdentityCount        int             `json:"contextual_identity_count"`
	YinyuanEntryCount              int             `json:"yinyuan_entry_count"`
	RewriteMapRowCount             int             `json:"rewrite_map_row_count"`
	NeutralSyllableCount           int             `json:"neutral_syllable_count"`
	SyllableProjectionCount        int             `json:"syllable_projection_count"`
	CompatibilityTupleMatchCount   int             `json:"compatibility_tuple_match_count"`
	SameBaseTone3CollisionCount    int             `json:"same_base_tone3_collision_count"`
	AmbiguousTupleObservationCount int             `json:"ambiguous_tuple_observation_count"`
	IssueCount                     int             `json:"issue_count"`
	RuntimeAliasesGenerated        int             `json:"runtime_aliases_generated"`
	InputHashesMatch               bool            `json:"input_hashes_match"`
	Gates                          map[string]bool `json:"gates"`
	Passed                         bool            `json:"passed"`
}

type NeutralSurfaceManifest struct {
	ToolVersion     string            `json:"tool_version"`
	InputSHA256     map[string]string `json:"input_sha256"`
	OutputSHA256    map[string]string `json:"output_sha256"`
	OutputHashScope string            `json:"output_hash_scope"`
}

type NeutralSurfaceAuditResult struct {
	Summary  NeutralSurfaceSummary
	Manifest NeutralSurfaceManifest
}

type neutralContextClass struct {
	ClassID                  string
	ConditioningSurfaceTone  int
	SurfacePitchLevel        int
	ExpectedProjectedGrade   string
	ConditioningStage        string
	AdjudicationStatus       string
	Note                     string
	ActualProjectedToneGrade string
}

type neutralCatalog struct {
	FormatVersion int                   `json:"format_version"`
	Entries       []neutralCatalogEntry `json:"entries"`
}

type neutralCatalogEntry struct {
	ID                   string `json:"id"`
	Category             string `json:"category"`
	QualityGroup         string `json:"quality_group"`
	ToneGrade            string `json:"tone_grade"`
	CoveredPianyinLevels []int  `json:"covered_pianyin_levels"`
}

type neutralSurfaceIssue struct {
	Code   string
	Target string
	Detail string
}

func DefaultNeutralSurfaceAuditConfig(repoRoot string) NeutralSurfaceAuditConfig {
	return NeutralSurfaceAuditConfig{
		RepoRoot:          repoRoot,
		ClassesPath:       filepath.Join(repoRoot, "docs", "project", "connected_speech", "neutral_tone_context_classes.tsv"),
		CatalogPath:       filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "trainer", "yinyuan_catalog.json"),
		DecompositionPath: filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "yime_syllable_decomposition.tsv"),
		OutputDir:         filepath.Join(repoRoot, ".tmp", "neutral-tone-context-audit"),
		AllowedOutputRoot: filepath.Join(repoRoot, ".tmp"),
	}
}

func RunNeutralSurfaceAudit(config NeutralSurfaceAuditConfig) (NeutralSurfaceAuditResult, error) {
	if err := validateNeutralSurfaceAuditConfig(&config); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	if err := prepareOutputDir(config.OutputDir); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	inputPaths := map[string]string{
		"context_classes": config.ClassesPath, "yinyuan_catalog": config.CatalogPath, "syllable_decomposition": config.DecompositionPath,
	}
	before, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	classes, err := loadNeutralContextClasses(config.ClassesPath)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	catalog, err := loadNeutralCatalog(config.CatalogPath)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	inventory, err := LoadInventory(config.DecompositionPath)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}

	issues := []neutralSurfaceIssue{}
	gradeTargets, pitchGrades, musicalEntries := validateNeutralCatalog(catalog, &issues)
	validateNeutralContextClasses(classes, pitchGrades, &issues)
	for index := range classes {
		classes[index].ActualProjectedToneGrade = pitchGrades[classes[index].SurfacePitchLevel]
	}

	classRows := [][]string{{"class_id", "conditioning_surface_tone", "surface_pitch_level", "projected_grade", "conditioning_stage", "adjudication_status", "note"}}
	gradeClasses := map[string][]neutralContextClass{}
	contextKeys := map[string]bool{}
	for _, class := range classes {
		classRows = append(classRows, []string{
			class.ClassID, strconv.Itoa(class.ConditioningSurfaceTone), strconv.Itoa(class.SurfacePitchLevel),
			class.ActualProjectedToneGrade, class.ConditioningStage, class.AdjudicationStatus, class.Note,
		})
		gradeClasses[class.ActualProjectedToneGrade] = append(gradeClasses[class.ActualProjectedToneGrade], class)
		contextKeys[fmt.Sprintf("%d/%s", class.ConditioningSurfaceTone, class.ActualProjectedToneGrade)] = true
	}

	collisionRows := [][]string{{"projected_grade", "class_count", "class_ids", "surface_pitch_levels", "contextual_identity_preserved"}}
	collisionBuckets := 0
	grades := make([]string, 0, len(gradeClasses))
	for grade := range gradeClasses {
		grades = append(grades, grade)
	}
	sort.Strings(grades)
	for _, grade := range grades {
		members := gradeClasses[grade]
		ids := make([]string, 0, len(members))
		levels := make([]string, 0, len(members))
		for _, member := range members {
			ids = append(ids, member.ClassID)
			levels = append(levels, strconv.Itoa(member.SurfacePitchLevel))
		}
		if len(members) > 1 {
			collisionBuckets++
		}
		collisionRows = append(collisionRows, []string{grade, strconv.Itoa(len(members)), strings.Join(ids, ","), strings.Join(levels, ","), "true"})
	}

	rewriteRows := [][]string{{"class_id", "surface_pitch_level", "projected_grade", "source_yinyuan_id", "quality_group", "target_yinyuan_id", "attributes"}}
	for _, class := range classes {
		for _, source := range musicalEntries {
			target := gradeTargets[source.QualityGroup][class.ActualProjectedToneGrade]
			rewriteRows = append(rewriteRows, []string{
				class.ClassID, strconv.Itoa(class.SurfacePitchLevel), class.ActualProjectedToneGrade,
				source.ID, source.QualityGroup, target, "tone_grade",
			})
		}
	}

	entryByID := map[string]neutralCatalogEntry{}
	for _, entry := range musicalEntries {
		entryByID[entry.ID] = entry
	}
	tuplePinyin := map[string][]string{}
	neutralPinyin := []string{}
	for pinyin, tuple := range inventory.Syllables {
		key := neutralTupleKey(tuple)
		tuplePinyin[key] = append(tuplePinyin[key], pinyin)
		if strings.HasSuffix(pinyin, "5") {
			neutralPinyin = append(neutralPinyin, pinyin)
		}
	}
	for key := range tuplePinyin {
		sort.Strings(tuplePinyin[key])
	}
	sort.Strings(neutralPinyin)
	projectionRows := [][]string{{"class_id", "neutral_pinyin", "surface_pitch_level", "projected_grade", "projected_yinyuan_ids", "matching_canonical_pinyin", "matches_compatibility_tuple", "collides_with_same_base_tone3"}}
	compatibilityMatches := 0
	tone3Collisions := 0
	ambiguousObservations := 0
	for _, class := range classes {
		for _, pinyin := range neutralPinyin {
			canonical := inventory.Syllables[pinyin]
			projected, projectErr := projectNeutralTuple(canonical, class.ActualProjectedToneGrade, entryByID, gradeTargets)
			if projectErr != nil {
				issues = append(issues, neutralSurfaceIssue{"syllable_projection_failed", class.ClassID + "/" + pinyin, projectErr.Error()})
				continue
			}
			matches := tuplePinyin[neutralTupleKey(projected)]
			compatibilityMatch := projected == canonical
			baseTone3 := strings.TrimSuffix(pinyin, "5") + "3"
			tone3, hasTone3 := inventory.Syllables[baseTone3]
			tone3Collision := hasTone3 && projected == tone3
			if compatibilityMatch {
				compatibilityMatches++
			}
			if tone3Collision {
				tone3Collisions++
			}
			if len(matches) > 1 {
				ambiguousObservations++
			}
			projectionRows = append(projectionRows, []string{
				class.ClassID, pinyin, strconv.Itoa(class.SurfacePitchLevel), class.ActualProjectedToneGrade,
				strings.Join(projected[:], " "), strings.Join(matches, ","), strconv.FormatBool(compatibilityMatch), strconv.FormatBool(tone3Collision),
			})
		}
	}

	issueRows := [][]string{{"code", "target", "detail"}}
	for _, issue := range issues {
		issueRows = append(issueRows, []string{issue.Code, issue.Target, issue.Detail})
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "context_classes.tsv"), classRows); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "projection_collisions.tsv"), collisionRows); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "yinyuan_rewrite_map.tsv"), rewriteRows); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "syllable_projection_collisions.tsv"), projectionRows); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	if err := writeTSV(filepath.Join(config.OutputDir, "issues.tsv"), issueRows); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}

	after, err := hashNamedFiles(inputPaths)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	hashesMatch := equalHashes(before, after)
	pitchLevels := map[int]bool{}
	for _, class := range classes {
		pitchLevels[class.SurfacePitchLevel] = true
	}
	gates := map[string]bool{
		"four_context_classes":                    len(classes) == 4,
		"four_surface_pitch_levels":               len(pitchLevels) == 4,
		"four_contextual_identities_preserved":    len(contextKeys) == 4,
		"expected_three_to_one_bucket_reported":   collisionBuckets == 1,
		"stable_yinyuan_rewrite_map_complete":     len(rewriteRows)-1 == len(classes)*len(musicalEntries),
		"all_neutral_syllables_projected":         len(projectionRows)-1 == len(classes)*len(neutralPinyin),
		"syllable_projection_collisions_reported": true,
		"post_tone_sandhi_conditioning_only":      allNeutralClassesUseSurfaceCondition(classes),
		"input_hashes_unchanged":                  hashesMatch,
		"runtime_aliases_generated_zero":          true,
		"validation_issues_zero":                  len(issues) == 0,
	}
	summary := NeutralSurfaceSummary{
		ToolVersion: NeutralSurfaceAuditToolVersion, ContextClassCount: len(classes), SurfacePitchLevelCount: len(pitchLevels),
		ProjectedGradeCount: len(gradeClasses), ProjectionCollisionBucketCount: collisionBuckets,
		ContextualIdentityCount: len(contextKeys), YinyuanEntryCount: len(musicalEntries), RewriteMapRowCount: len(rewriteRows) - 1,
		NeutralSyllableCount: len(neutralPinyin), SyllableProjectionCount: len(projectionRows) - 1,
		CompatibilityTupleMatchCount: compatibilityMatches, SameBaseTone3CollisionCount: tone3Collisions,
		AmbiguousTupleObservationCount: ambiguousObservations,
		IssueCount:                     len(issues), RuntimeAliasesGenerated: 0, InputHashesMatch: hashesMatch, Gates: gates,
	}
	summary.Passed = allGatesPass(gates)
	if err := writeJSON(filepath.Join(config.OutputDir, "summary.json"), summary); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}

	outputPaths := map[string]string{
		"context_classes.tsv":                filepath.Join(config.OutputDir, "context_classes.tsv"),
		"projection_collisions.tsv":          filepath.Join(config.OutputDir, "projection_collisions.tsv"),
		"yinyuan_rewrite_map.tsv":            filepath.Join(config.OutputDir, "yinyuan_rewrite_map.tsv"),
		"syllable_projection_collisions.tsv": filepath.Join(config.OutputDir, "syllable_projection_collisions.tsv"),
		"issues.tsv":                         filepath.Join(config.OutputDir, "issues.tsv"),
		"summary.json":                       filepath.Join(config.OutputDir, "summary.json"),
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	manifest := NeutralSurfaceManifest{
		ToolVersion: NeutralSurfaceAuditToolVersion, InputSHA256: before, OutputSHA256: outputHashes,
		OutputHashScope: "all deterministic neutral-tone context audit files except manifest.json",
	}
	if err := writeJSON(filepath.Join(config.OutputDir, "manifest.json"), manifest); err != nil {
		return NeutralSurfaceAuditResult{}, err
	}
	result := NeutralSurfaceAuditResult{Summary: summary, Manifest: manifest}
	if !summary.Passed {
		return result, errors.New("neutral-tone context projection gates did not pass")
	}
	return result, nil
}

func validateNeutralSurfaceAuditConfig(config *NeutralSurfaceAuditConfig) error {
	if config.RepoRoot == "" || config.ClassesPath == "" || config.CatalogPath == "" || config.DecompositionPath == "" || config.OutputDir == "" || config.AllowedOutputRoot == "" {
		return errors.New("all neutral-tone context audit paths are required")
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
	if filepath.Base(output) != "neutral-tone-context-audit" {
		return fmt.Errorf("neutral-tone context output directory must be named neutral-tone-context-audit: %s", output)
	}
	config.OutputDir = output
	config.AllowedOutputRoot = allowed
	return nil
}

func loadNeutralContextClasses(path string) ([]neutralContextClass, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	lineNumber := 0
	result := []neutralContextClass{}
	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if lineNumber == 1 {
			if line != "class_id\tconditioning_surface_tone\tsurface_pitch_level\texpected_projected_grade\tconditioning_stage\tadjudication_status\tnote" {
				return nil, fmt.Errorf("unexpected neutral context header in %s", path)
			}
			continue
		}
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 7 {
			return nil, fmt.Errorf("%s:%d: expected 7 fields, got %d", path, lineNumber, len(fields))
		}
		conditionTone, err := strconv.Atoi(fields[1])
		if err != nil {
			return nil, fmt.Errorf("%s:%d: invalid conditioning tone: %w", path, lineNumber, err)
		}
		pitchLevel, err := strconv.Atoi(fields[2])
		if err != nil {
			return nil, fmt.Errorf("%s:%d: invalid surface pitch level: %w", path, lineNumber, err)
		}
		result = append(result, neutralContextClass{
			ClassID: fields[0], ConditioningSurfaceTone: conditionTone, SurfacePitchLevel: pitchLevel,
			ExpectedProjectedGrade: fields[3], ConditioningStage: fields[4], AdjudicationStatus: fields[5], Note: fields[6],
		})
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func loadNeutralCatalog(path string) (neutralCatalog, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return neutralCatalog{}, err
	}
	var catalog neutralCatalog
	if err := json.Unmarshal(payload, &catalog); err != nil {
		return neutralCatalog{}, fmt.Errorf("decode yinyuan catalog: %w", err)
	}
	return catalog, nil
}

func validateNeutralCatalog(catalog neutralCatalog, issues *[]neutralSurfaceIssue) (map[string]map[string]string, map[int]string, []neutralCatalogEntry) {
	targets := map[string]map[string]string{}
	pitchGrades := map[int]string{}
	musical := []neutralCatalogEntry{}
	for _, entry := range catalog.Entries {
		if entry.Category != "yueyin" {
			continue
		}
		musical = append(musical, entry)
		if entry.QualityGroup == "" || entry.ToneGrade == "" || entry.ID == "" {
			*issues = append(*issues, neutralSurfaceIssue{"invalid_catalog_entry", entry.ID, "musical yinyuan requires id, quality_group, and tone_grade"})
			continue
		}
		if targets[entry.QualityGroup] == nil {
			targets[entry.QualityGroup] = map[string]string{}
		}
		if previous := targets[entry.QualityGroup][entry.ToneGrade]; previous != "" {
			*issues = append(*issues, neutralSurfaceIssue{"duplicate_quality_grade", entry.QualityGroup + "/" + entry.ToneGrade, previous + "," + entry.ID})
		}
		targets[entry.QualityGroup][entry.ToneGrade] = entry.ID
		for _, level := range entry.CoveredPianyinLevels {
			if previous := pitchGrades[level]; previous != "" && previous != entry.ToneGrade {
				*issues = append(*issues, neutralSurfaceIssue{"inconsistent_pitch_grade", strconv.Itoa(level), previous + " vs " + entry.ToneGrade})
			}
			pitchGrades[level] = entry.ToneGrade
		}
	}
	for quality, grades := range targets {
		for _, grade := range []string{"high", "mid", "low"} {
			if grades[grade] == "" {
				*issues = append(*issues, neutralSurfaceIssue{"missing_quality_grade", quality + "/" + grade, "no stable yinyuan target"})
			}
		}
	}
	for level := 1; level <= 5; level++ {
		if pitchGrades[level] == "" {
			*issues = append(*issues, neutralSurfaceIssue{"missing_pitch_level", strconv.Itoa(level), "no tone grade covers this level"})
		}
	}
	sort.Slice(musical, func(i, j int) bool { return musical[i].ID < musical[j].ID })
	return targets, pitchGrades, musical
}

func validateNeutralContextClasses(classes []neutralContextClass, pitchGrades map[int]string, issues *[]neutralSurfaceIssue) {
	classIDs := map[string]bool{}
	conditionTones := map[int]bool{}
	pitchLevels := map[int]bool{}
	for _, class := range classes {
		if classIDs[class.ClassID] {
			*issues = append(*issues, neutralSurfaceIssue{"duplicate_class_id", class.ClassID, "class_id must be unique"})
		}
		classIDs[class.ClassID] = true
		if class.ConditioningSurfaceTone < 1 || class.ConditioningSurfaceTone > 4 || conditionTones[class.ConditioningSurfaceTone] {
			*issues = append(*issues, neutralSurfaceIssue{"invalid_conditioning_tone", class.ClassID, strconv.Itoa(class.ConditioningSurfaceTone)})
		}
		conditionTones[class.ConditioningSurfaceTone] = true
		if class.SurfacePitchLevel < 1 || class.SurfacePitchLevel > 5 || pitchLevels[class.SurfacePitchLevel] {
			*issues = append(*issues, neutralSurfaceIssue{"invalid_surface_pitch_level", class.ClassID, strconv.Itoa(class.SurfacePitchLevel)})
		}
		pitchLevels[class.SurfacePitchLevel] = true
		actual := pitchGrades[class.SurfacePitchLevel]
		if actual == "" || actual != class.ExpectedProjectedGrade {
			*issues = append(*issues, neutralSurfaceIssue{"projected_grade_mismatch", class.ClassID, class.ExpectedProjectedGrade + " vs " + actual})
		}
		if class.ConditioningStage != "post_tone_sandhi_surface" {
			*issues = append(*issues, neutralSurfaceIssue{"invalid_conditioning_stage", class.ClassID, class.ConditioningStage})
		}
		if class.AdjudicationStatus != "research_only" {
			*issues = append(*issues, neutralSurfaceIssue{"invalid_adjudication_status", class.ClassID, class.AdjudicationStatus})
		}
	}
	if len(classes) != 4 || len(conditionTones) != 4 || len(pitchLevels) != 4 {
		*issues = append(*issues, neutralSurfaceIssue{"incomplete_context_inventory", "neutral_tone", fmt.Sprintf("classes=%d tones=%d levels=%d", len(classes), len(conditionTones), len(pitchLevels))})
	}
}

func allNeutralClassesUseSurfaceCondition(classes []neutralContextClass) bool {
	for _, class := range classes {
		if class.ConditioningStage != "post_tone_sandhi_surface" {
			return false
		}
	}
	return len(classes) > 0
}

func projectNeutralTuple(tuple YinyuanTuple, grade string, entries map[string]neutralCatalogEntry, targets map[string]map[string]string) (YinyuanTuple, error) {
	result := tuple
	for index := 1; index < len(result); index++ {
		source, ok := entries[result[index]]
		if !ok {
			return YinyuanTuple{}, fmt.Errorf("unknown musical yinyuan %s", result[index])
		}
		target := targets[source.QualityGroup][grade]
		if target == "" {
			return YinyuanTuple{}, fmt.Errorf("no %s target for quality %s", grade, source.QualityGroup)
		}
		result[index] = target
	}
	return result, nil
}

func neutralTupleKey(tuple YinyuanTuple) string {
	return strings.Join(tuple[:], "\x00")
}
