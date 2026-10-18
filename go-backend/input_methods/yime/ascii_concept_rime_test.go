//go:build windows

package yime

import (
	"bufio"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

var runASCIIConceptRime = flag.Bool("ascii-concept-rime", false, "run isolated real librime acceptance for the generated 134-key experiment")

type conceptErhuaCase struct {
	text, pinyin string
	fused        map[string]string
}

// This is a new-schema, disposable real-librime contract. It never refreshes
// installed data or copies historical product schemas. Its candidate buckets
// retain text and weight from the digest-bound full experimental dictionaries,
// including competing texts; only code syllable spaces are flattened, as in
// the Go index, for this table-translator fixture. The only synthetic records are explicitly named
// ASCII transport probes, not invented pronunciations or Yinyuan encodings.
func TestRealRimeASCIIConceptErhuaThreeModesAndRollback(t *testing.T) {
	if !*runASCIIConceptRime {
		t.Skip("set -ascii-concept-rime to run the isolated 134-key real Rime test")
	}
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate checkout")
	}
	repo := filepath.Clean(filepath.Join(filepath.Dir(filename), "..", "..", ".."))
	dataDir := filepath.Join(repo, ".generated", "ascii-keyboard-134", "data")
	manifestBytes, err := os.ReadFile(filepath.Join(dataDir, "ascii_keyboard_manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest struct {
		Layout   string            `json:"layout_projection_sha256"`
		Policy   string            `json:"input_policy"`
		Limit    int               `json:"limit"`
		Disabled []string          `json:"disabled_yinyuan_ids"`
		SHA      map[string]string `json:"dictionary_sha256"`
		Overlays struct {
			Summary struct {
				Passed bool `json:"passed"`
				Count  int  `json:"explicit_record_count"`
			} `json:"erhua_summary"`
		} `json:"reviewed_overlays"`
	}
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.Layout != codemode.LayoutProjectionSHA256 || manifest.Policy != "concept-keyboard-modes-v2" || manifest.Limit != 0 || len(manifest.Disabled) != 0 || !manifest.Overlays.Summary.Passed || manifest.Overlays.Summary.Count != 131 {
		t.Fatal("complete current 75-carrier, reviewed-erhua experiment manifest required")
	}
	if len(codemode.LayoutAlphabet) != 75 {
		t.Fatal("expected 75 ASCII carriers")
	}
	cases := readConceptErhuaCases(t, filepath.Join(dataDir, "yime_erhua_reverse_source.tsv"))
	codeMap := readConceptCodeMap(t, filepath.Join(dataDir, "yime_pinyin_codes.tsv"))
	tempRoot := t.TempDir()
	shared, user := filepath.Join(tempRoot, "shared"), filepath.Join(tempRoot, "user")
	for _, path := range []string{shared, user} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	modeNames := []string{"variable", "full", "shorthand"}
	suffix := map[string]map[string]string{}
	var schemas []string
	for _, mode := range modeNames {
		suffix[mode] = map[string]string{}
		codes := map[string]bool{}
		fusedPairs := map[string]bool{}
		for _, item := range cases {
			code, _, err := reverselookup.EncodeNumericTonePinyin(codeMap, item.pinyin, reverselookup.Mode(mode))
			if err != nil {
				t.Fatal(err)
			}
			if code == item.fused[mode] {
				t.Fatalf("%s/%s suffix and fused paths unexpectedly identical", mode, item.text)
			}
			suffix[mode][item.text] = code
			codes[code], codes[item.fused[mode]] = true, true
			fusedPairs[item.text+"\t"+item.fused[mode]] = true
		}
		name := "yime_" + mode + ".dict.yaml"
		rows := readConceptCandidateBuckets(t, filepath.Join(dataDir, name), manifest.SHA[name], codes)
		found := map[string]bool{}
		for _, row := range rows {
			parts := strings.Split(row, "\t")
			found[parts[0]+"\t"+parts[1]] = true
		}
		for _, item := range cases {
			for _, code := range []string{item.fused[mode], suffix[mode][item.text]} {
				if !found[item.text+"\t"+code] {
					t.Fatalf("complete corpus missing %s/%s/%q", mode, item.text, code)
				}
			}
		}
		for _, enabled := range []bool{true, false} {
			phase := "enabled"
			if !enabled {
				phase = "disabled"
			}
			schema := "ascii_concept_" + phase + "_" + mode
			schemas = append(schemas, schema)
			var selected []string
			for _, row := range rows {
				parts := strings.Split(row, "\t")
				if enabled || !fusedPairs[parts[0]+"\t"+parts[1]] {
					selected = append(selected, row)
				}
			}
			for _, carrier := range codemode.LayoutAlphabet {
				selected = append(selected, fmt.Sprintf("ASCII-probe-%02X\t%sa\t1", carrier, string(carrier)))
			}
			writeConceptRimeSchema(t, shared, schema, selected)
		}
		t.Logf("%s: %d complete source candidate-bucket rows; all 131 suffix/fused records retained; SHA-256 %s", mode, len(rows), manifest.SHA[name])
	}
	defaultYAML := "config_version: '1'\nschema_list:\n"
	for _, schema := range schemas {
		defaultYAML += "  - schema: " + schema + "\n"
	}
	if err := os.WriteFile(filepath.Join(shared, "default.yaml"), []byte(defaultYAML), 0600); err != nil {
		t.Fatal(err)
	}
	// RimeInit's existing pinned-runtime gate reads rime.dll and companions from
	// the package's working directory. Only shared/user data live in TempDir.
	if !RimeInit(shared, user, "ascii_concept_trial", "1", true) {
		t.Fatal("isolated RimeInit failed")
	}
	session, ok := StartSession()
	if !ok || session == 0 {
		Finalize()
		t.Fatal("isolated StartSession failed")
	}
	defer func() { EndSession(session); Finalize() }()
	for _, mode := range modeNames {
		for _, enabled := range []bool{true, false} {
			phase := "enabled"
			if !enabled {
				phase = "disabled"
			}
			schema := "ascii_concept_" + phase + "_" + mode
			if !SelectSchema(session, schema) {
				t.Fatalf("select %s", schema)
			}
			SetOption(session, "ascii_mode", false)
			for _, carrier := range codemode.LayoutAlphabet {
				probe := string(carrier) + "a"
				text := fmt.Sprintf("ASCII-probe-%02X", carrier)
				index, found := findConceptRimeCandidate(t, session, probe, text)
				if !found {
					t.Fatalf("%s transport carrier %q missing", schema, carrier)
				}
				if raw, ok := GetRawInput(session); !ok || raw != probe {
					t.Fatalf("%s folded/translated raw %q to %q", schema, probe, raw)
				}
				selectConceptRimeCandidate(t, session, index, text)
			}
			for _, item := range cases {
				index, found := findConceptRimeCandidate(t, session, item.fused[mode], item.text)
				if found != enabled {
					t.Fatalf("%s fused %s/%q found=%t want=%t", schema, item.text, item.fused[mode], found, enabled)
				}
				if found {
					selectConceptRimeCandidate(t, session, index, item.text)
				}
				index, found = findConceptRimeCandidate(t, session, suffix[mode][item.text], item.text)
				if !found {
					t.Fatalf("%s suffix compatibility %s/%q missing", schema, item.text, suffix[mode][item.text])
				}
				selectConceptRimeCandidate(t, session, index, item.text)
			}
			t.Logf("%s: 75 case-sensitive ASCII carrier probes; 131 fused-path checks; 131 suffix commits passed", schema)
		}
	}
}

func readConceptErhuaCases(t *testing.T, path string) []conceptErhuaCase {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	r := csv.NewReader(file)
	r.Comma = '\t'
	header, err := r.Read()
	if err != nil {
		t.Fatal(err)
	}
	columns := map[string]int{}
	for i, name := range header {
		columns[name] = i
	}
	for _, name := range []string{"record_id", "text", "source_kind", "compatibility_numeric_pinyin", "full_code", "variable_code", "shorthand_code"} {
		if _, ok := columns[name]; !ok {
			t.Fatalf("reverse projection missing %s", name)
		}
	}
	var result []conceptErhuaCase
	seen := map[string]bool{}
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		text := row[columns["text"]]
		if seen[text] || row[columns["source_kind"]] != "psc_erhua" {
			t.Fatalf("unexpected/duplicate reviewed row %q", text)
		}
		seen[text] = true
		item := conceptErhuaCase{text: text, pinyin: row[columns["compatibility_numeric_pinyin"]], fused: map[string]string{}}
		for _, mode := range []string{"variable", "full", "shorthand"} {
			code := row[columns[mode+"_code"]]
			if code == "" {
				t.Fatalf("missing fused code %s/%s", text, mode)
			}
			for _, c := range code {
				if !strings.ContainsRune(codemode.LayoutAlphabet, c) {
					t.Fatalf("foreign carrier %q", c)
				}
			}
			item.fused[mode] = code
		}
		result = append(result, item)
	}
	if len(result) != 131 {
		t.Fatalf("reviewed record count %d want 131", len(result))
	}
	return result
}

func readConceptCandidateBuckets(t *testing.T, path, digest string, codes map[string]bool) []string {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	hash := sha256.New()
	scanner := bufio.NewScanner(io.TeeReader(file, hash))
	scanner.Buffer(make([]byte, 64*1024), 8*1024*1024)
	started := false
	var result []string
	for scanner.Scan() {
		line := scanner.Text()
		if !started {
			started = strings.TrimSpace(line) == "..."
			continue
		}
		if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) < 3 {
			t.Fatalf("invalid source dictionary row in %s", path)
		}
		flat := strings.ReplaceAll(parts[1], " ", "")
		if codes[flat] {
			parts[1] = flat
			result = append(result, strings.Join(parts, "\t"))
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if !started || hex.EncodeToString(hash.Sum(nil)) != digest {
		t.Fatalf("source dictionary is not manifest-bound: %s", path)
	}
	sort.Strings(result)
	return result
}

func writeConceptRimeSchema(t *testing.T, dir, name string, rows []string) {
	t.Helper()
	quoted, _ := json.Marshal(codemode.LayoutAlphabet)
	schema := fmt.Sprintf("schema:\n  schema_id: %s\n  name: isolated-concept-trial\n  version: '1'\nswitches:\n  - name: ascii_mode\n    reset: 0\nengine:\n  processors: [speller, selector, navigator, express_editor]\n  segmentors: [abc_segmentor]\n  translators: [table_translator]\nspeller:\n  alphabet: %s\n  initials: %s\n  delimiter: ''\n  auto_select: false\ntranslator:\n  dictionary: %s\n  enable_user_dict: false\n  enable_sentence: false\n  enable_completion: false\nmenu:\n  page_size: 9\n", name, quoted, quoted, name)
	dictionary := fmt.Sprintf("---\nname: %s\nversion: '1'\nsort: by_weight\n...\n%s\n", name, strings.Join(rows, "\n"))
	for file, contents := range map[string]string{name + ".schema.yaml": schema, name + ".dict.yaml": dictionary} {
		if err := os.WriteFile(filepath.Join(dir, file), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func selectConceptRimeCandidate(t *testing.T, session RimeSessionId, index int, text string) {
	t.Helper()
	if !SelectCandidate(session, index) {
		t.Fatalf("select %q index %d", text, index)
	}
	commit, ok := GetCommit(session)
	if !ok || commit.Text != text {
		t.Fatalf("commit %q got %#v available=%t", text, commit, ok)
	}
}

func findConceptRimeCandidate(t *testing.T, session RimeSessionId, input, text string) (int, bool) {
	t.Helper()
	ClearComposition(session)
	typeASCII(t, session, input)
	for page := 0; page < 100; page++ {
		menu, ok := GetMenu(session)
		// librime can return an empty context with is_last_page=false. This is
		// absence, not an invitation to page forever through an empty menu.
		if !ok || len(menu.Candidates) == 0 {
			return -1, false
		}
		for index, candidate := range menu.Candidates {
			if candidate.Text == text {
				return menu.PageNo*menu.PageSize + index, true
			}
		}
		if menu.IsLastPage || !ProcessKey(session, rimeNext, 0) {
			return -1, false
		}
	}
	t.Fatalf("candidate paging exceeded 100 pages for %q after %q", text, input)
	return -1, false
}

// The opt-in experiment must not derive codes with the product default layout.
func readConceptCodeMap(t *testing.T, path string) map[string]reverselookup.CodeRecord {
	t.Helper()
	stream, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.Close()
	reader := csv.NewReader(stream)
	reader.Comma = '\t'
	if _, err := reader.Read(); err != nil {
		t.Fatal(err)
	}
	result := map[string]reverselookup.CodeRecord{}
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(row) != 2 {
			t.Fatalf("invalid experimental pinyin row: %v", err)
		}
		record, err := codemode.BuildRecord(row[1])
		if err != nil {
			t.Fatal(err)
		}
		key := strings.NewReplacer("u:", "ü", "v", "ü").Replace(strings.ToLower(row[0]))
		result[key] = reverselookup.CodeRecord{Full: record.Full, Variable: record.Variable, Shorthand: record.Shorthand}
	}
	return result
}
