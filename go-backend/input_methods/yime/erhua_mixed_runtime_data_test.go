package yime

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

type bundledErhuaMixedManifest struct {
	ToolVersion  string            `json:"tool_version"`
	OutputSHA256 map[string]string `json:"output_sha256"`
	Summary      struct {
		ExplicitRecordCount        int             `json:"explicit_record_count"`
		DualRouteReadyCount        int             `json:"dual_route_ready_count"`
		PendingFusionCount         int             `json:"pending_fusion_count"`
		InheritedWeightRecordCount int             `json:"inherited_weight_record_count"`
		DeferredMissingWeightCount int             `json:"deferred_missing_weight_count"`
		RoutesPerMode              int             `json:"routes_per_mode"`
		RuntimeAliasRows           int             `json:"runtime_alias_rows"`
		Gates                      map[string]bool `json:"gates"`
		Passed                     bool            `json:"passed"`
	} `json:"summary"`
	Deferred []string `json:"deferred_missing_weight"`
}

type bundledErhuaEntry struct {
	Text   string
	Code   string
	Weight int
}

func TestBundledExplicitErhuaMixedOverlayIsCompleteAndReversible(t *testing.T) {
	var manifest bundledErhuaMixedManifest
	readJSONFile(t, "yime_erhua_mixed_manifest.json", &manifest)
	if manifest.ToolVersion != "explicit-erhua-mixed-runtime-v1" ||
		manifest.Summary.ExplicitRecordCount != 131 ||
		manifest.Summary.DualRouteReadyCount != 29 ||
		manifest.Summary.PendingFusionCount != 102 ||
		manifest.Summary.InheritedWeightRecordCount != 15 ||
		manifest.Summary.DeferredMissingWeightCount != 14 ||
		manifest.Summary.RoutesPerMode != 30 ||
		manifest.Summary.RuntimeAliasRows != 90 ||
		!manifest.Summary.Passed {
		t.Fatalf("unexpected explicit-erhua mixed manifest: %#v", manifest)
	}
	for gate, passed := range manifest.Summary.Gates {
		if !passed {
			t.Fatalf("explicit-erhua mixed gate failed: %s", gate)
		}
	}

	deferred := make(map[string]struct{}, len(manifest.Deferred))
	for _, text := range manifest.Deferred {
		deferred[text] = struct{}{}
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		overlayName := "yime_erhua_mixed_" + mode + ".dict.yaml"
		if got := fileSHA256(t, filepath.Join("data", overlayName)); got != manifest.OutputSHA256[overlayName] {
			t.Fatalf("%s hash mismatch: got=%s want=%s", overlayName, got, manifest.OutputSHA256[overlayName])
		}
		overlay := readBundledErhuaDictionary(t, filepath.Join("data", overlayName))
		if len(overlay) != 30 {
			t.Fatalf("%s must contain exactly 30 routes, got %d", overlayName, len(overlay))
		}
		coreWeights := readMaximumWeights(t, filepath.Join("data", "yime_"+mode+".dict.yaml"))
		routesByText := map[string]int{}
		for _, entry := range overlay {
			routesByText[entry.Text]++
			if entry.Text == "鸟儿" {
				t.Fatal("unannotated lookalike 鸟儿 must not be inferred into the mixed overlay")
			}
			if _, blocked := deferred[entry.Text]; blocked {
				t.Fatalf("deferred missing-weight record entered runtime: %s", entry.Text)
			}
			if coreWeights[entry.Text] != entry.Weight {
				t.Fatalf("%s/%s weight=%d does not inherit core weight=%d", mode, entry.Text, entry.Weight, coreWeights[entry.Text])
			}
		}
		if len(routesByText) != 15 {
			t.Fatalf("%s must contain 15 explicit texts, got %d", overlayName, len(routesByText))
		}
		for text, count := range routesByText {
			if count != 2 {
				t.Fatalf("%s/%s must have suffix and fused routes, got %d", mode, text, count)
			}
		}
		schema, err := os.ReadFile(filepath.Join("data", "yime_"+mode+".schema.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		for _, fragment := range []string{
			"version: \"2026-08-15-core-1166300-layout-6d00e609f689-rank-v1-erhua-mixed-v1\"",
			"- yime_erhua_mixed_" + mode,
			"- table_translator@erhua_mixed",
			"dictionary: yime_erhua_mixed_" + mode,
			"enable_user_dict: false",
			"enable_sentence: false",
		} {
			if !strings.Contains(string(schema), fragment) {
				t.Fatalf("%s schema lacks explicit-erhua overlay setting %q", mode, fragment)
			}
		}
		dependencySchema, err := os.ReadFile(filepath.Join("data", "yime_erhua_mixed_"+mode+".schema.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(dependencySchema), "dictionary: yime_erhua_mixed_"+mode) {
			t.Fatalf("%s dependency schema does not compile its overlay dictionary", mode)
		}
	}
}

func TestRuntimeProfileDeclaresExplicitErhuaMixedOverlay(t *testing.T) {
	var profile coreRuntimeProfile
	readJSONFile(t, "yime_runtime_profile.json", &profile)
	if !containsString(profile.CandidateLayers, "explicit_source_backed_erhua_mixed_overlay") {
		t.Fatal("runtime profile does not declare the explicit-erhua mixed candidate layer")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_erhua_mixed_" + mode + ".dict.yaml"
		if !containsString(profile.RuntimeDictionaries, name) {
			t.Fatalf("runtime profile lacks %s", name)
		}
	}
}

func readBundledErhuaDictionary(t *testing.T, path string) []bundledErhuaEntry {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	entries := []bundledErhuaEntry{}
	inData := false
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !inData {
			inData = strings.TrimSpace(line) == "..."
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 3 {
			continue
		}
		weight, parseErr := strconv.Atoi(fields[2])
		if parseErr != nil {
			t.Fatalf("invalid weight in %s: %q", path, fields[2])
		}
		entries = append(entries, bundledErhuaEntry{Text: fields[0], Code: fields[1], Weight: weight})
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	return entries
}

func readMaximumWeights(t *testing.T, path string) map[string]int {
	t.Helper()
	entries := readBundledErhuaDictionary(t, path)
	weights := map[string]int{}
	for _, entry := range entries {
		if entry.Weight > weights[entry.Text] {
			weights[entry.Text] = entry.Weight
		}
	}
	return weights
}
