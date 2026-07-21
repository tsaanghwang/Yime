package layoutdesigner

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

type Plan struct {
	SourceDigest      string   `json:"source_digest"`
	TargetDigest      string   `json:"target_digest"`
	ChangedIDs        []string `json:"changed_yinyuan_ids"`
	PinyinEntries     int      `json:"pinyin_entries"`
	DictionaryEntries int      `json:"dictionary_entries"`
}

var generatedFiles = []string{ProfileFileName, "yime_pinyin_codes.tsv", "yime_full.dict.yaml", "yime_variable.dict.yaml", "yime_shorthand.dict.yaml", "yime_lexicon_manifest.json", "yime_full.schema.yaml", "yime_variable.schema.yaml", "yime_shorthand.schema.yaml"}

func Preview(dataDir string, target Profile) (Plan, error) {
	source, err := LoadProfile(filepath.Join(dataDir, ProfileFileName))
	if err != nil {
		return Plan{}, err
	}
	if err := target.Validate(); err != nil {
		return Plan{}, err
	}
	sourceDigest, _ := source.Digest()
	targetDigest, _ := target.Digest()
	changed := []string{}
	for _, id := range ExpectedIDs() {
		if source.Projection[id] != target.Projection[id] {
			changed = append(changed, id)
		}
	}
	pinyinCount, err := countTSV(filepath.Join(dataDir, "yime_pinyin_codes.tsv"))
	if err != nil {
		return Plan{}, err
	}
	entries, err := systemlexicon.LoadDictFile(filepath.Join(dataDir, "yime_full.dict.yaml"))
	if err != nil {
		return Plan{}, err
	}
	return Plan{sourceDigest, targetDigest, changed, pinyinCount, len(entries)}, nil
}

// Apply regenerates every layout-dependent artifact in a staging directory and
// replaces the set transactionally. It never edits Pinyin/Yinyuan semantics.
func Apply(dataDir string, target Profile) (Plan, error) {
	lockPath := filepath.Join(dataDir, ".yime-layout-design.lock")
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return Plan{}, fmt.Errorf("布局生成流程已被占用（%s）: %w", lockPath, err)
	}
	fmt.Fprintf(lock, "pid=%d time=%s\n", os.Getpid(), time.Now().Format(time.RFC3339))
	_ = lock.Close()
	defer os.Remove(lockPath)
	plan, err := Preview(dataDir, target)
	if err != nil {
		return Plan{}, err
	}
	if len(plan.ChangedIDs) == 0 {
		return plan, nil
	}
	if target.BasedOnDigest != "" && target.BasedOnDigest != plan.SourceDigest {
		return Plan{}, fmt.Errorf("草案基于布局 %s，但当前正式布局是 %s；拒绝覆盖外部变更", target.BasedOnDigest, plan.SourceDigest)
	}
	source, err := LoadProfile(filepath.Join(dataDir, ProfileFileName))
	if err != nil {
		return Plan{}, err
	}
	codec, err := NewCodec(source, target)
	if err != nil {
		return Plan{}, err
	}
	stage, err := os.MkdirTemp(dataDir, ".layout-design-stage-")
	if err != nil {
		return Plan{}, err
	}
	defer os.RemoveAll(stage)
	if err := writeCodeMap(filepath.Join(dataDir, "yime_pinyin_codes.tsv"), filepath.Join(stage, "yime_pinyin_codes.tsv"), codec); err != nil {
		return Plan{}, err
	}
	entries, err := systemlexicon.LoadDictFile(filepath.Join(dataDir, "yime_full.dict.yaml"))
	if err != nil {
		return Plan{}, err
	}
	outputs, err := buildDictionaries(entries, codec, plan.TargetDigest[:12])
	if err != nil {
		return Plan{}, err
	}
	hashes := map[string]string{}
	for name, data := range outputs {
		hashes[name] = hash(data)
		if err := os.WriteFile(filepath.Join(stage, name), data, 0644); err != nil {
			return Plan{}, err
		}
	}
	manifest := map[string]any{"format_version": 2, "generated_at": time.Now().Format(time.RFC3339), "source_file": "yime_full.dict.yaml", "source_sha256": hashes["yime_full.dict.yaml"], "transform_version": "yinyuan-layout-projection-v1", "layout_version": "layout-" + plan.TargetDigest[:12], "layout_digest": plan.TargetDigest, "entry_count": len(entries), "output_sha256": hashes}
	manifestData, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return Plan{}, err
	}
	manifestData = append(manifestData, '\n')
	if err := os.WriteFile(filepath.Join(stage, "yime_lexicon_manifest.json"), manifestData, 0644); err != nil {
		return Plan{}, err
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_" + mode + ".schema.yaml"
		data, err := os.ReadFile(filepath.Join(dataDir, name))
		if err != nil {
			return Plan{}, err
		}
		updated, err := updateSchema(data, mode, target.Alphabet(), plan.TargetDigest[:12])
		if err != nil {
			return Plan{}, err
		}
		if err := os.WriteFile(filepath.Join(stage, name), updated, 0644); err != nil {
			return Plan{}, err
		}
	}
	target.BasedOnDigest = ""
	if err := WriteProfileAtomic(filepath.Join(stage, ProfileFileName), target); err != nil {
		return Plan{}, err
	}
	if err := replaceSet(dataDir, stage, generatedFiles); err != nil {
		return Plan{}, err
	}
	return plan, nil
}

func countTSV(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	count := -1
	for s.Scan() {
		if strings.TrimSpace(s.Text()) != "" {
			count++
		}
	}
	if err := s.Err(); err != nil {
		return 0, err
	}
	if count < 0 {
		count = 0
	}
	return count, nil
}

func writeCodeMap(sourcePath, targetPath string, codec *Codec) error {
	in, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(targetPath)
	if err != nil {
		return err
	}
	defer out.Close()
	w := bufio.NewWriterSize(out, 256*1024)
	fmt.Fprintln(w, "pinyin_tone\tfull\tvariable\tshorthand")
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	line := 0
	for s.Scan() {
		line++
		if line == 1 {
			continue
		}
		fields := strings.Split(s.Text(), "\t")
		if len(fields) < 2 || strings.TrimSpace(fields[0]) == "" {
			continue
		}
		record, err := codec.Reencode(fields[1])
		if err != nil {
			return fmt.Errorf("拼音码表第 %d 行: %w", line, err)
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", fields[0], record.Full, record.Variable, record.Shorthand)
	}
	if err := s.Err(); err != nil {
		return err
	}
	if err := w.Flush(); err != nil {
		return err
	}
	return out.Sync()
}

type generatedEntry struct {
	text                                              string
	weight                                            int
	full, variable, shorthand                         string
	fullSpelling, variableSpelling, shorthandSpelling string
}

func buildDictionaries(entries []systemlexicon.Entry, codec *Codec, version string) (map[string][]byte, error) {
	result := make([]generatedEntry, 0, len(entries))
	for i, e := range entries {
		r, err := codec.Reencode(e.Code)
		if err != nil {
			return nil, fmt.Errorf("词典第 %d 条 %q: %w", i+1, e.Text, err)
		}
		result = append(result, generatedEntry{
			text: e.Text, weight: e.Weight,
			full: r.Full, variable: r.Variable, shorthand: r.Shorthand,
			fullSpelling: r.FullSpelling, variableSpelling: r.VariableSpelling,
			shorthandSpelling: r.ShorthandSpelling,
		})
	}
	outputs := map[string][]byte{}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		var b bytes.Buffer
		fmt.Fprintf(&b, "# Rime dictionary\n# GENERATED FILE - DO NOT EDIT\n# Rebuilt from Yinyuan IDs by layoutdesigner.\n---\nname: yime_%s\nversion: %q\nsort: by_weight\nuse_preset_vocabulary: false\n...\n", mode, version)
		for _, e := range result {
			code := e.fullSpelling
			if mode == "variable" {
				code = e.variableSpelling
			} else if mode == "shorthand" {
				code = e.shorthandSpelling
			}
			fmt.Fprintf(&b, "%s\t%s\t%d\n", e.text, code, e.weight)
		}
		outputs["yime_"+mode+".dict.yaml"] = b.Bytes()
	}
	return outputs, nil
}

func updateSchema(data []byte, mode, alphabet, digest string) ([]byte, error) {
	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	section := ""
	seenVersion, seenAlphabet, seenUser := false, false, false
	for i, line := range lines {
		trim := strings.TrimSpace(line)
		if trim != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") && strings.HasSuffix(trim, ":") {
			section = strings.TrimSuffix(trim, ":")
		}
		switch {
		case section == "schema" && strings.HasPrefix(trim, "version:"):
			lines[i] = "  version: " + strconv.Quote("layout-"+digest)
			seenVersion = true
		case section == "speller" && strings.HasPrefix(trim, "alphabet:"):
			lines[i] = "  alphabet: " + strconv.Quote(alphabet)
			seenAlphabet = true
		case section == "translator" && strings.HasPrefix(trim, "user_dict:") && !seenUser:
			lines[i] = "  user_dict: yime_" + mode + "_layout_" + digest + "_script_v1"
			seenUser = true
		}
	}
	if !seenVersion || !seenAlphabet || !seenUser {
		return nil, fmt.Errorf("yime_%s.schema.yaml 缺少 version/alphabet/translator.user_dict", mode)
	}
	return []byte(strings.Join(lines, "\n")), nil
}

func replaceSet(dir, stage string, names []string) error {
	backup, err := os.MkdirTemp(dir, ".layout-design-rollback-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(backup)
	ordered := append([]string(nil), names...)
	sort.Strings(ordered)
	moved, replaced := []string{}, []string{}
	rollback := func() {
		for _, n := range replaced {
			_ = os.Remove(filepath.Join(dir, n))
		}
		for _, n := range moved {
			_ = os.Rename(filepath.Join(backup, n), filepath.Join(dir, n))
		}
	}
	for _, n := range ordered {
		dst := filepath.Join(dir, n)
		if _, err := os.Stat(dst); err == nil {
			if err := os.Rename(dst, filepath.Join(backup, n)); err != nil {
				rollback()
				return err
			}
			moved = append(moved, n)
		} else if !os.IsNotExist(err) {
			rollback()
			return err
		}
		if err := os.Rename(filepath.Join(stage, n), dst); err != nil {
			rollback()
			return err
		}
		replaced = append(replaced, n)
	}
	return nil
}

func hash(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }
