// Package learningmigration migrates Rime learning records when a Yime
// keyboard layout assigns new key sequences to the same words.
package learningmigration

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

const reportFileName = "yime_layout_learning_migration.log"

type Transition struct {
	Mode, SourceDB, TargetDB, OldDictionary, Dictionary string
}

type Report struct {
	Mode, SourceDB, TargetDB              string
	Total, Migrated, Unmatched, Ambiguous int
}

type stats struct {
	Commits int
	Dee     float64
	Tick    int
	Other   []string
}

type record struct {
	Code, Text string
	Stats      stats
}

// DetectTransitions compares installed and incoming schemas before replacement.
// Only the main, versioned Yime user database is eligible; stable custom-phrase
// databases are deliberately excluded.
func DetectTransitions(sharedDir, userDir string) ([]Transition, error) {
	transitions, err := DetectTransitionsBetween(userDir, sharedDir)
	if err != nil {
		return nil, err
	}
	result := transitions[:0]
	for _, transition := range transitions {
		if migrationLogged(filepath.Join(userDir, reportFileName), transition.SourceDB, transition.TargetDB) {
			continue
		}
		result = append(result, transition)
	}
	return result, nil
}

// DetectTransitionsBetween compares an explicitly selected old and new data
// set. It is used by the user-layout designer, where the old effective layout
// may come from either the installed shared data or an earlier user override.
func DetectTransitionsBetween(oldDir, newDir string) ([]Transition, error) {
	var result []Transition
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_" + mode + ".schema.yaml"
		oldDB, err := schemaUserDB(filepath.Join(oldDir, name))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
		newDB, err := schemaUserDB(filepath.Join(newDir, name))
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		prefix := "yime_" + mode
		if oldDB == "" || newDB == "" || !strings.HasPrefix(newDB, prefix+"_layout_") {
			continue
		}
		if oldDB == newDB {
			// Upgrade installations that adopted versioned namespaces before the
			// migration feature existed. The log makes this one-shot.
			oldDB = prefix
		} else if !strings.HasPrefix(oldDB, prefix) {
			continue
		}
		result = append(result, Transition{mode, oldDB, newDB, filepath.Join(oldDir, "yime_"+mode+".dict.yaml"), filepath.Join(newDir, "yime_"+mode+".dict.yaml")})
	}
	return result, nil
}

func migrationLogged(path, source, target string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), "source="+source+" target="+target+" ")
}

func schemaUserDB(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	inTranslator := false
	for s.Scan() {
		raw, line := s.Text(), strings.TrimSpace(s.Text())
		if line == "translator:" {
			inTranslator = true
			continue
		}
		if inTranslator && line != "" && !strings.HasPrefix(raw, " ") && !strings.HasPrefix(raw, "\t") {
			break
		}
		if inTranslator && strings.HasPrefix(line, "user_dict:") {
			return strings.Trim(strings.TrimSpace(strings.TrimPrefix(line, "user_dict:")), "\"'"), nil
		}
	}
	return "", s.Err()
}

// MigrateAll backs up each old database, rewrites codes from the new system
// dictionary, and restores into the new namespace. Sources remain untouched.
func MigrateAll(sharedDir, userDir string, transitions []Transition) ([]Report, error) {
	if len(transitions) == 0 {
		return nil, nil
	}
	manager := findManager(sharedDir)
	if manager == "" {
		return nil, fmt.Errorf("找不到 rime_dict_manager.exe，不能安全迁移布局学习记录")
	}
	available, err := listDatabases(manager, userDir)
	if err != nil {
		return nil, err
	}
	reports := make([]Report, 0, len(transitions))
	for _, tr := range transitions {
		if !available[tr.SourceDB] {
			continue
		}
		r, err := migrateOne(manager, userDir, tr)
		if err != nil {
			return reports, fmt.Errorf("迁移 %s -> %s: %w", tr.SourceDB, tr.TargetDB, err)
		}
		reports = append(reports, r)
	}
	if err := appendReports(filepath.Join(userDir, reportFileName), reports); err != nil {
		return reports, err
	}
	return reports, nil
}

func listDatabases(manager, userDir string) (map[string]bool, error) {
	cmd := exec.Command(manager, "--list")
	cmd.Dir = userDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%s --list: %w: %s", filepath.Base(manager), err, strings.TrimSpace(string(output)))
	}
	result := map[string]bool{}
	for _, line := range strings.Split(string(output), "\n") {
		if name := strings.TrimSpace(line); name != "" {
			result[name] = true
		}
	}
	return result, nil
}

func migrateOne(manager, userDir string, tr Transition) (Report, error) {
	report := Report{Mode: tr.Mode, SourceDB: tr.SourceDB, TargetDB: tr.TargetDB}
	if err := runManager(manager, userDir, "--backup", tr.SourceDB); err != nil {
		return report, err
	}
	snapshot, err := newestSnapshot(userDir, tr.SourceDB)
	if err != nil {
		return report, err
	}
	entries, err := systemlexicon.LoadDictFile(tr.Dictionary)
	if err != nil {
		return report, err
	}
	in, err := os.Open(snapshot)
	if err != nil {
		return report, err
	}
	defer in.Close()
	stageDir, err := os.MkdirTemp(userDir, ".yime-learning-migration-")
	if err != nil {
		return report, err
	}
	defer os.RemoveAll(stageDir)
	target := filepath.Join(stageDir, tr.TargetDB+".userdb.txt")
	out, err := os.Create(target)
	if err != nil {
		return report, err
	}
	index := buildIndex(entries)
	if oldEntries, loadErr := systemlexicon.LoadDictFile(tr.OldDictionary); loadErr == nil && filepath.Clean(tr.OldDictionary) != filepath.Clean(tr.Dictionary) {
		index = buildIndexWithOld(oldEntries, entries)
	}
	report, transformErr := transform(in, out, tr, index)
	closeErr := out.Close()
	if transformErr != nil {
		return report, transformErr
	}
	if closeErr != nil {
		return report, closeErr
	}
	if report.Total == 0 {
		return report, nil
	}
	if report.Unmatched != 0 {
		return report, fmt.Errorf("%d/%d 条学习记录无法在新词典中找到；已保留旧库并取消切换", report.Unmatched, report.Total)
	}
	if report.Migrated == 0 {
		return report, fmt.Errorf("旧学习库的 %d 条记录均未迁移；已保留旧库并取消切换", report.Total)
	}
	if err := runManager(manager, userDir, "--restore", target); err != nil {
		return report, err
	}
	return report, nil
}

type choice struct {
	Code      string
	Weight    int
	Ambiguous bool
}

type codeIndex struct {
	preferred map[string]choice
	exact     map[string]choice
}

func buildIndex(entries []systemlexicon.Entry) codeIndex {
	index := make(map[string]choice, len(entries))
	for _, e := range entries {
		cur, ok := index[e.Text]
		if !ok || e.Weight > cur.Weight || (e.Weight == cur.Weight && e.Code < cur.Code) {
			index[e.Text] = choice{e.Code, e.Weight, ok && e.Code != cur.Code}
		} else if e.Code != cur.Code {
			cur.Ambiguous = true
			index[e.Text] = cur
		}
	}
	return codeIndex{preferred: index, exact: map[string]choice{}}
}

func buildIndexWithOld(oldEntries, newEntries []systemlexicon.Entry) codeIndex {
	result := buildIndex(newEntries)
	oldByText, newByText := groupCodes(oldEntries), groupCodes(newEntries)
	for text, oldCodes := range oldByText {
		newCodes := newByText[text]
		for i, oldCode := range oldCodes {
			if i < len(newCodes) {
				result.exact[text+"\x00"+oldCode] = choice{Code: newCodes[i]}
			}
		}
	}
	return result
}

func groupCodes(entries []systemlexicon.Entry) map[string][]string {
	result := map[string][]string{}
	seen := map[string]bool{}
	for _, e := range entries {
		key := e.Text + "\x00" + e.Code
		if !seen[key] {
			result[e.Text] = append(result[e.Text], e.Code)
			seen[key] = true
		}
	}
	return result
}

func transform(in io.Reader, out io.Writer, tr Transition, index codeIndex) (Report, error) {
	report := Report{Mode: tr.Mode, SourceDB: tr.SourceDB, TargetDB: tr.TargetDB}
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	merged := map[string]record{}
	var metadata []string
	for s.Scan() {
		line := s.Text()
		if strings.HasPrefix(line, "#@/") {
			if !strings.HasPrefix(line, "#@/db_name") && !strings.HasPrefix(line, "#@/db_type") {
				metadata = append(metadata, line)
			}
			continue
		}
		if strings.HasPrefix(line, "#") || strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 3 {
			continue
		}
		report.Total++
		pick, ok := index.exact[fields[1]+"\x00"+strings.TrimSpace(fields[0])]
		if !ok {
			pick, ok = index.preferred[fields[1]]
		}
		if !ok {
			report.Unmatched++
			continue
		}
		if pick.Ambiguous {
			report.Ambiguous++
		}
		// Rime's userdb key stores the table code followed by the schema
		// delimiter. Omitting this trailing space produces a restorable database
		// whose records are not found during normal input.
		r := record{strings.TrimSpace(pick.Code) + " ", fields[1], parseStats(fields[2])}
		key := r.Code + "\x00" + r.Text
		if old, ok := merged[key]; ok {
			r.Stats = mergeStats(old.Stats, r.Stats)
		}
		merged[key] = r
		report.Migrated++
	}
	if err := s.Err(); err != nil {
		return report, err
	}
	fmt.Fprintln(out, "# Rime user dictionary")
	fmt.Fprintln(out, "#@/db_name\t"+tr.TargetDB)
	fmt.Fprintln(out, "#@/db_type\tuserdb")
	for _, line := range metadata {
		fmt.Fprintln(out, line)
	}
	keys := make([]string, 0, len(merged))
	for k := range merged {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		r := merged[k]
		fmt.Fprintf(out, "%s\t%s\t%s\n", r.Code, r.Text, formatStats(r.Stats))
	}
	return report, nil
}

func parseStats(raw string) stats {
	var r stats
	for _, f := range strings.Fields(raw) {
		p := strings.SplitN(f, "=", 2)
		if len(p) != 2 {
			r.Other = append(r.Other, f)
			continue
		}
		switch p[0] {
		case "c":
			r.Commits, _ = strconv.Atoi(p[1])
		case "d":
			r.Dee, _ = strconv.ParseFloat(p[1], 64)
		case "t":
			r.Tick, _ = strconv.Atoi(p[1])
		default:
			r.Other = append(r.Other, f)
		}
	}
	return r
}

func mergeStats(a, b stats) stats {
	a.Commits += b.Commits
	if b.Dee > a.Dee {
		a.Dee = b.Dee
	}
	if b.Tick > a.Tick {
		a.Tick = b.Tick
	}
	a.Other = append(a.Other, b.Other...)
	return a
}
func formatStats(s stats) string {
	return strings.Join(append([]string{fmt.Sprintf("c=%d", s.Commits), fmt.Sprintf("d=%g", s.Dee), fmt.Sprintf("t=%d", s.Tick)}, s.Other...), " ")
}

func runManager(manager, userDir string, args ...string) error {
	cmd := exec.Command(manager, args...)
	cmd.Dir = userDir
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w: %s", filepath.Base(manager), err, strings.TrimSpace(string(output)))
	}
	return nil
}

func findManager(sharedDir string) string {
	p := filepath.Join(filepath.Dir(sharedDir), "rime_dict_manager.exe")
	if i, e := os.Stat(p); e == nil && !i.IsDir() {
		return p
	}
	return ""
}

func newestSnapshot(userDir, db string) (string, error) {
	var best string
	var when time.Time
	err := filepath.Walk(filepath.Join(userDir, "sync"), func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && strings.EqualFold(info.Name(), db+".userdb.txt") && (best == "" || info.ModTime().After(when)) {
			best, when = path, info.ModTime()
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	if best == "" {
		return "", fmt.Errorf("找不到 %s 的备份快照", db)
	}
	return best, nil
}

func appendReports(path string, reports []Report) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	for _, r := range reports {
		fmt.Fprintf(f, "%s mode=%s source=%s target=%s total=%d migrated=%d unmatched=%d ambiguous=%d\n", time.Now().Format(time.RFC3339), r.Mode, r.SourceDB, r.TargetDB, r.Total, r.Migrated, r.Unmatched, r.Ambiguous)
	}
	return nil
}
