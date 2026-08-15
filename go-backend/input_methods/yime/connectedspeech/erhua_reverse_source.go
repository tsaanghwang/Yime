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
	SurfaceClass               string
	AttachedSyllableSource     string
	CarrierYinyuanIDs          []string
	SurfaceSoundUnitIDs        []string
	KeyProjection              string
	FullCode                   string
	VariableCode               string
	ShorthandCode              string
}

func writeErhuaReverseSource(path string, rows []erhuaReverseSourceRow) error {
	lines := []string{
		"record_id\ttext\tsource_kind\tcompatibility_numeric_pinyin\tsurface_class\tattached_syllable_source\tcarrier_yinyuan_ids\tsurface_sound_unit_ids\tkey_projection\tfull_code\tvariable_code\tshorthand_code",
	}
	for _, row := range rows {
		fields := []string{
			row.RecordID,
			row.Text,
			row.SourceKind,
			row.CompatibilityNumericPinyin,
			row.SurfaceClass,
			row.AttachedSyllableSource,
			strings.Join(row.CarrierYinyuanIDs, " "),
			strings.Join(row.SurfaceSoundUnitIDs, " "),
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
