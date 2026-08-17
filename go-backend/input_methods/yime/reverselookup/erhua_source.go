package reverselookup

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const ErhuaSourceFileName = "yime_erhua_reverse_source.tsv"

type ErhuaLookupRecord struct {
	RecordID                   string
	Text                       string
	SourceKind                 string
	CompatibilityNumericPinyin string
	FeatureRuleID              string
	AttachedSyllableSource     string
	SourceYinyuanIDs           string
	DerivedYinyuanIDs          string
	KeyProjection              string
	FullCode                   string
	VariableCode               string
	ShorthandCode              string
}

func (record ErhuaLookupRecord) activeCode(mode Mode) string {
	switch mode {
	case ModeFull:
		return record.FullCode
	case ModeShorthand:
		return record.ShorthandCode
	default:
		return record.VariableCode
	}
}

func loadErhuaSource(path string) (map[string][]ErhuaLookupRecord, error) {
	result := map[string][]ErhuaLookupRecord{}
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return result, nil
		}
		return nil, err
	}
	defer file.Close()

	expectedHeader := []string{
		"record_id", "text", "source_kind", "compatibility_numeric_pinyin", "feature_rule_id",
		"attached_syllable_source", "source_yinyuan_ids", "derived_yinyuan_ids", "key_projection",
		"full_code", "variable_code", "shorthand_code",
	}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	lineNumber := 0
	seenIDs := map[string]struct{}{}
	for scanner.Scan() {
		lineNumber++
		fields := strings.Split(strings.TrimPrefix(scanner.Text(), "\ufeff"), "\t")
		if lineNumber == 1 {
			if len(fields) != len(expectedHeader) {
				return nil, fmt.Errorf("unexpected explicit-erhua reverse header in %s", path)
			}
			for index := range fields {
				if fields[index] != expectedHeader[index] {
					return nil, fmt.Errorf("unexpected explicit-erhua reverse header in %s", path)
				}
			}
			continue
		}
		if len(fields) != len(expectedHeader) {
			return nil, fmt.Errorf("explicit-erhua reverse line %d has %d columns, want %d", lineNumber, len(fields), len(expectedHeader))
		}
		record := ErhuaLookupRecord{
			RecordID:                   strings.TrimSpace(fields[0]),
			Text:                       strings.TrimSpace(fields[1]),
			SourceKind:                 strings.TrimSpace(fields[2]),
			CompatibilityNumericPinyin: normalizeNumericTonePinyinSpacing(fields[3]),
			FeatureRuleID:              strings.TrimSpace(fields[4]),
			AttachedSyllableSource:     strings.TrimSpace(fields[5]),
			SourceYinyuanIDs:           strings.TrimSpace(fields[6]),
			DerivedYinyuanIDs:          strings.TrimSpace(fields[7]),
			KeyProjection:              strings.TrimSpace(fields[8]),
			FullCode:                   strings.TrimSpace(fields[9]),
			VariableCode:               strings.TrimSpace(fields[10]),
			ShorthandCode:              strings.TrimSpace(fields[11]),
		}
		if record.RecordID == "" || record.Text == "" || record.SourceKind == "" ||
			record.CompatibilityNumericPinyin == "" || record.FeatureRuleID == "" || record.AttachedSyllableSource == "" ||
			record.SourceYinyuanIDs == "" || record.DerivedYinyuanIDs == "" || record.KeyProjection == "" ||
			record.FullCode == "" || record.VariableCode == "" || record.ShorthandCode == "" {
			return nil, fmt.Errorf("explicit-erhua reverse line %d has an empty required field", lineNumber)
		}
		if _, exists := seenIDs[record.RecordID]; exists {
			return nil, fmt.Errorf("duplicate explicit-erhua reverse record ID %s", record.RecordID)
		}
		seenIDs[record.RecordID] = struct{}{}
		result[record.Text] = append(result[record.Text], record)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	if lineNumber == 0 {
		return nil, fmt.Errorf("explicit-erhua reverse source is empty: %s", path)
	}
	return result, nil
}

func buildErhuaLookupResult(record ErhuaLookupRecord, mode Mode, markedLookup map[string]string) Result {
	return Result{
		Phrase:               record.Text,
		Source:               "融合儿化",
		NumericPinyin:        record.CompatibilityNumericPinyin,
		StandardPinyin:       numericPinyinToMarked(record.CompatibilityNumericPinyin, markedLookup),
		ActiveCode:           record.activeCode(mode),
		FullCode:             record.FullCode,
		VariableCode:         record.VariableCode,
		ShorthandCode:        record.ShorthandCode,
		ErhuaRecordID:        record.RecordID,
		ReadingIdentity:      "显式词汇化儿化（融合输入别名；规范拼音不改写）",
		EvidenceSource:       record.SourceKind,
		ErhuaFeatureRuleID:   record.FeatureRuleID,
		AttachedSyllable:     record.AttachedSyllableSource,
		SourceYinyuanIDs:     record.SourceYinyuanIDs,
		DerivedYinyuanIDs:    record.DerivedYinyuanIDs,
		SoundToKeyProjection: record.KeyProjection,
	}
}
