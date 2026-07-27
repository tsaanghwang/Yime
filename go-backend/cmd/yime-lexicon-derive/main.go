package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

func main() {
	input := flag.String("input", "", "canonical fixed-length Rime dict.yaml")
	outputDir := flag.String("output-dir", "", "directory for generated runtime dictionaries")
	coreTrial := flag.Bool(
		"core-trial",
		false,
		"derive only the isolated yime_core_trial variable dictionary",
	)
	flag.Parse()
	if *input == "" {
		fmt.Fprintln(os.Stderr, "missing required -input fixed-length dict.yaml")
		os.Exit(2)
	}
	if *outputDir == "" {
		*outputDir = filepath.Dir(*input)
	}
	var manifest systemlexicon.Manifest
	var err error
	if *coreTrial {
		manifest, err = systemlexicon.DeriveCoreTrialFromFullDictionary(*input, *outputDir)
	} else {
		manifest, err = systemlexicon.DeriveFromFullDictionary(*input, *outputDir)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "derive Yime lexicons:", err)
		os.Exit(1)
	}
	fmt.Printf("generated %d entries from %s\n", manifest.EntryCount, manifest.SourceSHA256)
	fmt.Printf("output: %s\n", *outputDir)
}
