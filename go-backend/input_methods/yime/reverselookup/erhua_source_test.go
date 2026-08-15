package reverselookup

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestExplicitErhuaReverseSourceExplainsFusedRouteAcrossModes(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())
	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), "pinyin\tfull\tvariable\tshorthand\nyi1\tabcd\tab\ta\n")
	writeTestFile(t, filepath.Join(sharedDir, ErhuaSourceFileName), testErhuaSourceContent("ERHUA-TEST"))

	for _, test := range []struct {
		mode Mode
		code string
	}{
		{ModeFull, "yjjj7UIO"},
		{ModeVariable, "yj7UIO"},
		{ModeShorthand, "yj7UO"},
	} {
		t.Run(string(test.mode), func(t *testing.T) {
			index, err := Load(sharedDir, userDir, test.mode)
			if err != nil {
				t.Fatal(err)
			}
			results := index.Search("一阵儿", false)
			if len(results) != 1 {
				t.Fatalf("results=%#v", results)
			}
			result := results[0]
			if result.Source != "融合儿化" || result.ActiveCode != test.code || result.NumericPinyin != "yi1 zhen4 er5" {
				t.Fatalf("unexpected result: %#v", result)
			}
			if result.ErhuaRecordID != "ERHUA-TEST" || result.SurfaceSoundUnitIDs != "N16 R01 R02 R03" ||
				result.SoundToKeyProjection != "N16→7；R01→ERHUA-KEY-HIGH→M22(U)" {
				t.Fatalf("missing explanation: %#v", result)
			}
			contains := index.Search("阵", true)
			if len(contains) != 1 || contains[0].ErhuaRecordID != "ERHUA-TEST" {
				t.Fatalf("contains lookup=%#v", contains)
			}
		})
	}
}

func TestExplicitErhuaReverseSourceChangeInvalidatesCache(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())
	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), "pinyin\tfull\tvariable\tshorthand\nyi1\tabcd\tab\ta\n")
	sidecar := filepath.Join(sharedDir, ErhuaSourceFileName)
	writeTestFile(t, sidecar, testErhuaSourceContent("ERHUA-OLD"))

	first, err := Load(sharedDir, userDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if results := first.Search("一阵儿", false); len(results) != 1 || results[0].ErhuaRecordID != "ERHUA-OLD" {
		t.Fatalf("first lookup=%#v", results)
	}

	writeTestFile(t, sidecar, testErhuaSourceContent("ERHUA-NEW"))
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(sidecar, future, future); err != nil {
		t.Fatal(err)
	}
	second, err := Load(sharedDir, userDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if results := second.Search("一阵儿", false); len(results) != 1 || results[0].ErhuaRecordID != "ERHUA-NEW" {
		t.Fatalf("lookup after sidecar change=%#v", results)
	}
}

func testErhuaSourceContent(recordID string) string {
	return "record_id\ttext\tsource_kind\tcompatibility_numeric_pinyin\tsurface_class\tattached_syllable_source\tcarrier_yinyuan_ids\tsurface_sound_unit_ids\tkey_projection\tfull_code\tvariable_code\tshorthand_code\n" +
		recordID + "\t一阵儿\tpsc_erhua\tyi1 zhen4 er5\tERHUA-ORAL-ER\tzhen4\tN16 M22 M23 M24\tN16 R01 R02 R03\tN16→7；R01→ERHUA-KEY-HIGH→M22(U)\tyjjj7UIO\tyj7UIO\tyj7UO\n"
}
