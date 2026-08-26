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
		"本\ta\t100", "地\tb\t100", "人\tc\t100",
		"本地\tab\t500", "本地人\tabc\t800", "",
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
			{Input: "abc", ExpectedTop: "本地人", ExpectedExact: true, RequiredEdge: "本地人", RequiredPath: []string{"本地", "人"}},
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
	if !report.Passed || len(report.Cases) != 1 || len(report.Cases[0].Steps) != 2 {
		t.Fatalf("regression report=%#v", report)
	}
}
