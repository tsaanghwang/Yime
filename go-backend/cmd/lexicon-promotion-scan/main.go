package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/learningmanager"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/lexiconpromotion"
)

type trialRuntimeStatus struct {
	IndexVersion string `json:"index_version"`
}

type trialPromotionReport struct {
	SchemaVersion string                      `json:"schema_version"`
	GeneratedAt   string                      `json:"generated_at"`
	IndexVersion  string                      `json:"index_version"`
	Mode          string                      `json:"mode"`
	Minimum       uint64                      `json:"minimum_selections"`
	Candidates    []learningmanager.Promotion `json:"candidates"`
}

func main() {
	sharedDir := flag.String("SharedDir", "", "Yime shared Rime data directory")
	userDir := flag.String("UserDir", "", "Yime Rime user data directory")
	schemaID := flag.String("SchemaID", "yime_variable", "active Yime schema id")
	minCommits := flag.Int("MinCommits", 3, "minimum learned commits")
	maxCandidates := flag.Int("MaxCandidates", 5000, "maximum candidates in report")
	openReport := flag.Bool("OpenReport", true, "show the generated report in Explorer on Windows")
	installRoot := flag.String("InstallRoot", "", "YimeCore Trial package root")
	indexRoot := flag.String("IndexRoot", "", "YimeCore Trial index root")
	mode := flag.String("Mode", "variable", "YimeCore Trial mode")
	experimental := flag.Bool("Experimental", false, "scan independent YimeCore Trial learning")
	flag.Parse()
	if *experimental {
		jsonPath, tsvPath, count, err := scanTrial(*installRoot, *userDir, *indexRoot, *mode, *minCommits, *maxCandidates, time.Now())
		if err != nil {
			fmt.Fprintln(os.Stderr, "scan Trial learned lexicon:", err)
			os.Exit(1)
		}
		fmt.Printf("candidates=%d\njson=%s\ntsv=%s\n", count, jsonPath, tsvPath)
		if *openReport && runtime.GOOS == "windows" {
			_ = exec.Command("explorer.exe", "/select,"+jsonPath).Start()
		}
		return
	}
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

func scanTrial(installRoot, stateRoot, indexRoot, mode string, minimum, maximum int, now time.Time) (jsonPath, tsvPath string, count int, resultErr error) {
	if strings.TrimSpace(installRoot) == "" || strings.TrimSpace(stateRoot) == "" || strings.TrimSpace(indexRoot) == "" {
		return "", "", 0, fmt.Errorf("missing -InstallRoot, -UserDir or -IndexRoot")
	}
	if mode != "full" && mode != "variable" && mode != "shorthand" {
		return "", "", 0, fmt.Errorf("unsupported Trial mode %q", mode)
	}
	if minimum < 1 || maximum < 1 {
		return "", "", 0, fmt.Errorf("minimum commits and maximum candidates must be positive")
	}
	statusData, err := os.ReadFile(filepath.Join(stateRoot, "runtime-status.json"))
	if err != nil {
		return "", "", 0, err
	}
	var status trialRuntimeStatus
	if err := json.Unmarshal(statusData, &status); err != nil {
		return "", "", 0, err
	}
	if strings.TrimSpace(status.IndexVersion) == "" {
		return "", "", 0, fmt.Errorf("Trial runtime status lacks index version")
	}
	runtimePath := filepath.Join(installRoot, "bin", "YimeCoreTrialRuntime.exe")
	runtimeArgs := []string{"-install-root", installRoot, "-state-root", stateRoot}
	stop := exec.Command(runtimePath, append(runtimeArgs, "-stop")...)
	if output, err := stop.CombinedOutput(); err != nil {
		return "", "", 0, fmt.Errorf("stop Trial runtime: %w: %s", err, strings.TrimSpace(string(output)))
	}
	defer func() {
		command := exec.Command(runtimePath, runtimeArgs...)
		if err := command.Start(); err == nil {
			_ = command.Process.Release()
		} else if resultErr == nil {
			resultErr = fmt.Errorf("restart Trial runtime: %w", err)
		}
	}()
	candidates, err := learningmanager.ScanStopped(stateRoot, status.IndexVersion, filepath.Join(indexRoot, mode+".yidx"), uint64(minimum))
	if err != nil {
		return "", "", 0, err
	}
	if len(candidates) > maximum {
		candidates = candidates[:maximum]
	}
	reportRoot := filepath.Join(stateRoot, "reports", "promotion")
	if err := os.MkdirAll(reportRoot, 0o700); err != nil {
		return "", "", 0, err
	}
	base := "promotion-" + now.UTC().Format("20060102T150405Z") + "-" + mode
	jsonPath = filepath.Join(reportRoot, base+".json")
	tsvPath = filepath.Join(reportRoot, base+".tsv")
	report := trialPromotionReport{SchemaVersion: "yimecore-trial-promotion-v1", GeneratedAt: now.UTC().Format(time.RFC3339Nano),
		IndexVersion: status.IndexVersion, Mode: mode, Minimum: uint64(minimum), Candidates: candidates}
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return "", "", 0, err
	}
	if err := os.WriteFile(jsonPath, append(data, '\n'), 0o600); err != nil {
		return "", "", 0, err
	}
	var tsv strings.Builder
	tsv.WriteString("词语\t编码\t自学次数\n")
	for _, candidate := range candidates {
		fmt.Fprintf(&tsv, "%s\t%s\t%d\n", candidate.Text, candidate.Code, candidate.Selections)
	}
	if err := os.WriteFile(tsvPath, []byte(tsv.String()), 0o600); err != nil {
		return "", "", 0, err
	}
	return jsonPath, tsvPath, len(candidates), nil
}
