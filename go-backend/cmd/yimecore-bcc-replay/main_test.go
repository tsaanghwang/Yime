package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestReplaySeparatesOfflinePathsFromRuntimeOutput(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"银\ta\t100", "行\tb\t100", "银行\tzz\t1", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, mode := range replayModes {
		if _, err := yimecore.BuildIndexFile(mode, dictionary, filepath.Join(root, mode+".yidx")); err != nil {
			t.Fatal(err)
		}
	}
	paths := pathFile{SchemaVersion: "test-v1", Samples: []pathSample{
		{Text: "银行", CompositionInputPaths: []compositionPath{testPath("ab")}},
		{Text: "银错", CompositionInputPaths: []compositionPath{testPath("ab")}},
	}}
	data, err := json.Marshal(paths)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paths.json")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := run(root, path)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed || len(result.Targets) != 2 {
		t.Fatalf("report=%#v", result)
	}
	if !result.Targets[0].OfflinePathReachable || !result.Targets[0].AllModesOutput {
		t.Fatalf("reachable target=%#v", result.Targets[0])
	}
	if !result.Targets[0].Modes[0].Attempts[0].TargetVisible || result.Targets[0].Modes[0].Attempts[0].ListedCandidateVisible {
		t.Fatalf("independent sentence channel=%#v", result.Targets[0].Modes[0].Attempts[0])
	}
	failed := result.Targets[1]
	if !failed.OfflinePathReachable || failed.AllModesOutput {
		t.Fatalf("mismatched target=%#v", failed)
	}
	for _, mode := range failed.Modes {
		if mode.DirectOutputWorks || mode.Attempts[0].Failure != "runtime_sentence_mismatch" ||
			mode.Attempts[0].ActualSentence != "银行" || mode.Attempts[0].Diagnosis != "runtime_index_graph_missing_target_path" {
			t.Fatalf("mode failure=%#v", mode)
		}
	}
}

func TestReplayDiagnosesRetainedTargetThatLosesRanking(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"铜\ta\t200", "银\ta\t100", "行\tb\t100", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, mode := range replayModes {
		if _, err := yimecore.BuildIndexFile(mode, dictionary, filepath.Join(root, mode+".yidx")); err != nil {
			t.Fatal(err)
		}
	}
	paths := pathFile{SchemaVersion: "test-v1", Samples: []pathSample{{
		Text: "银行", CompositionInputPaths: []compositionPath{testPath("ab")},
	}}}
	data, err := json.Marshal(paths)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(root, "paths.json")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := run(root, path)
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range result.Targets[0].Modes {
		attempt := mode.Attempts[0]
		if attempt.ActualSentence != "铜行" || !attempt.TargetPathInIndexGraph || !attempt.TargetPathRetained ||
			attempt.TargetPathRetainedRank < 2 || !attempt.TargetPathWithinTopN ||
			attempt.Diagnosis != "runtime_ranking_preferred_other_sentence" {
			t.Fatalf("ranking diagnosis=%#v", attempt)
		}
	}
}

func testPath(code string) compositionPath {
	codes := make(map[string]modeCode, len(replayModes))
	for _, mode := range replayModes {
		codes[mode] = modeCode{LayoutKeyCode: code}
	}
	return compositionPath{NumericComponentInput: "yin2 hang2", Codes: codes}
}
