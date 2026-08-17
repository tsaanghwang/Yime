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
	soundProjection := flag.String("sound-projection", "", "erhua sound-unit to key-class projection bundle")
	layout := flag.String("layout", "", "canonical Yinyuan-ID to physical-key layout")
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
	if *soundProjection != "" {
		config.SoundProjectionPath = *soundProjection
	}
	if *layout != "" {
		config.LayoutPath = *layout
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
