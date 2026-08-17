package connectedspeech

import (
	"fmt"
	"strings"
)

// projectErhuaYinyuanFeatures is the only fused-erhua encoding path. It starts
// from the canonical attached-syllable tuple, applies explicit rhotic/nasalized
// feature rewrites, resolves derived Yinyuan IDs, and only then derives all
// three code modes. Surface IPA and surface classes are not inputs.
func projectErhuaYinyuanFeatures(record erhuaAliasRecord, index erhuaSoundProjectionIndex) (erhuaAliasRecord, bool, error) {
	route, ok := record.Routes["fused_erhua"]
	if !ok || route.Status != "feature_projection_ready" {
		return record, false, nil
	}
	if route.FeatureRuleID == "" || len(route.AttachedSyllableSourceYinyuanIDs) != 4 || len(route.FeatureRewrites) == 0 {
		return record, false, fmt.Errorf("%s has an incomplete Yinyuan-feature route", record.RecordID)
	}
	suffixRoute, ok := record.Routes["suffix_compatibility"]
	if !ok || suffixRoute.Status != "available" {
		return record, false, fmt.Errorf("%s lacks an available suffix-compatible route", record.RecordID)
	}
	fullCode, ok := suffixRoute.Codes["full"]
	if !ok || len(fullCode.YinyuanIDs) < 8 || len(fullCode.YinyuanIDs)%4 != 0 {
		return record, false, fmt.Errorf("%s has no complete suffix-compatible full code", record.RecordID)
	}
	pinyinSyllables := strings.Fields(suffixRoute.NumericPinyin)
	if len(pinyinSyllables) < 2 || pinyinSyllables[len(pinyinSyllables)-1] != "er5" || len(pinyinSyllables)*4 != len(fullCode.YinyuanIDs) {
		return record, false, fmt.Errorf("%s has an invalid explicit 儿 suffix alignment", record.RecordID)
	}
	canonicalAttached := fullCode.YinyuanIDs[len(fullCode.YinyuanIDs)-8 : len(fullCode.YinyuanIDs)-4]
	if !equalStrings(canonicalAttached, route.AttachedSyllableSourceYinyuanIDs) {
		return record, false, fmt.Errorf("%s feature route does not start from its canonical attached syllable", record.RecordID)
	}
	derived := append([]string(nil), canonicalAttached...)
	seenPositions := map[int]struct{}{}
	for _, rewrite := range route.FeatureRewrites {
		if rewrite.Position < 1 || rewrite.Position > 3 {
			return record, false, fmt.Errorf("%s has invalid feature rewrite position %d", record.RecordID, rewrite.Position)
		}
		if _, exists := seenPositions[rewrite.Position]; exists {
			return record, false, fmt.Errorf("%s repeats feature rewrite position %d", record.RecordID, rewrite.Position)
		}
		seenPositions[rewrite.Position] = struct{}{}
		if canonicalAttached[rewrite.Position] != rewrite.SourceYinyuanID {
			return record, false, fmt.Errorf("%s position %d source ID is %s, want %s", record.RecordID, rewrite.Position, rewrite.SourceYinyuanID, canonicalAttached[rewrite.Position])
		}
		sound, ok := index.soundByFeature[featureProjectionKey(rewrite.BaseYinyuanID, rewrite.Features)]
		if !ok || sound.AdmissionStatus != "runtime_pilot" {
			return record, false, fmt.Errorf("%s has no admitted derived Yinyuan for %s plus rhotic=%t/nasalized=%t", record.RecordID, rewrite.BaseYinyuanID, rewrite.Features.Rhotic, rewrite.Features.Nasalized)
		}
		derived[rewrite.Position] = sound.SoundUnitID
	}
	fusedFullIDs := append([]string(nil), fullCode.YinyuanIDs[:len(fullCode.YinyuanIDs)-8]...)
	fusedFullIDs = append(fusedFullIDs, derived...)
	fusedCodes, err := index.deriveModeCodes(fusedFullIDs)
	if err != nil {
		return record, false, fmt.Errorf("%s: %w", record.RecordID, err)
	}
	record.Status = "dual_route_ready"
	route.Status = "available"
	route.AttachedSyllableSource = pinyinSyllables[len(pinyinSyllables)-2]
	route.AttachedSyllableYinyuanIDs = derived
	route.Codes = fusedCodes
	record.Routes["fused_erhua"] = route
	return record, true, nil
}

func (index erhuaSoundProjectionIndex) deriveModeCodes(fullIDs []string) (map[string]erhuaModeCode, error) {
	if len(fullIDs) == 0 || len(fullIDs)%4 != 0 {
		return nil, fmt.Errorf("fused full code length %d is not divisible by four", len(fullIDs))
	}
	modeIDs := map[string][]string{"full": append([]string(nil), fullIDs...)}
	variable, shorthand := make([]string, 0, len(fullIDs)), make([]string, 0, len(fullIDs))
	for offset := 0; offset < len(fullIDs); offset += 4 {
		syllable := fullIDs[offset : offset+4]
		variableFinal := make([]string, 0, 3)
		for _, id := range syllable[1:] {
			if len(variableFinal) == 0 || variableFinal[len(variableFinal)-1] != id {
				variableFinal = append(variableFinal, id)
			}
		}
		variable = append(variable, syllable[0])
		variable = append(variable, variableFinal...)
		shortFinal := append([]string(nil), variableFinal...)
		if len(variableFinal) == 3 {
			family0, ok0 := index.qualityFamilyForID(variableFinal[0])
			family1, ok1 := index.qualityFamilyForID(variableFinal[1])
			family2, ok2 := index.qualityFamilyForID(variableFinal[2])
			grade0, err0 := index.toneGradeForID(variableFinal[0])
			grade1, err1 := index.toneGradeForID(variableFinal[1])
			grade2, err2 := index.toneGradeForID(variableFinal[2])
			if ok0 && ok1 && ok2 && err0 == nil && err1 == nil && err2 == nil && family0 == family1 && family1 == family2 && ((grade0 == "high" && grade1 == "mid" && grade2 == "low") || (grade0 == "low" && grade1 == "mid" && grade2 == "high")) {
				shortFinal = []string{variableFinal[0], variableFinal[2]}
			}
		}
		shorthand = append(shorthand, syllable[0])
		shorthand = append(shorthand, shortFinal...)
	}
	modeIDs["variable"], modeIDs["shorthand"] = variable, shorthand
	result := make(map[string]erhuaModeCode, len(erhuaMixedModes))
	for _, mode := range erhuaMixedModes {
		ids := modeIDs[mode]
		var keys strings.Builder
		for _, id := range ids {
			key, ok := index.layoutKeyForID(id)
			if !ok {
				return nil, fmt.Errorf("derived %s code has unmapped Yinyuan ID %s", mode, id)
			}
			keys.WriteString(key)
		}
		result[mode] = erhuaModeCode{LayoutKeyCode: keys.String(), YinyuanIDs: append([]string(nil), ids...), Length: len(ids)}
	}
	return result, nil
}
