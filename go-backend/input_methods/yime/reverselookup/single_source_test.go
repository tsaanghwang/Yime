package reverselookup

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func TestShippedCodeMapContainsCanonicalFullOrExplicitLayoutCodes(t *testing.T) {
	path := filepath.Join("..", "data", "yime_pinyin_codes.tsv")
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	line := 0
	for scanner.Scan() {
		line++
		if strings.TrimSpace(scanner.Text()) == "" {
			continue
		}
		fields := strings.Split(scanner.Text(), "\t")
		if len(fields) != 2 && len(fields) != 4 {
			t.Fatalf("line %d must contain full-only or explicit three-mode columns, got %d", line, len(fields))
		}
		if line == 1 {
			if fields[0] != "pinyin_tone" || fields[1] != "full" || (len(fields) == 4 && (fields[2] != "variable" || fields[3] != "shorthand")) {
				t.Fatalf("unexpected header: %q", scanner.Text())
			}
			continue
		}
		if len(fields) == 2 {
			if _, err := codemode.BuildRecord(fields[1]); err != nil {
				t.Fatalf("line %d %s: %v", line, fields[0], err)
			}
		} else if fields[1] == "" || fields[2] == "" || fields[3] == "" || len([]rune(fields[1]))%codemode.SyllableCodeLength != 0 {
			t.Fatalf("line %d has invalid explicit mode codes: %q", line, scanner.Text())
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
}

func TestLoadCodeMapAcceptsFullOnlySource(t *testing.T) {
	path := filepath.Join(t.TempDir(), "codes.tsv")
	if err := os.WriteFile(path, []byte("pinyin_tone\tfull\na2\t'sdf\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := loadCodeMap(path)
	if err != nil {
		t.Fatal(err)
	}
	if record := got["a2"]; record.Variable != "'sdf" || record.Shorthand != "'sf" {
		t.Fatalf("unexpected derived record: %#v", record)
	}
}

func TestLoadCodeMapPrefersExplicitModesForCustomLayout(t *testing.T) {
	path := filepath.Join(t.TempDir(), "codes.tsv")
	// '?' is intentionally outside the legacy compiled LayoutAlphabet. If this
	// row were passed through codemode.BuildRecord, loading would fail.
	content := "pinyin_tone\tfull\tvariable\tshorthand\na2\t?abc\t?bc\t?c\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := loadCodeMap(path)
	if err != nil {
		t.Fatal(err)
	}
	if record := got["a2"]; record.Full != "?abc" || record.Variable != "?bc" || record.Shorthand != "?c" {
		t.Fatalf("unexpected explicit record: %#v", record)
	}
}
