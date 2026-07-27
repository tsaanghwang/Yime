package lexiconpromotion

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const (
	ReportJSONFile = "yime_lexicon_promotion_candidates.json"
	ReportTSVFile  = "yime_lexicon_promotion_candidates.tsv"
)

type Config struct {
	SharedDir     string `json:"shared_dir"`
	UserDir       string `json:"user_dir"`
	SchemaID      string `json:"schema_id"`
	MinCommits    int    `json:"min_commits"`
	MinLength     int    `json:"min_length"`
	MaxLength     int    `json:"max_length"`
	MaxCandidates int    `json:"max_candidates"`
}

type Candidate struct {
	Text       string  `json:"text"`
	Code       string  `json:"code"`
	Commits    int     `json:"commits"`
	Dee        float64 `json:"dee,omitempty"`
	Tick       int     `json:"tick,omitempty"`
	RuneLength int     `json:"rune_length"`
	SourceDB   string  `json:"source_db"`
}

type Summary struct {
	LearnedRecords      int `json:"learned_records"`
	AlreadyInSystem     int `json:"already_in_system"`
	BelowFrequency      int `json:"below_frequency"`
	RejectedLength      int `json:"rejected_length"`
	RejectedNonHan      int `json:"rejected_non_han"`
	PromotionCandidates int `json:"promotion_candidates"`
}

type Report struct {
	SchemaVersion    string      `json:"schema_version"`
	GeneratedAt      time.Time   `json:"generated_at"`
	OfflineOnly      bool        `json:"offline_only"`
	UploadPerformed  bool        `json:"upload_performed"`
	SchemaID         string      `json:"schema_id"`
	UserDB           string      `json:"user_db"`
	SystemDictionary string      `json:"system_dictionary"`
	SourceSnapshot   string      `json:"source_snapshot"`
	SnapshotModified time.Time   `json:"snapshot_modified"`
	SnapshotRefresh  string      `json:"snapshot_refresh"`
	Config           Config      `json:"config"`
	Summary          Summary     `json:"summary"`
	Candidates       []Candidate `json:"candidates"`
}

type Result struct {
	Report   Report
	JSONPath string
	TSVPath  string
}

type learnedRecord struct {
	Code, Text string
	Commits    int
	Dee        float64
	Tick       int
}

func DefaultConfig(sharedDir, userDir, schemaID string) Config {
	return Config{
		SharedDir: sharedDir, UserDir: userDir, SchemaID: schemaID,
		MinCommits: 3, MinLength: 2, MaxLength: 16, MaxCandidates: 5000,
	}
}

// Scan creates local-only JSON and TSV reports. It never sends data over the network.
func Scan(config Config, now time.Time) (Result, error) {
	config.SchemaID = strings.TrimSpace(config.SchemaID)
	if config.SchemaID == "" || filepath.Base(config.SchemaID) != config.SchemaID {
		return Result{}, fmt.Errorf("invalid schema id %q", config.SchemaID)
	}
	if config.MinCommits <= 0 || config.MinLength <= 0 || config.MaxLength < config.MinLength || config.MaxCandidates <= 0 {
		return Result{}, errors.New("invalid scan thresholds")
	}
	dictPath, err := findCurrentFile(config.UserDir, config.SharedDir, config.SchemaID+".dict.yaml")
	if err != nil {
		return Result{}, err
	}
	schemaPath, err := findCurrentFile(config.UserDir, config.SharedDir, config.SchemaID+".schema.yaml")
	if err != nil {
		return Result{}, err
	}
	userDB, err := readPrimaryUserDB(schemaPath)
	if err != nil {
		return Result{}, err
	}
	refreshStatus := refreshSnapshot(config.SharedDir, config.UserDir, userDB)
	snapshot, modified, err := newestSnapshot(config.UserDir, userDB)
	if err != nil {
		return Result{}, fmt.Errorf("%w; snapshot refresh: %s", err, refreshStatus)
	}
	systemTexts, err := loadSystemTexts(dictPath)
	if err != nil {
		return Result{}, err
	}
	records, err := loadLearnedRecords(snapshot)
	if err != nil {
		return Result{}, err
	}
	report := Report{
		SchemaVersion: "yime-lexicon-promotion-candidates-v1",
		GeneratedAt:   now.UTC(), OfflineOnly: true, UploadPerformed: false,
		SchemaID: config.SchemaID, UserDB: userDB, SystemDictionary: dictPath,
		SourceSnapshot: snapshot, SnapshotModified: modified.UTC(),
		SnapshotRefresh: refreshStatus, Config: config,
		Candidates: []Candidate{},
	}
	report.Summary.LearnedRecords = len(records)
	for _, record := range records {
		if _, ok := systemTexts[record.Text]; ok {
			report.Summary.AlreadyInSystem++
			continue
		}
		length := utf8.RuneCountInString(record.Text)
		if length < config.MinLength || length > config.MaxLength {
			report.Summary.RejectedLength++
			continue
		}
		if !hanOnly(record.Text) {
			report.Summary.RejectedNonHan++
			continue
		}
		if record.Commits < config.MinCommits {
			report.Summary.BelowFrequency++
			continue
		}
		report.Candidates = append(report.Candidates, Candidate{
			Text: record.Text, Code: record.Code, Commits: record.Commits,
			Dee: record.Dee, Tick: record.Tick, RuneLength: length, SourceDB: userDB,
		})
	}
	sort.Slice(report.Candidates, func(i, j int) bool {
		a, b := report.Candidates[i], report.Candidates[j]
		if a.Commits != b.Commits {
			return a.Commits > b.Commits
		}
		if a.Dee != b.Dee {
			return a.Dee > b.Dee
		}
		if a.Text != b.Text {
			return a.Text < b.Text
		}
		return a.Code < b.Code
	})
	if len(report.Candidates) > config.MaxCandidates {
		report.Candidates = report.Candidates[:config.MaxCandidates]
	}
	report.Summary.PromotionCandidates = len(report.Candidates)
	outputDir := filepath.Join(config.UserDir, "promotion_scan")
	if err := os.MkdirAll(outputDir, 0o700); err != nil {
		return Result{}, err
	}
	result := Result{
		Report:   report,
		JSONPath: filepath.Join(outputDir, ReportJSONFile),
		TSVPath:  filepath.Join(outputDir, ReportTSVFile),
	}
	if err := writeJSON(result.JSONPath, report); err != nil {
		return Result{}, err
	}
	if err := writeTSV(result.TSVPath, report.Candidates); err != nil {
		return Result{}, err
	}
	return result, nil
}

func refreshSnapshot(sharedDir, userDir, db string) string {
	manager := filepath.Join(filepath.Dir(sharedDir), "rime_dict_manager.exe")
	if info, err := os.Stat(manager); err != nil || !info.Mode().IsRegular() {
		return "manager_unavailable; using newest existing sync snapshot"
	}
	command := exec.Command(manager, "--backup", db)
	command.Dir = userDir
	if output, err := command.CombinedOutput(); err != nil {
		message := strings.TrimSpace(string(output))
		if message == "" {
			message = err.Error()
		}
		return "backup_failed; using newest existing sync snapshot: " + message
	}
	return "backup_succeeded"
}

func findCurrentFile(userDir, sharedDir, name string) (string, error) {
	for _, dir := range []string{userDir, sharedDir} {
		path := filepath.Join(dir, name)
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() && info.Size() > 0 {
			return path, nil
		}
	}
	return "", fmt.Errorf("missing active Rime file %s", name)
}

func readPrimaryUserDB(schemaPath string) (string, error) {
	file, err := os.Open(schemaPath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "user_dict:") {
			value := strings.Trim(strings.TrimSpace(strings.TrimPrefix(line, "user_dict:")), "\"'")
			if value != "" {
				return value, nil
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", fmt.Errorf("%s has no translator user_dict", schemaPath)
}

func newestSnapshot(userDir, db string) (string, time.Time, error) {
	var best string
	var newest time.Time
	root := filepath.Join(userDir, "sync")
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.EqualFold(entry.Name(), db+".userdb.txt") {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if best == "" || info.ModTime().After(newest) {
			best, newest = path, info.ModTime()
		}
		return nil
	})
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", time.Time{}, fmt.Errorf("no Rime sync directory; run 数据维护 → 同步数据 first")
		}
		return "", time.Time{}, err
	}
	if best == "" {
		return "", time.Time{}, fmt.Errorf("no snapshot for %s; run 数据维护 → 同步数据 first", db)
	}
	return best, newest, nil
}

func loadSystemTexts(path string) (map[string]struct{}, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	result := map[string]struct{}{}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	inData := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !inData {
			if line == "..." {
				inData = true
			}
			continue
		}
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) >= 2 && strings.TrimSpace(fields[0]) != "" {
			result[strings.TrimSpace(fields[0])] = struct{}{}
		}
	}
	return result, scanner.Err()
}

func loadLearnedRecords(path string) ([]learnedRecord, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	merged := map[string]learnedRecord{}
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 3 {
			continue
		}
		record := learnedRecord{Code: strings.TrimSpace(fields[0]), Text: strings.TrimSpace(fields[1])}
		for _, token := range strings.Fields(fields[2]) {
			parts := strings.SplitN(token, "=", 2)
			if len(parts) != 2 {
				continue
			}
			switch parts[0] {
			case "c":
				record.Commits, _ = strconv.Atoi(parts[1])
			case "d":
				record.Dee, _ = strconv.ParseFloat(parts[1], 64)
			case "t":
				record.Tick, _ = strconv.Atoi(parts[1])
			}
		}
		if record.Code == "" || record.Text == "" {
			continue
		}
		key := record.Text + "\x00" + record.Code
		if old, ok := merged[key]; !ok || record.Commits > old.Commits {
			merged[key] = record
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	result := make([]learnedRecord, 0, len(merged))
	for _, record := range merged {
		result = append(result, record)
	}
	return result, nil
}

func hanOnly(text string) bool {
	for _, r := range text {
		if !unicode.Is(unicode.Han, r) {
			return false
		}
	}
	return text != ""
}

func writeJSON(path string, report Report) error {
	payload, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(path, append(payload, '\n'))
}

func writeTSV(path string, candidates []Candidate) error {
	var out strings.Builder
	out.WriteString("text\tcode\tcommits\tdee\ttick\trune_length\tsource_db\n")
	for _, c := range candidates {
		fmt.Fprintf(&out, "%s\t%s\t%d\t%g\t%d\t%d\t%s\n", c.Text, c.Code, c.Commits, c.Dee, c.Tick, c.RuneLength, c.SourceDB)
	}
	return writeAtomic(path, []byte(out.String()))
}

func writeAtomic(path string, data []byte) error {
	temp, err := os.CreateTemp(filepath.Dir(path), ".promotion-*.tmp")
	if err != nil {
		return err
	}
	name := temp.Name()
	defer os.Remove(name)
	if _, err = temp.Write(data); err != nil {
		temp.Close()
		return err
	}
	if err = temp.Close(); err != nil {
		return err
	}
	if err = os.Rename(name, path); err == nil {
		return nil
	}
	if err = os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Rename(name, path)
}
