// Command yimecore-bundle-experiment validates one E4 bundle against locked
// reviewed alias probes. It neither derives rules nor reads Rime import files.
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

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
	"github.com/tsaanghwang/Yime/go-backend/internal/processmemory"
)

const toolVersion = "yimecore-e4b-reviewed-bundle-v2"

type moduleFlags []string

func (values *moduleFlags) String() string { return strings.Join(*values, ",") }
func (values *moduleFlags) Set(value string) error {
	*values = append(*values, value)
	return nil
}

type probe struct {
	ID               string `json:"id"`
	Module           string `json:"module"`
	Text             string `json:"text"`
	Code             string `json:"code"`
	CanonicalCode    string `json:"canonical_code"`
	ContinuationText string `json:"continuation_text,omitempty"`
	ContinuationCode string `json:"continuation_code,omitempty"`
}

type probeFile struct {
	Version int                `json:"version"`
	Source  string             `json:"source"`
	Modes   map[string][]probe `json:"modes"`
}

type check struct {
	ID                        string `json:"id"`
	Module                    string `json:"module"`
	AliasAvailable            bool   `json:"alias_available"`
	AliasSourceVerified       bool   `json:"alias_source_verified"`
	CanonicalAvailable        bool   `json:"canonical_available"`
	CanonicalSourceVerified   bool   `json:"canonical_source_verified"`
	AliasRemovedWhenDisabled  bool   `json:"alias_removed_when_disabled"`
	TextReachableAfterDisable bool   `json:"text_reachable_after_disable"`
	CanonicalSurvivesDisable  bool   `json:"canonical_survives_disable"`
	MixedSentenceAvailable    bool   `json:"mixed_sentence_available,omitempty"`
	MixedSourcesVerified      bool   `json:"mixed_sources_verified,omitempty"`
	Passed                    bool   `json:"passed"`
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
	ToolVersion   string                          `json:"tool_version"`
	GeneratedAt   string                          `json:"generated_at"`
	Mode          string                          `json:"mode"`
	CoreIndex     string                          `json:"core_index"`
	ModuleIndexes map[string]string               `json:"module_indexes"`
	BundleSource  string                          `json:"bundle_source_id"`
	ProbeSource   string                          `json:"probe_source"`
	Checks        []check                         `json:"checks"`
	Coverage      []yimecore.ModuleCoverageReport `json:"coverage"`
	Latency       latency                         `json:"latency"`
	ProcessMemory processmemory.Snapshot          `json:"process_memory"`
	Passed        bool                            `json:"passed"`
}

func main() {
	mode := flag.String("mode", "", "full, variable or shorthand")
	corePath := flag.String("core-index", "", "canonical core index")
	probesPath := flag.String("probes", "", "reviewed E4 probe JSON")
	outputPath := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 100, "latency iterations")
	var moduleArgs moduleFlags
	flag.Var(&moduleArgs, "module", "enabled module in id=path form; repeatable")
	flag.Parse()
	if *mode == "" || *corePath == "" || *probesPath == "" || *outputPath == "" || *iterations < 1 {
		fail(fmt.Errorf("mode, core-index, probes, output and positive iterations are required"))
	}

	core := openIndex(*corePath, *mode)
	defer core.Close()
	moduleIndexes := make(map[string]*yimecore.FileIndex, len(moduleArgs))
	modulePaths := make(map[string]string, len(moduleArgs))
	for _, argument := range moduleArgs {
		id, path, ok := strings.Cut(argument, "=")
		id, path = strings.TrimSpace(id), strings.TrimSpace(path)
		if !ok || id == "" || path == "" {
			fail(fmt.Errorf("invalid module argument %q", argument))
		}
		if _, exists := moduleIndexes[id]; exists {
			fail(fmt.Errorf("duplicate module %q", id))
		}
		index := openIndex(path, *mode)
		defer index.Close()
		moduleIndexes[id] = index
		modulePaths[id] = filepath.Clean(path)
	}
	probes := loadProbes(*probesPath, *mode)
	modules := selectedModules(moduleIndexes, "")
	bundle := newBundle(core, modules)
	engine := newEngine(bundle)

	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		CoreIndex: filepath.Clean(*corePath), ModuleIndexes: modulePaths, BundleSource: bundle.SourceID(),
		ProbeSource: filepath.Clean(*probesPath), Passed: len(probes) > 0,
	}
	for _, item := range probes {
		if _, exists := moduleIndexes[item.Module]; !exists {
			fail(fmt.Errorf("probe %q references unavailable module %q", item.ID, item.Module))
		}
		current := runCheck(engine, item, item.Module)
		without := newEngine(newBundle(core, selectedModules(moduleIndexes, item.Module)))
		aliasAfterDisable := findAcrossPages(without, item.Code, item.Text)
		canonicalAfterDisable := findAcrossPages(without, item.CanonicalCode, item.Text)
		current.TextReachableAfterDisable = aliasAfterDisable != nil
		current.AliasRemovedWhenDisabled = aliasAfterDisable == nil || !usesSource(aliasAfterDisable, item.Module)
		current.CanonicalSurvivesDisable = canonicalAfterDisable != nil && strings.HasPrefix(canonicalAfterDisable.SourceID, "core@")
		current.Passed = current.AliasAvailable && current.AliasSourceVerified && current.CanonicalAvailable &&
			current.CanonicalSourceVerified && current.AliasRemovedWhenDisabled && current.CanonicalSurvivesDisable
		if item.ContinuationText != "" || item.ContinuationCode != "" {
			want := item.Text + item.ContinuationText
			mixed := findAcrossPages(engine, item.Code+item.ContinuationCode, want)
			current.MixedSentenceAvailable = mixed != nil && len(mixed.Segments) == 2
			current.MixedSourcesVerified = current.MixedSentenceAvailable &&
				strings.HasPrefix(mixed.Segments[0].SourceID, item.Module+"@") &&
				strings.HasPrefix(mixed.Segments[1].SourceID, "core@")
			current.Passed = current.Passed && current.MixedSentenceAvailable && current.MixedSourcesVerified
		}
		result.Checks = append(result.Checks, current)
		result.Passed = result.Passed && current.Passed
	}
	result.Latency = benchmark(engine, probes, *iterations)
	memory, err := processmemory.Current()
	if err != nil {
		fail(err)
	}
	result.ProcessMemory = memory
	// Keep the resource snapshot comparable with the real-Rime probe process.
	// Exhaustive coverage intentionally faults many more index pages and runs
	// only after the matched-workload snapshot has been captured.
	for _, module := range modules {
		coverage, err := bundle.AuditModuleCoverage(module.ID, 9)
		if err != nil {
			fail(err)
		}
		result.Coverage = append(result.Coverage, coverage)
		result.Passed = result.Passed && coverage.Passed
	}
	writeJSON(*outputPath, result)
	fmt.Printf("YimeCore E4-B bundle: mode=%s passed=%t evidence=%s\n", *mode, result.Passed, *outputPath)
	if !result.Passed {
		os.Exit(1)
	}
}

func runCheck(engine *yimecore.Engine, item probe, module string) check {
	alias := findAcrossPages(engine, item.Code, item.Text)
	canonical := findAcrossPages(engine, item.CanonicalCode, item.Text)
	return check{
		ID: item.ID, Module: module,
		AliasAvailable: alias != nil, AliasSourceVerified: alias != nil && strings.HasPrefix(alias.SourceID, module+"@"),
		CanonicalAvailable: canonical != nil, CanonicalSourceVerified: canonical != nil && strings.HasPrefix(canonical.SourceID, "core@"),
	}
}

func selectedModules(indexes map[string]*yimecore.FileIndex, excluded string) []yimecore.BundleModule {
	ids := make([]string, 0, len(indexes))
	for id := range indexes {
		if id != excluded {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	modules := make([]yimecore.BundleModule, 0, len(ids))
	for _, id := range ids {
		modules = append(modules, yimecore.BundleModule{ID: id, Index: indexes[id]})
	}
	return modules
}

func newBundle(core *yimecore.FileIndex, modules []yimecore.BundleModule) *yimecore.BundleIndex {
	bundle, err := yimecore.NewBundleIndex(core, modules)
	if err != nil {
		fail(err)
	}
	return bundle
}

func newEngine(bundle *yimecore.BundleIndex) *yimecore.Engine {
	engine, err := yimecore.NewBundleEngine(bundle, 9)
	if err != nil {
		fail(err)
	}
	return engine
}

func openIndex(path, mode string) *yimecore.FileIndex {
	index, err := yimecore.OpenFileIndex(path)
	if err != nil {
		fail(err)
	}
	if index.Mode() != mode {
		index.Close()
		fail(fmt.Errorf("index %s has mode %q, expected %q", path, index.Mode(), mode))
	}
	return index
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
	if file.Version != 1 || file.Source == "" {
		fail(fmt.Errorf("unsupported or unproven probe file"))
	}
	return file.Modes[mode]
}

func apply(engine *yimecore.Engine, code string) engineapi.State {
	engine.Reset()
	var result engineapi.Result
	for _, key := range strings.ReplaceAll(code, " ", "") {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			fail(err)
		}
	}
	return result.State
}

func findCandidate(state engineapi.State, text string) *engineapi.Candidate {
	for i := range state.Candidates {
		if state.Candidates[i].Text == text {
			return &state.Candidates[i]
		}
	}
	return nil
}

func findAcrossPages(engine *yimecore.Engine, code, text string) *engineapi.Candidate {
	state := apply(engine, code)
	for page := 0; page < 100; page++ {
		if candidate := findCandidate(state, text); candidate != nil {
			return candidate
		}
		if !state.HasNext {
			return nil
		}
		result, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
		if err != nil {
			fail(err)
		}
		state = result.State
	}
	fail(fmt.Errorf("YimeCore paging exceeded 100 pages for %q after %q", text, code))
	return nil
}

func usesSource(candidate *engineapi.Candidate, source string) bool {
	if candidate == nil {
		return false
	}
	if strings.HasPrefix(candidate.SourceID, source+"@") {
		return true
	}
	for _, segment := range candidate.Segments {
		if strings.HasPrefix(segment.SourceID, source+"@") {
			return true
		}
	}
	return false
}

func benchmark(engine *yimecore.Engine, probes []probe, iterations int) latency {
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
				candidate := findAcrossPages(engine, item.Code, item.Text)
				if candidate == nil {
					fail(fmt.Errorf("latency probe %q disappeared after %q", item.ID, item.Code))
				}
				if _, err := engine.Select(candidate.ID); err != nil {
					fail(err)
				}
			}
		}
		durations = append(durations, time.Since(started)/time.Duration(count))
	}
	sort.Slice(durations, func(i, j int) bool { return durations[i] < durations[j] })
	return latency{
		Measurement: "batch-amortized complete reviewed alias probe set", BatchSize: batchSize, Samples: len(durations),
		P50NS: percentile(durations, 50).Nanoseconds(), P95NS: percentile(durations, 95).Nanoseconds(),
		P99NS: percentile(durations, 99).Nanoseconds(), MaxNS: durations[len(durations)-1].Nanoseconds(),
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
