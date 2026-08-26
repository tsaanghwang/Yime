// Command yimecore-explain emits a host-neutral, machine-readable explanation
// of one YimeCore decode. It never starts TSF or a candidate window.
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

const toolVersion = "yimecore-explain-v1"

type report struct {
	ToolVersion   string               `json:"tool_version"`
	GeneratedAt   string               `json:"generated_at"`
	IndexPath     string               `json:"index_path"`
	IndexMode     string               `json:"index_mode"`
	RequestedPage int                  `json:"requested_page"`
	PageNumber    int                  `json:"page_number"`
	HasPrevious   bool                 `json:"has_previous"`
	HasNext       bool                 `json:"has_next"`
	Trace         yimecore.DecodeTrace `json:"trace"`
}

func main() {
	indexPath := flag.String("index", "", "validated compact .yidx index")
	input := flag.String("input", "", "raw Yime key code; spaces are ignored")
	page := flag.Int("page", 0, "zero-based candidate page to explain")
	output := flag.String("output", "", "optional output JSON; stdout when omitted")
	flag.Parse()
	if err := run(*indexPath, *input, *page, *output); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(indexPath, input string, page int, output string) error {
	if strings.TrimSpace(indexPath) == "" || strings.TrimSpace(input) == "" {
		return errors.New("index and input are required")
	}
	if page < 0 {
		return errors.New("page must not be negative")
	}
	index, err := yimecore.OpenFileIndex(indexPath)
	if err != nil {
		return err
	}
	defer index.Close()
	engine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		return err
	}
	var state engineapi.State
	for _, key := range strings.ReplaceAll(input, " ", "") {
		result, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			return fmt.Errorf("apply input key %q: %w", key, err)
		}
		state = result.State
	}
	for current := 0; current < page; current++ {
		if !state.HasNext {
			return fmt.Errorf("candidate page %d does not exist", page)
		}
		result, err := engine.Apply(engineapi.Event{Operation: engineapi.PageNext})
		if err != nil {
			return fmt.Errorf("open candidate page %d: %w", current+1, err)
		}
		state = result.State
	}
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		IndexPath: filepath.Clean(indexPath), IndexMode: index.Mode(),
		RequestedPage: page, PageNumber: state.PageNumber,
		HasPrevious: state.HasPrevious, HasNext: state.HasNext,
		Trace: engine.Explain(),
	}
	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if output == "" {
		_, err = os.Stdout.Write(data)
		return err
	}
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	return os.WriteFile(output, data, 0o644)
}
