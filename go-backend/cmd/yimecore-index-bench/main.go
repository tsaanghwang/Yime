// Command yimecore-index-bench validates curated E1 probes against one full
// compact index and records batch-amortized session latency.
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
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const toolVersion = "yimecore-index-bench-v2"

type probe struct {
	Text      string `json:"text"`
	Code      string `json:"code"`
	Generated bool   `json:"generated,omitempty"`
}

type probeFile struct {
	Version int                `json:"version"`
	Source  string             `json:"source"`
	Modes   map[string][]probe `json:"modes"`
}

type latency struct {
	Measurement string `json:"measurement"`
	BatchSize   int    `json:"batch_size"`
	Samples     int    `json:"samples"`
	P50NS       int64  `json:"p50_ns"`
	P95NS       int64  `json:"p95_ns"`
	P99NS       int64  `json:"p99_ns"`
	MaxNS       int64  `json:"max_ns"`
}

type report struct {
	ToolVersion     string                           `json:"tool_version"`
	GeneratedAt     string                           `json:"generated_at"`
	Mode            string                           `json:"mode"`
	IndexPath       string                           `json:"index_path"`
	IndexBytes      int64                            `json:"index_bytes"`
	IndexRecords    int                              `json:"index_records"`
	IndexOpenNS     int64                            `json:"index_open_ns"`
	HeapBeforeBytes uint64                           `json:"heap_before_bytes"`
	HeapAfterBytes  uint64                           `json:"heap_after_bytes"`
	HeapDeltaBytes  int64                            `json:"heap_delta_bytes"`
	ProcessMemory   processmemory.Snapshot           `json:"process_memory"`
	Iterations      int                              `json:"iterations"`
	ProbeCount      int                              `json:"probe_count"`
	ProbeChecks     map[string]bool                  `json:"probe_checks"`
	ProbeCandidates map[string][]engineapi.Candidate `json:"probe_candidates"`
	Latency         latency                          `json:"latency"`
	Passed          bool                             `json:"passed"`
	ComparisonScope string                           `json:"comparison_scope"`
}

func main() {
	indexPath := flag.String("index", "", "compact .yidx file")
	probesPath := flag.String("probes", "", "E1 probe JSON")
	mode := flag.String("mode", "", "codemode")
	output := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 1000, "number of full probe-set iterations")
	flag.Parse()
	if *indexPath == "" || *probesPath == "" || *mode == "" || *output == "" || *iterations < 1 {
		fail(fmt.Errorf("index, probes, mode, output and positive iterations are required"))
	}

	probes := loadProbes(*probesPath, *mode)
	if len(probes) == 0 {
		fail(fmt.Errorf("no probes for mode %s", *mode))
	}
	info, err := os.Stat(*indexPath)
	if err != nil {
		fail(err)
	}
	runtime.GC()
	before := heapAlloc()
	openedAt := time.Now()
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	openElapsed := time.Since(openedAt)
	after := heapAlloc()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %s does not match requested mode %s", index.Mode(), *mode))
	}
	engine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		fail(err)
	}

	checks := make(map[string]bool, len(probes))
	observed := make(map[string][]engineapi.Candidate, len(probes))
	for _, item := range probes {
		key := item.Text + "|" + item.Code
		ok, candidates := inspectProbe(engine, item)
		checks[key] = ok
		observed[key] = candidates
	}
	const batchSize = 10
	durations := make([]time.Duration, 0, (*iterations+batchSize-1)/batchSize)
	for batchStart := 0; batchStart < *iterations; batchStart += batchSize {
		count := batchSize
		if remaining := *iterations - batchStart; remaining < count {
			count = remaining
		}
		started := time.Now()
		for iteration := 0; iteration < count; iteration++ {
			for _, item := range probes {
				if !runProbe(engine, item) {
					checks[item.Text+"|"+item.Code] = false
				}
			}
		}
		durations = append(durations, time.Since(started)/time.Duration(count))
	}

	passed := true
	for _, ok := range checks {
		passed = passed && ok
	}
	memory, err := processmemory.Current()
	if err != nil {
		fail(err)
	}
	report := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexBytes: info.Size(), IndexRecords: index.RecordCount(),
		IndexOpenNS: openElapsed.Nanoseconds(), HeapBeforeBytes: before, HeapAfterBytes: after,
		HeapDeltaBytes: int64(after) - int64(before), Iterations: *iterations, ProbeCount: len(probes),
		ProcessMemory: memory, ProbeChecks: checks, ProbeCandidates: observed,
		Latency: summarize(durations, batchSize), Passed: passed,
		ComparisonScope: "whole-word, prefix and deterministic generated-sentence session lookup; no learning, IPC or TSF",
	}
	writeJSON(*output, report)
	fmt.Printf("YimeCore query: mode=%s probes=%d passed=%t p95_ns=%d\n", *mode, len(probes), passed, report.Latency.P95NS)
	if !passed {
		os.Exit(1)
	}
}

func runProbe(engine *yimecore.Engine, item probe) bool {
	ok, _ := inspectProbe(engine, item)
	return ok
}

func inspectProbe(engine *yimecore.Engine, item probe) (bool, []engineapi.Candidate) {
	engine.Reset()
	var result engineapi.Result
	for _, key := range item.Code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			return false, nil
		}
	}
	for _, candidate := range result.State.Candidates {
		if candidate.Text != item.Text || candidate.Code != item.Code || !candidate.Exact || (item.Generated && len(candidate.Segments) < 2) {
			continue
		}
		selected, err := engine.Select(candidate.ID)
		return err == nil && selected.Commit == item.Text && selected.State.RawInput == "", result.State.Candidates
	}
	return false, result.State.Candidates
}

func loadProbes(path, mode string) []probe {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err)
	}
	var file probeFile
	if err := json.Unmarshal(data, &file); err != nil {
		fail(err)
	}
	if file.Version != 1 {
		fail(fmt.Errorf("unsupported probe version %d", file.Version))
	}
	return file.Modes[mode]
}

func heapAlloc() uint64 {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return stats.HeapAlloc
}

func summarize(values []time.Duration, batchSize int) latency {
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return latency{
		Measurement: "batch-amortized complete curated probe set including per-key snapshots and selection",
		BatchSize:   batchSize, Samples: len(values),
		P50NS: percentile(values, 50).Nanoseconds(), P95NS: percentile(values, 95).Nanoseconds(),
		P99NS: percentile(values, 99).Nanoseconds(), MaxNS: values[len(values)-1].Nanoseconds(),
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

func writeJSON(path string, value any) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fail(err)
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
