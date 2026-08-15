package connectedspeech

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const ErhuaMixedRuntimeToolVersion = "explicit-erhua-mixed-runtime-v2"

var erhuaMixedModes = []string{"full", "variable", "shorthand"}

type ErhuaMixedRuntimeConfig struct {
	DataDir             string
	AliasesPath         string
	AnnotationsPath     string
	SoundProjectionPath string
	LayoutPath          string
	OutputDir           string
}

func DefaultErhuaMixedRuntimeConfig(repoRoot string) ErhuaMixedRuntimeConfig {
	sourceDir := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	return ErhuaMixedRuntimeConfig{
		DataDir:             filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
		AliasesPath:         filepath.Join(sourceDir, "erhua_input_aliases.json"),
		AnnotationsPath:     filepath.Join(sourceDir, "erhua_lexical_annotations.json"),
		SoundProjectionPath: filepath.Join(sourceDir, "erhua_sound_key_projection.json"),
		LayoutPath:          filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data", "yime_yinyuan_layout.json"),
		OutputDir:           filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data"),
	}
}

type erhuaModeCode struct {
	LayoutKeyCode string   `json:"layout_key_code"`
	YinyuanIDs    []string `json:"yinyuan_ids"`
	Length        int      `json:"length"`
}

type erhuaRoute struct {
	Status                     string                   `json:"status"`
	NumericPinyin              string                   `json:"numeric_pinyin"`
	SurfaceClass               string                   `json:"surface_class"`
	AttachedSyllableSource     string                   `json:"attached_syllable_source"`
	AttachedSyllableYinyuanIDs []string                 `json:"attached_syllable_yinyuan_ids"`
	Codes                      map[string]erhuaModeCode `json:"codes"`
}

type erhuaAliasRecord struct {
	RecordID string                `json:"record_id"`
	Text     string                `json:"text"`
	Status   string                `json:"status"`
	Routes   map[string]erhuaRoute `json:"routes"`
}

type erhuaAliasBundle struct {
	SchemaVersion  int                `json:"schema_version"`
	RuntimeEnabled bool               `json:"runtime_enabled"`
	Counts         map[string]int     `json:"counts"`
	Records        []erhuaAliasRecord `json:"records"`
}

type erhuaAnnotationAuthorization struct {
	SourceKind string `json:"source_kind"`
}

type erhuaAnnotationRecord struct {
	RecordID            string                       `json:"record_id"`
	RecordType          string                       `json:"record_type"`
	Text                string                       `json:"text"`
	ProductiveInference string                       `json:"productive_inference"`
	Authorization       erhuaAnnotationAuthorization `json:"authorization"`
}

type erhuaAnnotationBundle struct {
	SchemaVersion  int                     `json:"schema_version"`
	RuntimeEnabled bool                    `json:"runtime_enabled"`
	Records        []erhuaAnnotationRecord `json:"records"`
}

type ErhuaMixedRuntimeSummary struct {
	ToolVersion                string          `json:"tool_version"`
	ExplicitRecordCount        int             `json:"explicit_record_count"`
	DualRouteReadyCount        int             `json:"dual_route_ready_count"`
	PendingFusionCount         int             `json:"pending_fusion_count"`
	InheritedWeightRecordCount int             `json:"inherited_weight_record_count"`
	DeferredMissingWeightCount int             `json:"deferred_missing_weight_count"`
	RoutesPerMode              int             `json:"routes_per_mode"`
	RuntimeAliasRows           int             `json:"runtime_alias_rows"`
	DeclaredSoundUnitCount     int             `json:"declared_sound_unit_count"`
	PilotSoundUnitCount        int             `json:"pilot_sound_unit_count"`
	ResearchSoundUnitCount     int             `json:"research_sound_unit_count"`
	SharedKeyClassCount        int             `json:"shared_key_class_count"`
	PilotSurfaceClassCount     int             `json:"pilot_surface_class_count"`
	ProjectedReadyRecordCount  int             `json:"projected_ready_record_count"`
	ReverseLookupRowCount      int             `json:"reverse_lookup_row_count"`
	Gates                      map[string]bool `json:"gates"`
	Passed                     bool            `json:"passed"`
}

type ErhuaMixedRuntimeManifest struct {
	ToolVersion  string                   `json:"tool_version"`
	InputSHA256  map[string]string        `json:"input_sha256"`
	OutputSHA256 map[string]string        `json:"output_sha256"`
	Summary      ErhuaMixedRuntimeSummary `json:"summary"`
	Deferred     []string                 `json:"deferred_missing_weight"`
}

type erhuaRuntimeEntry struct {
	RecordID string
	Text     string
	Weight   string
	Suffix   map[string]string
	Fused    map[string]string
	Reverse  erhuaReverseSourceRow
}

func RunErhuaMixedRuntime(config ErhuaMixedRuntimeConfig) (ErhuaMixedRuntimeManifest, error) {
	if config.DataDir == "" || config.AliasesPath == "" || config.AnnotationsPath == "" ||
		config.SoundProjectionPath == "" || config.LayoutPath == "" || config.OutputDir == "" {
		return ErhuaMixedRuntimeManifest{}, errors.New("all explicit-erhua runtime paths are required")
	}
	aliases, err := loadErhuaAliasBundle(config.AliasesPath)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	annotations, err := loadErhuaAnnotationBundle(config.AnnotationsPath)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	soundProjection, err := loadErhuaSoundProjection(config.SoundProjectionPath)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	layout, err := loadErhuaYinyuanLayout(config.LayoutPath)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	projectionIndex, err := indexErhuaSoundProjection(soundProjection, layout)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	annotationByID := make(map[string]erhuaAnnotationRecord, len(annotations.Records))
	for _, item := range annotations.Records {
		if item.RecordID == "" || item.Text == "" {
			return ErhuaMixedRuntimeManifest{}, errors.New("explicit erhua annotation has an empty record ID or text")
		}
		if _, exists := annotationByID[item.RecordID]; exists {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("duplicate explicit erhua annotation ID %s", item.RecordID)
		}
		annotationByID[item.RecordID] = item
	}

	ready := make([]erhuaAliasRecord, 0)
	projectedSoundUnits := map[string]struct{}{}
	projectedByRecordID := map[string]erhuaProjectedRoute{}
	researchSoundProjected := false
	projectedReadyRecords := 0
	pending := 0
	aliasIDs := make(map[string]struct{}, len(aliases.Records))
	aliasTexts := make(map[string]struct{}, len(aliases.Records))
	for _, item := range aliases.Records {
		if _, exists := aliasIDs[item.RecordID]; exists {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("duplicate explicit erhua alias ID %s", item.RecordID)
		}
		if _, exists := aliasTexts[item.Text]; exists {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("duplicate explicit erhua alias text %s", item.Text)
		}
		aliasIDs[item.RecordID] = struct{}{}
		aliasTexts[item.Text] = struct{}{}
		annotation, ok := annotationByID[item.RecordID]
		if !ok || annotation.Text != item.Text || annotation.RecordType != "explicit_word_final_erhua" ||
			annotation.ProductiveInference != "forbidden" || annotation.Authorization.SourceKind != "psc_erhua" {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("%s lacks matching explicit erhua authorization", item.RecordID)
		}
		if !strings.HasSuffix(item.Text, "儿") {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("%s is not a written word-final 儿 record", item.RecordID)
		}
		switch item.Status {
		case "dual_route_ready":
			if err := validateErhuaRouteCodes(item); err != nil {
				return ErhuaMixedRuntimeManifest{}, err
			}
			if err := projectionIndex.validateRouteLayout(item); err != nil {
				return ErhuaMixedRuntimeManifest{}, err
			}
			projected, err := projectionIndex.projectFusedRoute(item)
			if err != nil {
				return ErhuaMixedRuntimeManifest{}, err
			}
			for _, id := range projected.SoundUnitIDs[1:] {
				sound, isDerivedSound := projectionIndex.soundByID[id]
				if !isDerivedSound {
					continue
				}
				projectedSoundUnits[id] = struct{}{}
				if sound.AdmissionStatus == "research_only" {
					researchSoundProjected = true
				}
			}
			projectedReadyRecords++
			projectedByRecordID[item.RecordID] = projected
			ready = append(ready, item)
		case "suffix_only_encoding_pending":
			pending++
		default:
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("%s has unsupported status %q", item.RecordID, item.Status)
		}
	}

	weightByMode := map[string]map[string]string{}
	for _, mode := range erhuaMixedModes {
		weights, loadErr := loadMaximumTextWeights(filepath.Join(config.DataDir, "yime_"+mode+".dict.yaml"))
		if loadErr != nil {
			return ErhuaMixedRuntimeManifest{}, loadErr
		}
		weightByMode[mode] = weights
	}

	entries := make([]erhuaRuntimeEntry, 0, len(ready))
	deferred := make([]string, 0)
	for _, item := range ready {
		weight := ""
		found := 0
		for _, mode := range erhuaMixedModes {
			current, ok := weightByMode[mode][item.Text]
			if !ok {
				continue
			}
			found++
			if weight == "" {
				weight = current
			} else if current != weight {
				return ErhuaMixedRuntimeManifest{}, fmt.Errorf("%s has inconsistent weights across modes", item.Text)
			}
		}
		if found == 0 {
			deferred = append(deferred, item.Text)
			continue
		}
		if found != len(erhuaMixedModes) {
			return ErhuaMixedRuntimeManifest{}, fmt.Errorf("%s has a partial three-mode weight path", item.Text)
		}
		entry := erhuaRuntimeEntry{
			RecordID: item.RecordID,
			Text:     item.Text,
			Weight:   weight,
			Suffix:   map[string]string{},
			Fused:    map[string]string{},
		}
		for _, mode := range erhuaMixedModes {
			entry.Suffix[mode] = item.Routes["suffix_compatibility"].Codes[mode].LayoutKeyCode
			entry.Fused[mode] = item.Routes["fused_erhua"].Codes[mode].LayoutKeyCode
		}
		projected := projectedByRecordID[item.RecordID]
		fusedRoute := item.Routes["fused_erhua"]
		entry.Reverse = erhuaReverseSourceRow{
			RecordID:                   item.RecordID,
			Text:                       item.Text,
			SourceKind:                 annotationByID[item.RecordID].Authorization.SourceKind,
			CompatibilityNumericPinyin: item.Routes["suffix_compatibility"].NumericPinyin,
			SurfaceClass:               fusedRoute.SurfaceClass,
			AttachedSyllableSource:     fusedRoute.AttachedSyllableSource,
			CarrierYinyuanIDs:          append([]string(nil), fusedRoute.AttachedSyllableYinyuanIDs...),
			SurfaceSoundUnitIDs:        append([]string(nil), projected.SoundUnitIDs...),
			KeyProjection:              projected.KeyProjection,
			FullCode:                   entry.Fused["full"],
			VariableCode:               entry.Fused["variable"],
			ShorthandCode:              entry.Fused["shorthand"],
		}
		entries = append(entries, entry)
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].RecordID < entries[j].RecordID })
	sort.Strings(deferred)
	if err := os.MkdirAll(config.OutputDir, 0o755); err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	outputPaths := map[string]string{}
	for _, mode := range erhuaMixedModes {
		name := "yime_erhua_mixed_" + mode + ".dict.yaml"
		path := filepath.Join(config.OutputDir, name)
		if err := writeErhuaMixedDictionary(path, mode, entries); err != nil {
			return ErhuaMixedRuntimeManifest{}, err
		}
		outputPaths[name] = path
	}
	reverseRows := make([]erhuaReverseSourceRow, 0, len(entries))
	for _, entry := range entries {
		reverseRows = append(reverseRows, entry.Reverse)
	}
	reverseSourcePath := filepath.Join(config.OutputDir, ErhuaReverseSourceFileName)
	if err := writeErhuaReverseSource(reverseSourcePath, reverseRows); err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	outputPaths[ErhuaReverseSourceFileName] = reverseSourcePath

	gates := map[string]bool{
		"source_bundles_are_offline_only":      !aliases.RuntimeEnabled && !annotations.RuntimeEnabled,
		"explicit_authorization_complete":      len(annotationByID) == len(aliases.Records),
		"productive_inference_forbidden":       true,
		"pending_fusions_not_exported":         pending == aliases.Counts["suffix_only_encoding_pending"],
		"all_runtime_weights_inherited":        len(entries)+len(deferred) == len(ready),
		"three_mode_routes_complete":           true,
		"candidate_text_unchanged":             true,
		"sound_units_separate_from_keys":       true,
		"many_to_one_sound_key_projection":     true,
		"layout_codes_recomputed_from_ids":     true,
		"ready_fused_routes_sound_projected":   projectedReadyRecords == len(ready),
		"research_only_sounds_not_exported":    !researchSoundProjected && len(projectedSoundUnits) == projectionIndex.pilotSoundUnits,
		"reverse_lookup_explanations_complete": len(reverseRows) == len(entries),
	}
	pilotSurfaceClassCount := 0
	for _, item := range soundProjection.SurfaceClasses {
		if item.RuntimeStatus == "pilot" {
			pilotSurfaceClassCount++
		}
	}
	summary := ErhuaMixedRuntimeSummary{
		ToolVersion:                ErhuaMixedRuntimeToolVersion,
		ExplicitRecordCount:        len(aliases.Records),
		DualRouteReadyCount:        len(ready),
		PendingFusionCount:         pending,
		InheritedWeightRecordCount: len(entries),
		DeferredMissingWeightCount: len(deferred),
		RoutesPerMode:              len(entries) * 2,
		RuntimeAliasRows:           len(entries) * 2 * len(erhuaMixedModes),
		DeclaredSoundUnitCount:     len(soundProjection.SoundUnits),
		PilotSoundUnitCount:        projectionIndex.pilotSoundUnits,
		ResearchSoundUnitCount:     projectionIndex.researchSoundUnits,
		SharedKeyClassCount:        len(soundProjection.KeyClasses),
		PilotSurfaceClassCount:     pilotSurfaceClassCount,
		ProjectedReadyRecordCount:  projectedReadyRecords,
		ReverseLookupRowCount:      len(reverseRows),
		Gates:                      gates,
	}
	summary.Passed = allGatesPass(gates) && len(entries) > 0
	inputHashes, err := hashNamedFiles(map[string]string{
		"aliases":              config.AliasesPath,
		"annotations":          config.AnnotationsPath,
		"sound_key_projection": config.SoundProjectionPath,
		"yinyuan_layout":       config.LayoutPath,
		"full_dictionary":      filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable_dictionary":  filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand_dictionary": filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	})
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	outputHashes, err := hashNamedFiles(outputPaths)
	if err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	manifest := ErhuaMixedRuntimeManifest{
		ToolVersion:  ErhuaMixedRuntimeToolVersion,
		InputSHA256:  inputHashes,
		OutputSHA256: outputHashes,
		Summary:      summary,
		Deferred:     deferred,
	}
	manifestPath := filepath.Join(config.OutputDir, "yime_erhua_mixed_manifest.json")
	if err := writeJSON(manifestPath, manifest); err != nil {
		return ErhuaMixedRuntimeManifest{}, err
	}
	if !summary.Passed {
		return manifest, errors.New("explicit-erhua mixed runtime gates did not pass")
	}
	return manifest, nil
}

func loadErhuaAliasBundle(path string) (erhuaAliasBundle, error) {
	var payload erhuaAliasBundle
	data, err := os.ReadFile(path)
	if err != nil {
		return payload, err
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return payload, err
	}
	if payload.SchemaVersion != 1 || len(payload.Records) == 0 {
		return payload, errors.New("explicit erhua alias bundle has an invalid schema or no records")
	}
	return payload, nil
}

func loadErhuaAnnotationBundle(path string) (erhuaAnnotationBundle, error) {
	var payload erhuaAnnotationBundle
	data, err := os.ReadFile(path)
	if err != nil {
		return payload, err
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return payload, err
	}
	if payload.SchemaVersion != 1 || len(payload.Records) == 0 {
		return payload, errors.New("explicit erhua annotation bundle has an invalid schema or no records")
	}
	return payload, nil
}

func validateErhuaRouteCodes(record erhuaAliasRecord) error {
	for _, routeName := range []string{"suffix_compatibility", "fused_erhua"} {
		route, ok := record.Routes[routeName]
		if !ok || route.Status != "available" {
			return fmt.Errorf("%s lacks available %s route", record.RecordID, routeName)
		}
		for _, mode := range erhuaMixedModes {
			code, ok := route.Codes[mode]
			if !ok || strings.TrimSpace(code.LayoutKeyCode) == "" || strings.ContainsAny(code.LayoutKeyCode, " \t\r\n") ||
				code.Length != len([]rune(code.LayoutKeyCode)) || code.Length != len(code.YinyuanIDs) {
				return fmt.Errorf("%s has invalid %s/%s code", record.RecordID, routeName, mode)
			}
		}
	}
	if strings.TrimSpace(record.Routes["suffix_compatibility"].NumericPinyin) == "" {
		return fmt.Errorf("%s lacks compatibility numeric Pinyin for reverse lookup", record.RecordID)
	}
	if strings.TrimSpace(record.Routes["fused_erhua"].AttachedSyllableSource) == "" {
		return fmt.Errorf("%s lacks attached-syllable source for fused reverse lookup", record.RecordID)
	}
	for _, mode := range erhuaMixedModes {
		suffixLength := record.Routes["suffix_compatibility"].Codes[mode].Length
		fusedLength := record.Routes["fused_erhua"].Codes[mode].Length
		if fusedLength > suffixLength {
			return fmt.Errorf("%s fused %s code is longer than its suffix-compatible code", record.RecordID, mode)
		}
	}
	return nil
}

func loadMaximumTextWeights(path string) (map[string]string, error) {
	result := map[string]string{}
	err := scanRimeDictionary(path, func(entry dictionaryEntry) {
		weight, parseErr := strconv.Atoi(entry.Weight)
		if parseErr != nil {
			return
		}
		previous, ok := result[entry.Text]
		if !ok {
			result[entry.Text] = strconv.Itoa(weight)
			return
		}
		old, _ := strconv.Atoi(previous)
		if weight > old {
			result[entry.Text] = strconv.Itoa(weight)
		}
	})
	return result, err
}

func writeErhuaMixedDictionary(path, mode string, entries []erhuaRuntimeEntry) error {
	name := "yime_erhua_mixed_" + mode
	lines := []string{
		"# Rime dictionary",
		"# GENERATED FILE - explicit source-backed erhua mixed routes",
		"# Contains only inherited-weight aliases; no productive erhua inference.",
		"---",
		"name: " + name,
		"version: \"explicit-erhua-mixed-v1\"",
		"sort: by_weight",
		"use_preset_vocabulary: false",
		"...",
	}
	for _, entry := range entries {
		lines = append(lines, rimeDictionaryLine(entry.Text, entry.Suffix[mode], entry.Weight))
		lines = append(lines, rimeDictionaryLine(entry.Text, entry.Fused[mode], entry.Weight))
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
