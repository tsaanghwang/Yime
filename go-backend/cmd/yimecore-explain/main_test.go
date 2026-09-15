package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func TestExplainCommandUsesRealCompactIndexWithoutAHostUI(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "fixture.dict.yaml")
	indexPath := filepath.Join(root, "fixture.yidx")
	output := filepath.Join(root, "trace.json")
	content := strings.Join([]string{
		"---", "name: fixture", "version: \"1\"", "sort: by_weight", "...",
		"本\ta\t100", "地\tb\t100", "人\tc\t100",
		"本地\tab\t500", "本地人\tabc\t800", "",
	}, "\n")
	if err := os.WriteFile(dictionary, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", dictionary, indexPath); err != nil {
		t.Fatal(err)
	}
	if err := run(indexPath, "a b c", 0, output); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, expected := range []string{`"tool_version": "yimecore-explain-v1"`, `"text": "本地人"`, `"text": "本地"`, `"index_mode": "variable"`} {
		if !strings.Contains(text, expected) {
			t.Fatalf("trace lacks %s:\n%s", expected, text)
		}
	}
}

func TestExplainCommandCanInspectLaterCandidatePages(t *testing.T) {
	root := t.TempDir()
	dictionary := filepath.Join(root, "paged.dict.yaml")
	indexPath := filepath.Join(root, "paged.yidx")
	output := filepath.Join(root, "page-one.json")
	var content strings.Builder
	content.WriteString("---\nname: paged\nversion: \"1\"\nsort: by_weight\n...\n")
	for i := 0; i < 12; i++ {
		content.WriteString("同码")
		content.WriteRune(rune('A' + i))
		content.WriteString("\ta\t")
		content.WriteString(string(rune('9' - i%9)))
		content.WriteByte('\n')
	}
	content.WriteString("预测\tab\t999\n")
	if err := os.WriteFile(dictionary, []byte(content.String()), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := yimecore.BuildIndexFile("variable", dictionary, indexPath); err != nil {
		t.Fatal(err)
	}
	if err := run(indexPath, "a", 1, output); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, expected := range []string{`"requested_page": 1`, `"page_number": 1`, `"has_previous": true`} {
		if !strings.Contains(text, expected) {
			t.Fatalf("paged trace lacks %s:\n%s", expected, text)
		}
	}
}
