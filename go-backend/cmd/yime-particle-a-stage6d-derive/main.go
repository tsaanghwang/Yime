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
	repoRoot := flag.String("repo-root", "", "Yime repository root")
	outputDir := flag.String("output-dir", "", "runtime Rime data output directory")
	dataDir := flag.String("data-dir", "", "source Rime data directory")
	flag.Parse()
	root := *repoRoot
	if root == "" {
		cwd, err := os.Getwd()
		if err != nil {
			fatal(err)
		}
		root = filepath.Clean(filepath.Join(cwd, ".."))
	}
	config := connectedspeech.DefaultParticleAStage6DConfig(root)
	if *outputDir != "" {
		config.OutputDir = *outputDir
	}
	if *dataDir != "" {
		config.DataDir = *dataDir
	}
	manifest, err := connectedspeech.RunParticleAStage6DRuntime(config)
	if err != nil {
		fatal(err)
	}
	payload, _ := json.MarshalIndent(manifest.Summary, "", "  ")
	fmt.Println(string(payload))
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
