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
	dataDir := flag.String("data-dir", "", "baseline three-mode dictionary directory")
	aliases := flag.String("aliases", "", "explicit erhua alias bundle")
	annotations := flag.String("annotations", "", "explicit erhua annotation bundle")
	outputDir := flag.String("output-dir", "", "generated runtime dictionary directory")
	flag.Parse()

	root, err := filepath.Abs(*repoRoot)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	config := connectedspeech.DefaultErhuaMixedRuntimeConfig(root)
	if *dataDir != "" {
		config.DataDir = *dataDir
	}
	if *aliases != "" {
		config.AliasesPath = *aliases
	}
	if *annotations != "" {
		config.AnnotationsPath = *annotations
	}
	if *outputDir != "" {
		config.OutputDir = *outputDir
	}
	result, err := connectedspeech.RunErhuaMixedRuntime(config)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	encoded, _ := json.MarshalIndent(result.Summary, "", "  ")
	fmt.Println(string(encoded))
}
