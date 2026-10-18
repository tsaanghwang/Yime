package main

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

var integrationRoot = flag.String("keyboard-lab-integration-root", "", "optional checkout root for full generated-corpus HTTP acceptance")

func TestCanonicalCorpusHTTP(t *testing.T) {
	if *integrationRoot == "" {
		t.Skip("set -keyboard-lab-integration-root to test all generated dictionary entries")
	}
	root, err := filepath.Abs(*integrationRoot)
	if err != nil {
		t.Fatal(err)
	}
	dataDir := filepath.Join(root, ".generated", "ascii-keyboard-134", "data")
	data, err := os.ReadFile(filepath.Join(root, "prototypes", "touch-terminal", "data", "physical-layout.json"))
	if err != nil {
		t.Fatal(err)
	}
	var layout struct {
		LayoutID string `json:"layoutId"`
		Keys     []struct {
			YinyuanIDs      []string `json:"baseYinyuanIds"`
			ShiftYinyuanIDs []string `json:"shiftYinyuanIds"`
			ShiftAction     struct {
				Type  string `json:"type"`
				ASCII string `json:"ascii"`
			} `json:"shiftAction"`
			Disabled []string `json:"disabledYinyuanIds"`
			Action   struct {
				Type  string `json:"type"`
				ASCII string `json:"ascii"`
			} `json:"action"`
		} `json:"keys"`
	}
	if err := json.Unmarshal(data, &layout); err != nil {
		t.Fatal(err)
	}
	manifest, err := loadManifest(dataDir, layout.LayoutID)
	if err != nil {
		t.Fatal(err)
	}
	projection := map[string]string{}
	for _, key := range layout.Keys {
		if key.Action.Type != "input" {
			continue
		}
		disabled := map[string]bool{}
		for _, id := range key.Disabled {
			disabled[id] = true
		}
		for _, id := range key.ShiftYinyuanIDs {
			if !disabled[id] {
				projection[id] = key.ShiftAction.ASCII
			}
		}
		for _, id := range key.YinyuanIDs {
			if !disabled[id] {
				projection[id] = key.Action.ASCII
			}
		}
	}
	// Source IDs come from the canonical decomposition, never dictionary keys.
	// Its historical layout_code column is deliberately ignored.
	cases := canonicalCases(t, root, projection)
	indices := map[string]*yimecore.FileIndex{}
	for _, mode := range modes {
		source := filepath.Join(dataDir, "yime_"+mode+".dict.yaml")
		output := filepath.Join(t.TempDir(), mode+".yidx")
		build, err := yimecore.BuildIndexFile(mode, source, output)
		if err != nil {
			t.Fatal(err)
		}
		if build.SourceSHA256 != manifest.DictionarySHA256[filepath.Base(source)] {
			t.Fatalf("%s source digest mismatch", mode)
		}
		index, err := yimecore.OpenFileIndex(output)
		if err != nil {
			t.Fatal(err)
		}
		indices[mode] = index
		t.Cleanup(func() { _ = index.Close() })
		t.Logf("%s actual corpus: %d entries; source SHA-256 %s", mode, build.IndexedRecords, build.SourceSHA256)
	}
	a := newLab(filepath.Join(root, "prototypes", "touch-terminal"), layout.LayoutID, "", func(mode string) (engineapi.Engine, error) { return yimecore.NewFileEngine(indices[mode], 9) })
	server := httptest.NewServer(a)
	defer server.Close()
	a.origin = server.URL
	client := server.Client()
	post := func(path string, value any) response {
		t.Helper()
		body, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		req, err := http.NewRequest(http.MethodPost, server.URL+path, bytes.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Yime-Lab-Token", a.token)
		req.Header.Set("Origin", server.URL)
		resp, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		data, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		if resp.StatusCode != 200 {
			t.Fatalf("%s status %d: %s", path, resp.StatusCode, data)
		}
		var result response
		if err := json.Unmarshal(data, &result); err != nil {
			t.Fatal(err)
		}
		if !result.OK {
			t.Fatalf("%s rejected: %s", path, data)
		}
		return result
	}
	for _, mode := range modes {
		s := post("/api/session", map[string]string{"mode": mode, "layoutId": layout.LayoutID})
		sequence := 0
		mutate := func(kind, code, candidate string, delta int) {
			t.Helper()
			sequence++
			s = post("/api/event", eventRequest{SessionID: s.SessionID, EventID: fmt.Sprintf("event-%d", sequence), BaseRevision: s.Revision, Type: kind, Code: code, CandidateID: candidate, Delta: delta})
		}
		for _, item := range cases {
			code := map[string]string{"variable": item.record.Variable, "full": item.record.Full, "shorthand": item.record.Shorthand}[mode]
			for _, key := range code {
				mutate("input", string(key), "", 0)
			}
			if s.State.RawInput != code || s.Commit != "" {
				t.Fatalf("%s %s did not compose %q: %+v", mode, item.pinyin, code, s)
			}
			var candidateID string
			for pages := 0; pages < 100; pages++ {
				for _, candidate := range s.State.Candidates {
					if candidate.Text == item.text && candidate.Exact {
						candidateID = candidate.ID
						break
					}
				}
				if candidateID != "" || !s.State.HasNext {
					break
				}
				mutate("page", "", "", 1)
			}
			if candidateID == "" {
				t.Fatalf("%s %s %q exact candidate %q missing", mode, item.pinyin, code, item.text)
			}
			mutate("select", "", candidateID, 0)
			if s.Commit != item.text || s.State.RawInput != "" {
				t.Fatalf("%s commit: %+v", mode, s)
			}
			t.Logf("%s %s: source IDs -> %q -> real candidate -> commit %q", mode, item.pinyin, code, s.Commit)
		}
		// Ordinary prefixes retain native engine paging. The single-symbol
		// candidate overlay is exercised separately below.
		mutate("input", cases[0].record.Full[:1], "", 0)
		if !s.State.HasNext {
			t.Fatalf("%s expected multi-page corpus prefix", mode)
		}
		first := s.State.Candidates[0].ID
		mutate("page", "", "", 1)
		if s.State.PageNumber != 1 || !s.State.HasPrevious {
			t.Fatalf("%s next-page state: %+v", mode, s.State)
		}
		mutate("page", "", "", -1)
		if s.State.PageNumber != 0 || s.State.Candidates[0].ID != first {
			t.Fatalf("%s page round trip: %+v", mode, s.State)
		}
		mutate("clear", "", "", 0)
		for _, symbol := range codingSymbols() {
			mutate("input", symbol, "", 0)
			last := s.State.Candidates[len(s.State.Candidates)-1]
			if last.Text != symbol || last.SourceID != literalSource || len(s.State.Candidates) > 9 {
				t.Fatalf("%s %q first-page literal missing: %+v", mode, symbol, s.State)
			}
			if s.State.HasNext {
				mutate("page", "", "", 1)
				if s.State.PageNumber != 1 || len(s.State.Candidates) == 0 {
					t.Fatalf("%s %q offset page empty: %+v", mode, symbol, s.State)
				}
				want := s.State.Candidates[0].Text
				mutate("input", "1", "", 0)
				if s.Commit != want || s.State.RawInput != "" {
					t.Fatalf("%s %q offset candidate selection failed: %+v", mode, symbol, s)
				}
				mutate("input", symbol, "", 0)
			}
			mutate("select", "", last.ID, 0)
			if s.Commit != symbol || s.State.RawInput != "" {
				t.Fatalf("%s literal commit: %+v", mode, s)
			}
		}
		mutate("input", "7", "", 0)
		if s.Commit != "7" || s.State.RawInput != "" {
			t.Fatalf("%s idle digit: %+v", mode, s)
		}
		code := map[string]string{"variable": cases[0].record.Variable, "full": cases[0].record.Full, "shorthand": cases[0].record.Shorthand}[mode]
		for _, key := range code {
			mutate("input", string(key), "", 0)
		}
		punct := nonCodingSymbol(t)
		want := s.State.Candidates[0].Text + punct
		mutate("input", punct, "", 0)
		if s.Commit != want || s.State.RawInput != "" {
			t.Fatalf("%s automatic first-candidate plus punctuation: %+v", mode, s)
		}
		mutate("close", "", "", 0)
	}
}

type canonicalCase struct {
	pinyin, text string
	record       codemode.Record
}

func canonicalCases(t *testing.T, root string, projection map[string]string) []canonicalCase {
	t.Helper()
	file, err := os.Open(filepath.Join(root, "internal_data", "yime_syllable_decomposition.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.Comma = '\t'
	header, err := reader.Read()
	if err != nil {
		t.Fatal(err)
	}
	columns := map[string]int{}
	for i, name := range header {
		columns[name] = i
	}
	selected := map[string]string{"ni3": "你", "hao3": "好"}
	found := map[string]codemode.Record{}
	for {
		row, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		pinyin := row[columns["pinyin_tone"]]
		if _, ok := selected[pinyin]; !ok {
			continue
		}
		if row[columns["status"]] != "ok" {
			t.Fatalf("unadmitted syllable %s", pinyin)
		}
		full := ""
		for _, slot := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			id := row[columns[slot]]
			key := projection[id]
			if len(key) != 1 {
				t.Fatalf("active layout lacks ASCII for %s", id)
			}
			full += key
		}
		record, err := codemode.BuildRecord(full)
		if err != nil {
			t.Fatal(err)
		}
		found[pinyin] = record
	}
	var result []canonicalCase
	for _, pinyin := range []string{"ni3", "hao3"} {
		record, ok := found[pinyin]
		if !ok {
			t.Fatalf("canonical syllable missing: %s", pinyin)
		}
		result = append(result, canonicalCase{pinyin, selected[pinyin], record})
	}
	return result
}
