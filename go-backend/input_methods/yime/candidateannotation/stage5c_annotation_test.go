package candidateannotation

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

// Only the repository's fixed reviewed sources are read. This invokes the
// existing forward admission in memory, not historical generators or Rime.
func reviewedStage5CAnnotations(t *testing.T) connectedspeech.AdmissionResult {
	t.Helper()
	repo, err := filepath.Abs("../../../..")
	if err != nil {
		t.Fatal(err)
	}
	paths := map[string]string{"review": "docs/project/connected_speech/third_tone_stage5b_review.tsv", "decisions": "docs/project/connected_speech/third_tone_stage5b_decisions.tsv", "sources": "docs/project/connected_speech/third_tone_stage5b_sources.tsv", "inventory": "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv", "layout": "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"}
	hashes := map[string]string{}
	for role, relative := range paths {
		path := filepath.Join(repo, filepath.FromSlash(relative))
		paths[role] = path
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(data)
		hashes[role] = hex.EncodeToString(sum[:])
	}
	result, err := connectedspeech.AdmitStage5C(connectedspeech.AdmissionInput{ReviewPath: paths["review"], DecisionsPath: paths["decisions"], SourcesPath: paths["sources"], InventoryPath: paths["inventory"], LayoutPath: paths["layout"], ExpectedSHA256: hashes})
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func TestStage5CStandardAnnotationUsesCanonicalReadingInAllModes(t *testing.T) {
	admitted := reviewedStage5CAnnotations(t)
	for _, mode := range []string{"full", "variable", "shorthand"} {
		resolver, err := Load("../data", mode)
		if err != nil {
			t.Fatal(err)
		}
		resolver, err = resolver.WithAdmittedRecords(admitted, true)
		if err != nil {
			t.Fatal(err)
		}
		for _, record := range admitted.Records {
			t.Run(mode+"/"+record.ReviewID, func(t *testing.T) {
				for _, source := range []string{"third-tone-stage5c@reviewed", "user-model"} {
					candidate := engineapi.Candidate{Text: record.Text, Code: record.Codes[mode].Alias, SourceID: source}
					resolver.Annotate(&candidate)
					standard, standardOK := resolver.markedSequence(strings.Fields(record.CanonicalPinyin))
					yinyuan, yinyuanOK := resolver.yinyuanSequence(strings.Fields(record.SurfacePinyin))
					if !standardOK || candidate.Annotations.StandardPinyin != standard {
						t.Fatal("reviewed alias standard annotation is not canonical")
					}
					if !yinyuanOK || candidate.Annotations.Yinyuan != yinyuan || candidate.Annotations.KeySequence != record.Codes[mode].Alias {
						t.Fatal("alias annotation no longer describes actual surface keys/Yinyuan")
					}
				}
			})
		}
	}
}

func TestStage5CAnnotationMixedSentenceAndLearnedWithoutSegments(t *testing.T) {
	admitted := reviewedStage5CAnnotations(t)
	for _, mode := range []string{"full", "variable", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			legacy, err := Load("../data", mode)
			if err != nil {
				t.Fatal(err)
			}
			resolver, err := legacy.WithAdmittedRecords(admitted, true)
			if err != nil {
				t.Fatal(err)
			}
			record := admitted.Records[0]
			alias := record.Codes[mode].Alias
			ordinary, ok := resolver.activeCode([]string{"shi4"})
			if !ok {
				t.Fatal("missing ordinary canonical syllable")
			}
			// An explicit isolated ordinary canonical source record; no hand-coded keys.
			resolver.sourceTruth[reverselookup.SourceTruthLookupKey("是", ordinary)] = []string{"shi4"}
			standard, _ := resolver.markedSequence(strings.Fields(record.CanonicalPinyin + " shi4"))
			yinyuan, _ := resolver.yinyuanSequence(strings.Fields(record.SurfacePinyin + " shi4"))
			mixed := engineapi.Candidate{Text: record.Text + "是", Code: alias + ordinary, SourceID: "sentence", Segments: []engineapi.Segment{{Start: 0, End: len(alias), Text: record.Text, Code: alias, SourceID: "user-model"}, {Start: len(alias), End: len(alias + ordinary), Text: "是", Code: ordinary, SourceID: "core"}}}
			resolver.Annotate(&mixed)
			if mixed.Annotations.StandardPinyin != standard || mixed.Annotations.Yinyuan != yinyuan || mixed.Annotations.KeySequence != alias+ordinary {
				t.Fatal("mixed segment annotation did not retain canonical reading and surface projection")
			}
			// State.Sentence and selectable candidates both cross the real decorator.
			result := engineapi.Result{State: engineapi.State{Candidates: []engineapi.Candidate{mixed}, Sentence: &mixed}}
			wrapper := Engine{resolver: resolver}
			wrapper.decorate(&result)
			if result.State.Sentence.Annotations.StandardPinyin != standard || result.State.Candidates[0].Annotations.StandardPinyin != standard {
				t.Fatal("sentence/candidate decoration diverged")
			}
			boundary := mixed
			boundary.Code = alias + "'" + ordinary
			boundary.Segments = append([]engineapi.Segment(nil), mixed.Segments...)
			boundary.Segments[1].Start++
			boundary.Segments[1].End++
			resolver.Annotate(&boundary)
			if boundary.Annotations.StandardPinyin != standard || boundary.Annotations.Yinyuan != yinyuan || boundary.Annotations.KeySequence != boundary.Code {
				t.Fatal("explicit segment boundary lost reviewed canonical reading")
			}
			// Apostrophe is also an actual base key. A segment containing it is
			// compared byte-for-byte, not stripped as if it were a word boundary.
			baseCode, ok := resolver.activeCode([]string{"a1"})
			if !ok || !strings.Contains(baseCode, "'") {
				t.Fatal("missing admitted base-apostrophe fixture")
			}
			resolver.sourceTruth[reverselookup.SourceTruthLookupKey("啊", baseCode)] = []string{"a1"}
			base := mixed
			base.Text = record.Text + "啊"
			base.Code = alias + "'" + baseCode
			base.Segments = []engineapi.Segment{mixed.Segments[0], {Start: len(alias) + 1, End: len(base.Code), Text: "啊", Code: baseCode, SourceID: "core"}}
			resolver.Annotate(&base)
			baseStandard, _ := resolver.markedSequence(strings.Fields(record.CanonicalPinyin + " a1"))
			baseYinyuan, _ := resolver.yinyuanSequence(strings.Fields(record.SurfacePinyin + " a1"))
			if base.Annotations.StandardPinyin != baseStandard || base.Annotations.Yinyuan != baseYinyuan || base.Annotations.KeySequence != base.Code {
				t.Fatal("base apostrophe conflated with explicit word boundary")
			}
			base.Segments[1].Code = strings.ReplaceAll(baseCode, "'", "")
			resolver.Annotate(&base)
			if base.Annotations.StandardPinyin != "" || base.Annotations.Yinyuan != "" {
				t.Fatal("missing real base apostrophe accepted")
			}
			malformed := mixed
			malformed.Segments = append([]engineapi.Segment(nil), mixed.Segments...)
			malformed.Segments[1].Start++
			resolver.Annotate(&malformed)
			if malformed.Annotations.StandardPinyin != "" || malformed.Annotations.Yinyuan != "" {
				t.Fatal("inconsistent reviewed segments guessed")
			}
			learned := mixed
			learned.SourceID = "user-model"
			learned.Segments = nil
			resolver.Annotate(&learned)
			if learned.Annotations.StandardPinyin != "" || learned.Annotations.KeySequence != alias+ordinary {
				t.Fatal("unsegmented learned composite guessed canonical reading or lost keys")
			}
			legacy.Annotate(&learned)
			if mode == "full" && learned.Annotations.StandardPinyin == "" {
				t.Fatal("legacy no-capability fallback changed")
			}
			// Exact canonical source truth still resolves ordinary learned words.
			canonical := engineapi.Candidate{Text: record.Text, Code: record.Codes[mode].Canonical, SourceID: "user-model"}
			resolver.Annotate(&canonical)
			canonicalStandard, _ := resolver.markedSequence(strings.Fields(record.CanonicalPinyin))
			if canonical.Annotations.StandardPinyin != canonicalStandard {
				t.Fatal("canonical learned source lost")
			}
		})
	}
}

func TestStage5CAnnotationLayoutMismatchKeepsOnlyKnownCanonical(t *testing.T) {
	admitted := reviewedStage5CAnnotations(t)
	for _, mode := range []string{"full", "variable", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			legacy, err := Load("../data", mode)
			if err != nil {
				t.Fatal(err)
			}
			resolver, err := legacy.WithAdmittedRecords(admitted, false)
			if err != nil {
				t.Fatal(err)
			}
			for _, record := range admitted.Records {
				candidate := engineapi.Candidate{Text: record.Text, Code: record.Codes[mode].Alias, SourceID: "user-model"}
				resolver.Annotate(&candidate)
				standard, _ := resolver.markedSequence(strings.Fields(record.CanonicalPinyin))
				if candidate.Annotations.StandardPinyin != standard || candidate.Annotations.Yinyuan != "" || candidate.Annotations.KeySequence != record.Codes[mode].Alias {
					t.Fatal("old-layout learned alias given fabricated active-layout projection")
				}
			}
			if len(legacy.reviewed) != 0 {
				t.Fatal("binding mutated legacy resolver")
			}
		})
	}
}

func TestStage5CAdmittedAnnotationRecordsStrictParsing(t *testing.T) {
	admitted := reviewedStage5CAnnotations(t)
	data, err := json.Marshal(admitted)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = DecodeAdmittedRecords(data); err != nil {
		t.Fatal(err)
	}
	for _, kind := range []string{"unknown", "duplicate", "trailing", "scope", "missing_mode", "extra_mode", "code_length", "missing_record", "duplicate_record"} {
		t.Run(kind, func(t *testing.T) {
			var value connectedspeech.AdmissionResult
			if err := json.Unmarshal(data, &value); err != nil {
				t.Fatal(err)
			}
			switch kind {
			case "scope":
				value.ModuleID = "other"
			case "missing_mode":
				delete(value.Records[0].Codes, "full")
			case "extra_mode":
				value.Records[0].Codes["extra"] = value.Records[0].Codes["full"]
			case "code_length":
				code := value.Records[0].Codes["full"]
				code.AliasLength++
				value.Records[0].Codes["full"] = code
			case "missing_record":
				value.Records = value.Records[:23]
			case "duplicate_record":
				value.Records[0] = value.Records[1]
			}
			payload, _ := json.Marshal(value)
			switch kind {
			case "unknown":
				payload = append([]byte(`{"unknown":true,`), payload[1:]...)
			case "duplicate":
				payload = append([]byte(`{"module_id":"third-tone-stage5c",`), payload[1:]...)
			case "trailing":
				payload = append(payload, []byte(" {}")...)
			}
			if _, err := DecodeAdmittedRecords(payload); err == nil {
				t.Fatal("invalid pinned annotation records accepted")
			}
		})
	}
}
