package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDataCheckCannotOpenWindowOrUseImplicitData(t *testing.T) {
	for _, o := range []options{
		{CheckData: true},
		{CheckData: true, DataDir: "unused", Smoke: true},
		{CheckData: true, DataDir: "unused", Shot: "unused.png"},
		{DataDir: "unused"},
		{Preview: true},
		{Preview: true, DataDir: "unused", CheckData: true},
		{Preview: true, DataDir: "unused", Smoke: true},
		{Preview: true, DataDir: "unused", DataReport: "unused.json"},
		{Host: true},
		{HostSmoke: true},
		{Host: true, DataDir: "unused", Preview: true},
		{Host: true, DataDir: "unused", CheckData: true},
		{Host: true, DataDir: "unused", Smoke: true},
		{Host: true, DataDir: "unused", Shot: "unused.png"},
	} {
		if err := execute(o); err == nil {
			t.Fatal("ambiguous data/UI invocation accepted")
		}
	}
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	report := filepath.Join(dir, "report.json")
	err = execute(options{Root: root, Zones: "none", Gutters: true, CheckData: true, DataDir: dir, DataReport: report})
	if err == nil || !strings.Contains(err.Error(), "read experimental manifest") {
		t.Fatalf("missing data: %v", err)
	}
	if _, err := os.Stat(report); !os.IsNotExist(err) {
		t.Fatal("failed check emitted success report")
	}
}
