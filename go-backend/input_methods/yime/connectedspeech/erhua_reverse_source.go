package connectedspeech

import (
	"fmt"
	"os"
	"strings"
)

const ErhuaReverseSourceFileName = "yime_erhua_reverse_source.tsv"

type erhuaReverseSourceRow struct {
	RecordID                   string
	Text                       string
	SourceKind                 string
	CompatibilityNumericPinyin string
	FeatureRuleID              string
	AttachedSyllableSource     string
	SourceYinyuanIDs           []string
	DerivedYinyuanIDs          []string
	KeyProjection              string
	FullCode                   string
	VariableCode               string
	ShorthandCode              string
}

func writeErhuaReverseSource(path string, rows []erhuaReverseSourceRow) error {
	lines := []string{
		"record_id\ttext\tsource_kind\tcompatibility_numeric_pinyin\tfeature_rule_id\tattached_syllable_source\tsource_yinyuan_ids\tderived_yinyuan_ids\tkey_projection\tfull_code\tvariable_code\tshorthand_code",
	}
	for _, row := range rows {
		fields := []string{
			row.RecordID,
			row.Text,
			row.SourceKind,
			row.CompatibilityNumericPinyin,
			row.FeatureRuleID,
			row.AttachedSyllableSource,
			strings.Join(row.SourceYinyuanIDs, " "),
			strings.Join(row.DerivedYinyuanIDs, " "),
			row.KeyProjection,
			row.FullCode,
			row.VariableCode,
			row.ShorthandCode,
		}
		for _, field := range fields {
			if strings.ContainsAny(field, "\t\r\n") {
				return fmt.Errorf("explicit-erhua reverse row %s contains a tab or newline", row.RecordID)
			}
		}
		lines = append(lines, strings.Join(fields, "\t"))
	}
	return os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}
