package syllableinspector

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const fixture = "pinyin_tone\tmarked_pinyin\tnormalized\tshouyin_label\tganyin_label\trule_id\tshouyin_symbol\thuyin_symbol\tzhuyin_symbol\tmoyin_symbol\tshouyin_id\thuyin_id\tzhuyin_id\tmoyin_id\tshouyin_name\thuyin_name\tzhuyin_name\tmoyin_name\tlayout_code\taliases\tstatus\n" +
	"a1\tā\ta1\t'\ta1\tzero-initial\tA\tB\tB\tB\tN12\tM10\tM10\tM10\t零首音\ta高\ta高\ta高\t'fff\ta1\tok\n" +
	"yu1\tyū\tyu1\ty\tü1\tvirtual-h-rounded\tY\tU\tU\tU\tN23\tM07\tM07\tM07\ty\tü高\tü高\tü高\tym..\tyu1\tok\n"

func TestLoadFilterAndTrace(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, DataFileName), []byte(fixture), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "yime_pinyin_codes.tsv"), []byte("pinyin_tone\tfull\na1\t'fff\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	inventory, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(inventory.Rows) != 2 || len(inventory.Categories) != 2 {
		t.Fatalf("unexpected inventory: %#v", inventory)
	}
	if inventory.RuntimeEntries != 1 || inventory.SourceOnly != 1 || inventory.RuntimeOnly != 0 || inventory.Mismatches != 0 {
		t.Fatalf("unexpected runtime comparison: %#v", inventory)
	}
	filtered := inventory.Filter("N12", "zero-initial")
	if len(filtered) != 1 || inventory.Rows[filtered[0]].PinyinTone != "a1" {
		t.Fatalf("unexpected filter result: %#v", filtered)
	}
	trace := inventory.Rows[1].Trace(map[string]string{"N23": "y", "M07": "m"})
	for _, wanted := range []string{"命中规则：virtual-h-rounded", "N23", "M07", "当前布局键码：ymmm"} {
		if !strings.Contains(trace, wanted) {
			t.Fatalf("trace missing %q: %s", wanted, trace)
		}
	}
}

func TestBundledInventoryIsExhaustiveAndContainsSpecialRules(t *testing.T) {
	inventory, err := Load(filepath.Join("..", "data"))
	if err != nil {
		t.Fatal(err)
	}
	if len(inventory.Rows) < 1700 {
		t.Fatalf("expected full canonical inventory, got %d rows", len(inventory.Rows))
	}
	if inventory.RuntimeEntries+inventory.SourceOnly != len(inventory.Rows) || inventory.RuntimeOnly != 0 || inventory.Mismatches != 0 {
		t.Fatalf("runtime coverage was hidden or inconsistent: %#v", inventory)
	}
	categories := strings.Join(inventory.Categories, " ")
	for _, wanted := range []string{"zero-initial", "virtual-j", "virtual-h-rounded", "syllabic-ng"} {
		if !strings.Contains(categories, wanted) {
			t.Fatalf("bundled inventory missing %s: %s", wanted, categories)
		}
	}
}
