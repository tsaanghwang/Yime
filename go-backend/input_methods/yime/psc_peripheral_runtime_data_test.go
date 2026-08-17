package yime

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

type bundledPSCPeripheralManifest struct {
	ToolVersion  string            `json:"tool_version"`
	OutputSHA256 map[string]string `json:"output_sha256"`
	Summary      struct {
		SourceRecordCount        int             `json:"source_record_count"`
		NeutralToneRecordCount   int             `json:"neutral_tone_record_count"`
		ErhuaRecordCount         int             `json:"erhua_record_count"`
		EncodedRecordCount       int             `json:"encoded_record_count"`
		AlreadyInCoreRecordCount int             `json:"already_in_core_record_count"`
		RuntimeRowsPerMode       int             `json:"runtime_rows_per_mode"`
		FixedPeripheralWeight    int             `json:"fixed_peripheral_weight"`
		Gates                    map[string]bool `json:"gates"`
		Passed                   bool            `json:"passed"`
	} `json:"summary"`
}

func TestBundledPSCPeripheralIsCompleteLowFrequencyAndThreeMode(t *testing.T) {
	var manifest bundledPSCPeripheralManifest
	readJSONFile(t, "yime_psc_peripheral_manifest.json", &manifest)
	if manifest.ToolVersion != "psc-pronunciation-peripheral-runtime-v1" ||
		manifest.Summary.SourceRecordCount != 315 ||
		manifest.Summary.NeutralToneRecordCount != 183 ||
		manifest.Summary.ErhuaRecordCount != 132 ||
		manifest.Summary.EncodedRecordCount != 315 ||
		manifest.Summary.AlreadyInCoreRecordCount != 0 ||
		manifest.Summary.RuntimeRowsPerMode != 315 ||
		manifest.Summary.FixedPeripheralWeight != 1 ||
		!manifest.Summary.Passed {
		t.Fatalf("unexpected PSC peripheral manifest: %#v", manifest)
	}
	for gate, passed := range manifest.Summary.Gates {
		if !passed {
			t.Fatalf("PSC peripheral gate failed: %s", gate)
		}
	}

	for _, mode := range []string{"full", "variable", "shorthand"} {
		name := "yime_psc_peripheral_" + mode + ".dict.yaml"
		path := filepath.Join("data", name)
		if got := fileSHA256(t, path); got != manifest.OutputSHA256[name] {
			t.Fatalf("%s hash mismatch: got=%s want=%s", name, got, manifest.OutputSHA256[name])
		}
		file, err := os.Open(path)
		if err != nil {
			t.Fatal(err)
		}
		rows := 0
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
			if parseErr != nil || weight != 1 {
				t.Fatalf("%s has non-peripheral weight %q", name, fields[2])
			}
			rows++
		}
		if err := scanner.Err(); err != nil {
			t.Fatal(err)
		}
		if err := file.Close(); err != nil {
			t.Fatal(err)
		}
		if rows != 315 {
			t.Fatalf("%s rows=%d, want 315", name, rows)
		}

		schemaData, err := os.ReadFile(filepath.Join("data", "yime_"+mode+".schema.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		schema := string(schemaData)
		for _, fragment := range []string{
			"- yime_psc_peripheral_" + mode,
			"- table_translator@psc_peripheral",
			"dictionary: yime_psc_peripheral_" + mode,
			"initial_quality: -1",
		} {
			if !strings.Contains(schema, fragment) {
				t.Fatalf("%s schema lacks PSC peripheral setting %q", mode, fragment)
			}
		}
		dependencyData, err := os.ReadFile(filepath.Join("data", "yime_psc_peripheral_"+mode+".schema.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(dependencyData), "dictionary: yime_psc_peripheral_"+mode) {
			t.Fatalf("%s dependency schema does not compile its PSC peripheral dictionary", mode)
		}
	}
}

func TestRuntimeProfileDeclaresPSCPeripheralWithoutChangingCoreCount(t *testing.T) {
	var profile coreRuntimeProfile
	readJSONFile(t, "yime_runtime_profile.json", &profile)
	if profile.EntryCountPerMode != curatedCoreEntryCount ||
		profile.PSCPeripheralManifest != "yime_psc_peripheral_manifest.json" ||
		profile.PSCPeripheralEntries != 315 ||
		profile.PSCPeripheralNeutralTone != 183 ||
		profile.PSCPeripheralErhua != 132 ||
		profile.PSCPeripheralWeight != 1 {
		t.Fatalf("unexpected PSC peripheral runtime profile: %#v", profile)
	}
	if !containsString(profile.CandidateLayers, "reviewed_psc_neutral_erhua_low_frequency_periphery") {
		t.Fatal("runtime profile lacks PSC peripheral candidate layer")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		if !containsString(profile.RuntimeSchemaDependencies, "yime_psc_peripheral_"+mode) {
			t.Fatalf("runtime profile lacks PSC peripheral dependency for %s", mode)
		}
		if !containsString(profile.RuntimeDictionaries, "yime_psc_peripheral_"+mode+".dict.yaml") {
			t.Fatalf("runtime profile lacks PSC peripheral dictionary for %s", mode)
		}
	}
}
