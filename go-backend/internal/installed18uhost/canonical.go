package installed18uhost

import (
	"encoding/csv"
	"encoding/json"
	"errors"
	codemode "github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
	"io"
	"os"
	"path/filepath"
)

// CanonicalNi is extracted unchanged from the registered formal-host test.
func CanonicalNi(root string) (string, error) {
	return CanonicalNiMode(root, "variable")
}
func CanonicalNiMode(root, mode string) (string, error) {
	raw, e := os.ReadFile(filepath.Join(root, "prototypes/touch-terminal/encoding/yime_yinyuan_layout.json"))
	if e != nil {
		return "", e
	}
	var layout struct {
		Keys map[string]string `json:"yinyuan_id_to_key"`
	}
	if e = json.Unmarshal(raw, &layout); e != nil {
		return "", e
	}
	f, e := os.Open(filepath.Join(root, "internal_data/yime_syllable_decomposition.tsv"))
	if e != nil {
		return "", e
	}
	defer f.Close()
	r := csv.NewReader(f)
	r.Comma = '\t'
	head, e := r.Read()
	if e != nil {
		return "", e
	}
	cols := map[string]int{}
	for i, k := range head {
		cols[k] = i
	}
	for _, k := range []string{"pinyin_tone", "status", "shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
		if _, ok := cols[k]; !ok {
			return "", errors.New("canonical column missing")
		}
	}
	for {
		row, e := r.Read()
		if e != nil {
			if e == io.EOF {
				return "", errors.New("canonical ni3 absent")
			}
			return "", e
		}
		if row[cols["pinyin_tone"]] != "ni3" {
			continue
		}
		if row[cols["status"]] != "ok" {
			return "", errors.New("ni3 not admitted")
		}
		full := ""
		for _, k := range []string{"shouyin_id", "huyin_id", "zhuyin_id", "moyin_id"} {
			v := layout.Keys[row[cols[k]]]
			if len(v) != 1 {
				return "", errors.New("projection incomplete")
			}
			full += v
		}
		record, e := codemode.BuildRecord(full)
		if e != nil {
			return "", e
		}
		switch mode {
		case "variable":
			return record.Variable, nil
		case "full":
			return record.Full, nil
		case "shorthand":
			return record.Shorthand, nil
		}
		return "", errors.New("unsupported canonical mode")
	}
}
