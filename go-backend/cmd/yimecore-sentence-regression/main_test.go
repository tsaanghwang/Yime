package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestRegressionReplaysIncrementalWordFirstComposition(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"本\ta\t100", "地\tb\t100", "人\tcde\t100",
		"本地\tab\t500", "本地人\tabcde\t800", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", dictionary, filepath.Join(root, "variable.yidx")); err != nil {
		t.Fatal(err)
	}
	cases := caseFile{SchemaVersion: caseSchemaVersion, Cases: []regressionCase{{
		ID: "synthetic", Mode: "variable", Steps: []step{
			{Input: "ab", ExpectedTop: "本地", ExpectedExact: true, RequiredEdge: "本地"},
			{Input: "abc", ExpectedExact: false, RequiredPath: []string{"本地", "人"}},
			{Input: "abcde", ExpectedTop: "本地人", ExpectedExact: true, RequiredEdge: "本地人", RequiredPath: []string{"本地", "人"}},
		},
	}}}
	data, err := json.Marshal(cases)
	if err != nil {
		t.Fatal(err)
	}
	casePath := filepath.Join(root, "cases.json")
	if err := os.WriteFile(casePath, data, 0o600); err != nil {
		t.Fatal(err)
	}
	report, err := run(root, casePath)
	if err != nil {
		t.Fatal(err)
	}
	if !report.Passed || len(report.Cases) != 1 || len(report.Cases[0].Steps) != 3 {
		t.Fatalf("regression report=%#v", report)
	}
}

func TestRegressionValidatesGeneratedPreeditInsteadOfOrdinaryCandidates(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"工程\tab\t500", "进度\tcd\t400", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", dictionary, filepath.Join(root, "variable.yidx")); err != nil {
		t.Fatal(err)
	}
	cases := caseFile{SchemaVersion: caseSchemaVersion, Cases: []regressionCase{{
		ID: "generated-preedit", Mode: "variable", Steps: []step{{
			Input: "abcd", ExpectedTop: "工程进度", ExpectedExact: true,
			RequiredPath: []string{"工程", "进度"},
		}},
	}}}
	data, err := json.Marshal(cases)
	if err != nil {
		t.Fatal(err)
	}
	casePath := filepath.Join(root, "cases.json")
	if err := os.WriteFile(casePath, data, 0o600); err != nil {
		t.Fatal(err)
	}
	report, err := run(root, casePath)
	if err != nil {
		t.Fatal(err)
	}
	if !report.Passed || report.Cases[0].Steps[0].ActualTop != "工程进度" {
		t.Fatalf("generated preedit regression report=%#v", report)
	}
}

func TestRegressionValidatesRunnerUpAndMinimumMargin(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"这个是\tab\t1016", "这个事\tab\t1000", "什么\tcd\t500", "问题\tef\t500", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", dictionary, filepath.Join(root, "variable.yidx")); err != nil {
		t.Fatal(err)
	}
	casePath := filepath.Join(root, "cases.json")
	writeCases := func(minimumMargin int64) report {
		t.Helper()
		cases := caseFile{SchemaVersion: caseSchemaVersion, Cases: []regressionCase{{
			ID: "margin", Mode: "variable", Steps: []step{{
				Input: "abcdef", ExpectedTop: "这个是什么问题", ExpectedExact: true,
				ExpectedRunnerUp: "这个事什么问题", MinimumMargin: minimumMargin,
			}},
		}}}
		data, err := json.Marshal(cases)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(casePath, data, 0o600); err != nil {
			t.Fatal(err)
		}
		result, err := run(root, casePath)
		if err != nil {
			t.Fatal(err)
		}
		return result
	}

	passing := writeCases(16)
	step := passing.Cases[0].Steps[0]
	if !passing.Passed || step.ActualRunnerUp != "这个事什么问题" || step.ActualMargin != 16 {
		t.Fatalf("passing margin report=%#v", passing)
	}
	if failing := writeCases(17); failing.Passed {
		t.Fatalf("margin regression should fail: %#v", failing)
	}
}
