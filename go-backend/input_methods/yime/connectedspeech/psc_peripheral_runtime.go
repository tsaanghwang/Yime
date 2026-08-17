package connectedspeech

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

const (
	PSCPeripheralRuntimeToolVersion = "psc-pronunciation-peripheral-runtime-v2"
	PSCPeripheralSourceSchema       = "yime-psc-pronunciation-peripheral-source-v1"
	pscPeripheralSourceCategory     = "reviewed_psc_neutral_erhua_peripheral"
	pscPeripheralCandidateLayer     = "psc_normative_low_frequency_periphery"
	pscPeripheralWeight             = 1
)

var pscPeripheralModes = []string{"full", "variable", "shorthand"}

type PSCPeripheralRuntimeConfig struct {
	CatalogPath string
	CodesPath   string
	DataDir     string
	SourcePath  string
	OutputDir   string
}

func DefaultPSCPeripheralRuntimeConfig(repoRoot string) PSCPeripheralRuntimeConfig {
	sourceDir := filepath.Join(repoRoot, "docs", "project", "connected_speech")
	dataDir := filepath.Join(repoRoot, "go-backend", "input_methods", "yime", "data")
	return PSCPeripheralRuntimeConfig{
		CatalogPath: filepath.Join(sourceDir, "psc_pronunciation_peripheral_source.json"),
		CodesPath:   filepath.Join(dataDir, "yime_pinyin_codes.tsv"),
		DataDir:     dataDir,
		SourcePath:  filepath.Join(sourceDir, "psc_pronunciation_peripheral_source.json"),
		OutputDir:   dataDir,
	}
}

type pscCandidateCatalog struct {
	SchemaVersion string                       `json:"schema_version"`
	Records       []pscCandidateCoverageRecord `json:"records"`
}

type pscCandidateCoverageRecord struct {
	Text           string                 `json:"text"`
	MarkedPinyin   string                 `json:"marked_pinyin"`
	NumericPinyin  string                 `json:"numeric_pinyin"`
	Source         string                 `json:"source"`
	SourceCategory string                 `json:"source_category"`
	SourceRank     int                    `json:"source_rank"`
	SourcePrimary  bool                   `json:"source_primary"`
	CandidateLayer string                 `json:"candidate_layer,omitempty"`
	Evidence       []pscCandidateEvidence `json:"evidence"`
}

type pscCandidateEvidence struct {
	SourceKind      string                 `json:"source_kind"`
	SourceKey       string                 `json:"source_key"`
	ReviewState     string                 `json:"review_state"`
	SourceText      string                 `json:"source_text"`
	SourcePinyin    string                 `json:"source_pinyin"`
	ExpandedText    string                 `json:"expanded_text"`
	ExpandedPinyin  string                 `json:"expanded_pinyin"`
	InputDerivation string                 `json:"input_derivation"`
	Locator         map[string]interface{} `json:"locator,omitempty"`
	Note            string                 `json:"note"`
}

type PSCPeripheralSource struct {
	SchemaVersion string                       `json:"schema_version"`
	SourceCatalog string                       `json:"source_catalog_schema"`
	Policy        map[string]string            `json:"policy"`
	Counts        map[string]int               `json:"counts"`
	Records       []pscCandidateCoverageRecord `json:"records"`
}

type pscPeripheralEntry struct {
	Text              string
	NumericPinyin     string
	SourceKinds       []string
	ReviewStates      []string
	Full              string
	Variable          string
	Shorthand         string
	FullSpelling      string
	VariableSpelling  string
	ShorthandSpelling string
}

type PSCPeripheralRuntimeSummary struct {
	ToolVersion              string          `json:"tool_version"`
	SourceRecordCount        int             `json:"source_record_count"`
	NeutralToneRecordCount   int             `json:"neutral_tone_record_count"`
	ErhuaRecordCount         int             `json:"erhua_record_count"`
	EncodedRecordCount       int             `json:"encoded_record_count"`
	AlreadyInCoreRecordCount int             `json:"already_in_core_record_count"`
	RuntimeRowsPerMode       int             `json:"runtime_rows_per_mode"`
	SentenceRowsPerMode      int             `json:"sentence_rows_per_mode"`
	FixedPeripheralWeight    int             `json:"fixed_peripheral_weight"`
	Gates                    map[string]bool `json:"gates"`
	Passed                   bool            `json:"passed"`
}

type PSCPeripheralRuntimeManifest struct {
	ToolVersion  string                      `json:"tool_version"`
	InputSHA256  map[string]string           `json:"input_sha256"`
	OutputSHA256 map[string]string           `json:"output_sha256"`
	Summary      PSCPeripheralRuntimeSummary `json:"summary"`
}

func RunPSCPeripheralRuntime(config PSCPeripheralRuntimeConfig) (PSCPeripheralRuntimeManifest, error) {
	if config.CatalogPath == "" || config.CodesPath == "" || config.DataDir == "" || config.SourcePath == "" || config.OutputDir == "" {
		return PSCPeripheralRuntimeManifest{}, errors.New("all PSC peripheral runtime paths are required")
	}
	source, err := loadPSCPeripheralSource(config.CatalogPath)
	if err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	if err := validatePSCPeripheralSource(source); err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	codes, err := loadPSCFullCodes(config.CodesPath)
	if err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	coreByMode, err := loadPSCModeCoreKeys(config.DataDir)
	if err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}

	entries := make([]pscPeripheralEntry, 0, len(source.Records))
	alreadyInCore := 0
	for _, record := range source.Records {
		fullParts := make([]string, 0, len(strings.Fields(record.NumericPinyin)))
		for _, syllable := range strings.Fields(record.NumericPinyin) {
			code, ok := codes[syllable]
			if !ok {
				return PSCPeripheralRuntimeManifest{}, fmt.Errorf("%s / %s lacks a formal syllable code for %s", record.Text, record.NumericPinyin, syllable)
			}
			fullParts = append(fullParts, code)
		}
		fullCode := strings.Join(fullParts, "")
		modeRecord, err := codemode.BuildRecord(fullCode)
		if err != nil {
			return PSCPeripheralRuntimeManifest{}, fmt.Errorf("derive %s / %s: %w", record.Text, record.NumericPinyin, err)
		}
		modeCodes := map[string]string{
			"full":      modeRecord.FullSpelling,
			"variable":  modeRecord.VariableSpelling,
			"shorthand": modeRecord.ShorthandSpelling,
		}
		duplicate := false
		for _, mode := range pscPeripheralModes {
			if _, ok := coreByMode[mode][record.Text+"\x00"+modeCodes[mode]]; ok {
				duplicate = true
				break
			}
		}
		if duplicate {
			alreadyInCore++
			continue
		}
		sourceKinds, reviewStates := pscRecordEvidenceLabels(record)
		entries = append(entries, pscPeripheralEntry{
			Text: record.Text, NumericPinyin: record.NumericPinyin,
			SourceKinds: sourceKinds, ReviewStates: reviewStates,
			Full: modeRecord.Full, Variable: modeRecord.Variable, Shorthand: modeRecord.Shorthand,
			FullSpelling: modeRecord.FullSpelling, VariableSpelling: modeRecord.VariableSpelling, ShorthandSpelling: modeRecord.ShorthandSpelling,
		})
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Text != entries[j].Text {
			return entries[i].Text < entries[j].Text
		}
		return entries[i].NumericPinyin < entries[j].NumericPinyin
	})

	if err := os.MkdirAll(config.OutputDir, 0o755); err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	if err := writePSCPeripheralSource(config.SourcePath, source); err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	outputs := map[string]string{}
	for _, mode := range pscPeripheralModes {
		name := "yime_psc_peripheral_" + mode + ".dict.yaml"
		path := filepath.Join(config.OutputDir, name)
		if err := writePSCPeripheralDictionary(path, mode, entries); err != nil {
			return PSCPeripheralRuntimeManifest{}, err
		}
		outputs[name] = path

		sentenceName := "yime_psc_peripheral_sentence_" + mode + ".dict.yaml"
		sentencePath := filepath.Join(config.OutputDir, sentenceName)
		if err := writePSCPeripheralSentenceDictionary(sentencePath, mode, entries); err != nil {
			return PSCPeripheralRuntimeManifest{}, err
		}
		outputs[sentenceName] = sentencePath
	}

	neutralCount, erhuaCount := 0, 0
	for _, record := range source.Records {
		kinds, _ := pscRecordEvidenceLabels(record)
		for _, kind := range kinds {
			switch kind {
			case "psc_neutral_tone":
				neutralCount++
			case "psc_erhua":
				erhuaCount++
			}
		}
	}
	gates := map[string]bool{
		"reviewed_source_only":                  true,
		"source_primary_forbidden":              true,
		"only_neutral_tone_or_erhua_selected":   neutralCount+erhuaCount == len(source.Records),
		"candidate_text_unchanged":              true,
		"formal_syllable_chain_complete":        len(entries)+alreadyInCore == len(source.Records),
		"three_mode_derivation_complete":        true,
		"sentence_spelling_boundaries_complete": true,
		"core_dictionary_files_unchanged":       true,
		"fixed_low_frequency_weight":            pscPeripheralWeight == 1,
	}
	summary := PSCPeripheralRuntimeSummary{
		ToolVersion:       PSCPeripheralRuntimeToolVersion,
		SourceRecordCount: len(source.Records), NeutralToneRecordCount: neutralCount, ErhuaRecordCount: erhuaCount,
		EncodedRecordCount: len(entries), AlreadyInCoreRecordCount: alreadyInCore,
		RuntimeRowsPerMode: len(entries), SentenceRowsPerMode: len(entries), FixedPeripheralWeight: pscPeripheralWeight,
		Gates: gates,
	}
	summary.Passed = allGatesPass(gates) && len(source.Records) > 0
	inputHashes, err := hashNamedFiles(map[string]string{
		"catalog": config.CatalogPath, "pinyin_codes": config.CodesPath,
		"full_dictionary":      filepath.Join(config.DataDir, "yime_full.dict.yaml"),
		"variable_dictionary":  filepath.Join(config.DataDir, "yime_variable.dict.yaml"),
		"shorthand_dictionary": filepath.Join(config.DataDir, "yime_shorthand.dict.yaml"),
	})
	if err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	outputHashes, err := hashNamedFiles(outputs)
	if err != nil {
		return PSCPeripheralRuntimeManifest{}, err
	}
	manifest := PSCPeripheralRuntimeManifest{ToolVersion: PSCPeripheralRuntimeToolVersion, InputSHA256: inputHashes, OutputSHA256: outputHashes, Summary: summary}
	manifestPath := filepath.Join(config.OutputDir, "yime_psc_peripheral_manifest.json")
	data, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return manifest, err
	}
	if err := os.WriteFile(manifestPath, append(data, '\n'), 0o644); err != nil {
		return manifest, err
	}
	if !summary.Passed {
		return manifest, errors.New("PSC peripheral runtime gates did not pass")
	}
	return manifest, nil
}

func loadPSCPeripheralSource(path string) (PSCPeripheralSource, error) {
	var source PSCPeripheralSource
	data, err := os.ReadFile(path)
	if err != nil {
		return source, err
	}
	if err := json.Unmarshal(data, &source); err == nil && source.SchemaVersion == PSCPeripheralSourceSchema {
		return source, nil
	}
	var catalog pscCandidateCatalog
	if err := json.Unmarshal(data, &catalog); err != nil {
		return source, err
	}
	if catalog.SchemaVersion != "yime-reviewed-psc-candidate-readings-v1" {
		return source, fmt.Errorf("unsupported PSC candidate catalog schema %q", catalog.SchemaVersion)
	}
	records := make([]pscCandidateCoverageRecord, 0)
	for _, record := range catalog.Records {
		if pscRecordHasPeripheralEvidence(record) {
			records = append(records, record)
		}
	}
	sort.Slice(records, func(i, j int) bool {
		if records[i].Text != records[j].Text {
			return records[i].Text < records[j].Text
		}
		return records[i].NumericPinyin < records[j].NumericPinyin
	})
	return PSCPeripheralSource{
		SchemaVersion: PSCPeripheralSourceSchema,
		SourceCatalog: catalog.SchemaVersion,
		Policy: map[string]string{
			"scope":       "reviewed psc_neutral_tone and psc_erhua text-pronunciation pairs absent from the curated core",
			"ranking":     "fixed low-frequency overlay; never source-primary and never reranks the curated core",
			"orthography": "candidate text is preserved; unwritten-er oral-r hints remain outside the source records",
		},
		Counts:  map[string]int{"records": len(records)},
		Records: records,
	}, nil
}

func validatePSCPeripheralSource(source PSCPeripheralSource) error {
	if source.SchemaVersion != PSCPeripheralSourceSchema || len(source.Records) == 0 {
		return errors.New("PSC peripheral source has an invalid schema or no records")
	}
	seen := map[string]struct{}{}
	for _, record := range source.Records {
		if record.Text == "" || strings.TrimSpace(record.NumericPinyin) == "" {
			return errors.New("PSC peripheral source has an empty text or pronunciation")
		}
		if record.SourcePrimary {
			return fmt.Errorf("%s / %s is unexpectedly source-primary", record.Text, record.NumericPinyin)
		}
		if !pscRecordHasPeripheralEvidence(record) {
			return fmt.Errorf("%s / %s lacks reviewed neutral-tone or erhua evidence", record.Text, record.NumericPinyin)
		}
		key := record.Text + "\x00" + record.NumericPinyin
		if _, ok := seen[key]; ok {
			return fmt.Errorf("duplicate PSC peripheral pair %s / %s", record.Text, record.NumericPinyin)
		}
		seen[key] = struct{}{}
	}
	if expected := source.Counts["records"]; expected != 0 && expected != len(source.Records) {
		return fmt.Errorf("PSC peripheral source count mismatch: %d != %d", expected, len(source.Records))
	}
	return nil
}

func pscRecordHasPeripheralEvidence(record pscCandidateCoverageRecord) bool {
	if record.SourceCategory != pscPeripheralSourceCategory ||
		record.CandidateLayer != pscPeripheralCandidateLayer {
		return false
	}
	for _, evidence := range record.Evidence {
		if (evidence.SourceKind == "psc_neutral_tone" || evidence.SourceKind == "psc_erhua") &&
			(evidence.ReviewState == "machine_verified" || evidence.ReviewState == "confirmed" || evidence.ReviewState == "corrected") {
			if evidence.SourceKind != "psc_erhua" || strings.Contains(record.Text, "儿") {
				return true
			}
		}
	}
	return false
}

func pscRecordEvidenceLabels(record pscCandidateCoverageRecord) ([]string, []string) {
	kindSet, stateSet := map[string]struct{}{}, map[string]struct{}{}
	for _, evidence := range record.Evidence {
		if evidence.SourceKind == "psc_neutral_tone" || evidence.SourceKind == "psc_erhua" {
			kindSet[evidence.SourceKind] = struct{}{}
			stateSet[evidence.ReviewState] = struct{}{}
		}
	}
	kinds, states := make([]string, 0, len(kindSet)), make([]string, 0, len(stateSet))
	for item := range kindSet {
		kinds = append(kinds, item)
	}
	for item := range stateSet {
		states = append(states, item)
	}
	sort.Strings(kinds)
	sort.Strings(states)
	return kinds, states
}

func loadPSCFullCodes(path string) (map[string]string, error) {
	stream, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer stream.Close()
	result := map[string]string{}
	scanner := bufio.NewScanner(stream)
	line := 0
	for scanner.Scan() {
		line++
		fields := strings.Split(scanner.Text(), "\t")
		if line == 1 && len(fields) >= 2 && fields[0] == "pinyin_tone" {
			continue
		}
		if len(fields) < 2 || strings.TrimSpace(fields[0]) == "" || strings.TrimSpace(fields[1]) == "" {
			continue
		}
		result[strings.TrimSpace(fields[0])] = strings.TrimSpace(fields[1])
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if len(result) == 0 {
		return nil, errors.New("PSC peripheral Pinyin code map is empty")
	}
	return result, nil
}

func loadPSCModeCoreKeys(dataDir string) (map[string]map[string]struct{}, error) {
	result := map[string]map[string]struct{}{}
	for _, mode := range pscPeripheralModes {
		keys := map[string]struct{}{}
		err := scanRimeDictionary(filepath.Join(dataDir, "yime_"+mode+".dict.yaml"), func(entry dictionaryEntry) {
			keys[entry.Text+"\x00"+entry.Code] = struct{}{}
		})
		if err != nil {
			return nil, err
		}
		result[mode] = keys
	}
	return result, nil
}

func writePSCPeripheralSource(path string, source PSCPeripheralSource) error {
	data, err := json.MarshalIndent(source, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

func writePSCPeripheralDictionary(path, mode string, entries []pscPeripheralEntry) error {
	var content strings.Builder
	content.WriteString("# Rime dictionary\n# GENERATED FILE - reviewed PSC neutral-tone/erhua low-frequency periphery\n")
	content.WriteString("# Separate overlay: the curated core dictionary and its ranking remain unchanged.\n")
	content.WriteString("---\nname: yime_psc_peripheral_")
	content.WriteString(mode)
	content.WriteString("\nversion: \"")
	content.WriteString(PSCPeripheralRuntimeToolVersion)
	content.WriteString("\"\nsort: by_weight\nuse_preset_vocabulary: false\n...\n")
	for _, entry := range entries {
		// This overlay is consumed by table_translator, so write the continuous
		// lookup code. The *Spelling fields contain script-dictionary syllable
		// separators and belong only in script_translator dictionaries.
		code := entry.Full
		if mode == "variable" {
			code = entry.Variable
		}
		if mode == "shorthand" {
			code = entry.Shorthand
		}
		fmt.Fprintf(&content, "%s\t%s\t%d\n", entry.Text, code, pscPeripheralWeight)
	}
	return os.WriteFile(path, []byte(content.String()), 0o644)
}

func writePSCPeripheralSentenceDictionary(path, mode string, entries []pscPeripheralEntry) error {
	var content strings.Builder
	content.WriteString("# Rime dictionary\n# GENERATED FILE - reviewed PSC entries with explicit syllable boundaries\n")
	content.WriteString("# Imported only by the main script_translator sentence dictionary.\n")
	content.WriteString("---\nname: yime_psc_peripheral_sentence_")
	content.WriteString(mode)
	content.WriteString("\nversion: \"")
	content.WriteString(PSCPeripheralRuntimeToolVersion)
	content.WriteString("\"\nsort: by_weight\nuse_preset_vocabulary: false\n...\n")
	for _, entry := range entries {
		spelling := entry.FullSpelling
		code := entry.Full
		if mode == "variable" {
			spelling = entry.VariableSpelling
			code = entry.Variable
		}
		if mode == "shorthand" {
			spelling = entry.ShorthandSpelling
			code = entry.Shorthand
		}
		parts := strings.Fields(spelling)
		if len(parts) != len(strings.Fields(entry.NumericPinyin)) || strings.Join(parts, "") != code {
			return fmt.Errorf("%s has an invalid %s sentence spelling %q", entry.Text, mode, spelling)
		}
		fmt.Fprintf(&content, "%s\t%s\t%d\n", entry.Text, spelling, pscPeripheralWeight)
	}
	return os.WriteFile(path, []byte(content.String()), 0o644)
}

func fileSHA256(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:]), nil
}
