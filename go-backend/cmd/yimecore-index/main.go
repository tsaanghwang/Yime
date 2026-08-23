// Command yimecore-index builds and verifies one E1 compact index. The caller
// must explicitly constrain both source and output roots.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const toolVersion = "yimecore-index-e1-v1"

type manifest struct {
	ToolVersion   string                    `json:"tool_version"`
	GeneratedAt   string                    `json:"generated_at"`
	Build         yimecore.IndexBuildResult `json:"build"`
	Verified      bool                      `json:"verified"`
	OpenElapsedNS int64                     `json:"open_elapsed_ns"`
}

func main() {
	mode := flag.String("mode", "", "codemode: full, variable or shorthand")
	source := flag.String("source", "", "source Rime dictionary")
	output := flag.String("output", "", "output .yidx path")
	manifestPath := flag.String("manifest", "", "output build manifest path")
	allowedSourceRoot := flag.String("allowed-source-root", "", "required source root boundary")
	allowedOutputRoot := flag.String("allowed-output-root", "", "required output root boundary")
	flag.Parse()

	if !oneOf(*mode, "full", "variable", "shorthand") {
		fail(fmt.Errorf("mode must be full, variable or shorthand"))
	}
	for name, value := range map[string]string{
		"source": *source, "output": *output, "manifest": *manifestPath,
		"allowed-source-root": *allowedSourceRoot, "allowed-output-root": *allowedOutputRoot,
	} {
		if strings.TrimSpace(value) == "" {
			fail(fmt.Errorf("%s is required", name))
		}
	}
	if !within(*allowedSourceRoot, *source) {
		fail(fmt.Errorf("source escapes allowed root"))
	}
	if !within(*allowedOutputRoot, *output) || !within(*allowedOutputRoot, *manifestPath) {
		fail(fmt.Errorf("output escapes allowed root"))
	}
	if err := os.MkdirAll(filepath.Dir(*manifestPath), 0o755); err != nil {
		fail(err)
	}

	result, err := yimecore.BuildIndexFile(*mode, *source, *output)
	if err != nil {
		fail(err)
	}
	openedAt := time.Now()
	index, err := yimecore.OpenFileIndex(*output)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	openElapsed := time.Since(openedAt)
	verified := index.Mode() == *mode && index.RecordCount() == result.IndexedRecords
	report := manifest{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		Build: result, Verified: verified, OpenElapsedNS: openElapsed.Nanoseconds(),
	}
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		fail(err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(*manifestPath, data, 0o644); err != nil {
		fail(err)
	}
	fmt.Printf("YimeCore E1 index: mode=%s records=%d verified=%t sha256=%s\n", *mode, result.IndexedRecords, verified, result.IndexSHA256)
	if !verified {
		os.Exit(1)
	}
}

func within(root, path string) bool {
	absoluteRoot, err := filepath.Abs(root)
	if err != nil {
		return false
	}
	absolutePath, err := filepath.Abs(path)
	if err != nil {
		return false
	}
	relative, err := filepath.Rel(absoluteRoot, absolutePath)
	if err != nil {
		return false
	}
	return relative == "." || (relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)))
}

func oneOf(value string, choices ...string) bool {
	for _, choice := range choices {
		if value == choice {
			return true
		}
	}
	return false
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
