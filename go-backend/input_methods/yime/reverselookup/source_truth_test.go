package reverselookup

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"
)

func TestSourceTruthRestoresMultiplePinyinAcrossModes(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())

	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"),
		"pinyin\tfull\tvariable\tshorthand\n"+
			"e2\tabcd\tab\ta\n"+
			"o2\tabcd\tab\ta\n")
	writeTestFile(t, filepath.Join(sharedDir, SourceTruthFileName),
		"text\tsource_full_code\tnumeric_pinyin\tmarked_pinyin\n"+
			"哦\tabcd\te2\té\n"+
			"哦\tabcd\to2\tó\n")

	for _, test := range []struct {
		mode     Mode
		schemaID string
		code     string
	}{
		{ModeFull, "yime_full", "abcd"},
		{ModeVariable, "yime_variable", "ab"},
		{ModeShorthand, "yime_shorthand", "a"},
	} {
		t.Run(string(test.mode), func(t *testing.T) {
			writeTestFile(t, filepath.Join(sharedDir, test.schemaID+".dict.yaml"), "name: test\n...\n哦\t"+test.code+"\n")
			index, err := Load(sharedDir, userDir, test.mode)
			if err != nil {
				t.Fatal(err)
			}
			results := index.Search("哦", false)
			if len(results) != 2 {
				t.Fatalf("got %d results: %#v", len(results), results)
			}
			got := []string{results[0].NumericPinyin, results[1].NumericPinyin}
			sort.Strings(got)
			if !reflect.DeepEqual(got, []string{"e2", "o2"}) {
				t.Fatalf("numeric Pinyin = %#v", got)
			}
			for _, result := range results {
				if result.ActiveCode != test.code {
					t.Fatalf("active code = %q, want %q", result.ActiveCode, test.code)
				}
			}
		})
	}
}

func TestSourceTruthMissingKeepsLegacyFallback(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())
	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), "pinyin\tfull\tvariable\tshorthand\ne2\tabcd\tab\ta\no2\tabcd\tab\ta\n")
	writeTestFile(t, filepath.Join(sharedDir, "yime_full.dict.yaml"), "name: test\n...\n哦\tabcd\n")
	index, err := Load(sharedDir, userDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if results := index.Search("哦", false); len(results) != 1 || results[0].NumericPinyin == "" {
		t.Fatalf("legacy fallback failed: %#v", results)
	}
}

func TestSourceTruthChangeInvalidatesReverseLookupCache(t *testing.T) {
	sharedDir := t.TempDir()
	userDir := t.TempDir()
	t.Setenv("LOCALAPPDATA", t.TempDir())
	writeTestFile(t, filepath.Join(sharedDir, "yime_pinyin_codes.tsv"), "pinyin\tfull\tvariable\tshorthand\ne2\tabcd\tab\ta\no2\tabcd\tab\ta\n")
	writeTestFile(t, filepath.Join(sharedDir, "yime_full.dict.yaml"), "name: test\n...\n哦\tabcd\n")
	sidecar := filepath.Join(sharedDir, SourceTruthFileName)
	writeTestFile(t, sidecar, "text\tsource_full_code\tnumeric_pinyin\tmarked_pinyin\n哦\tabcd\te2\té\n")

	first, err := Load(sharedDir, userDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if results := first.Search("哦", false); len(results) != 1 || results[0].NumericPinyin != "e2" {
		t.Fatalf("first lookup = %#v", results)
	}

	writeTestFile(t, sidecar, "text\tsource_full_code\tnumeric_pinyin\tmarked_pinyin\n哦\tabcd\to2\tó\n")
	future := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(sidecar, future, future); err != nil {
		t.Fatal(err)
	}
	second, err := Load(sharedDir, userDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if results := second.Search("哦", false); len(results) != 1 || results[0].NumericPinyin != "o2" {
		t.Fatalf("lookup after sidecar change = %#v", results)
	}
}

func TestDeriveSourceTruthWritesOnlyAffectedEntriesAndReplacesOutput(t *testing.T) {
	dir := t.TempDir()
	codes := filepath.Join(dir, "codes.tsv")
	dict := filepath.Join(dir, "dict.yaml")
	entries := filepath.Join(dir, "entries.tsv")
	output := filepath.Join(dir, SourceTruthFileName)
	writeTestFile(t, codes, "pinyin\tfull\tvariable\tshorthand\ne2\tabcd\tab\ta\no2\tabcd\tab\ta\nba1\twxyz\twx\tw\n")
	writeTestFile(t, dict, "name: test\n...\n哦\tabcd\n吧\twxyz\n")
	writeTestFile(t, entries, "text\tpinyin_marked\tpinyin_numeric\n哦\té\te2\n哦\tó\to2\n吧\tbā\tba1\n")
	writeTestFile(t, output, "old data")

	summary, err := DeriveSourceTruth(codes, dict, entries, output)
	if err != nil {
		t.Fatal(err)
	}
	if summary.AmbiguousFullCodes != 1 || summary.AffectedEntries != 1 || summary.SourceRows != 2 || summary.UnresolvedEntries != 0 {
		t.Fatalf("unexpected summary: %#v", summary)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if !strings.Contains(text, "哦\tabcd\te2\té") || !strings.Contains(text, "哦\tabcd\to2\tó") || strings.Contains(text, "吧") || strings.Contains(text, "old data") {
		t.Fatalf("unexpected output:\n%s", text)
	}
}

func TestCheckedInSourceTruthPreservesKnownMergedPinyin(t *testing.T) {
	dataDir := filepath.Join("..", "data")
	lookup, err := LoadSourceTruth(dataDir, ModeFull)
	if err != nil {
		t.Fatal(err)
	}
	if len(lookup) != 41964 {
		t.Fatalf("source truth keys = %d, want 41964", len(lookup))
	}
	checks := []struct {
		text string
		code string
		want []string
	}{
		{"哦", "'wer", []string{"e2", "o2"}},
		{"饿", "'rew", []string{"e4"}},
		{"了", `\eee`, []string{"le5"}},
		{"咯", `\eee`, []string{"lo5"}},
	}
	for _, check := range checks {
		got := lookup[SourceTruthLookupKey(check.text, check.code)]
		if !reflect.DeepEqual(got, check.want) {
			t.Fatalf("%s/%s = %#v, want %#v", check.text, check.code, got, check.want)
		}
	}
}

func TestDeriveSourceTruthRejectsUnresolvedEntryWithoutReplacingOutput(t *testing.T) {
	dir := t.TempDir()
	codes := filepath.Join(dir, "codes.tsv")
	dict := filepath.Join(dir, "dict.yaml")
	entries := filepath.Join(dir, "entries.tsv")
	output := filepath.Join(dir, SourceTruthFileName)
	writeTestFile(t, codes, "pinyin\tfull\tvariable\tshorthand\ne2\tabcd\tab\ta\no2\tabcd\tab\ta\n")
	writeTestFile(t, dict, "name: test\n...\n未收\tabcd\n")
	writeTestFile(t, entries, "text\tpinyin_marked\tpinyin_numeric\n别词\té\te2\n")
	writeTestFile(t, output, "preserve me")

	summary, err := DeriveSourceTruth(codes, dict, entries, output)
	if err == nil || summary.UnresolvedEntries != 1 {
		t.Fatalf("summary=%#v err=%v", summary, err)
	}
	data, readErr := os.ReadFile(output)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(data) != "preserve me" {
		t.Fatalf("failed derivation replaced output: %q", data)
	}
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
