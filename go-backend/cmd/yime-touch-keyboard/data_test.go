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
