// Command yimecore-learning-experiment validates E3-A selection learning,
// persistence, forgetting and hot-path overhead against one immutable index.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

const toolVersion = "yimecore-learning-experiment-e3a-v1"

type latency struct {
	Samples   int   `json:"samples"`
	BatchSize int   `json:"batch_size"`
	P50NS     int64 `json:"p50_ns"`
	P95NS     int64 `json:"p95_ns"`
	P99NS     int64 `json:"p99_ns"`
	MaxNS     int64 `json:"max_ns"`
}

type report struct {
	ToolVersion         string                `json:"tool_version"`
	GeneratedAt         string                `json:"generated_at"`
	Mode                string                `json:"mode"`
	IndexPath           string                `json:"index_path"`
	IndexSourceID       string                `json:"index_source_id"`
	LearningCode        string                `json:"learning_code"`
	InitialCandidates   []engineapi.Candidate `json:"initial_candidates"`
	SelectedText        string                `json:"selected_text"`
	PromotedCandidates  []engineapi.Candidate `json:"promoted_candidates"`
	PersistedCandidates []engineapi.Candidate `json:"persisted_candidates"`
	ForgottenCandidates []engineapi.Candidate `json:"forgotten_candidates"`
	LearnedSnapshotPath string                `json:"learned_snapshot_path"`
	LearnedSnapshotSHA  string                `json:"learned_snapshot_sha256"`
	StaticLatency       latency               `json:"static_latency"`
	LearnedLatency      latency               `json:"learned_latency"`
	P95OverheadRatio    float64               `json:"p95_overhead_ratio"`
	P99OverheadRatio    float64               `json:"p99_overhead_ratio"`
	PromotionPassed     bool                  `json:"promotion_passed"`
	PersistencePassed   bool                  `json:"persistence_passed"`
	ForgetPassed        bool                  `json:"forget_passed"`
	LatencyGatePassed   bool                  `json:"latency_gate_passed"`
	Passed              bool                  `json:"passed"`
}

func main() {
	indexPath := flag.String("index", "", "validated compact index")
	mode := flag.String("mode", "", "full, variable or shorthand")
	output := flag.String("output", "", "evidence JSON path")
	modelPath := flag.String("model", "", "new primary user-model path")
	iterations := flag.Int("iterations", 1000, "latency samples")
	flag.Parse()
	if *indexPath == "" || *mode == "" || *output == "" || *modelPath == "" || *iterations < 10 {
		fail(fmt.Errorf("index, mode, output, model and at least 10 iterations are required"))
	}
	if _, err := os.Stat(*modelPath); !os.IsNotExist(err) {
		fail(fmt.Errorf("model path must not already exist: %s", *modelPath))
	}

	index, err := yimecore.OpenFileIndex(*indexPath)
	if err != nil {
		fail(err)
	}
	defer index.Close()
	if index.Mode() != *mode {
		fail(fmt.Errorf("index mode %s does not match %s", index.Mode(), *mode))
	}
	code := "bj"
	if *mode == "full" {
		code = "bjjj"
	}
	model, err := yimecore.OpenUserModel(*modelPath, index.SourceID())
	if err != nil {
		fail(err)
	}
	engine, err := yimecore.NewFileEngineWithUserModel(index, 9, model)
	if err != nil {
		fail(err)
	}
	initial := applyCode(engine, code)
	if len(initial) < 2 {
		fail(fmt.Errorf("learning probe %q has fewer than two candidates", code))
	}
	staticTop := initial[0].Text
	target := initial[1]
	if _, err := engine.Select(target.ID); err != nil {
		fail(err)
	}
	promoted := applyCode(engine, code)
	promotionPassed := len(promoted) > 0 && promoted[0].Text == target.Text && promoted[0].Score.User > 0
	if err := model.Save(); err != nil {
		fail(err)
	}
	learnedSnapshot := filepath.Join(filepath.Dir(*modelPath), *mode+"-learned-backup.json")
	if err := model.SaveTo(learnedSnapshot); err != nil {
		fail(err)
	}
	reopened, err := yimecore.OpenUserModel(*modelPath, index.SourceID())
	if err != nil {
		fail(err)
	}
	persistedEngine, err := yimecore.NewFileEngineWithUserModel(index, 9, reopened)
	if err != nil {
		fail(err)
	}
	persisted := applyCode(persistedEngine, code)
	persistencePassed := len(persisted) > 0 && persisted[0].Text == target.Text && persisted[0].Score.User > 0
	if !reopened.Forget(code, target.Text) {
		fail(fmt.Errorf("learned candidate could not be forgotten"))
	}
	persistedEngine.Reset()
	forgotten := applyCode(persistedEngine, code)
	forgetPassed := len(forgotten) > 0 && forgotten[0].Text == staticTop && forgotten[0].Score.User == 0
	if err := reopened.Save(); err != nil {
		fail(err)
	}

	staticEngine, err := yimecore.NewFileEngine(index, 9)
	if err != nil {
		fail(err)
	}
	learnedModel, err := yimecore.OpenUserModel(learnedSnapshot, index.SourceID())
	if err != nil {
		fail(err)
	}
	learnedEngine, err := yimecore.NewFileEngineWithUserModel(index, 9, learnedModel)
	if err != nil {
		fail(err)
	}
	staticLatency := measure(staticEngine, code, *iterations)
	learnedLatency := measure(learnedEngine, code, *iterations)
	p95Ratio := float64(learnedLatency.P95NS) / float64(staticLatency.P95NS)
	p99Ratio := float64(learnedLatency.P99NS) / float64(staticLatency.P99NS)
	latencyPassed := p95Ratio <= 1.10 && p99Ratio <= 1.20
	snapshotHash := hashFile(learnedSnapshot)
	result := report{
		ToolVersion: toolVersion, GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano), Mode: *mode,
		IndexPath: filepath.Clean(*indexPath), IndexSourceID: index.SourceID(), LearningCode: code,
		InitialCandidates: initial, SelectedText: target.Text, PromotedCandidates: promoted,
		PersistedCandidates: persisted, ForgottenCandidates: forgotten,
		LearnedSnapshotPath: filepath.Clean(learnedSnapshot), LearnedSnapshotSHA: snapshotHash,
		StaticLatency: staticLatency, LearnedLatency: learnedLatency,
		P95OverheadRatio: p95Ratio, P99OverheadRatio: p99Ratio,
		PromotionPassed: promotionPassed, PersistencePassed: persistencePassed,
		ForgetPassed: forgetPassed, LatencyGatePassed: latencyPassed,
	}
	result.Passed = result.PromotionPassed && result.PersistencePassed && result.ForgetPassed && result.LatencyGatePassed
	writeJSON(*output, result)
	fmt.Printf("YimeCore E3-A learning: mode=%s selected=%s passed=%t p95_ratio=%.3f\n", *mode, target.Text, result.Passed, p95Ratio)
	if !result.Passed {
		os.Exit(1)
	}
}

func applyCode(engine *yimecore.Engine, code string) []engineapi.Candidate {
	engine.Reset()
	var result engineapi.Result
	for _, key := range code {
		var err error
		result, err = engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
		if err != nil {
			fail(err)
		}
	}
	return result.State.Candidates
}

func measure(engine *yimecore.Engine, code string, iterations int) latency {
	const batchSize = 100
	values := make([]time.Duration, 0, iterations)
	for i := 0; i < iterations; i++ {
		started := time.Now()
		for batch := 0; batch < batchSize; batch++ {
			_ = applyCode(engine, code)
		}
		values = append(values, time.Since(started)/batchSize)
	}
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	return latency{Samples: len(values), BatchSize: batchSize, P50NS: percentile(values, 50).Nanoseconds(), P95NS: percentile(values, 95).Nanoseconds(), P99NS: percentile(values, 99).Nanoseconds(), MaxNS: values[len(values)-1].Nanoseconds()}
}

func percentile(values []time.Duration, percent int) time.Duration {
	position := (len(values)*percent + 99) / 100
	if position < 1 {
		position = 1
	}
	return values[position-1]
}

func hashFile(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		fail(err)
	}
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

func writeJSON(path string, value any) {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fail(err)
	}
	data = append(data, '\n')
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fail(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
