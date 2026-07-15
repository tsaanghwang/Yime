package reverselookup

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

func TestShippedCodeMapContainsOnlyCanonicalFullCodes(t *testing.T) {
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
		if len(fields) != 2 {
			t.Fatalf("line %d must contain only pinyin_tone and full, got %d columns", line, len(fields))
		}
		if line == 1 {
			if fields[0] != "pinyin_tone" || fields[1] != "full" {
				t.Fatalf("unexpected header: %q", scanner.Text())
			}
			continue
		}
		if _, err := codemode.BuildRecord(fields[1]); err != nil {
			t.Fatalf("line %d %s: %v", line, fields[0], err)
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
}

func TestLoadCodeMapAcceptsFullOnlySource(t *testing.T) {
	path := filepath.Join(t.TempDir(), "codes.tsv")
	if err := os.WriteFile(path, []byte("pinyin_tone\tfull\na2\tHsdf\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := loadCodeMap(path)
	if err != nil {
		t.Fatal(err)
	}
	if record := got["a2"]; record.Variable != "sdf" || record.Shorthand != "sf" {
		t.Fatalf("unexpected derived record: %#v", record)
	}
}
