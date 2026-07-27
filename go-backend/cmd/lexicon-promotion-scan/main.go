package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/lexiconpromotion"
)

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared Rime data directory")
	userDir := flag.String("UserDir", "", "Yime Rime user data directory")
	schemaID := flag.String("SchemaID", "yime_variable", "active Yime schema id")
	minCommits := flag.Int("MinCommits", 3, "minimum learned commits")
	maxCandidates := flag.Int("MaxCandidates", 5000, "maximum candidates in report")
	openReport := flag.Bool("OpenReport", true, "show the generated report in Explorer on Windows")
	flag.Parse()
	if *sharedDir == "" || *userDir == "" {
		fmt.Fprintln(os.Stderr, "missing -SharedDir or -UserDir")
		os.Exit(2)
	}
	config := lexiconpromotion.DefaultConfig(*sharedDir, *userDir, *schemaID)
	config.MinCommits = *minCommits
	config.MaxCandidates = *maxCandidates
	result, err := lexiconpromotion.Scan(config, time.Now())
	if err != nil {
		fmt.Fprintln(os.Stderr, "scan learned lexicon:", err)
		os.Exit(1)
	}
	fmt.Printf("candidates=%d learned=%d existing=%d\njson=%s\ntsv=%s\n",
		result.Report.Summary.PromotionCandidates,
		result.Report.Summary.LearnedRecords,
		result.Report.Summary.AlreadyInSystem,
		result.JSONPath,
		result.TSVPath,
	)
	if *openReport && runtime.GOOS == "windows" {
		_ = exec.Command("explorer.exe", "/select,"+result.JSONPath).Start()
	}
}
