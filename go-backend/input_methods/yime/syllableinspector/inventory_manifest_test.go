package syllableinspector

import (
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

type inventoryManifest struct {
	SchemaVersion                     int      `json:"schema_version"`
	SourceProject                     string   `json:"source_project"`
	SourceRevision                    string   `json:"source_revision"`
	MaterializedTable                 string   `json:"materialized_table"`
	MaterializedNumericSyllableCount  int      `json:"materialized_numeric_syllable_count"`
	MaterializedNumericSyllableSHA256 string   `json:"materialized_numeric_syllable_sha256"`
	CanonicalInventoryCount           int      `json:"canonical_inventory_count"`
	CanonicalOnlySyllables            []string `json:"canonical_only_syllables"`
}

func TestBundledRuntimeInventoryMatchesPrototypeMaterializationManifest(t *testing.T) {
	dataDir := filepath.Join("..", "data")
	manifestBytes, err := os.ReadFile(filepath.Join(dataDir, "yime_syllable_inventory_manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest inventoryManifest
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.SchemaVersion != 1 || manifest.SourceProject != "Yime-python-prototype" ||
		manifest.MaterializedTable != "m_distinct_syllable_inventory" || len(manifest.SourceRevision) != 40 {
		t.Fatalf("invalid prototype materialization provenance: %#v", manifest)
	}

	runtimeSyllables := readRuntimeSyllables(t, filepath.Join(dataDir, "yime_pinyin_codes.tsv"))
	if len(runtimeSyllables) != manifest.MaterializedNumericSyllableCount {
		t.Fatalf("runtime syllables=%d, prototype materialized=%d", len(runtimeSyllables), manifest.MaterializedNumericSyllableCount)
	}
	hash := sha256.New()
	for _, syllable := range runtimeSyllables {
		fmt.Fprintln(hash, syllable)
	}
	if got := hex.EncodeToString(hash.Sum(nil)); got != manifest.MaterializedNumericSyllableSHA256 {
		t.Fatalf("runtime syllable set hash=%s, prototype materialized=%s", got, manifest.MaterializedNumericSyllableSHA256)
	}

	inventory, err := Load(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(inventory.Rows) != manifest.CanonicalInventoryCount ||
		inventory.RuntimeEntries != manifest.MaterializedNumericSyllableCount ||
		inventory.RuntimeOnly != 0 || inventory.Mismatches != 0 {
		t.Fatalf("canonical/runtime inventory mismatch: %#v", inventory)
	}
	canonicalOnly := make([]string, 0, inventory.CanonicalOnly)
	for _, row := range inventory.Rows {
		if row.Status == "canonical-only" {
			canonicalOnly = append(canonicalOnly, row.PinyinTone)
		}
	}
	sort.Strings(canonicalOnly)
	wantCanonicalOnly := append([]string(nil), manifest.CanonicalOnlySyllables...)
	sort.Strings(wantCanonicalOnly)
	if !reflect.DeepEqual(canonicalOnly, wantCanonicalOnly) {
		t.Fatalf("canonical-only syllables=%v, manifest=%v", canonicalOnly, wantCanonicalOnly)
	}
}

func readRuntimeSyllables(t *testing.T, path string) []string {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil || len(header) < 2 || header[0] != "pinyin_tone" || header[1] != "full" {
		t.Fatalf("invalid runtime syllable header in %s", path)
	}
	seen := map[string]struct{}{}
	for {
		record, readErr := reader.Read()
		if readErr == io.EOF {
			break
		}
		if readErr != nil || len(record) < 2 || strings.TrimSpace(record[0]) == "" {
			t.Fatalf("invalid runtime syllable row in %s: %v", path, readErr)
		}
		if _, exists := seen[record[0]]; exists {
			t.Fatalf("duplicate runtime syllable %s", record[0])
		}
		seen[record[0]] = struct{}{}
	}
	result := make([]string, 0, len(seen))
	for syllable := range seen {
		result = append(result, syllable)
	}
	sort.Strings(result)
	return result
}
