package layoutdesigner

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
)

// TrialPinyin projects numeric-tone Pinyin through an in-memory draft without
// changing dictionaries. It is intentionally based on the current canonical
// full-code table and the Yinyuan bridge, never on a direct Pinyin-to-new-key map.
func TrialPinyin(dataDir string, target Profile, pinyin string) (codemode.Record, error) {
	source, err := LoadProfile(filepath.Join(dataDir, ProfileFileName))
	if err != nil {
		return codemode.Record{}, err
	}
	codec, err := NewCodec(source, target)
	if err != nil {
		return codemode.Record{}, err
	}
	wanted := strings.Fields(strings.ToLower(strings.TrimSpace(pinyin)))
	if len(wanted) == 0 {
		return codemode.Record{}, fmt.Errorf("请输入数字标调拼音，例如 zhong1 guo2")
	}
	lookup := map[string]string{}
	f, err := os.Open(filepath.Join(dataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return codemode.Record{}, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	first := true
	for s.Scan() {
		if first {
			first = false
			continue
		}
		fields := strings.Split(s.Text(), "\t")
		if len(fields) >= 2 {
			lookup[strings.ToLower(strings.TrimSpace(fields[0]))] = strings.TrimSpace(fields[1])
		}
	}
	if err := s.Err(); err != nil {
		return codemode.Record{}, err
	}
	var full strings.Builder
	for _, item := range wanted {
		code := lookup[item]
		if code == "" {
			return codemode.Record{}, fmt.Errorf("拼音码表中找不到 %s", item)
		}
		full.WriteString(code)
	}
	return codec.Reencode(full.String())
}
