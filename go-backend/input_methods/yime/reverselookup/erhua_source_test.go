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
			if result.ErhuaRecordID != "ERHUA-TEST" || result.DerivedYinyuanIDs != "N16 M22 M23 M24" ||
				result.SoundToKeyProjection != "N16→7；M22+rhotic=true+nasalized=false→M22→ERHUA-KEY-HIGH(U)" {
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

func TestExplicitErhuaReverseSourceSuppressesMisleadingCharacterFallback(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())
	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"),
		"pinyin\tfull\tvariable\tshorthand\n"+
			"dao1\tdddd\td\td\nren4\trrrr\tr\tr\nren2\teeee\te\te\n")
	writeTestFile(t, filepath.Join(sharedDir, "yime_variable.dict.yaml"),
		"name: test\n...\n刀\td\n刃\tr\n儿\te\n")
	writeTestFile(t, filepath.Join(sharedDir, ErhuaSourceFileName),
		testErhuaSourceContentFor("ERHUA-KNIFE", "刀刃儿", "dao1 ren4 er5"))

	index, err := Load(sharedDir, userDir, ModeVariable)
	if err != nil {
		t.Fatal(err)
	}
	results := index.Search("刀刃儿", false)
	if len(results) != 1 || results[0].Source != "融合儿化" || results[0].NumericPinyin != "dao1 ren4 er5" {
		t.Fatalf("explicit erhua must replace the misleading character fallback: %#v", results)
	}
}

func testErhuaSourceContent(recordID string) string {
	return testErhuaSourceContentFor(recordID, "一阵儿", "yi1 zhen4 er5")
}

func testErhuaSourceContentFor(recordID, text, numericPinyin string) string {
	return "record_id\ttext\tsource_kind\tcompatibility_numeric_pinyin\tfeature_rule_id\tattached_syllable_source\tsource_yinyuan_ids\tderived_yinyuan_ids\tkey_projection\tfull_code\tvariable_code\tshorthand_code\n" +
		recordID + "\t" + text + "\tpsc_erhua\t" + numericPinyin + "\tERHUA-YINYUAN-CENTRAL-ALL\tzhen4\tN16 M22 M23 M24\tN16 M22 M23 M24\tN16→7；M22+rhotic=true+nasalized=false→M22→ERHUA-KEY-HIGH(U)\tyjjj7UIO\tyj7UIO\tyj7UO\n"
}
