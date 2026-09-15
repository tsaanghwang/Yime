package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/candidateannotation"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/speechruntime"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimecore"
)

func speechAnnotationAdmission(t *testing.T) connectedspeech.AdmissionResult {
	t.Helper()
	repo, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	paths := map[string]string{"review": "docs/project/connected_speech/third_tone_stage5b_review.tsv", "decisions": "docs/project/connected_speech/third_tone_stage5b_decisions.tsv", "sources": "docs/project/connected_speech/third_tone_stage5b_sources.tsv", "inventory": "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv", "layout": "go-backend/input_methods/yime/data/yime_yinyuan_layout.json"}
	hashes := map[string]string{}
	for role, path := range paths {
		paths[role] = filepath.Join(repo, filepath.FromSlash(path))
		data, err := os.ReadFile(paths[role])
		if err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(data)
		hashes[role] = hex.EncodeToString(sum[:])
	}
	admitted, err := connectedspeech.AdmitStage5C(connectedspeech.AdmissionInput{ReviewPath: paths["review"], DecisionsPath: paths["decisions"], SourcesPath: paths["sources"], InventoryPath: paths["inventory"], LayoutPath: paths["layout"], ExpectedSHA256: hashes})
	if err != nil {
		t.Fatal(err)
	}
	return admitted
}

func speechAnnotationResolvers(t *testing.T, config multiModeConfig, product *brokerSpeechProduct) map[string]*candidateannotation.Resolver {
	t.Helper()
	resolvers := map[string]*candidateannotation.Resolver{}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		resolver, err := candidateannotation.Load(config.annotationDataDir, mode)
		if err != nil {
			t.Fatal(err)
		}
		resolvers[mode] = resolver
	}
	if err := product.BindAnnotations(resolvers); err != nil {
		t.Fatal(err)
	}
	return resolvers
}

func TestSpeechProductReviewedAnnotationsNormalBuilderAcrossRestartAndOff(t *testing.T) {
	admitted := speechAnnotationAdmission(t)
	for _, mode := range []string{"full", "variable", "shorthand"} {
		t.Run(mode, func(t *testing.T) {
			config, _ := speechBrokerProductFixture(t, admitted)
			product, err := openBrokerSpeechProduct(config)
			if err != nil {
				t.Fatal(err)
			}
			defer product.Close()
			resolvers := speechAnnotationResolvers(t, config, product)
			if _, err := os.Stat(filepath.Dir(config.userSnapshot)); !os.IsNotExist(err) {
				t.Fatal("annotation validation created durable state")
			}
			core, err := yimecore.OpenResidentFileIndex(filepath.Join(config.indexRoot, mode+".yidx"))
			if err != nil {
				t.Fatal(err)
			}
			defer core.Close()
			if modules, err := product.Modules(mode, core); err != nil || len(modules) != 0 {
				t.Fatal("default-off module snapshot changed")
			}
			if err := speechruntime.SaveSettings(config.speechSettings, true, true); err != nil {
				t.Fatal(err)
			}
			modules, err := product.Modules(mode, core)
			if err != nil || len(modules) != 1 {
				t.Fatal("enabled module snapshot failed")
			}
			model, err := yimecore.OpenUserModel(config.userSnapshot, config.userModelSourceID)
			if err != nil {
				t.Fatal(err)
			}
			engine, err := buildMultiModeEngine(config, mode, core, modules, model, resolvers[mode])
			if err != nil {
				t.Fatal(err)
			}
			markedData, err := os.ReadFile(filepath.Join(config.annotationDataDir, "pinyin_normalized.json"))
			if err != nil {
				t.Fatal(err)
			}
			marked := map[string]string{}
			if err = json.Unmarshal(markedData, &marked); err != nil {
				t.Fatal(err)
			}
			canonicalText := func(numeric string) string {
				var parts []string
				for _, part := range strings.Fields(numeric) {
					if marked[part] == "" {
						t.Fatal("missing canonical marked fixture")
					}
					parts = append(parts, marked[part])
				}
				return strings.Join(parts, " ")
			}
			record := admitted.Records[0]
			alias := record.Codes[mode].Alias
			standard := canonicalText(record.CanonicalPinyin)
			find := func(result engineapi.Result, text, code string) engineapi.Candidate {
				t.Helper()
				for _, candidate := range result.State.Candidates {
					if candidate.Text == text && candidate.Code == code {
						return candidate
					}
				}
				t.Fatal("expected reviewed/learned synthetic-fixture candidate missing")
				return engineapi.Candidate{}
			}
			candidate := find(speechProductApply(t, engine, alias), record.Text, alias)
			if candidate.Annotations.StandardPinyin != standard || candidate.Annotations.KeySequence != alias || candidate.Annotations.Yinyuan == "" {
				t.Fatal("normal builder bypassed reviewed annotation resolver")
			}
			if _, err = engine.Select(candidate.ID); err != nil {
				t.Fatal(err)
			}
			second := admitted.Records[1]
			mixedCode := alias + second.Codes[mode].Canonical
			mixedText := record.Text + second.Text
			mixedStandard := standard + " " + canonicalText(second.CanonicalPinyin)
			for _, separator := range []string{"", "'"} {
				code := alias + separator + second.Codes[mode].Canonical
				result := speechProductApply(t, engine, code)
				if result.State.Sentence == nil || result.State.Sentence.Text != mixedText || result.State.Sentence.Annotations.StandardPinyin != mixedStandard || result.State.Sentence.Annotations.KeySequence != code {
					t.Fatal("normal generated mixed sentence annotation lost canonical segment reading")
				}
				if separator == "" {
					if _, err = engine.Select(result.State.Sentence.ID); err != nil {
						t.Fatal(err)
					}
				}
			}
			if err = model.Save(); err != nil {
				t.Fatal(err)
			}
			generation := model.Generation()
			if err = speechruntime.SaveSettings(config.speechSettings, false, true); err != nil {
				t.Fatal(err)
			}
			// A fresh loader/resolver/model simulates a new Broker lifetime. The static
			// module is absent, while learned records stay in the ordinary namespace.
			restarted, err := openBrokerSpeechProduct(config)
			if err != nil {
				t.Fatal(err)
			}
			defer restarted.Close()
			offResolvers := speechAnnotationResolvers(t, config, restarted)
			offModules, err := restarted.Modules(mode, core)
			if err != nil || len(offModules) != 0 {
				t.Fatal("off restart retained static aliases")
			}
			reopened, err := yimecore.OpenUserModel(config.userSnapshot, config.userModelSourceID)
			if err != nil {
				t.Fatal(err)
			}
			off, err := buildMultiModeEngine(config, mode, core, offModules, reopened, offResolvers[mode])
			if err != nil {
				t.Fatal(err)
			}
			learned := find(speechProductApply(t, off, alias), record.Text, alias)
			if learned.SourceID != "user-model" || len(learned.Segments) != 0 || learned.Annotations.StandardPinyin != standard || learned.Annotations.KeySequence != alias {
				t.Fatal("learned exact alias lost canonical evidence when module disabled")
			}
			mixedResult := speechProductApply(t, off, mixedCode)
			learnedMixed := find(mixedResult, mixedText, mixedCode)
			if learnedMixed.SourceID != "user-model" || len(learnedMixed.Segments) != 0 || learnedMixed.Annotations.StandardPinyin != "" || learnedMixed.Annotations.KeySequence != mixedCode {
				t.Fatal("unsegmented learned composite guessed a canonical reading")
			}
			if mixedResult.State.Sentence != nil && len(mixedResult.State.Sentence.Segments) > 0 && mixedResult.State.Sentence.Annotations.StandardPinyin != mixedStandard {
				t.Fatal("reconstructed learned sentence lost segment annotation")
			}
			if reopened.Generation() != generation || reopened.SourceID() != config.userModelSourceID {
				t.Fatal("annotation/module toggle mutated learning or namespace")
			}
			old := find(speechProductApply(t, engine, alias), record.Text, alias)
			if !strings.HasPrefix(old.SourceID, speechruntime.ModuleID+"@") || old.Annotations.StandardPinyin != standard {
				t.Fatal("new off session changed existing enabled snapshot")
			}
			// An explicitly disabled different active layout retains known old-code
			// canonical annotations, but must not fabricate current-layout Yinyuan.
			speechProductWrite(t, filepath.Join(config.annotationDataDir, "yime_yinyuan_layout.json"), []byte("different-active-layout-fixture"))
			alternative, err := openBrokerSpeechProduct(config)
			if err != nil {
				t.Fatal(err)
			}
			defer alternative.Close()
			alternativeResolvers := speechAnnotationResolvers(t, config, alternative)
			alternativeResolvers[mode].Annotate(&learned)
			if learned.Annotations.StandardPinyin != standard || learned.Annotations.Yinyuan != "" || learned.Annotations.KeySequence != alias {
				t.Fatal("different-layout off resolver explained old keys using new projection")
			}
		})
	}
}

func TestSpeechProductNormalCLIValidatesAnnotationRecordsBeforeDurable(t *testing.T) {
	admitted := speechAnnotationAdmission(t)
	for _, kind := range []string{"valid_off", "invalid_records"} {
		t.Run(kind, func(t *testing.T) {
			config, _ := speechBrokerProductFixture(t, admitted)
			if kind == "invalid_records" {
				// Corrupt only the pinned typed record payload, then recompute its
				// enclosing fixture hashes: hash validation alone must not be enough.
				root := filepath.Join(config.speechProductRoot, "speech")
				data, err := os.ReadFile(filepath.Join(root, "admission.json"))
				if err != nil {
					t.Fatal(err)
				}
				var receipt speechruntime.AdmissionReceipt
				if err = json.Unmarshal(data, &receipt); err != nil {
					t.Fatal(err)
				}
				receipt.Records.SHA256 = speechProductWrite(t, filepath.Join(root, "admitted-records.json"), []byte(`{"unknown":true}`))
				data, _ = json.Marshal(receipt)
				receiptHash := speechProductWrite(t, filepath.Join(root, "admission.json"), data)
				data, err = os.ReadFile(filepath.Join(root, "product.json"))
				if err != nil {
					t.Fatal(err)
				}
				var manifest speechruntime.ProductManifest
				if err = json.Unmarshal(data, &manifest); err != nil {
					t.Fatal(err)
				}
				manifest.Admission.SHA256 = receiptHash
				data, _ = json.Marshal(manifest)
				config.speechProductSHA = speechProductWrite(t, filepath.Join(root, "product.json"), data)
				disabled := false
				data, _ = json.Marshal(speechruntime.Capability{SchemaVersion: speechruntime.CapabilitySchema, Product: speechruntime.FileRef{Path: speechruntime.ProductManifestPath, SHA256: config.speechProductSHA}, DefaultEnabled: &disabled})
				speechProductWrite(t, filepath.Join(config.speechProductRoot, speechruntime.CapabilityFilename), data)
			}
			args := []string{"-index-root", config.indexRoot, "-annotation-data-dir", config.annotationDataDir, "-trusted-client-id", "synthetic-normal-client", "-user-model-snapshot", config.userSnapshot, "-user-model-journal", config.userJournal, "-user-model-source-id", config.userModelSourceID, "-speech-product-root", config.speechProductRoot, "-speech-product-manifest", config.speechProductManifest, "-speech-product-sha256", config.speechProductSHA, "-speech-settings", config.speechSettings}
			output, err := runSpeechProductTestProcess(t, filepath.Dir(config.indexRoot), args, `{"version":1,"sequence":1,"operation":"open","mode":"variable"}`+"\n")
			if kind == "invalid_records" {
				if err == nil {
					t.Fatal("normal startup accepted malformed annotation records")
				}
				if _, err = os.Stat(filepath.Dir(config.userSnapshot)); !os.IsNotExist(err) {
					t.Fatal("bad annotation records opened durable state")
				}
				return
			}
			if err != nil {
				t.Fatalf("normal capability startup: %v %s", err, output)
			}
			var response yimebroker.Response
			if err = json.Unmarshal(output, &response); err != nil || response.Error != nil || response.SessionID == "" {
				t.Fatal("normal product transport startup failed")
			}
			if _, err = os.Stat(config.speechSettings); !os.IsNotExist(err) {
				t.Fatal("default-off validation created speech state")
			}
		})
	}
}
