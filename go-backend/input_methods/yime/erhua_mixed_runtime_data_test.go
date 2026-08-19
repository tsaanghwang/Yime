package yime

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestTrialErhuaDedicatedKeyProjectionIsPinned(t *testing.T) {
	projectionPath := filepath.Join("..", "..", "..", "docs", "project", "connected_speech", "erhua_sound_key_projection.json")
	payload, err := os.ReadFile(projectionPath)
	if err != nil {
		t.Fatal(err)
	}
	var projection struct {
		KeyClasses []struct {
			ID  string `json:"key_class_id"`
			Key string `json:"layout_key"`
		} `json:"key_classes"`
	}
	if err := json.Unmarshal(payload, &projection); err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, keyClass := range projection.KeyClasses {
		got[keyClass.ID] = keyClass.Key
	}
	want := map[string]string{
		"ERHUA-KEY-NASAL-A-RHOTIC-LOW":         "Q",
		"ERHUA-KEY-NASAL-A-RHOTIC-MID":         "T",
		"ERHUA-KEY-NASAL-A-RHOTIC-HIGH":        "Y",
		"ERHUA-KEY-NASAL-BACK-MID-RHOTIC-HIGH": "V",
		"ERHUA-KEY-NASAL-BACK-MID-RHOTIC-MID":  "C",
		"ERHUA-KEY-NASAL-BACK-MID-RHOTIC-LOW":  "X",
		"ERHUA-KEY-U-RHOTIC-HIGH":              "P",
		"ERHUA-KEY-U-RHOTIC-MID":               "A",
		"ERHUA-KEY-U-RHOTIC-LOW":               "Z",
	}
	for id, key := range want {
		if got[id] != key {
			t.Fatalf("%s layout key=%q, want %q", id, got[id], key)
		}
	}
}

type bundledErhuaMixedManifest struct {
	ToolVersion  string            `json:"tool_version"`
	OutputSHA256 map[string]string `json:"output_sha256"`
	Summary      struct {
		ExplicitRecordCount        int             `json:"explicit_record_count"`
		DualRouteReadyCount        int             `json:"dual_route_ready_count"`
		FeatureProjectedCount      int             `json:"feature_projected_count"`
		PendingFusionCount         int             `json:"pending_fusion_count"`
		InheritedWeightRecordCount int             `json:"inherited_weight_record_count"`
		FixedRuntimeWeight         int             `json:"fixed_runtime_weight"`
		CoreWeightRecordCount      int             `json:"core_weight_record_count"`
		PSCPeripheralWeightCount   int             `json:"psc_peripheral_weight_record_count"`
		DeferredMissingWeightCount int             `json:"deferred_missing_weight_count"`
		RoutesPerMode              int             `json:"routes_per_mode"`
		RuntimeAliasRows           int             `json:"runtime_alias_rows"`
		SentenceAliasRows          int             `json:"sentence_alias_rows"`
		SentenceDictionaryCount    int             `json:"sentence_dictionary_count"`
		DeclaredSoundUnitCount     int             `json:"declared_sound_unit_count"`
		PilotSoundUnitCount        int             `json:"pilot_sound_unit_count"`
		ResearchSoundUnitCount     int             `json:"research_sound_unit_count"`
		SharedKeyClassCount        int             `json:"shared_key_class_count"`
		DedicatedKeyClassCount     int             `json:"dedicated_key_class_count"`
		FeatureRuleCount           int             `json:"feature_rule_count"`
		ProjectedReadyRecordCount  int             `json:"projected_ready_record_count"`
		ReverseLookupRowCount      int             `json:"reverse_lookup_row_count"`
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
	if manifest.ToolVersion != "explicit-erhua-yinyuan-feature-runtime-v8" ||
		manifest.Summary.ExplicitRecordCount != 131 ||
		manifest.Summary.DualRouteReadyCount != 131 ||
		manifest.Summary.FeatureProjectedCount != 131 ||
		manifest.Summary.PendingFusionCount != 0 ||
		manifest.Summary.InheritedWeightRecordCount != 131 ||
		manifest.Summary.FixedRuntimeWeight != 1 ||
		manifest.Summary.CoreWeightRecordCount != 65 ||
		manifest.Summary.PSCPeripheralWeightCount != 66 ||
		manifest.Summary.DeferredMissingWeightCount != 0 ||
		manifest.Summary.RoutesPerMode != 196 ||
		manifest.Summary.RuntimeAliasRows != 588 ||
		manifest.Summary.SentenceAliasRows != 393 ||
		manifest.Summary.SentenceDictionaryCount != 3 ||
		manifest.Summary.DeclaredSoundUnitCount != 18 ||
		manifest.Summary.PilotSoundUnitCount != 18 ||
		manifest.Summary.ResearchSoundUnitCount != 0 ||
		manifest.Summary.SharedKeyClassCount != 3 ||
		manifest.Summary.DedicatedKeyClassCount != 15 ||
		manifest.Summary.FeatureRuleCount == 0 ||
		manifest.Summary.FeatureRuleCount != 15 ||
		manifest.Summary.ProjectedReadyRecordCount != 131 ||
		manifest.Summary.ReverseLookupRowCount != 131 ||
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
		sentenceAliasName := "yime_erhua_mixed_sentence_" + mode + ".dict.yaml"
		sentenceAliasPath := filepath.Join("data", sentenceAliasName)
		if got := fileSHA256(t, sentenceAliasPath); got != manifest.OutputSHA256[sentenceAliasName] {
			t.Fatalf("%s hash mismatch: got=%s want=%s", sentenceAliasName, got, manifest.OutputSHA256[sentenceAliasName])
		}
		sentenceAliases := readBundledErhuaDictionary(t, sentenceAliasPath)
		if len(sentenceAliases) != 131 {
			t.Fatalf("%s must contain 131 fused sentence routes, got %d", sentenceAliasName, len(sentenceAliases))
		}
		sentenceName := "yime_sentence_" + mode + ".dict.yaml"
		sentencePath := filepath.Join("data", sentenceName)
		if got := fileSHA256(t, sentencePath); got != manifest.OutputSHA256[sentenceName] {
			t.Fatalf("%s hash mismatch: got=%s want=%s", sentenceName, got, manifest.OutputSHA256[sentenceName])
		}
		sentenceData, err := os.ReadFile(sentencePath)
		if err != nil {
			t.Fatal(err)
		}
		for _, imported := range []string{"  - yime_" + mode, "  - yime_psc_peripheral_sentence_" + mode, "  - yime_erhua_mixed_sentence_" + mode} {
			if !strings.Contains(string(sentenceData), imported) {
				t.Fatalf("%s lacks import %q", sentenceName, imported)
			}
		}
		overlay := readBundledErhuaDictionary(t, filepath.Join("data", overlayName))
		if len(overlay) != 196 {
			t.Fatalf("%s must contain exactly 196 routes, got %d", overlayName, len(overlay))
		}
		coreEntries := readBundledErhuaDictionary(t, filepath.Join("data", "yime_"+mode+".dict.yaml"))
		coreWeights := maximumWeights(coreEntries)
		for _, entry := range coreEntries {
			if strings.ContainsAny(entry.Code, "QTYVCXPAZ") {
				t.Fatalf("%s canonical core unexpectedly uses trial erhua key in %q", mode, entry.Code)
			}
		}
		pscWeights := readMaximumWeights(t, filepath.Join("data", "yime_psc_peripheral_"+mode+".dict.yaml"))
		routesByText := map[string]int{}
		shiftCodes := map[string]struct{}{}
		shiftRows := 0
		for _, entry := range overlay {
			routesByText[entry.Text]++
			if strings.ContainsAny(entry.Code, "FDSREWQTYVCXPAZ") {
				shiftRows++
				shiftCodes[entry.Code] = struct{}{}
			}
			if entry.Text == "鸟儿" {
				t.Fatal("unannotated lookalike 鸟儿 must not be inferred into the mixed overlay")
			}
			if _, blocked := deferred[entry.Text]; blocked {
				t.Fatalf("deferred missing-weight record entered runtime: %s", entry.Text)
			}
			if coreWeights[entry.Text] == 0 && pscWeights[entry.Text] == 0 {
				t.Fatalf("%s/%s has no canonical or PSC source weight", mode, entry.Text)
			}
			if entry.Weight != 1 {
				t.Fatalf("%s/%s alias weight=%d, want fixed low-frequency weight 1", mode, entry.Text, entry.Weight)
			}
		}
		if len(routesByText) != 131 {
			t.Fatalf("%s must contain 131 explicit texts, got %d", overlayName, len(routesByText))
		}
		if shiftRows != 98 || len(shiftCodes) != 98 {
			t.Fatalf("%s dedicated Shift routes=%d distinct=%d, want 98/98", overlayName, shiftRows, len(shiftCodes))
		}
		for text, count := range routesByText {
			want := 2
			if coreWeights[text] == 0 {
				want = 1 // The suffix-compatible route already lives in the PSC peripheral overlay.
			}
			if count != want {
				t.Fatalf("%s/%s routes=%d, want %d", mode, text, count, want)
			}
		}
		schema, err := os.ReadFile(filepath.Join("data", "yime_"+mode+".schema.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		for _, fragment := range []string{
			"version: \"2026-08-17-core-1167501-layout-58f69f370aea-rank-v1-erhua-mixed-v4-psc-peripheral-v1-sentence-v1-third-tone-v1-alphabet-v2\"",
			"alphabet: \"`1234567890-=qwertyuiop[]\\\\asdfghjkl;'zxcvbnm,./JKLUIOM<>NGFDSREWQTYVCXPAZ\"",
			"- yime_erhua_mixed_" + mode,
			"- table_translator@erhua_mixed",
			"dictionary: yime_erhua_mixed_" + mode,
			"dictionary: yime_sentence_" + mode,
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
	reverseSourcePath := filepath.Join("data", "yime_erhua_reverse_source.tsv")
	if got := fileSHA256(t, reverseSourcePath); got != manifest.OutputSHA256["yime_erhua_reverse_source.tsv"] {
		t.Fatalf("explicit-erhua reverse source hash mismatch: got=%s want=%s", got, manifest.OutputSHA256["yime_erhua_reverse_source.tsv"])
	}
	reverseSource, err := os.ReadFile(reverseSourcePath)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(reverseSource)), "\n")
	if len(lines) != 132 {
		t.Fatalf("explicit-erhua reverse source rows=%d, want header + 131", len(lines))
	}
	for _, want := range []string{
		"一阵儿\tpsc_erhua\tyi1 zhen4 er5\tERHUA-YINYUAN-CENTRAL-ALL\tzhen4\tN16 M16 M17 M30\tN16 M22 M23 M24",
		"M22+rhotic=true+nasalized=false→M22→ERHUA-KEY-HIGH(U)",
		"yjjj7UIO\tyj7UIO\tyj7UO",
		"刀刃儿\tpsc_erhua\tdao1 ren4 er5\tERHUA-YINYUAN-CENTRAL-ALL\tren4",
		"]ffu0UIO\t]fu0UIO\t]fu0UO",
		"号码儿\tpsc_erhua\thao4 ma3 er5\tERHUA-YINYUAN-A-RHOTIC\tma3\tN04 M12 M12 M12\tN04 M12 R12 R12",
		"M12+rhotic=true+nasalized=false→R12→ERHUA-KEY-A-RHOTIC-LOW(S)",
		"单个儿\tpsc_erhua\tdan1 ge4 er5\tERHUA-YINYUAN-BACK-MID-RHOTIC\tge4\tN09 M13 M14 M15\tN09 M13 R14 R15",
		"M14+rhotic=true+nasalized=false→R14→ERHUA-KEY-BACK-MID-RHOTIC-MID(E)",
		"香肠儿\tpsc_erhua\txiang1 chang2 er5\tERHUA-YINYUAN-NASAL-A\tchang2\tN17 M12 M11 M31\tN17 M12 R05 R04",
		"M11+rhotic=true+nasalized=true→R05→ERHUA-KEY-NASAL-A-RHOTIC-MID(T)",
		"人影儿\tpsc_erhua\tren2 ying3 er5\tERHUA-YINYUAN-NASAL-BACK-MID\tying3\tN23 M03 M15 M33\tN23 M03 R09 R09",
		"M15+rhotic=true+nasalized=true→R09→ERHUA-KEY-NASAL-BACK-MID-RHOTIC-LOW(X)",
		"加油儿\tpsc_erhua\tjia1 you2 er5\tERHUA-YINYUAN-IOU\tyou2\tN23 M03 M14 M04\tN23 M03 R14 R16",
		"M04+rhotic=true+nasalized=false→R16→ERHUA-KEY-U-RHOTIC-HIGH(P)",
		"小鞋儿\tpsc_erhua\txiao3 xie2 er5\tERHUA-YINYUAN-FRONT-MID-CENTRAL\txie2\tN22 M03 M17 M16\tN22 M03 M23 M22",
		"雨点儿\tpsc_erhua\tyu3 dian3 er5\tERHUA-YINYUAN-MEDIAL-A-RHOTIC\tdian3\tN05 M03 M12 M30\tN05 M03 R12 R12",
		"火锅儿\tpsc_erhua\thuo3 guo1 er5\tERHUA-YINYUAN-BACK-MID-RHOTIC\tguo1\tN09 M04 M13 M13\tN09 M04 R13 R13",
		"红包儿\tpsc_erhua\thong2 bao1 er5\tERHUA-YINYUAN-IAO\tbao1\tN01 M10 M10 M04\tN01 M10 R10 R16",
		"衣兜儿\tpsc_erhua\tyi1 dou1 er5\tERHUA-YINYUAN-IOU\tdou1\tN05 M13 M13 M04\tN05 M13 R13 R16",
		"泪珠儿\tpsc_erhua\tlei4 zhu1 er5\tERHUA-YINYUAN-U-RHOTIC\tzhu1\tN16 M04 M04 M04\tN16 M04 R16 R16",
	} {
		if !strings.Contains(string(reverseSource), want) {
			t.Fatalf("explicit-erhua reverse source lacks %q", want)
		}
	}
}

func TestRuntimeProfileDeclaresExplicitErhuaMixedOverlay(t *testing.T) {
	var profile coreRuntimeProfile
	readJSONFile(t, "yime_runtime_profile.json", &profile)
	if !containsString(profile.CandidateLayers, "explicit_source_backed_erhua_mixed_overlay") {
		t.Fatal("runtime profile does not declare the explicit-erhua mixed candidate layer")
	}
	if profile.ExplicitErhuaReverseSource != "yime_erhua_reverse_source.tsv" {
		t.Fatalf("runtime profile lacks explicit-erhua reverse source: %q", profile.ExplicitErhuaReverseSource)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_erhua_mixed_" + mode + ".dict.yaml"
		if !containsString(profile.RuntimeDictionaries, name) {
			t.Fatalf("runtime profile lacks %s", name)
		}
		for _, sentenceName := range []string{"yime_erhua_mixed_sentence_" + mode + ".dict.yaml", "yime_sentence_" + mode + ".dict.yaml"} {
			if !containsString(profile.RuntimeDictionaries, sentenceName) {
				t.Fatalf("runtime profile lacks %s", sentenceName)
			}
		}
	}
	if !containsString(profile.CandidateLayers, "reviewed_sentence_composition_extension") {
		t.Fatal("runtime profile does not declare the reviewed sentence-composition extension")
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
	return maximumWeights(readBundledErhuaDictionary(t, path))
}

func maximumWeights(entries []bundledErhuaEntry) map[string]int {
	weights := map[string]int{}
	for _, entry := range entries {
		if entry.Weight > weights[entry.Text] {
			weights[entry.Text] = entry.Weight
		}
	}
	return weights
}
