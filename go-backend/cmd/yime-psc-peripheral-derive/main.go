package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
)

func main() {
	repoRoot := flag.String("repo-root", "..", "Yime repository root")
	catalog := flag.String("catalog", "", "reviewed PSC candidate catalog or filtered source snapshot")
	codes := flag.String("codes", "", "formal Pinyin-to-full-code TSV")
	dataDir := flag.String("data-dir", "", "curated core three-mode dictionary directory")
	source := flag.String("source-output", "", "filtered checked source snapshot")
	outputDir := flag.String("output-dir", "", "generated runtime dictionary directory")
	flag.Parse()

	root, err := filepath.Abs(*repoRoot)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	config := connectedspeech.DefaultPSCPeripheralRuntimeConfig(root)
	if *catalog != "" {
		config.CatalogPath = *catalog
	}
	if *codes != "" {
		config.CodesPath = *codes
	}
	if *dataDir != "" {
		config.DataDir = *dataDir
	}
	if *source != "" {
		config.SourcePath = *source
	}
	if *outputDir != "" {
		config.OutputDir = *outputDir
	}
	result, err := connectedspeech.RunPSCPeripheralRuntime(config)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	encoded, _ := json.MarshalIndent(result.Summary, "", "  ")
	fmt.Println(string(encoded))
}
