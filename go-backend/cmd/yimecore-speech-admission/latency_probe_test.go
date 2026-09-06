package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

type latencyProbeSample struct {
	Mode       string `json:"mode"`
	Variant    string `json:"variant"`
	Round      int    `json:"round"`
	ReviewID   string `json:"review_id"`
	Route      string `json:"route"`
	CodeLength int    `json:"code_length"`
	PrefixLen  int    `json:"prefix_length"`
	ElapsedNS  int64  `json:"elapsed_ns"`
}

// Read-only cache-shape introspection identifies the slow lookup without
// logging its prefix, candidate text, candidate IDs or input code.
func TestSpeechLatencyFixedCoreCacheShape(t *testing.T) {
	root, output := os.Getenv("YIME_SPEECH_LATENCY_ROOT"), os.Getenv("YIME_SPEECH_LATENCY_OUTPUT")
	if root == "" && output == "" {
		t.Skip("explicit private diagnostic only")
	}
	if root == "" || output == "" {
		t.Fatal("explicit private diagnostic paths required")
	}
	if err := speechruntime.IsTrialRoot(root); err != nil {
		t.Fatal(err)
	}
	indexPath, err := speechruntime.Child(root, "indexes/full-core.yidx")
	if err != nil {
		t.Fatal(err)
	}
	index, err := yimecore.OpenResidentFileIndex(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	defer index.Close()
	recordPath, err := speechruntime.Child(root, "admitted-records.json")
	if err != nil {
		t.Fatal(err)
	}
	var records connectedspeech.AdmissionResult
	if err := readJSON(recordPath, &records); err != nil {
		t.Fatal(err)
	}
	code := ""
	for _, record := range records.Records {
		if record.ReviewID == "T3-5B-003" {
			code = record.Codes["full"].Alias
		}
	}
	if len(code) != 8 {
		t.Fatal("fixed diagnostic record missing")
	}
	engine, err := yimecore.NewFileEngine(index, 5)
	if err != nil {
		t.Fatal(err)
	}
	cache := reflect.ValueOf(index).Elem().FieldByName("prefixCache")
	before := map[string]bool{}
	for _, key := range []rune(code)[:7] {
		if _, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)}); err != nil {
			t.Fatal("fixed prefix input failed")
		}
	}
	cacheKey := func(key reflect.Value) string {
		return key.FieldByName("prefix").String() + fmt.Sprint(key.FieldByName("limit").Int())
	}
	for _, key := range cache.MapKeys() {
		before[cacheKey(key)] = true
	}
	started := time.Now()
	if _, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string([]rune(code)[7])}); err != nil {
		t.Fatal("fixed last key failed")
	}
	elapsed := time.Since(started)
	var rows []map[string]int
	for _, key := range cache.MapKeys() {
		if before[cacheKey(key)] {
			continue
		}
		value := cache.MapIndex(key)
		single := 0
		for i := 0; i < value.Len(); i++ {
			if utf8.RuneCountInString(value.Index(i).FieldByName("text").String()) == 1 {
				single++
			}
		}
		rows = append(rows, map[string]int{"prefix_length": len(key.FieldByName("prefix").String()), "fetch_limit": int(key.FieldByName("limit").Int()), "returned_records": value.Len(), "single_character_records": single})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i]["prefix_length"] != rows[j]["prefix_length"] {
			return rows[i]["prefix_length"] < rows[j]["prefix_length"]
		}
		return rows[i]["fetch_limit"] < rows[j]["fetch_limit"]
	})
	result := map[string]any{"measurement_completed": true, "acceptance_inferred": false, "review_id": "T3-5B-003", "mode": "full", "route": "alias", "prefix_length": 8, "elapsed_ns": elapsed.Nanoseconds(), "new_cache_entries": rows}
	if err := writeNew(output, result); err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(result)
	t.Log(string(data))
}

type latencyProbeSummary struct {
	Mode      string  `json:"mode"`
	Variant   string  `json:"variant"`
	Round     int     `json:"round"`
	Samples   int     `json:"samples"`
	P50MS     float64 `json:"p50_ms"`
	MaximumMS float64 `json:"maximum_ms"`
	Over50MS  int     `json:"over_50_ms"`
	MaxReview string  `json:"max_review_id"`
	MaxRoute  string  `json:"max_route"`
	MaxPrefix int     `json:"max_prefix_length"`
}

// TestSpeechLatencyProbe is an explicit, read-only diagnostic over a prepared
// private trial. Its completion is not acceptance: actual >50ms observations
// are retained and reported without changing the Broker deadline or engine.
// No process, Rime session, installed state, text or code logging is involved.
func TestSpeechLatencyProbe(t *testing.T) {
	root, output := os.Getenv("YIME_SPEECH_LATENCY_ROOT"), os.Getenv("YIME_SPEECH_LATENCY_OUTPUT")
	if root == "" && output == "" {
		t.Skip("explicit private latency diagnostic only")
	}
	if root == "" || output == "" {
		t.Fatal("both explicit private diagnostic paths are required")
	}
	if err := speechruntime.IsTrialRoot(root); err != nil {
		t.Fatal(err)
	}
	manifestPath, err := speechruntime.Child(root, "bundle-off.json")
	if err != nil {
		t.Fatal(err)
	}
	manifestHash, err := speechruntime.HashFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := speechruntime.Load(root, "bundle-off.json", manifestHash)
	if err != nil {
		t.Fatal(err)
	}
	if manifest.Enabled {
		t.Fatal("diagnostic requires core-only manifest")
	}
	recordPath, err := speechruntime.Child(root, "admitted-records.json")
	if err != nil {
		t.Fatal(err)
	}
	var records connectedspeech.AdmissionResult
	if err := readJSON(recordPath, &records); err != nil {
		t.Fatal(err)
	}
	if len(records.Records) != 24 {
		t.Fatal("expected exactly 24 approved diagnostic records")
	}
	var samples []latencyProbeSample
	var summaries []latencyProbeSummary
	for round := 1; round <= 2; round++ {
		variants := []string{"file", "bundle-core-only", "file-empty-model", "bundle-core-only-empty-model"}
		if round == 2 {
			variants = []string{"bundle-core-only-empty-model", "file-empty-model", "bundle-core-only", "file"}
		}
		for _, mode := range []string{"full", "variable", "shorthand"} {
			for _, variant := range variants {
				indexPath := manifest.Generation.Modes[mode].Core.Path
				if got, err := speechruntime.HashFile(indexPath); err != nil || got != manifest.Generation.Modes[mode].Core.ExpectedSHA256 {
					t.Fatal("private core index hash mismatch")
				}
				index, err := yimecore.OpenResidentFileIndex(indexPath)
				if err != nil {
					t.Fatal(err)
				}
				var engine *yimecore.Engine
				model, err := yimecore.NewUserModel("isolated-latency-probe")
				if err != nil {
					index.Close()
					t.Fatal(err)
				}
				if variant == "file" {
					engine, err = yimecore.NewFileEngine(index, 5)
				} else if variant == "file-empty-model" {
					engine, err = yimecore.NewFileEngineWithUserModel(index, 5, model)
				} else {
					bundle, bundleErr := yimecore.NewBundleIndex(index, nil)
					if bundleErr != nil {
						index.Close()
						t.Fatal(bundleErr)
					}
					if variant == "bundle-core-only" {
						engine, err = yimecore.NewBundleEngine(bundle, 5)
					} else {
						engine, err = yimecore.NewBundleEngineWithUserModel(bundle, 5, model)
					}
				}
				if err != nil {
					index.Close()
					t.Fatal(err)
				}
				start := len(samples)
				for _, record := range records.Records {
					for _, route := range []string{"canonical", "alias"} {
						code := record.Codes[mode].Canonical
						if route == "alias" {
							code = record.Codes[mode].Alias
						}
						engine.Reset()
						for prefix, key := range []rune(code) {
							started := time.Now()
							result, err := engine.Apply(engineapi.Event{Operation: engineapi.AppendCode, Code: string(key)})
							elapsed := time.Since(started)
							if err != nil || result.Commit != "" {
								index.Close()
								t.Fatal("diagnostic append failed or committed")
							}
							samples = append(samples, latencyProbeSample{mode, variant, round, record.ReviewID, route, len([]rune(code)), prefix + 1, elapsed.Nanoseconds()})
						}
					}
				}
				if err := index.Close(); err != nil {
					t.Fatal(err)
				}
				measured := samples[start:]
				durations := make([]int64, len(measured))
				summary := latencyProbeSummary{Mode: mode, Variant: variant, Round: round, Samples: len(measured)}
				var maximum int64
				for i, sample := range measured {
					durations[i] = sample.ElapsedNS
					if sample.ElapsedNS > int64(50*time.Millisecond) {
						summary.Over50MS++
					}
					if sample.ElapsedNS > maximum {
						maximum = sample.ElapsedNS
						summary.MaxReview, summary.MaxRoute, summary.MaxPrefix = sample.ReviewID, sample.Route, sample.PrefixLen
					}
				}
				sort.Slice(durations, func(i, j int) bool { return durations[i] < durations[j] })
				summary.P50MS, summary.MaximumMS = float64(durations[len(durations)/2])/1e6, float64(maximum)/1e6
				summaries = append(summaries, summary)
				encoded, _ := json.Marshal(summary)
				t.Log(string(encoded))
			}
		}
	}
	if !filepath.IsAbs(output) {
		t.Fatal("absolute diagnostic output required")
	}
	if err := speechruntime.PlainPath(output); err != nil {
		t.Fatal(err)
	}
	if err := writeNew(output, map[string]any{"schema_version": "speech-latency-probe-v1", "measurement_completed": true, "acceptance_inferred": false, "module_enabled": false, "broker_deadline_ms_unchanged": 50, "manifest_sha256": manifestHash, "summaries": summaries, "samples": samples}); err != nil {
		t.Fatal(err)
	}
	t.Log(fmt.Sprintf("measurement only: %d metadata samples", len(samples)))
}
