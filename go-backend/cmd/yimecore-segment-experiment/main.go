// Command yimecore-segment-experiment exercises E2-B local segment correction
// over one immutable full-size index. It records no user data and commits only
// after both segment replacements have been incorporated into a full sentence.
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

const toolVersion = "yimecore-e2b-segment-correction-v1"

type probe struct {
	Text string `json:"text"`
	Code string `json:"code"`
}

type probeFile struct {
	Version int                `json:"version"`
	Source  string             `json:"source"`
	Modes   map[string][]probe `json:"modes"`
}

type latency struct {
	Measurement string `json:"measurement"`
	Samples     int    `json:"samples"`
	P50NS       int64  `json:"p50_ns"`
	P95NS       int64  `json:"p95_ns"`
	P99NS       int64  `json:"p99_ns"`
	MaxNS       int64  `json:"max_ns"`
}

type workflow struct {
	OriginalText           string `json:"original_text"`
	Code                   string `json:"code"`
	FirstReplacement       string `json:"first_replacement"`
	FinalReplacement       string `json:"final_replacement"`
	CorrectedText          string `json:"corrected_text"`
	FirstSelectionNoCommit bool   `json:"first_selection_no_commit"`
	FinalSelectionNoCommit bool   `json:"final_selection_no_commit"`
	OtherSegmentsPreserved bool   `json:"other_segments_preserved"`
	ExplicitCommitPassed   bool   `json:"explicit_commit_passed"`
	Passed                 bool   `json:"passed"`
}

type report struct {
	ToolVersion   string                 `json:"tool_version"`
	GeneratedAt   string                 `json:"generated_at"`
	Mode          string                 `json:"mode"`
	IndexPath     string                 `json:"index_path"`
	IndexSourceID string                 `json:"index_source_id"`
	ProbePath     string                 `json:"probe_path"`
	Workflow      workflow               `json:"workflow"`
	Latency       latency                `json:"latency"`
	ProcessMemory processmemory.Snapshot `json:"process_memory"`
	Passed        bool                   `json:"passed"`
}

func main() {
	mode := flag.String("mode", "", "full, variable or shorthand")
	indexPath := flag.String("index", "", "validated compact core index")
	probePath := flag.String("probes", "", "E2-B probe JSON")
	outputPath := flag.String("output", "", "evidence JSON")
	iterations := flag.Int("iterations", 100, "workflow latency samples")
	flag.Parse()
	if *mode == "" || *indexPath == "" || *probePath == "" || *outputPath == "" || *iterations < 1 {
		fail(fmt.Errorf("mode, index, probes, output and positive iterations are required"))
	}
	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %q does not match %q", index.Mode(), *mode))
	}
	probes := loadProbes(*probePath, *mode)
	if len(probes) != 1 {
		fail(fmt.Errorf("mode %q must have exactly one E2-B probe", *mode))
	}
	engine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		fail(err)
	}
	checked := runWorkflow(engine, probes[0])
	durations := make([]time.Duration, 0, *iterations)
	for i := 0; i < *iterations; i++ {
		started := time.Now()
		current := runWorkflow(engine, probes[0])
		durations = append(durations, time.Since(started))
		if !current.Passed || current.CorrectedText != checked.CorrectedText {
			fail(fmt.Errorf("workflow became nondeterministic at iteration %d", i))
		}
	}
	memory, err := processmemory.Current()
	if err != nil {
		fail(err)
	}
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), ProbePath: filepath.Clean(*probePath),
		Workflow: checked, Latency: summarize(durations), ProcessMemory: memory,
		Passed: checked.Passed && percentile(durations, 95) <= 50*time.Millisecond &&
			percentile(durations, 99) <= 50*time.Millisecond && durations[len(durations)-1] <= 50*time.Millisecond,
	}
	writeJSON(*outputPath, result)
	fmt.Printf("YimeCore E2-B segment correction: mode=%s passed=%t evidence=%s\n", *mode, result.Passed, *outputPath)
	if !result.Passed {
		os.Exit(1)
	}
}

func runWorkflow(engine *yimecore.Engine, item probe) workflow {
	state := applyCode(engine, item.Code)
	original := findTextAcrossPages(engine, state, item.Text)
	if original == nil || len(original.Segments) < 2 {
		fail(fmt.Errorf("generated sentence %q with at least two segments is unavailable", item.Text))
	}
	originalSegments := append([]engineapi.Segment(nil), original.Segments...)
	firstReplacement, firstResult := replaceSegment(engine, original, originalSegments[0])
	firstCorrected := findSentenceBySegments(engine, firstResult.State, replaceText(originalSegments, 0, firstReplacement.Text))
	if firstCorrected == nil {
		fail(fmt.Errorf("first correction did not restore the full sentence"))
	}
	last := len(firstCorrected.Segments) - 1
	finalReplacement, finalResult := replaceSegment(engine, firstCorrected, firstCorrected.Segments[last])
	expectedSegments := append([]engineapi.Segment(nil), firstCorrected.Segments...)
	expectedSegments[last].Text = finalReplacement.Text
	corrected := findSentenceBySegments(engine, finalResult.State, segmentTexts(expectedSegments))
	if corrected == nil {
		fail(fmt.Errorf("final correction did not restore the full sentence"))
	}
	committed, err := engine.Select(corrected.ID)
	if err != nil {
		fail(err)
	}
	otherPreserved := len(firstCorrected.Segments) == len(originalSegments)
	for i := 1; i < len(originalSegments) && otherPreserved; i++ {
		otherPreserved = firstCorrected.Segments[i].Text == originalSegments[i].Text &&
			firstCorrected.Segments[i].Start == originalSegments[i].Start && firstCorrected.Segments[i].End == originalSegments[i].End
	}
	result := workflow{
		OriginalText: item.Text, Code: item.Code, FirstReplacement: firstReplacement.Text,
		FinalReplacement: finalReplacement.Text, CorrectedText: corrected.Text,
		FirstSelectionNoCommit: firstResult.Commit == "", FinalSelectionNoCommit: finalResult.Commit == "",
		OtherSegmentsPreserved: otherPreserved,
		ExplicitCommitPassed:   committed.Commit == corrected.Text && committed.State.RawInput == "",
	}
	result.Passed = result.FirstSelectionNoCommit && result.FinalSelectionNoCommit && result.OtherSegmentsPreserved && result.ExplicitCommitPassed
	return result
}

func replaceSegment(engine *yimecore.Engine, sentence *engineapi.Candidate, segment engineapi.Segment) (*engineapi.Candidate, engineapi.Result) {
	focused, err := engine.Apply(engineapi.Event{
		Operation: engineapi.FocusSegment, CandidateID: sentence.ID,
		SegmentStart: segment.Start, SegmentEnd: segment.End,
	})
	if err != nil {
		fail(err)
	}
	replacement := findDifferentAcrossPages(engine, focused.State, segment.Text)
	if replacement == nil {
		fail(fmt.Errorf("segment %d:%d has no alternative exact candidate", segment.Start, segment.End))
	}
	selected, err := engine.Select(replacement.ID)
	if err != nil {
		fail(err)
	}
	return replacement, selected
}

func applyCode(engine *yimecore.Engine, code string) engineapi.State {
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

func findTextAcrossPages(engine *yimecore.Engine, state engineapi.State, text string) *engineapi.Candidate {
	return findAcrossPages(engine, state, func(candidate engineapi.Candidate) bool { return candidate.Text == text })
}

func findDifferentAcrossPages(engine *yimecore.Engine, state engineapi.State, text string) *engineapi.Candidate {
	return findAcrossPages(engine, state, func(candidate engineapi.Candidate) bool { return candidate.Text != text })
}

func findSentenceBySegments(engine *yimecore.Engine, state engineapi.State, texts []string) *engineapi.Candidate {
	return findAcrossPages(engine, state, func(candidate engineapi.Candidate) bool {
		if len(candidate.Segments) != len(texts) {
			return false
		}
		for i := range texts {
			if candidate.Segments[i].Text != texts[i] {
				return false
			}
		}
		return true
	})
}

func findAcrossPages(engine *yimecore.Engine, state engineapi.State, match func(engineapi.Candidate) bool) *engineapi.Candidate {
	for page := 0; page < 100; page++ {
		for i := range state.Candidates {
			if match(state.Candidates[i]) {
				candidate := state.Candidates[i]
				return &candidate
			}
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
	fail(fmt.Errorf("candidate paging exceeded 100 pages"))
	return nil
}

func replaceText(segments []engineapi.Segment, position int, text string) []string {
	texts := segmentTexts(segments)
	texts[position] = text
	return texts
}

func segmentTexts(segments []engineapi.Segment) []string {
	texts := make([]string, len(segments))
	for i := range segments {
		texts[i] = segments[i].Text
	}
	return texts
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
		fail(fmt.Errorf("unsupported or unproven E2-B probe file"))
	}
	return file.Modes[mode]
}

func summarize(values []time.Duration) latency {
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return latency{
		Measurement: "complete two-segment correction plus explicit commit", Samples: len(values),
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
