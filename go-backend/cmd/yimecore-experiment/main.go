// Command yimecore-experiment runs the synthetic E0 correctness and latency
// smoke. Its output is evidence for the experimental Go core only; it is not
// a librime comparison or a production-readiness result.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const toolVersion = "yimecore-e0-experiment-v1"

type latencyReport struct {
	Measurement string `json:"measurement"`
	BatchSize   int    `json:"batch_size"`
	Samples     int    `json:"samples"`
	P50NS       int64  `json:"p50_ns"`
	P95NS       int64  `json:"p95_ns"`
	P99NS       int64  `json:"p99_ns"`
	MaxNS       int64  `json:"max_ns"`
}

type report struct {
	ToolVersion  string          `json:"tool_version"`
	Scope        string          `json:"scope"`
	GeneratedAt  string          `json:"generated_at"`
	GitCommit    string          `json:"git_commit"`
	GitDirty     bool            `json:"git_dirty"`
	GoVersion    string          `json:"go_version"`
	GOOS         string          `json:"goos"`
	GOARCH       string          `json:"goarch"`
	EntryCount   int             `json:"entry_count"`
	Iterations   int             `json:"iterations"`
	CandidateCap int             `json:"candidate_cap"`
	TraceID      string          `json:"trace_id"`
	Checks       map[string]bool `json:"checks"`
	Latency      latencyReport   `json:"latency"`
	Passed       bool            `json:"passed"`
	Limitations  []string        `json:"limitations"`
}

func main() {
	output := flag.String("output", "", "path to manifest.json")
	entryCount := flag.Int("entries", 20000, "synthetic entry count")
	iterations := flag.Int("iterations", 1000, "trace replay count")
	gitCommit := flag.String("git-commit", "unknown", "source Git commit")
	gitDirty := flag.Bool("git-dirty", false, "whether the source tree is dirty")
	flag.Parse()

	if *output == "" || *entryCount < 100 || *iterations < 1 {
		fmt.Fprintln(os.Stderr, "output is required; entries must be >= 100 and iterations must be >= 1")
		os.Exit(2)
	}

	entries := syntheticEntries(*entryCount)
	index, err := yimecore.NewIndex(entries)
	if err != nil {
		fail(err)
	}
	engine, err := yimecore.NewEngine(index, 9)
	if err != nil {
		fail(err)
	}

	const latencyBatchSize = 20
	durations := make([]time.Duration, 0, (*iterations+latencyBatchSize-1)/latencyBatchSize)
	checks := map[string]bool{
		"digits_remain_composition": true,
		"exact_candidate_found":     true,
		"selection_commits_target":  true,
		"selection_clears_state":    true,
	}
	events := []engineapi.Event{
		{Operation: engineapi.AppendCode, Code: "a"},
		{Operation: engineapi.AppendCode, Code: "1"},
		{Operation: engineapi.AppendCode, Code: "2"},
		{Operation: engineapi.AppendCode, Code: "3"},
		{Operation: engineapi.AppendCode, Code: "4"},
	}

	for batchStart := 0; batchStart < *iterations; batchStart += latencyBatchSize {
		batchCount := latencyBatchSize
		if remaining := *iterations - batchStart; remaining < batchCount {
			batchCount = remaining
		}
		started := time.Now()
		for iteration := 0; iteration < batchCount; iteration++ {
			runTrace(engine, events, checks)
		}
		durations = append(durations, time.Since(started)/time.Duration(batchCount))
	}

	passed := true
	for _, check := range checks {
		passed = passed && check
	}
	result := report{
		ToolVersion:  toolVersion,
		Scope:        "synthetic E0 YimeCore smoke; not a Rime comparison",
		GeneratedAt:  time.Now().UTC().Format(time.RFC3339Nano),
		GitCommit:    *gitCommit,
		GitDirty:     *gitDirty,
		GoVersion:    runtime.Version(),
		GOOS:         runtime.GOOS,
		GOARCH:       runtime.GOARCH,
		EntryCount:   len(entries),
		Iterations:   *iterations,
		CandidateCap: 9,
		TraceID:      "e0-a1234-select-target-v1",
		Checks:       checks,
		Latency:      summarize(durations, latencyBatchSize),
		Passed:       passed,
		Limitations: []string{
			"uses a synthetic in-memory index",
			"does not exercise segmentation, sentence generation, learning, IPC, TSF or installation",
			"does not compare against librime",
		},
	}
	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fail(err)
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(*output), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(*output, data, 0o644); err != nil {
		fail(err)
	}
	fmt.Printf("YimeCore E0 experiment: passed=%t evidence=%s\n", passed, *output)
	if !passed {
		os.Exit(1)
	}
}

func syntheticEntries(count int) []yimecore.Entry {
	entries := make([]yimecore.Entry, 0, count+1)
	for i := 0; i < count; i++ {
		entries = append(entries, yimecore.Entry{
			Text:   fmt.Sprintf("候选%05d", i),
			Code:   syntheticCode(i),
			Weight: int64(i % 1000),
		})
	}
	return append(entries, yimecore.Entry{Text: "目标", Code: "a1234", Weight: 10000})
}

func syntheticCode(value int) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	buf := []byte{'a', '0', '0', '0', '0'}
	for i := len(buf) - 1; i >= 1; i-- {
		buf[i] = alphabet[value%len(alphabet)]
		value /= len(alphabet)
	}
	return string(buf)
}

func runTrace(engine *yimecore.Engine, events []engineapi.Event, checks map[string]bool) {
	engine.Reset()
	var result engineapi.Result
	for step, event := range events {
		var err error
		result, err = engine.Apply(event)
		if err != nil {
			fail(err)
		}
		if result.State.RawInput != "a1234"[:step+1] {
			checks["digits_remain_composition"] = false
		}
	}

	var targetID string
	for _, candidate := range result.State.Candidates {
		if candidate.Text == "目标" && candidate.Code == "a1234" && candidate.Exact {
			targetID = candidate.ID
			break
		}
	}
	if targetID == "" {
		checks["exact_candidate_found"] = false
		return
	}
	selected, err := engine.Select(targetID)
	if err != nil {
		fail(err)
	}
	if selected.Commit != "目标" {
		checks["selection_commits_target"] = false
	}
	if selected.State.RawInput != "" || len(selected.State.Candidates) != 0 {
		checks["selection_clears_state"] = false
	}
}

func summarize(durations []time.Duration, batchSize int) latencyReport {
	sort.Slice(durations, func(i, j int) bool { return durations[i] < durations[j] })
	return latencyReport{
		Measurement: "batch-amortized full trace: five key events plus candidate selection",
		BatchSize:   batchSize,
		Samples:     len(durations),
		P50NS:       percentile(durations, 50).Nanoseconds(),
		P95NS:       percentile(durations, 95).Nanoseconds(),
		P99NS:       percentile(durations, 99).Nanoseconds(),
		MaxNS:       durations[len(durations)-1].Nanoseconds(),
	}
}

func percentile(values []time.Duration, percent int) time.Duration {
	index := (len(values)*percent + 99) / 100
	if index < 1 {
		index = 1
	}
	if index > len(values) {
		index = len(values)
	}
	return values[index-1]
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
