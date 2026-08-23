//go:build windows

// Command yimecore-rime-compare runs the same curated exact-word probe set
// through real librime and records a matched-scope latency/correctness baseline.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	yime "github.com/tsaanghwang/Yime/go-backend/input_methods/yime"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const toolVersion = "yimecore-rime-compare-e1-v1"

type probe struct {
	Text string `json:"text"`
	Code string `json:"code"`
}

type probeFile struct {
	Version int                `json:"version"`
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

type modeReport struct {
	Mode        string          `json:"mode"`
	Schema      string          `json:"schema"`
	ProbeChecks map[string]bool `json:"probe_checks"`
	Latency     latency         `json:"latency"`
	Passed      bool            `json:"passed"`
}

type report struct {
	ToolVersion     string                 `json:"tool_version"`
	GeneratedAt     string                 `json:"generated_at"`
	DataRoot        string                 `json:"data_root"`
	Iterations      int                    `json:"iterations"`
	Modes           []modeReport           `json:"modes"`
	Passed          bool                   `json:"passed"`
	ProcessMemory   processmemory.Snapshot `json:"process_memory"`
	ComparisonScope string                 `json:"comparison_scope"`
}

func main() {
	dataRoot := flag.String("data-root", "", "Yime shared Rime data directory")
	probesPath := flag.String("probes", "", "E1 probe JSON")
	output := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 100, "number of full probe-set iterations per mode")
	onlyMode := flag.String("mode", "", "optional single mode: full, variable or shorthand")
	flag.Parse()
	if *dataRoot == "" || *probesPath == "" || *output == "" || *iterations < 1 {
		fail(fmt.Errorf("data-root, probes, output and positive iterations are required"))
	}
	probes := loadProbes(*probesPath)
	userRoot, err := os.MkdirTemp("", "yimecore-rime-e1-")
	if err != nil {
		fail(err)
	}
	defer os.RemoveAll(userRoot)
	if err := writeDefaultCustom(userRoot); err != nil {
		fail(err)
	}
	if !yime.RimeInit(*dataRoot, userRoot, yime.APP, yime.APP_VERSION, false) {
		fail(fmt.Errorf("RimeInit failed"))
	}
	defer yime.Finalize()
	sessionID, ok := yime.StartSession()
	if !ok || sessionID == 0 {
		fail(fmt.Errorf("StartSession failed"))
	}
	defer yime.EndSession(sessionID)
	yime.SetOption(sessionID, "ascii_mode", false)

	definitions := []struct {
		mode   string
		schema string
	}{
		{"full", "yime_full"},
		{"variable", "yime_variable"},
		{"shorthand", "yime_shorthand"},
	}
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		DataRoot: filepath.Clean(*dataRoot), Iterations: *iterations, Passed: true,
		ComparisonScope: "real librime exact whole-word and prefix session lookup; includes clear, per-key processing, menu retrieval, selection and commit",
	}
	for _, definition := range definitions {
		if *onlyMode != "" && definition.mode != *onlyMode {
			continue
		}
		modeResult := runMode(sessionID, definition.mode, definition.schema, probes.Modes[definition.mode], *iterations)
		result.Modes = append(result.Modes, modeResult)
		result.Passed = result.Passed && modeResult.Passed
	}
	if len(result.Modes) == 0 {
		fail(fmt.Errorf("mode %q is not supported", *onlyMode))
	}
	memory, err := processmemory.Current()
	if err != nil {
		fail(err)
	}
	result.ProcessMemory = memory
	writeJSON(*output, result)
	fmt.Printf("YimeCore real-Rime baseline: passed=%t evidence=%s\n", result.Passed, *output)
	if !result.Passed {
		os.Exit(1)
	}
}

func runMode(sessionID yime.RimeSessionId, mode, schema string, probes []probe, iterations int) modeReport {
	if !yime.SelectSchema(sessionID, schema) {
		fail(fmt.Errorf("schema %s is not selectable", schema))
	}
	yime.SetOption(sessionID, "ascii_mode", false)
	checks := make(map[string]bool, len(probes))
	for _, item := range probes {
		checks[item.Text+"|"+item.Code] = true
	}
	const batchSize = 5
	durations := make([]time.Duration, 0, (iterations+batchSize-1)/batchSize)
	for batchStart := 0; batchStart < iterations; batchStart += batchSize {
		count := batchSize
		if remaining := iterations - batchStart; remaining < count {
			count = remaining
		}
		started := time.Now()
		for iteration := 0; iteration < count; iteration++ {
			for _, item := range probes {
				if !runProbe(sessionID, item) {
					checks[item.Text+"|"+item.Code] = false
				}
			}
		}
		durations = append(durations, time.Since(started)/time.Duration(count))
	}
	passed := len(probes) > 0
	for _, check := range checks {
		passed = passed && check
	}
	return modeReport{Mode: mode, Schema: schema, ProbeChecks: checks, Latency: summarize(durations, batchSize), Passed: passed}
}

func runProbe(sessionID yime.RimeSessionId, item probe) bool {
	yime.ClearComposition(sessionID)
	for _, key := range item.Code {
		if !yime.ProcessKey(sessionID, int(key), 0) {
			return false
		}
	}
	for page := 0; page < 100; page++ {
		menu, ok := yime.GetMenu(sessionID)
		if !ok {
			return false
		}
		for i, candidate := range menu.Candidates {
			if candidate.Text == item.Text {
				if !yime.SelectCandidate(sessionID, i) {
					return false
				}
				commit, ok := yime.GetCommit(sessionID)
				return ok && commit.Text == item.Text
			}
		}
		if menu.IsLastPage || !yime.ProcessKey(sessionID, 0xFF56, 0) {
			return false
		}
	}
	return false
}

func loadProbes(path string) probeFile {
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
	return file
}

func writeDefaultCustom(userRoot string) error {
	content := strings.Join([]string{
		"patch:", "  schema_list:", "    - schema: yime_variable", "    - schema: yime_full",
		"    - schema: yime_shorthand", ""}, "\n")
	return os.WriteFile(filepath.Join(userRoot, "default.custom.yaml"), []byte(content), 0o644)
}

func summarize(values []time.Duration, batchSize int) latency {
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return latency{
		Measurement: "batch-amortized complete curated probe set", BatchSize: batchSize, Samples: len(values),
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
