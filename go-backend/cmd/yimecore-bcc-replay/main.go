// Command yimecore-bcc-replay checks offline BCC component paths against the
// three real compact indexes without starting TSF or attaching a user model.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const toolVersion = "yimecore-bcc-composition-replay-v1"

var replayModes = []string{"full", "variable", "shorthand"}

type pathFile struct {
	SchemaVersion string       `json:"schema_version"`
	Samples       []pathSample `json:"samples"`
}

type pathSample struct {
	Text                  string            `json:"text"`
	CompositionInputPaths []compositionPath `json:"composition_input_paths"`
}

type compositionPath struct {
	NumericComponentInput string              `json:"numeric_component_input"`
	Codes                 map[string]modeCode `json:"codes"`
}

type modeCode struct {
	LayoutKeyCode string `json:"layout_key_code"`
}

type attemptResult struct {
	NumericComponentInput  string                          `json:"numeric_component_input"`
	Input                  string                          `json:"input"`
	SegmentLimitPressure   []yimecore.SegmentLimitPressure `json:"segment_limit_pressure,omitempty"`
	ActualSentence         string                          `json:"actual_sentence,omitempty"`
	ActualSegments         []string                        `json:"actual_segments,omitempty"`
	TargetPathInIndexGraph bool                            `json:"target_path_in_index_graph"`
	TargetPathRetained     bool                            `json:"target_path_retained_by_beam"`
	TargetPathRetainedRank int                             `json:"target_path_retained_rank,omitempty"`
	TargetPathWithinTopN   bool                            `json:"target_path_within_top_n_retained"`
	Diagnosis              string                          `json:"diagnosis"`
	TargetVisible          bool                            `json:"runtime_target_visible"`
	ListedCandidateVisible bool                            `json:"runtime_listed_candidate_visible"`
	CommitMatches          bool                            `json:"runtime_commit_matches"`
	Failure                string                          `json:"failure,omitempty"`
	Error                  string                          `json:"error,omitempty"`
}

type modeResult struct {
	Mode              string          `json:"mode"`
	IndexSourceID     string          `json:"index_source_id"`
	Attempts          []attemptResult `json:"attempts"`
	SuccessfulPaths   int             `json:"successful_paths"`
	DirectOutputWorks bool            `json:"runtime_direct_output_success"`
	TopNRetainedWorks bool            `json:"estimated_correctable_within_top_n"`
}

type targetResult struct {
	Text                 string       `json:"text"`
	OfflinePathReachable bool         `json:"offline_path_reachable"`
	OfflinePathCount     int          `json:"offline_path_count"`
	Modes                []modeResult `json:"modes"`
	AllModesOutput       bool         `json:"all_modes_direct_output_success"`
}

type report struct {
	ToolVersion string         `json:"tool_version"`
	GeneratedAt string         `json:"generated_at"`
	PathsPath   string         `json:"paths_path"`
	IndexRoot   string         `json:"index_root"`
	Targets     []targetResult `json:"targets"`
	Passed      bool           `json:"passed"`
}

func main() {
	indexRoot := flag.String("index-root", "", "directory containing full/variable/shorthand.yidx")
	pathsPath := flag.String("paths", "", "BCC composition_input_paths.json")
	output := flag.String("output", "", "replay evidence JSON")
	failOnMismatch := flag.Bool("fail-on-mismatch", false, "return exit code 1 when any target fails a mode")
	flag.Parse()
	result, err := run(*indexRoot, *pathsPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := writeJSON(*output, result); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("YimeCore BCC replay: targets=%d passed=%t evidence=%s\n", len(result.Targets), result.Passed, *output)
	if *failOnMismatch && !result.Passed {
		os.Exit(1)
	}
}

func run(indexRoot, pathsPath string) (report, error) {
	if strings.TrimSpace(indexRoot) == "" || strings.TrimSpace(pathsPath) == "" {
		return report{}, errors.New("index-root and paths are required")
	}
	data, err := os.ReadFile(pathsPath)
	if err != nil {
		return report{}, err
	}
	var paths pathFile
	if err := json.Unmarshal(data, &paths); err != nil {
		return report{}, err
	}
	if paths.SchemaVersion == "" || len(paths.Samples) == 0 {
		return report{}, errors.New("unsupported or empty BCC composition paths")
	}

	indexes := make(map[string]*yimecore.FileIndex, len(replayModes))
	for _, mode := range replayModes {
		index, openErr := yimecore.OpenFileIndex(filepath.Join(indexRoot, mode+".yidx"))
		if openErr != nil {
			for _, opened := range indexes {
				_ = opened.Close()
			}
			return report{}, fmt.Errorf("open %s index: %w", mode, openErr)
		}
		if index.Mode() != mode {
			_ = index.Close()
			for _, opened := range indexes {
				_ = opened.Close()
			}
			return report{}, fmt.Errorf("%s index reports mode %s", mode, index.Mode())
		}
		indexes[mode] = index
	}
	defer func() {
		for _, index := range indexes {
			_ = index.Close()
		}
	}()

	result := report{
		ToolVersion: toolVersion,
		GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		PathsPath:   filepath.Clean(pathsPath),
		IndexRoot:   filepath.Clean(indexRoot),
		Passed:      true,
	}
	for _, sample := range paths.Samples {
		target := targetResult{
			Text: sample.Text, OfflinePathReachable: len(sample.CompositionInputPaths) > 0,
			OfflinePathCount: len(sample.CompositionInputPaths), AllModesOutput: true,
		}
		for _, mode := range replayModes {
			checked, checkErr := replayMode(indexes[mode], mode, sample)
			if checkErr != nil {
				return report{}, fmt.Errorf("replay %q in %s: %w", sample.Text, mode, checkErr)
			}
			target.Modes = append(target.Modes, checked)
			target.AllModesOutput = target.AllModesOutput && checked.DirectOutputWorks
		}
		result.Targets = append(result.Targets, target)
		result.Passed = result.Passed && target.AllModesOutput
	}
	return result, nil
}

func replayMode(index *yimecore.FileIndex, mode string, sample pathSample) (modeResult, error) {
	if sample.Text == "" || len(sample.CompositionInputPaths) == 0 {
		return modeResult{}, errors.New("target text and composition paths are required")
	}
	result := modeResult{Mode: mode, IndexSourceID: index.SourceID()}
	for _, path := range sample.CompositionInputPaths {
		code, found := path.Codes[mode]
		attempt := attemptResult{NumericComponentInput: path.NumericComponentInput, Input: code.LayoutKeyCode}
		if !found || code.LayoutKeyCode == "" {
			attempt.Failure = "missing_mode_code"
			result.Attempts = append(result.Attempts, attempt)
			continue
		}
		engine, err := yimecore.NewFileEngine(index, 9)
		if err != nil {
			return modeResult{}, err
		}
		var state engineapi.State
		for _, key := range code.LayoutKeyCode {
			applied, applyErr := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
			if applyErr != nil {
				attempt.Failure = "input_rejected"
				attempt.Error = applyErr.Error()
				break
			}
			state = applied.State
		}
		if attempt.Failure == "" {
			trace := engine.Explain()
			attempt.SegmentLimitPressure = append(
				[]yimecore.SegmentLimitPressure(nil), trace.SegmentLimitPressure...,
			)
			attempt.TargetPathInIndexGraph = targetPathExists(trace, sample.Text)
			for _, retained := range trace.RetainedPaths {
				if retained.Complete && retained.Text == sample.Text {
					attempt.TargetPathRetained = true
					attempt.TargetPathRetainedRank = retained.Rank
					attempt.TargetPathWithinTopN = retained.Rank <= 9
					break
				}
			}
			if state.Sentence == nil {
				attempt.Failure = "no_runtime_sentence"
			} else {
				attempt.ActualSentence = state.Sentence.Text
				for _, segment := range state.Sentence.Segments {
					attempt.ActualSegments = append(attempt.ActualSegments, segment.Text)
				}
				for _, candidate := range state.Candidates {
					if candidate.Text == sample.Text {
						attempt.ListedCandidateVisible = true
						break
					}
				}
				attempt.TargetVisible = state.Sentence.Text == sample.Text
				if !attempt.TargetVisible {
					attempt.Failure = "runtime_sentence_mismatch"
				} else {
					committed, commitErr := engine.Select(state.Sentence.ID)
					if commitErr != nil {
						attempt.Failure = "runtime_commit_error"
						attempt.Error = commitErr.Error()
					} else {
						attempt.CommitMatches = committed.Commit == sample.Text
						if !attempt.CommitMatches {
							attempt.Failure = "runtime_commit_mismatch"
						}
					}
				}
			}
		}
		attempt.Diagnosis = diagnoseAttempt(attempt)
		if attempt.TargetVisible && attempt.CommitMatches {
			result.SuccessfulPaths++
		}
		result.TopNRetainedWorks = result.TopNRetainedWorks || attempt.TargetPathWithinTopN
		result.Attempts = append(result.Attempts, attempt)
	}
	result.DirectOutputWorks = result.SuccessfulPaths > 0
	return result, nil
}

func targetPathExists(trace yimecore.DecodeTrace, target string) bool {
	if trace.Input == "" || target == "" {
		return false
	}
	states := make([]map[int]struct{}, len(trace.Input)+1)
	states[0] = map[int]struct{}{0: {}}
	for _, edge := range trace.Edges {
		if edge.Start < 0 || edge.End <= edge.Start || edge.End > len(trace.Input) || len(states[edge.Start]) == 0 {
			continue
		}
		for textStart := range states[edge.Start] {
			if textStart > len(target) || !strings.HasPrefix(target[textStart:], edge.Text) {
				continue
			}
			textEnd := textStart + len(edge.Text)
			if states[edge.End] == nil {
				states[edge.End] = make(map[int]struct{})
			}
			states[edge.End][textEnd] = struct{}{}
		}
	}
	_, found := states[len(trace.Input)][len(target)]
	return found
}

func diagnoseAttempt(attempt attemptResult) string {
	if attempt.TargetVisible && attempt.CommitMatches {
		return "direct_output_success"
	}
	if attempt.Failure == "missing_mode_code" || attempt.Failure == "input_rejected" {
		return "input_path_invalid"
	}
	if !attempt.TargetPathInIndexGraph {
		return "runtime_index_graph_missing_target_path"
	}
	if !attempt.TargetPathRetained {
		return "runtime_beam_pruned_target_path"
	}
	return "runtime_ranking_preferred_other_sentence"
}

func writeJSON(path string, value any) error {
	if path == "" {
		return errors.New("output is required")
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
