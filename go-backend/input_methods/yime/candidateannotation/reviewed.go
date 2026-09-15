package candidateannotation

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"unicode/utf8"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/connectedspeech"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

type reviewedAnnotation struct{ standard, yinyuan string }

// DecodeAdmittedRecords consumes the receipt-pinned bytes supplied by Product,
// not a caller-selected source path or a new pronunciation source. No rules run.
func DecodeAdmittedRecords(data []byte) (connectedspeech.AdmissionResult, error) {
	var admitted connectedspeech.AdmissionResult
	if len(data) == 0 || len(data) > 512*1024 {
		return admitted, errors.New("admitted annotation records missing or oversized")
	}
	check := json.NewDecoder(bytes.NewReader(data))
	var walk func() error
	walk = func() error {
		token, err := check.Token()
		if err != nil {
			return err
		}
		if delimiter, ok := token.(json.Delim); ok {
			switch delimiter {
			case '{':
				seen := map[string]bool{}
				for check.More() {
					key, err := check.Token()
					if err != nil {
						return err
					}
					name, ok := key.(string)
					if !ok || seen[name] {
						return errors.New("duplicate admitted annotation field")
					}
					seen[name] = true
					if err = walk(); err != nil {
						return err
					}
				}
			case '[':
				for check.More() {
					if err = walk(); err != nil {
						return err
					}
				}
			default:
				return errors.New("invalid admitted annotation JSON")
			}
			_, err = check.Token()
			return err
		}
		return nil
	}
	if err := walk(); err != nil {
		return admitted, err
	}
	if _, err := check.Token(); err != io.EOF {
		return admitted, errors.New("trailing admitted annotation JSON")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&admitted); err != nil {
		return admitted, err
	}
	if admitted.ModuleID != connectedspeech.Stage5CAdmissionModuleID || len(admitted.Records) != 24 {
		return admitted, errors.New("only reviewed Stage5C annotation batch allowed")
	}
	seen := map[string]bool{}
	for _, record := range admitted.Records {
		if seen[record.ReviewID] || record.Text == "" || record.CanonicalPinyin == "" || record.SurfacePinyin == "" || len(record.Codes) != 3 {
			return admitted, errors.New("admitted annotation record incomplete or duplicate")
		}
		seen[record.ReviewID] = true
		for _, mode := range []string{"full", "variable", "shorthand"} {
			code, ok := record.Codes[mode]
			if !ok || code.Canonical == "" || code.Alias == "" || len(code.Alias) > len(code.Canonical) || code.CanonicalLength != len(code.Canonical) || code.AliasLength != len(code.Alias) || code.Delta != len(code.Alias)-len(code.Canonical) {
				return admitted, errors.New("admitted annotation three-mode codes incomplete")
			}
		}
	}
	for i := 1; i <= 24; i++ {
		if !seen[fmt.Sprintf("T3-5B-%03d", i)] {
			return admitted, errors.New("unknown admitted annotation record scope")
		}
	}
	return admitted, nil
}

// WithAdmittedRecords returns an immutable resolver copy. Standard Pinyin is
// bound to the reviewed canonical reading, while Yinyuan follows the actual
// alias only when its admitted layout is the active layout. This table remains
// available with the static module disabled, including user-model candidates.
func (r *Resolver) WithAdmittedRecords(admitted connectedspeech.AdmissionResult, layoutMatches bool) (*Resolver, error) {
	if r == nil || admitted.ModuleID != connectedspeech.Stage5CAdmissionModuleID || len(admitted.Records) != 24 {
		return nil, errors.New("reviewed annotation resolver and scope required")
	}
	result := *r
	result.reviewed = make(map[string]reviewedAnnotation, 48)
	seen := map[string]bool{}
	for _, record := range admitted.Records {
		if seen[record.ReviewID] {
			return nil, errors.New("duplicate reviewed annotation ID")
		}
		seen[record.ReviewID] = true
		codes, ok := record.Codes[string(r.mode)]
		if !ok || record.Text == "" || codes.Canonical == "" || codes.Alias == "" {
			return nil, errors.New("reviewed annotation missing mode/text/code")
		}
		standard, ok := r.markedSequence(strings.Fields(record.CanonicalPinyin))
		if !ok {
			return nil, errors.New("reviewed canonical pronunciation absent from annotation inventory")
		}
		if _, ok := r.markedSequence(strings.Fields(record.SurfacePinyin)); !ok {
			return nil, errors.New("reviewed surface pronunciation absent from annotation inventory")
		}
		for _, surface := range []bool{false, true} {
			code, numeric := codes.Canonical, record.CanonicalPinyin
			if surface {
				code, numeric = codes.Alias, record.SurfacePinyin
			}
			yinyuan := ""
			if layoutMatches {
				projected, ok := r.activeCode(strings.Fields(numeric))
				if !ok || projected != strings.ReplaceAll(code, " ", "") {
					return nil, errors.New("reviewed pronunciation code does not match active annotation layout")
				}
				var valid bool
				yinyuan, valid = r.yinyuanSequence(strings.Fields(numeric))
				if !valid {
					return nil, errors.New("reviewed pronunciation lacks Yinyuan annotation")
				}
			}
			key := reverselookup.SourceTruthLookupKey(record.Text, code)
			value := reviewedAnnotation{standard: standard, yinyuan: yinyuan}
			if previous, exists := result.reviewed[key]; exists && previous != value {
				return nil, errors.New("conflicting reviewed annotation identity")
			}
			result.reviewed[key] = value
		}
	}
	for i := 1; i <= 24; i++ {
		if !seen[fmt.Sprintf("T3-5B-%03d", i)] {
			return nil, errors.New("unknown reviewed annotation batch")
		}
	}
	return &result, nil
}

func (r *Resolver) activeCode(parts []string) (string, bool) {
	var result strings.Builder
	for _, numeric := range parts {
		record, ok := r.codeByNumeric[normalizeNumeric(numeric)]
		if !ok {
			return "", false
		}
		code := record.variable
		if r.mode == reverselookup.ModeFull {
			code = record.full
		} else if r.mode == reverselookup.ModeShorthand {
			code = record.shorthand
		}
		result.WriteString(code)
	}
	return result.String(), result.Len() > 0
}

func (r *Resolver) annotateReviewed(candidate *engineapi.Candidate) bool {
	if len(r.reviewed) == 0 {
		return false
	}
	key := reverselookup.SourceTruthLookupKey(candidate.Text, candidate.Code)
	if value, ok := r.reviewed[key]; ok {
		candidate.Annotations.StandardPinyin = value.standard
		candidate.Annotations.Yinyuan = value.yinyuan
		return true
	}
	// Trust explicit engine segment boundaries before attempting a whole-code
	// split, which would otherwise turn a known alias segment into surface Pinyin.
	var text strings.Builder
	hasReviewed, validSegments := false, true
	previousEnd := 0
	raw := candidate.Annotations.KeySequence
	for position, segment := range candidate.Segments {
		partCode := strings.ReplaceAll(segment.Code, " ", "")
		spanValid := previousEnd >= 0 && segment.Start >= previousEnd && segment.End > segment.Start && segment.End <= len(raw)
		if spanValid {
			gap := raw[previousEnd:segment.Start]
			spanValid = raw[segment.Start:segment.End] == partCode && (gap == "" || (position > 0 && strings.Trim(gap, "'") == ""))
		}
		validSegments = validSegments && segment.Text != "" && partCode != "" && spanValid
		text.WriteString(segment.Text)
		previousEnd = segment.End
		_, known := r.reviewed[reverselookup.SourceTruthLookupKey(segment.Text, segment.Code)]
		hasReviewed = hasReviewed || known
	}
	if hasReviewed && validSegments && text.String() == candidate.Text && previousEnd == len(raw) {
		var standard, yinyuan []string
		standardOK, yinyuanOK := true, true
		for _, segment := range candidate.Segments {
			part := engineapi.Candidate{Text: segment.Text, Code: segment.Code, SourceID: segment.SourceID}
			r.Annotate(&part)
			standardOK = standardOK && part.Annotations.StandardPinyin != ""
			yinyuanOK = yinyuanOK && part.Annotations.Yinyuan != ""
			standard = append(standard, part.Annotations.StandardPinyin)
			yinyuan = append(yinyuan, part.Annotations.Yinyuan)
		}
		candidate.Annotations.StandardPinyin = ""
		candidate.Annotations.Yinyuan = ""
		if standardOK {
			candidate.Annotations.StandardPinyin = strings.Join(standard, " ")
		}
		if yinyuanOK {
			candidate.Annotations.Yinyuan = strings.Join(yinyuan, "")
		}
		return true
	}
	if hasReviewed {
		// A known alias with inconsistent segment boundaries is not evidence for
		// either whole-sentence pronunciation. Never fall back to surface guessing.
		candidate.Annotations.StandardPinyin = ""
		candidate.Annotations.Yinyuan = ""
		return true
	}
	// Learned multi-word records can lose their original segment observations.
	// With speech capability present, code alone cannot prove canonical reading.
	// Keep the older resolver untouched when there is no admitted table.
	if candidate.SourceID == "user-model" && utf8.RuneCountInString(candidate.Text) > 1 && len(r.sourceTruth[key]) == 0 {
		candidate.Annotations.StandardPinyin = ""
		candidate.Annotations.Yinyuan = ""
		if parts, ok := r.splitCode(candidate.Annotations.KeySequence); ok {
			candidate.Annotations.Yinyuan, _ = r.yinyuanSequence(parts)
		}
		return true
	}
	return false
}
