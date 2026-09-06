package connectedspeech

import (
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/codemode"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const Stage5CAdmissionModuleID = "third-tone-stage5c"

// These are the reviewed first batch, not a caller-controlled approval list.
// Expanding or replacing this batch requires a new reviewed admission contract.
var stage5CApprovedSHA256 = map[string]string{
	"review":    "484f37fe78a1b6144c0abf5addd55245e1d0517eee21a142e9f735e495aa931b",
	"decisions": "575bd0ed7794c46c8aee53c1560bb0020f9397c06a20bda9ee7e6ad714adb0c8",
	"sources":   "dbba5cc8dc25fcbb70185b70aa3296503100e480c49fd462db76842f21338579",
}

// AdmissionInput names only reviewed sources and forward-generated semantic
// inventory/layout projections. The caller must establish the trusted lock
// chain for inventory and layout, including the manual-layout source. No Rime
// dictionary, reverse lookup, deployer, session or user data is an input.
type AdmissionInput struct {
	ReviewPath     string
	DecisionsPath  string
	SourcesPath    string
	InventoryPath  string
	LayoutPath     string
	ExpectedSHA256 map[string]string // exactly review, decisions, sources, inventory, layout
}

type AdmissionCode struct {
	Canonical       string `json:"canonical"`
	Alias           string `json:"alias"`
	CanonicalLength int    `json:"canonical_length"`
	AliasLength     int    `json:"alias_length"`
	Delta           int    `json:"delta"`
}

type AdmissionSource struct {
	ID         string `json:"id"`
	Title      string `json:"title"`
	Authority  string `json:"authority"`
	URL        string `json:"url"`
	Supports   string `json:"supports"`
	Limitation string `json:"limitation"`
}

type AdmissionRecord struct {
	ReviewID          string                   `json:"review_id"`
	Text              string                   `json:"text"`
	CanonicalPinyin   string                   `json:"canonical_pinyin"`
	SurfacePinyin     string                   `json:"surface_pinyin"`
	CanonicalIDs      YinyuanSequence          `json:"canonical_ids"`
	SurfaceIDs        YinyuanSequence          `json:"surface_ids"`
	Codes             map[string]AdmissionCode `json:"codes"`
	Sources           []AdmissionSource        `json:"sources"`
	Scope             string                   `json:"scope"`
	ApplicableContext string                   `json:"applicable_context"`
	BlockingContext   string                   `json:"blocking_context"`
	InputPolicy       string                   `json:"input_policy"`
	Adjudicator       string                   `json:"adjudicator"`
	AdjudicatedOn     string                   `json:"adjudicated_on"`
	ReviewNote        string                   `json:"review_note"`
	DecisionNote      string                   `json:"decision_note"`
	Weight            int                      `json:"weight"`
}

type AdmissionResult struct {
	ModuleID     string            `json:"module_id"`
	InputSHA256  map[string]string `json:"input_sha256"`
	LayoutDigest string            `json:"layout_digest"`
	Records      []AdmissionRecord `json:"records"`
}

// AdmitStage5C produces in-memory aliases only for the 24 independently reviewed
// records. It never invokes the historical Stage5A/B generators, which locate
// pronunciation via generated dictionary codes. The reviewed pronunciation is
// looked up forward in the admitted syllable inventory, retaining all four IDs.
func AdmitStage5C(input AdmissionInput) (AdmissionResult, error) {
	paths := map[string]string{
		"review": input.ReviewPath, "decisions": input.DecisionsPath, "sources": input.SourcesPath,
		"inventory": input.InventoryPath, "layout": input.LayoutPath,
	}
	if len(input.ExpectedSHA256) != len(paths) {
		return AdmissionResult{}, fmt.Errorf("admission requires exactly five expected input hashes")
	}
	for role, path := range paths {
		if path == "" || !sha256Pattern.MatchString(input.ExpectedSHA256[role]) {
			return AdmissionResult{}, fmt.Errorf("admission missing path or valid expected SHA256 for %s", role)
		}
		if approved := stage5CApprovedSHA256[role]; approved != "" && input.ExpectedSHA256[role] != approved {
			return AdmissionResult{}, fmt.Errorf("admission %s is not the reviewed Stage5C batch", role)
		}
	}
	before, err := hashNamedFiles(paths)
	if err != nil {
		return AdmissionResult{}, err
	}
	if !reflect.DeepEqual(before, input.ExpectedSHA256) {
		return AdmissionResult{}, fmt.Errorf("admission input SHA256 differs from expected lock")
	}
	reviews, err := loadThirdToneStage5BReviews(input.ReviewPath)
	if err != nil {
		return AdmissionResult{}, err
	}
	decisions, err := loadThirdToneStage5BDecisions(input.DecisionsPath)
	if err != nil {
		return AdmissionResult{}, err
	}
	sources, err := loadThirdToneStage5BSources(input.SourcesPath)
	if err != nil {
		return AdmissionResult{}, err
	}
	inventory, err := LoadInventory(input.InventoryPath)
	if err != nil {
		return AdmissionResult{}, err
	}
	layout, err := layoutdesigner.LoadProfile(input.LayoutPath)
	if err != nil {
		return AdmissionResult{}, err
	}
	records, err := admitStage5CRecords(reviews, decisions, sources, inventory, layout)
	if err != nil {
		return AdmissionResult{}, err
	}
	after, err := hashNamedFiles(paths)
	if err != nil {
		return AdmissionResult{}, err
	}
	if !reflect.DeepEqual(before, after) {
		return AdmissionResult{}, fmt.Errorf("admission source changed while being read")
	}
	digest, err := layout.Digest()
	if err != nil {
		return AdmissionResult{}, err
	}
	return AdmissionResult{Stage5CAdmissionModuleID, before, digest, records}, nil
}

func admitStage5CRecords(reviews []thirdToneStage5BReview, decisions map[string]thirdToneStage5BDecision, sources map[string]thirdToneStage5BSource, inventory Inventory, layout layoutdesigner.Profile) ([]AdmissionRecord, error) {
	if len(reviews) != 24 || len(decisions) != 24 || len(sources) != 2 {
		return nil, fmt.Errorf("Stage5C requires exactly 24 reviews, 24 decisions and 2 sources")
	}
	seenReviews, seenCandidates := map[string]bool{}, map[string]bool{}
	result := make([]AdmissionRecord, 0, len(reviews))
	for _, review := range reviews {
		if review.ReviewID == "" || seenReviews[review.ReviewID] {
			return nil, fmt.Errorf("missing or duplicate Stage5C review ID")
		}
		seenReviews[review.ReviewID] = true
		if err := validateThirdToneStage5BPendingBoundary(review); err != nil {
			return nil, fmt.Errorf("%s review boundary: %w", review.ReviewID, err)
		}
		decision, ok := decisions[review.ReviewID]
		if !ok || decision.ReviewID != review.ReviewID {
			return nil, fmt.Errorf("%s lacks its exact review decision", review.ReviewID)
		}
		if err := validateThirdToneStage5BDecision(decision); err != nil {
			return nil, fmt.Errorf("%s decision: %w", review.ReviewID, err)
		}
		canonical := strings.Fields(review.CanonicalPinyin)
		surface := strings.Fields(review.ExpectedSurfacePinyin)
		if len(canonical) != 2 || len(surface) != 2 || utf8.RuneCountInString(review.Text) != 2 ||
			toneSuffix(canonical[0]) != '3' || toneSuffix(canonical[1]) != '3' ||
			surface[0] != replaceToneSuffix(canonical[0], '2') || surface[1] != canonical[1] {
			return nil, fmt.Errorf("%s is not an explicit two-syllable 3+3 to 2+3 record", review.ReviewID)
		}
		key := thirdToneStage5BKey(review.Text, review.CanonicalPinyin)
		if seenCandidates[key] {
			return nil, fmt.Errorf("%s repeats a canonical candidate", review.ReviewID)
		}
		seenCandidates[key] = true
		canonicalIDs, err := admissionLookup(canonical, inventory, layout)
		if err != nil {
			return nil, fmt.Errorf("%s canonical: %w", review.ReviewID, err)
		}
		surfaceIDs, err := admissionLookup(surface, inventory, layout)
		if err != nil {
			return nil, fmt.Errorf("%s surface: %w", review.ReviewID, err)
		}
		if err := validateStage5CSubstitution(canonicalIDs, surfaceIDs); err != nil {
			return nil, fmt.Errorf("%s: %w", review.ReviewID, err)
		}
		canonicalProjection, err := projectAdmissionIDs(canonicalIDs, layout)
		if err != nil {
			return nil, err
		}
		surfaceProjection, err := projectAdmissionIDs(surfaceIDs, layout)
		if err != nil {
			return nil, err
		}
		codes := map[string]AdmissionCode{}
		for mode, pair := range map[string][2]string{
			"full":      {canonicalProjection.Full, surfaceProjection.Full},
			"variable":  {canonicalProjection.Variable, surfaceProjection.Variable},
			"shorthand": {canonicalProjection.Shorthand, surfaceProjection.Shorthand},
		} {
			cl, al := utf8.RuneCountInString(pair[0]), utf8.RuneCountInString(pair[1])
			codes[mode] = AdmissionCode{pair[0], pair[1], cl, al, al - cl}
		}
		if err := ValidateAdmissionLengths(codes); err != nil {
			return nil, fmt.Errorf("%s: %w", review.ReviewID, err)
		}
		if len(review.SourceIDs) != 2 {
			return nil, fmt.Errorf("%s must retain both reviewed sources", review.ReviewID)
		}
		evidence := make([]AdmissionSource, 0, len(review.SourceIDs))
		seenSources := map[string]bool{}
		for _, id := range review.SourceIDs {
			source, ok := sources[id]
			if !ok || seenSources[id] || source.ID != id || source.Title == "" || source.Authority == "" ||
				!strings.HasPrefix(source.URL, "https://") || source.Supports == "" || source.Limitation == "" {
				return nil, fmt.Errorf("%s has missing, duplicate or incomplete source", review.ReviewID)
			}
			seenSources[id] = true
			evidence = append(evidence, AdmissionSource{source.ID, source.Title, source.Authority, source.URL, source.Supports, source.Limitation})
		}
		result = append(result, AdmissionRecord{
			ReviewID: review.ReviewID, Text: review.Text, CanonicalPinyin: review.CanonicalPinyin,
			SurfacePinyin: review.ExpectedSurfacePinyin, CanonicalIDs: canonicalIDs, SurfaceIDs: surfaceIDs,
			Codes: codes, Sources: evidence, Scope: "lexical", ApplicableContext: decision.ApplicableContext,
			BlockingContext: decision.BlockingContext, InputPolicy: decision.InputPolicy,
			Adjudicator: decision.Adjudicator, AdjudicatedOn: decision.AdjudicatedOn,
			ReviewNote: review.Note, DecisionNote: decision.Note, Weight: 1,
		})
	}
	return result, nil
}

func admissionLookup(pinyin []string, inventory Inventory, layout layoutdesigner.Profile) (YinyuanSequence, error) {
	result := make(YinyuanSequence, 0, len(pinyin))
	for _, syllable := range pinyin {
		tuple, ok := inventory.Syllables[syllable]
		if !ok {
			return nil, fmt.Errorf("unattested syllable %s", syllable)
		}
		for position, id := range tuple {
			if !inventory.StableIDs[id] || layout.Projection[id] == "" ||
				(position == 0 && !strings.HasPrefix(id, "N")) || (position > 0 && !strings.HasPrefix(id, "M")) {
				return nil, fmt.Errorf("unknown or misplaced stable ID at syllable %s position %d", syllable, position)
			}
		}
		result = append(result, tuple)
	}
	return result, nil
}

func validateStage5CSubstitution(canonical, surface YinyuanSequence) error {
	if len(canonical) != 2 || len(surface) != 2 || canonical[1] != surface[1] || canonical[0][0] != surface[0][0] {
		return fmt.Errorf("Stage5C must preserve both syllables, onset and the entire second tuple")
	}
	for position := 1; position < 4; position++ {
		// Existing stable M01..M33 IDs form three grades per quality group,
		// high/mid/low, as used by layoutdesigner's ID-level shorthand rules.
		// Verify attested tuples; do not synthesize a new ID or syllable.
		from, fromErr := strconv.Atoi(strings.TrimPrefix(canonical[0][position], "M"))
		to, toErr := strconv.Atoi(strings.TrimPrefix(surface[0][position], "M"))
		if fromErr != nil || toErr != nil || !strings.HasPrefix(canonical[0][position], "M") || !strings.HasPrefix(surface[0][position], "M") ||
			from < 1 || from > 33 || to < 1 || to > 33 || (from-1)/3 != (to-1)/3 ||
			(from-1)%3 != 2 || (to-1)%3 != 3-position {
			return fmt.Errorf("Stage5C position %d must retain quality and change only attested low to low/mid/high grades", position)
		}
	}
	return nil
}

func projectAdmissionIDs(sequence YinyuanSequence, profile layoutdesigner.Profile) (codemode.Record, error) {
	ids := make([]string, 0, len(sequence)*4)
	for _, tuple := range sequence {
		ids = append(ids, tuple[:]...)
	}
	return layoutdesigner.ProjectIDRecord(ids, profile)
}

// ValidateAdmissionLengths independently measures actual strings, rather than
// trusting supplied lengths/deltas. Current independent-runtime admission is
// deliberately stricter than historical research audits: no mode may grow.
func ValidateAdmissionLengths(codes map[string]AdmissionCode) error {
	if len(codes) != 3 {
		return fmt.Errorf("admission requires exactly full, variable and shorthand modes")
	}
	for _, mode := range []string{"full", "variable", "shorthand"} {
		code, ok := codes[mode]
		if !ok || code.Canonical == "" || code.Alias == "" || strings.ContainsAny(code.Canonical+code.Alias, " \t\r\n") ||
			!utf8.ValidString(code.Canonical) || !utf8.ValidString(code.Alias) {
			return fmt.Errorf("admission %s has missing or malformed code", mode)
		}
		cl, al := utf8.RuneCountInString(code.Canonical), utf8.RuneCountInString(code.Alias)
		if code.CanonicalLength != cl || code.AliasLength != al || code.Delta != al-cl {
			return fmt.Errorf("admission %s length evidence does not match actual code", mode)
		}
		if al > cl {
			return fmt.Errorf("admission %s alias grows from %d to %d", mode, cl, al)
		}
	}
	return nil
}
