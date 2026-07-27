//go:build windows

package yime

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
	"unicode"
	"unicode/utf8"
)

type coreTrialReplaySnapshot struct {
	Schema     string          `json:"schema"`
	Input      string          `json:"input"`
	ElapsedUS  int64           `json:"elapsed_us"`
	PageSize   int             `json:"page_size"`
	Candidates []RimeCandidate `json:"candidates"`
}

func captureCoreTrialReplay(
	t *testing.T,
	sessionID RimeSessionId,
	schemaID string,
	input string,
) coreTrialReplaySnapshot {
	t.Helper()
	ClearComposition(sessionID)
	if !SelectSchema(sessionID, schemaID) {
		t.Fatalf("could not select schema %s", schemaID)
	}
	started := time.Now()
	typeASCII(t, sessionID, input)
	elapsed := time.Since(started)
	menu, ok := GetMenu(sessionID)
	if !ok {
		return coreTrialReplaySnapshot{
			Schema:    schemaID,
			Input:     input,
			ElapsedUS: elapsed.Microseconds(),
		}
	}
	return coreTrialReplaySnapshot{
		Schema:     schemaID,
		Input:      input,
		ElapsedUS:  elapsed.Microseconds(),
		PageSize:   menu.PageSize,
		Candidates: menu.Candidates,
	}
}

func candidateTextSet(candidates []RimeCandidate) map[string]struct{} {
	result := make(map[string]struct{}, len(candidates))
	for _, candidate := range candidates {
		result[candidate.Text] = struct{}{}
	}
	return result
}

func candidateTextPresent(candidates []RimeCandidate, target string) bool {
	for _, candidate := range candidates {
		if candidate.Text == target {
			return true
		}
	}
	return false
}

func topCandidateText(candidates []RimeCandidate) string {
	if len(candidates) == 0 {
		return ""
	}
	return candidates[0].Text
}

func TestCoreTrialReplayAgainstProductionLexicon(t *testing.T) {
	if os.Getenv("YIME_RUN_CORE_TRIAL_REPLAY") != "1" {
		t.Skip("set YIME_RUN_CORE_TRIAL_REPLAY=1 to compare production and core-trial candidates")
	}
	session := newRealRimeSession(t)
	cases := []struct {
		input       string
		expectedTop string
	}{
		{input: "bj"},
		{input: "bjbj"},
		{input: `\lda1m,.]e`},
		{input: `\lda1m,.]eguew8we;`, expectedTop: "连续的过程"},
		{input: `]s8u\e4fa7J9wo`, expectedTop: "打出了三只手"},
	}
	for _, testCase := range cases {
		production := captureCoreTrialReplay(
			t,
			session.sessionID,
			"yime_variable",
			testCase.input,
		)
		trial := captureCoreTrialReplay(
			t,
			session.sessionID,
			"yime_core_trial",
			testCase.input,
		)
		if testCase.expectedTop != "" {
			if len(production.Candidates) == 0 ||
				production.Candidates[0].Text != testCase.expectedTop {
				t.Fatalf(
					"production top candidate for %q: got %#v want %q",
					testCase.input,
					production.Candidates,
					testCase.expectedTop,
				)
			}
			if len(trial.Candidates) == 0 ||
				trial.Candidates[0].Text != testCase.expectedTop {
				t.Fatalf(
					"core-trial top candidate for %q: got %#v want %q",
					testCase.input,
					trial.Candidates,
					testCase.expectedTop,
				)
			}
		}
		productionTexts := candidateTextSet(production.Candidates)
		overlap := 0
		for _, candidate := range trial.Candidates {
			if _, ok := productionTexts[candidate.Text]; ok {
				overlap++
			}
		}
		payload, err := json.Marshal(struct {
			Input            string                  `json:"input"`
			FirstPageOverlap int                     `json:"first_page_overlap"`
			Production       coreTrialReplaySnapshot `json:"production"`
			CoreTrial        coreTrialReplaySnapshot `json:"core_trial"`
		}{
			Input:            testCase.input,
			FirstPageOverlap: overlap,
			Production:       production,
			CoreTrial:        trial,
		})
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("CORE_TRIAL_REPLAY %s", payload)
	}
}

const coreTrialCoverageSamplesPerBucket = 100

type coreTrialCoverageCase struct {
	Target       string `json:"target"`
	Input        string `json:"input"`
	LengthBucket string `json:"length_bucket"`
	InCore       bool   `json:"in_core"`
	Weight       int    `json:"weight"`
}

type coreTrialCoverageResult struct {
	coreTrialCoverageCase
	ProductionTop             string `json:"production_top"`
	CoreTrialTop              string `json:"core_trial_top"`
	ProductionTargetTop1      bool   `json:"production_target_top1"`
	CoreTrialTargetTop1       bool   `json:"core_trial_target_top1"`
	ProductionTargetFirstPage bool   `json:"production_target_first_page"`
	CoreTrialTargetFirstPage  bool   `json:"core_trial_target_first_page"`
	CoreTrialMatchesProdTop1  bool   `json:"core_trial_matches_production_top1"`
	FirstPageOverlap          int    `json:"first_page_overlap"`
	ProductionElapsedUS       int64  `json:"production_elapsed_us"`
	CoreTrialElapsedUS        int64  `json:"core_trial_elapsed_us"`
}

type coreTrialCoverageMetrics struct {
	Cases                               int     `json:"cases"`
	ProductionTargetTop1                int     `json:"production_target_top1"`
	CoreTrialTargetTop1                 int     `json:"core_trial_target_top1"`
	ProductionTargetFirstPage           int     `json:"production_target_first_page"`
	CoreTrialTargetFirstPage            int     `json:"core_trial_target_first_page"`
	CoreTrialMatchesProductionTop1      int     `json:"core_trial_matches_production_top1"`
	Top1RetentionWhenProductionTop1     int     `json:"top1_retention_when_production_top1"`
	FirstPageRetentionWhenProductionHit int     `json:"first_page_retention_when_production_hit"`
	AverageFirstPageOverlap             float64 `json:"average_first_page_overlap"`
	AverageProductionElapsedUS          float64 `json:"average_production_elapsed_us"`
	AverageCoreTrialElapsedUS           float64 `json:"average_core_trial_elapsed_us"`
	Top1RetentionRate                   float64 `json:"top1_retention_rate"`
	FirstPageRetentionRate              float64 `json:"first_page_retention_rate"`
	CoreTrialMatchesProductionRate      float64 `json:"core_trial_matches_production_top1_rate"`
}

type coreTrialCoverageReport struct {
	SchemaVersion      int                                 `json:"schema_version"`
	GeneratedAt        string                              `json:"generated_at"`
	SamplingPolicy     string                              `json:"sampling_policy"`
	SamplesPerBucket   int                                 `json:"samples_per_bucket"`
	ProductionManifest json.RawMessage                     `json:"production_manifest"`
	CoreTrialManifest  json.RawMessage                     `json:"core_trial_manifest"`
	Summary            coreTrialCoverageMetrics            `json:"summary"`
	LengthGroups       map[string]coreTrialCoverageMetrics `json:"length_groups"`
	MembershipGroups   map[string]coreTrialCoverageMetrics `json:"membership_groups"`
	Buckets            map[string]coreTrialCoverageMetrics `json:"buckets"`
	Cases              []coreTrialCoverageResult           `json:"cases"`
}

func coreTrialLexiconKey(text, code string) string {
	return text + "\x00" + code
}

func visitCoreTrialDictionary(
	path string,
	visit func(text, code string, weight int) error,
) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
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
		if len(fields) < 2 {
			continue
		}
		text := strings.TrimSpace(fields[0])
		code := strings.TrimSpace(fields[1])
		if text == "" || code == "" {
			continue
		}
		weight := 0
		if len(fields) >= 3 {
			weight, _ = strconv.Atoi(strings.TrimSpace(fields[2]))
		}
		if err := visit(text, code, weight); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func coreTrialLengthBucket(text string) (string, bool) {
	length := utf8.RuneCountInString(text)
	if length < 2 || length > 12 {
		return "", false
	}
	for _, char := range text {
		if !unicode.Is(unicode.Han, char) {
			return "", false
		}
	}
	if length >= 8 {
		return "8-12", true
	}
	return strconv.Itoa(length), true
}

func betterCoreTrialCoverageCase(
	left coreTrialCoverageCase,
	right coreTrialCoverageCase,
) bool {
	if left.Weight != right.Weight {
		return left.Weight > right.Weight
	}
	if left.Target != right.Target {
		return left.Target < right.Target
	}
	return left.Input < right.Input
}

func addCoreTrialCoverageSample(
	buckets map[string][]coreTrialCoverageCase,
	key string,
	candidate coreTrialCoverageCase,
) {
	items := buckets[key]
	if len(items) < coreTrialCoverageSamplesPerBucket {
		buckets[key] = append(items, candidate)
		return
	}
	worst := 0
	for index := 1; index < len(items); index++ {
		if betterCoreTrialCoverageCase(items[worst], items[index]) {
			worst = index
		}
	}
	if betterCoreTrialCoverageCase(candidate, items[worst]) {
		items[worst] = candidate
	}
}

func loadCoreTrialCoverageCases(
	t *testing.T,
	dataDir string,
) []coreTrialCoverageCase {
	t.Helper()
	coreEntries := map[string]struct{}{}
	err := visitCoreTrialDictionary(
		filepath.Join(dataDir, "yime_core_trial.dict.yaml"),
		func(text, code string, _ int) error {
			coreEntries[coreTrialLexiconKey(text, code)] = struct{}{}
			return nil
		},
	)
	if err != nil {
		t.Fatal(err)
	}

	buckets := map[string][]coreTrialCoverageCase{}
	err = visitCoreTrialDictionary(
		filepath.Join(dataDir, "yime_variable.dict.yaml"),
		func(text, code string, weight int) error {
			lengthBucket, ok := coreTrialLengthBucket(text)
			if !ok {
				return nil
			}
			_, inCore := coreEntries[coreTrialLexiconKey(text, code)]
			bucketKey := fmt.Sprintf("length=%s,in_core=%t", lengthBucket, inCore)
			addCoreTrialCoverageSample(
				buckets,
				bucketKey,
				coreTrialCoverageCase{
					Target:       text,
					Input:        strings.ReplaceAll(code, " ", ""),
					LengthBucket: lengthBucket,
					InCore:       inCore,
					Weight:       weight,
				},
			)
			return nil
		},
	)
	if err != nil {
		t.Fatal(err)
	}

	lengthOrder := []string{"2", "3", "4", "5", "6", "7", "8-12"}
	result := make([]coreTrialCoverageCase, 0, len(lengthOrder)*2*coreTrialCoverageSamplesPerBucket)
	for _, lengthBucket := range lengthOrder {
		for _, inCore := range []bool{true, false} {
			key := fmt.Sprintf("length=%s,in_core=%t", lengthBucket, inCore)
			items := buckets[key]
			for index := 0; index < len(items); index++ {
				for previous := index; previous > 0 &&
					betterCoreTrialCoverageCase(items[previous], items[previous-1]); previous-- {
					items[previous], items[previous-1] = items[previous-1], items[previous]
				}
			}
			result = append(result, items...)
		}
	}
	return result
}

func loadCoreTrialCoverageCasesFromReport(
	t *testing.T,
	path string,
) []coreTrialCoverageCase {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var report struct {
		Cases []coreTrialCoverageResult `json:"cases"`
	}
	if err := json.Unmarshal(data, &report); err != nil {
		t.Fatal(err)
	}
	if len(report.Cases) == 0 {
		t.Fatalf("coverage corpus report has no cases: %s", path)
	}
	result := make([]coreTrialCoverageCase, 0, len(report.Cases))
	seen := map[string]struct{}{}
	for _, item := range report.Cases {
		testCase := item.coreTrialCoverageCase
		key := coreTrialLexiconKey(testCase.Target, testCase.Input)
		if _, found := seen[key]; found {
			t.Fatalf(
				"coverage corpus report repeats target/input %q / %q",
				testCase.Target,
				testCase.Input,
			)
		}
		seen[key] = struct{}{}
		result = append(result, testCase)
	}
	return result
}

func TestCoreTrialCoverageCorpusIsStratified(t *testing.T) {
	cases := loadCoreTrialCoverageCases(t, "data")
	if len(cases) < 1_000 {
		t.Fatalf("coverage corpus is unexpectedly small: %d", len(cases))
	}
	buckets := map[string]int{}
	for _, testCase := range cases {
		key := fmt.Sprintf(
			"length=%s,in_core=%t",
			testCase.LengthBucket,
			testCase.InCore,
		)
		buckets[key]++
	}
	for _, lengthBucket := range []string{"2", "3", "4", "5", "6", "7", "8-12"} {
		for _, inCore := range []bool{true, false} {
			key := fmt.Sprintf("length=%s,in_core=%t", lengthBucket, inCore)
			if buckets[key] == 0 {
				t.Fatalf("coverage corpus has no cases for %s", key)
			}
		}
	}
}

func captureSelectedCoreTrialReplay(
	t *testing.T,
	sessionID RimeSessionId,
	schemaID string,
	input string,
) coreTrialReplaySnapshot {
	t.Helper()
	ClearComposition(sessionID)
	started := time.Now()
	typeASCII(t, sessionID, input)
	elapsed := time.Since(started)
	menu, ok := GetMenu(sessionID)
	if !ok {
		return coreTrialReplaySnapshot{
			Schema:    schemaID,
			Input:     input,
			ElapsedUS: elapsed.Microseconds(),
		}
	}
	return coreTrialReplaySnapshot{
		Schema:     schemaID,
		Input:      input,
		ElapsedUS:  elapsed.Microseconds(),
		PageSize:   menu.PageSize,
		Candidates: menu.Candidates,
	}
}

func addCoreTrialCoverageMetrics(
	metrics *coreTrialCoverageMetrics,
	result coreTrialCoverageResult,
) {
	metrics.Cases++
	if result.ProductionTargetTop1 {
		metrics.ProductionTargetTop1++
		if result.CoreTrialTargetTop1 {
			metrics.Top1RetentionWhenProductionTop1++
		}
	}
	if result.CoreTrialTargetTop1 {
		metrics.CoreTrialTargetTop1++
	}
	if result.ProductionTargetFirstPage {
		metrics.ProductionTargetFirstPage++
		if result.CoreTrialTargetFirstPage {
			metrics.FirstPageRetentionWhenProductionHit++
		}
	}
	if result.CoreTrialTargetFirstPage {
		metrics.CoreTrialTargetFirstPage++
	}
	if result.CoreTrialMatchesProdTop1 {
		metrics.CoreTrialMatchesProductionTop1++
	}
	metrics.AverageFirstPageOverlap += float64(result.FirstPageOverlap)
	metrics.AverageProductionElapsedUS += float64(result.ProductionElapsedUS)
	metrics.AverageCoreTrialElapsedUS += float64(result.CoreTrialElapsedUS)
}

func finalizeCoreTrialCoverageMetrics(metrics *coreTrialCoverageMetrics) {
	if metrics.Cases == 0 {
		return
	}
	divisor := float64(metrics.Cases)
	metrics.AverageFirstPageOverlap /= divisor
	metrics.AverageProductionElapsedUS /= divisor
	metrics.AverageCoreTrialElapsedUS /= divisor
	metrics.CoreTrialMatchesProductionRate =
		float64(metrics.CoreTrialMatchesProductionTop1) / divisor
	if metrics.ProductionTargetTop1 > 0 {
		metrics.Top1RetentionRate =
			float64(metrics.Top1RetentionWhenProductionTop1) /
				float64(metrics.ProductionTargetTop1)
	}
	if metrics.ProductionTargetFirstPage > 0 {
		metrics.FirstPageRetentionRate =
			float64(metrics.FirstPageRetentionWhenProductionHit) /
				float64(metrics.ProductionTargetFirstPage)
	}
}

func TestCoreTrialReplayCoverage(t *testing.T) {
	if os.Getenv("YIME_RUN_CORE_TRIAL_COVERAGE") != "1" {
		t.Skip("set YIME_RUN_CORE_TRIAL_COVERAGE=1 to run stratified full/core replay")
	}
	dataDir := rimeRuntimeTestDataDir(t)
	cases := []coreTrialCoverageCase(nil)
	samplingPolicy := "top weight per Han-only length and exact core-membership bucket"
	if corpusPath := strings.TrimSpace(
		os.Getenv("YIME_CORE_TRIAL_REPLAY_CORPUS"),
	); corpusPath != "" {
		cases = loadCoreTrialCoverageCasesFromReport(t, corpusPath)
		samplingPolicy = "fixed cases imported from " + corpusPath
	} else {
		cases = loadCoreTrialCoverageCases(t, dataDir)
	}
	if len(cases) < 100 {
		t.Fatalf("coverage corpus is unexpectedly small: %d", len(cases))
	}

	session := newRealRimeSession(t)
	productionSession := session.sessionID
	coreSession, ok := StartSession()
	if !ok || coreSession == 0 {
		t.Fatal("could not create core-trial replay session")
	}
	t.Cleanup(func() { EndSession(coreSession) })
	if !SelectSchema(coreSession, "yime_core_trial") {
		t.Fatal("expected yime_core_trial schema to be selectable")
	}
	SetOption(coreSession, "ascii_mode", false)

	report := coreTrialCoverageReport{
		SchemaVersion:    2,
		GeneratedAt:      time.Now().Format(time.RFC3339),
		SamplingPolicy:   samplingPolicy,
		SamplesPerBucket: coreTrialCoverageSamplesPerBucket,
		LengthGroups:     map[string]coreTrialCoverageMetrics{},
		MembershipGroups: map[string]coreTrialCoverageMetrics{},
		Buckets:          map[string]coreTrialCoverageMetrics{},
		Cases:            make([]coreTrialCoverageResult, 0, len(cases)),
	}
	productionManifest, err := os.ReadFile(
		filepath.Join(dataDir, "yime_lexicon_manifest.json"),
	)
	if err != nil {
		t.Fatal(err)
	}
	coreManifest, err := os.ReadFile(
		filepath.Join(dataDir, "yime_core_trial_manifest.json"),
	)
	if err != nil {
		t.Fatal(err)
	}
	report.ProductionManifest = json.RawMessage(productionManifest)
	report.CoreTrialManifest = json.RawMessage(coreManifest)
	for _, testCase := range cases {
		production := captureSelectedCoreTrialReplay(
			t,
			productionSession,
			"yime_variable",
			testCase.Input,
		)
		trial := captureSelectedCoreTrialReplay(
			t,
			coreSession,
			"yime_core_trial",
			testCase.Input,
		)
		productionTexts := candidateTextSet(production.Candidates)
		overlap := 0
		for _, candidate := range trial.Candidates {
			if _, found := productionTexts[candidate.Text]; found {
				overlap++
			}
		}
		result := coreTrialCoverageResult{
			coreTrialCoverageCase:     testCase,
			ProductionTop:             topCandidateText(production.Candidates),
			CoreTrialTop:              topCandidateText(trial.Candidates),
			ProductionTargetTop1:      topCandidateText(production.Candidates) == testCase.Target,
			CoreTrialTargetTop1:       topCandidateText(trial.Candidates) == testCase.Target,
			ProductionTargetFirstPage: candidateTextPresent(production.Candidates, testCase.Target),
			CoreTrialTargetFirstPage:  candidateTextPresent(trial.Candidates, testCase.Target),
			CoreTrialMatchesProdTop1:  topCandidateText(production.Candidates) != "" && topCandidateText(production.Candidates) == topCandidateText(trial.Candidates),
			FirstPageOverlap:          overlap,
			ProductionElapsedUS:       production.ElapsedUS,
			CoreTrialElapsedUS:        trial.ElapsedUS,
		}
		report.Cases = append(report.Cases, result)
		addCoreTrialCoverageMetrics(&report.Summary, result)
		lengthMetrics := report.LengthGroups[testCase.LengthBucket]
		addCoreTrialCoverageMetrics(&lengthMetrics, result)
		report.LengthGroups[testCase.LengthBucket] = lengthMetrics
		membershipKey := "out_of_core"
		if testCase.InCore {
			membershipKey = "in_core"
		}
		membershipMetrics := report.MembershipGroups[membershipKey]
		addCoreTrialCoverageMetrics(&membershipMetrics, result)
		report.MembershipGroups[membershipKey] = membershipMetrics
		bucketKey := fmt.Sprintf(
			"length=%s,in_core=%t",
			testCase.LengthBucket,
			testCase.InCore,
		)
		bucket := report.Buckets[bucketKey]
		addCoreTrialCoverageMetrics(&bucket, result)
		report.Buckets[bucketKey] = bucket
	}
	finalizeCoreTrialCoverageMetrics(&report.Summary)
	for key, metrics := range report.LengthGroups {
		finalizeCoreTrialCoverageMetrics(&metrics)
		report.LengthGroups[key] = metrics
	}
	for key, metrics := range report.MembershipGroups {
		finalizeCoreTrialCoverageMetrics(&metrics)
		report.MembershipGroups[key] = metrics
	}
	for key, bucket := range report.Buckets {
		finalizeCoreTrialCoverageMetrics(&bucket)
		report.Buckets[key] = bucket
	}

	reportData, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	reportData = append(reportData, '\n')
	if reportPath := strings.TrimSpace(os.Getenv("YIME_CORE_TRIAL_REPLAY_REPORT")); reportPath != "" {
		if err := os.MkdirAll(filepath.Dir(reportPath), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(reportPath, reportData, 0o644); err != nil {
			t.Fatal(err)
		}
		t.Logf("CORE_TRIAL_COVERAGE_REPORT %s", reportPath)
	}
	summary, err := json.Marshal(report.Summary)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("CORE_TRIAL_COVERAGE_SUMMARY %s", summary)
}
