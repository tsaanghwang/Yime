package main

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"io"
	"os"
	"path/filepath"
)

// Package diagnostics: never infer pronunciation or Yinyuan IDs from
// dictionary codes, and never manufacture an encoding to make this check pass.
func hostProbeCodes(root string) (map[string]string, error) {
	data, err := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if err != nil {
		return nil, err
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	if err = json.Unmarshal(data, &layout); err != nil {
		return nil, err
	}
	f, err := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.Comma = '\t'
	header, err := r.Read()
	if err != nil {
		return nil, err
	}
	columns := map[string]int{}
	for i, k := range header {
		columns[k] = i
	}
	for _, key := range []string{"pinyin_tone", "status", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
		if _, ok := columns[key]; !ok {
			return nil, fmt.Errorf("canonical column missing: %s", key)
		}
	}
	for {
		row, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		if row[columns["pinyin_tone"]] != "ni3" {
			continue
		}
		if row[columns["status"]] != "ok" {
			return nil, errors.New("probe not admitted")
		}
		full := ""
		for _, slot := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			key := layout.Keys[row[columns[slot]]]
			if len(key) != 1 {
				return nil, errors.New("probe projection missing")
			}
			full += key
		}
		record, err := codemode.BuildRecord(full)
		if err != nil {
			return nil, err
		}
		return map[string]string{"variable": record.Variable, "full": record.Full, "shorthand": record.Shorthand}, nil
	}
	return nil, errors.New("canonical ni3 missing")
}
