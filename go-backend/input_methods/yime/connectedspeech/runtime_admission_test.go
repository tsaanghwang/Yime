package connectedspeech

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

func admissionFixture(t *testing.T) AdmissionInput {
	t.Helper()
	dir := t.TempDir()
	reviewRoot := filepath.Join("..", "..", "..", "..", "docs", "project", "connected_speech")
	inputs := map[string]string{
		"review":    filepath.Join(reviewRoot, "third_tone_stage5b_review.tsv"),
		"decisions": filepath.Join(reviewRoot, "third_tone_stage5b_decisions.tsv"),
		"sources":   filepath.Join(reviewRoot, "third_tone_stage5b_sources.tsv"),
		"inventory": filepath.Join("..", "data", "yime_syllable_decomposition.tsv"),
		"layout":    filepath.Join("..", "data", "yime_yinyuan_layout.json"),
	}
	paths := map[string]string{}
	for role, path := range inputs {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		paths[role] = filepath.Join(dir, filepath.Base(path))
		if err := os.WriteFile(paths[role], data, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	hashes, err := hashNamedFiles(paths)
	if err != nil {
		t.Fatal(err)
	}
	return AdmissionInput{paths["review"], paths["decisions"], paths["sources"], paths["inventory"], paths["layout"], hashes}
}

func TestStage5CAdmissionForwardReviewedBatch(t *testing.T) {
	input := admissionFixture(t)
	result, err := AdmitStage5C(input)
	if err != nil {
		t.Fatal(err)
	}
	if result.ModuleID != Stage5CAdmissionModuleID || len(result.Records) != 24 || result.LayoutDigest == "" || !reflect.DeepEqual(result.InputSHA256, input.ExpectedSHA256) {
		t.Fatal("wrong first-batch manifest")
	}
	for _, record := range result.Records {
		if len(record.CanonicalIDs) != 2 || len(record.SurfaceIDs) != 2 || record.Weight != 1 || record.Scope != "lexical" ||
			record.BlockingContext == "" || record.ApplicableContext == "" || len(record.Sources) != 2 || record.InputPolicy != "parallel_alias_keep_canonical" {
			t.Fatalf("lost semantic provenance on %s", record.ReviewID)
		}
		if err := ValidateAdmissionLengths(record.Codes); err != nil {
			t.Fatal(err)
		}
		if record.Codes["full"].CanonicalLength != 8 || record.Codes["full"].AliasLength != 8 || record.Codes["full"].Canonical == record.Codes["full"].Alias {
			t.Fatalf("not a position-preserving tone alias on %s", record.ReviewID)
		}
	}
	again, err := AdmitStage5C(input)
	if err != nil || !reflect.DeepEqual(result, again) {
		t.Fatal("admission is not deterministic or changed inputs")
	}
}

func TestStage5CAdmissionRejectsHashForgeryAndIncompleteLock(t *testing.T) {
	for _, kind := range []string{"missing", "extra", "invalid", "wrong", "rehash_unapproved_review", "changed_inventory"} {
		t.Run(kind, func(t *testing.T) {
			input := admissionFixture(t)
			switch kind {
			case "missing":
				delete(input.ExpectedSHA256, "inventory")
			case "extra":
				input.ExpectedSHA256["dictionary"] = strings.Repeat("0", 64)
			case "invalid":
				input.ExpectedSHA256["layout"] = "not-a-sha"
			case "wrong":
				input.ExpectedSHA256["layout"] = strings.Repeat("0", 64)
			case "rehash_unapproved_review":
				bytes, err := os.ReadFile(input.ReviewPath)
				if err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(input.ReviewPath, append(bytes, '\n'), 0o600); err != nil {
					t.Fatal(err)
				}
				hashes, err := hashNamedFiles(map[string]string{"review": input.ReviewPath})
				if err != nil {
					t.Fatal(err)
				}
				input.ExpectedSHA256["review"] = hashes["review"]
			case "changed_inventory":
				bytes, err := os.ReadFile(input.InventoryPath)
				if err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(input.InventoryPath, append(bytes, '\n'), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			got, err := AdmitStage5C(input)
			if err == nil || len(got.Records) != 0 {
				t.Fatal("untrusted or mismatched input produced aliases")
			}
		})
	}
}

func TestStage5CAdmissionRejectsUnreviewedOrCorruptSemantics(t *testing.T) {
	for _, kind := range []string{
		"missing_review", "duplicate_review", "duplicate_candidate", "missing_decision", "orphan_decision",
		"research_only", "missing_scope", "missing_exclusions", "wrong_input_policy", "missing_adjudicator",
		"unknown_source", "duplicate_source", "lost_source_limitation", "unknown_canonical", "unknown_surface",
		"wrong_surface_tone", "changed_second_syllable", "unknown_id", "misplaced_id", "changed_onset", "changed_quality", "changed_grade", "changed_second_tuple",
	} {
		t.Run(kind, func(t *testing.T) {
			input := admissionFixture(t)
			reviews, err := loadThirdToneStage5BReviews(input.ReviewPath)
			if err != nil {
				t.Fatal(err)
			}
			decisions, err := loadThirdToneStage5BDecisions(input.DecisionsPath)
			if err != nil {
				t.Fatal(err)
			}
			sources, err := loadThirdToneStage5BSources(input.SourcesPath)
			if err != nil {
				t.Fatal(err)
			}
			inventory, err := LoadInventory(input.InventoryPath)
			if err != nil {
				t.Fatal(err)
			}
			profile, err := layoutdesigner.LoadProfile(input.LayoutPath)
			if err != nil {
				t.Fatal(err)
			}
			r := &reviews[0]
			d := decisions[r.ReviewID]
			canonical := strings.Fields(r.CanonicalPinyin)
			surface := strings.Fields(r.ExpectedSurfacePinyin)
			switch kind {
			case "missing_review":
				reviews = reviews[:23]
			case "duplicate_review":
				reviews[1] = reviews[0]
			case "duplicate_candidate":
				reviews[1].Text, reviews[1].CanonicalPinyin, reviews[1].ExpectedSurfacePinyin = r.Text, r.CanonicalPinyin, r.ExpectedSurfacePinyin
			case "missing_decision":
				delete(decisions, r.ReviewID)
			case "orphan_decision":
				delete(decisions, r.ReviewID)
				d.ReviewID = "unreviewed"
				decisions[d.ReviewID] = d
			case "research_only":
				r.EvidenceClass = "research_only"
			case "missing_scope":
				d.ApplicableContext = ""
				decisions[r.ReviewID] = d
			case "missing_exclusions":
				d.BlockingContext = "internal_emphasis"
				decisions[r.ReviewID] = d
			case "wrong_input_policy":
				d.InputPolicy = "replace_canonical"
				decisions[r.ReviewID] = d
			case "missing_adjudicator":
				d.Adjudicator = ""
				decisions[r.ReviewID] = d
			case "unknown_source":
				r.SourceIDs[0] = "unknown"
			case "duplicate_source":
				r.SourceIDs[0] = r.SourceIDs[1]
			case "lost_source_limitation":
				s := sources[r.SourceIDs[0]]
				s.Limitation = ""
				sources[s.ID] = s
			case "unknown_canonical":
				delete(inventory.Syllables, canonical[0])
			case "unknown_surface":
				delete(inventory.Syllables, surface[0])
			case "wrong_surface_tone":
				r.ExpectedSurfacePinyin = r.CanonicalPinyin
			case "changed_second_syllable":
				r.ExpectedSurfacePinyin = surface[0] + " " + replaceToneSuffix(surface[1], '2')
			case "unknown_id":
				tuple := inventory.Syllables[surface[0]]
				tuple[1] = "M99"
				inventory.Syllables[surface[0]] = tuple
			case "misplaced_id":
				tuple := inventory.Syllables[surface[0]]
				tuple[1] = tuple[0]
				inventory.Syllables[surface[0]] = tuple
			case "changed_onset":
				tuple := inventory.Syllables[surface[0]]
				tuple[0] = "N01"
				inventory.Syllables[surface[0]] = tuple
			case "changed_quality":
				tuple := inventory.Syllables[surface[0]]
				tuple[1] = "M06"
				inventory.Syllables[surface[0]] = tuple
			case "changed_grade":
				tuple := inventory.Syllables[surface[0]]
				tuple[2] = tuple[1]
				inventory.Syllables[surface[0]] = tuple
			case "changed_second_tuple":
				c, s := YinyuanSequence{inventory.Syllables[canonical[0]], inventory.Syllables[canonical[1]]}, YinyuanSequence{inventory.Syllables[surface[0]], inventory.Syllables[surface[1]]}
				s[1][1] = "M01"
				if err := validateStage5CSubstitution(c, s); err == nil {
					t.Fatal("changed second tuple accepted")
				}
				return
			}
			got, err := admitStage5CRecords(reviews, decisions, sources, inventory, profile)
			if err == nil || got != nil {
				t.Fatal("invalid semantics produced aliases")
			}
		})
	}
}

func TestStage5CAdmissionLengthsMeasureEachModeIndependently(t *testing.T) {
	base := func() map[string]AdmissionCode {
		return map[string]AdmissionCode{
			"full":      {"abcdefgh", "hgfedcba", 8, 8, 0},
			"variable":  {"abcdef", "fedcba", 6, 6, 0},
			"shorthand": {"abcd", "dcba", 4, 4, 0},
		}
	}
	if err := ValidateAdmissionLengths(base()); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		t.Run(mode+"_alone_grows", func(t *testing.T) {
			codes := base()
			code := codes[mode]
			code.Alias += "x"
			code.AliasLength++
			code.Delta++
			codes[mode] = code
			if err := ValidateAdmissionLengths(codes); err == nil || !strings.Contains(err.Error(), mode) {
				t.Fatal("single-mode growth accepted")
			}
		})
	}
	for _, kind := range []string{"missing", "extra", "wrong_mode", "forged_canonical_length", "forged_alias_length", "forged_delta", "space", "invalid_utf8"} {
		t.Run(kind, func(t *testing.T) {
			codes := base()
			code := codes["variable"]
			switch kind {
			case "missing":
				delete(codes, "full")
			case "extra":
				codes["other"] = code
			case "wrong_mode":
				delete(codes, "full")
				codes["other"] = code
			case "forged_canonical_length":
				code.CanonicalLength++
			case "forged_alias_length":
				code.AliasLength--
			case "forged_delta":
				code.Delta--
			case "space":
				code.Alias = "fed cb"
			case "invalid_utf8":
				code.Alias = string([]byte{0xff})
			}
			codes["variable"] = code
			if err := ValidateAdmissionLengths(codes); err == nil {
				t.Fatal("forged evidence accepted")
			}
		})
	}
	unicode := base()
	unicode["variable"] = AdmissionCode{"甲乙", "丙丁", 2, 2, 0}
	if err := ValidateAdmissionLengths(unicode); err != nil {
		t.Fatal("length validator counted bytes, not runes")
	}
}

func TestStage5CAdmissionAlternativeLayoutPreservesSemanticRecords(t *testing.T) {
	input := admissionFixture(t)
	baseline, err := AdmitStage5C(input)
	if err != nil {
		t.Fatal(err)
	}
	profile, err := layoutdesigner.LoadProfile(input.LayoutPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := profile.Assign("M16", "]"); err != nil {
		t.Fatal(err)
	}
	for _, record := range baseline.Records {
		canonical, err := projectAdmissionIDs(record.CanonicalIDs, profile)
		if err != nil {
			t.Fatal(err)
		}
		surface, err := projectAdmissionIDs(record.SurfaceIDs, profile)
		if err != nil {
			t.Fatal(err)
		}
		if len(canonical.Full) != record.Codes["full"].CanonicalLength || len(surface.Full) != record.Codes["full"].AliasLength ||
			len(canonical.Variable) != record.Codes["variable"].CanonicalLength || len(surface.Variable) != record.Codes["variable"].AliasLength ||
			len(canonical.Shorthand) != record.Codes["shorthand"].CanonicalLength || len(surface.Shorthand) != record.Codes["shorthand"].AliasLength {
			t.Fatal("physical key reassignment changed semantic mode selection")
		}
	}
}
