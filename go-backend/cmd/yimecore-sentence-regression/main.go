// Command yimecore-sentence-regression replays reviewed dynamic composition
// cases against the three real compact indexes without a TSF host.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const (
	toolVersion       = "yimecore-dynamic-sentence-regression-v1"
	caseSchemaVersion = "yimecore-dynamic-sentence-cases-v1"
)

type caseFile struct {
	SchemaVersion string           `json:"schema_version"`
	Description   string           `json:"description"`
	Cases         []regressionCase `json:"cases"`
}

type regressionCase struct {
	ID    string `json:"id"`
	Mode  string `json:"mode"`
	Steps []step `json:"steps"`
}

type step struct {
	Input            string   `json:"input"`
	ExpectedTop      string   `json:"expected_top"`
	ExpectedExact    bool     `json:"expected_exact"`
	ExpectedRunnerUp string   `json:"expected_runner_up,omitempty"`
	MinimumMargin    int64    `json:"minimum_margin,omitempty"`
	RequiredEdge     string   `json:"required_edge,omitempty"`
	RequiredPath     []string `json:"required_path,omitempty"`
}

type stepResult struct {
	Input            string   `json:"input"`
	ExpectedTop      string   `json:"expected_top"`
	ActualTop        string   `json:"actual_top"`
	ActualExact      bool     `json:"actual_exact"`
	ExpectedRunnerUp string   `json:"expected_runner_up,omitempty"`
	ActualRunnerUp   string   `json:"actual_runner_up,omitempty"`
	MinimumMargin    int64    `json:"minimum_margin,omitempty"`
	ActualMargin     int64    `json:"actual_margin,omitempty"`
	RequiredEdge     string   `json:"required_edge,omitempty"`
	RequiredPath     []string `json:"required_path,omitempty"`
	EdgeFound        bool     `json:"edge_found"`
	PathFound        bool     `json:"path_found"`
	Passed           bool     `json:"passed"`
}

type caseResult struct {
	ID            string       `json:"id"`
	Mode          string       `json:"mode"`
	IndexSourceID string       `json:"index_source_id"`
	Steps         []stepResult `json:"steps"`
	Passed        bool         `json:"passed"`
}

type report struct {
	ToolVersion string       `json:"tool_version"`
	GeneratedAt string       `json:"generated_at"`
	CasePath    string       `json:"case_path"`
	IndexRoot   string       `json:"index_root"`
	Cases       []caseResult `json:"cases"`
	Passed      bool         `json:"passed"`
}

func main() {
	indexRoot := flag.String("index-root", "", "directory containing full/variable/shorthand.yidx")
	casePath := flag.String("cases", "", "reviewed dynamic sentence case JSON")
	output := flag.String("output", "", "evidence JSON")
	flag.Parse()
	result, err := run(*indexRoot, *casePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := writeJSON(*output, result); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("YimeCore dynamic sentence regression: cases=%d passed=%t evidence=%s\n", len(result.Cases), result.Passed, *output)
	if !result.Passed {
		os.Exit(1)
	}
}

func run(indexRoot, casePath string) (report, error) {
	if indexRoot == "" || casePath == "" {
		return report{}, errors.New("index-root and cases are required")
	}
	data, err := os.ReadFile(casePath)
	if err != nil {
		return report{}, err
	}
	var cases caseFile
	if err := json.Unmarshal(data, &cases); err != nil {
		return report{}, err
	}
	if cases.SchemaVersion != caseSchemaVersion || len(cases.Cases) == 0 {
		return report{}, errors.New("unsupported or empty dynamic sentence cases")
	}
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		CasePath: filepath.Clean(casePath), IndexRoot: filepath.Clean(indexRoot), Passed: true,
	}
	for _, item := range cases.Cases {
		checked, err := runCase(indexRoot, item)
		if err != nil {
			return report{}, fmt.Errorf("case %s: %w", item.ID, err)
		}
		result.Cases = append(result.Cases, checked)
		result.Passed = result.Passed && checked.Passed
	}
	return result, nil
}

func runCase(indexRoot string, item regressionCase) (caseResult, error) {
	if item.ID == "" || item.Mode == "" || len(item.Steps) == 0 {
		return caseResult{}, errors.New("id, mode and steps are required")
	}
	index, err := yimecore.OpenFileIndex(filepath.Join(indexRoot, item.Mode+".yidx"))
	if err != nil {
		return caseResult{}, err
	}
	defer index.Close()
	if index.Mode() != item.Mode {
		return caseResult{}, fmt.Errorf("index mode=%s", index.Mode())
	}
	engine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		return caseResult{}, err
	}
	result := caseResult{ID: item.ID, Mode: item.Mode, IndexSourceID: index.SourceID(), Passed: true}
	current := ""
	for _, expected := range item.Steps {
		input := strings.ReplaceAll(expected.Input, " ", "")
		if !strings.HasPrefix(input, current) {
			engine.Reset()
			current = ""
		}
		for _, key := range input[len(current):] {
			if _, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}); err != nil {
				return caseResult{}, err
			}
		}
		current = input
		trace := engine.Explain()
		actual := stepResult{
			Input: input, ExpectedTop: expected.ExpectedTop,
			ExpectedRunnerUp: expected.ExpectedRunnerUp, MinimumMargin: expected.MinimumMargin,
			RequiredEdge: expected.RequiredEdge,
			RequiredPath: append([]string(nil), expected.RequiredPath...),
			EdgeFound:    expected.RequiredEdge == "", PathFound: len(expected.RequiredPath) == 0,
		}
		if trace.PreeditSentence != nil {
			actual.ActualTop = trace.PreeditSentence.Text
			actual.ActualExact = trace.PreeditSentence.Exact
		}
		for _, edge := range trace.Edges {
			if edge.Text == expected.RequiredEdge && edge.Start == 0 && edge.End == len(input) {
				actual.EdgeFound = true
			}
		}
		for _, path := range trace.RetainedPaths {
			texts := make([]string, len(path.Segments))
			for i := range path.Segments {
				texts[i] = path.Segments[i].Text
			}
			if reflect.DeepEqual(texts, expected.RequiredPath) {
				actual.PathFound = true
				break
			}
		}
		if len(trace.RetainedPaths) >= 2 {
			actual.ActualRunnerUp = trace.RetainedPaths[1].Text
			actual.ActualMargin = trace.RetainedPaths[0].Score.Total - trace.RetainedPaths[1].Score.Total
		}
		topPassed := expected.ExpectedTop == "" || actual.ActualTop == expected.ExpectedTop
		runnerUpPassed := expected.ExpectedRunnerUp == "" || actual.ActualRunnerUp == expected.ExpectedRunnerUp
		marginPassed := expected.MinimumMargin == 0 ||
			(len(trace.RetainedPaths) >= 2 && actual.ActualMargin >= expected.MinimumMargin)
		actual.Passed = topPassed && actual.ActualExact == expected.ExpectedExact &&
			runnerUpPassed && marginPassed && actual.EdgeFound && actual.PathFound
		result.Steps = append(result.Steps, actual)
		result.Passed = result.Passed && actual.Passed
	}
	return result, nil
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
