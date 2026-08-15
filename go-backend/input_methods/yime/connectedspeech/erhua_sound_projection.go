package connectedspeech

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type erhuaSoundKeyClass struct {
	KeyClassID       string `json:"key_class_id"`
	ToneGrade        string `json:"tone_grade"`
	CarrierYinyuanID string `json:"carrier_yinyuan_id"`
}

type erhuaSoundUnit struct {
	SoundUnitID       string `json:"sound_unit_id"`
	QualityFamily     string `json:"quality_family"`
	ToneGrade         string `json:"tone_grade"`
	RepresentativeIPA string `json:"representative_ipa"`
	KeyClassID        string `json:"key_class_id"`
	AdmissionStatus   string `json:"admission_status"`
}

type erhuaSurfaceProjection struct {
	SurfaceClass               string              `json:"surface_class"`
	RuntimeStatus              string              `json:"runtime_status"`
	RhoticFinalPositions       []int               `json:"rhotic_final_positions"`
	RetainedPositionYinyuanIDs map[string][]string `json:"retained_position_yinyuan_ids"`
	SoundFamily                string              `json:"sound_family"`
}

type erhuaSoundProjectionBundle struct {
	SchemaVersion  int                      `json:"schema_version"`
	RuntimeEnabled bool                     `json:"runtime_enabled"`
	KeyClasses     []erhuaSoundKeyClass     `json:"key_classes"`
	SoundUnits     []erhuaSoundUnit         `json:"sound_units"`
	SurfaceClasses []erhuaSurfaceProjection `json:"surface_classes"`
}

type erhuaYinyuanLayout struct {
	FormatVersion  int               `json:"format_version"`
	YinyuanIDToKey map[string]string `json:"yinyuan_id_to_key"`
}

type erhuaSoundProjectionIndex struct {
	keyClassByID       map[string]erhuaSoundKeyClass
	keyClassByCarrier  map[string]erhuaSoundKeyClass
	soundByID          map[string]erhuaSoundUnit
	soundByFamilyTone  map[string]erhuaSoundUnit
	surfaceClassByID   map[string]erhuaSurfaceProjection
	layoutKeyByYinyuan map[string]string
	pilotSoundUnits    int
	researchSoundUnits int
}

type erhuaProjectedRoute struct {
	SoundUnitIDs  []string
	KeyProjection string
}

func loadErhuaSoundProjection(path string) (erhuaSoundProjectionBundle, error) {
	var payload erhuaSoundProjectionBundle
	data, err := os.ReadFile(path)
	if err != nil {
		return payload, err
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return payload, err
	}
	if payload.SchemaVersion != 1 || len(payload.KeyClasses) == 0 || len(payload.SoundUnits) == 0 || len(payload.SurfaceClasses) == 0 {
		return payload, errors.New("erhua sound-key projection has an invalid schema or no records")
	}
	if payload.RuntimeEnabled {
		return payload, errors.New("erhua sound-key projection is a derivation source and must remain runtime-disabled")
	}
	return payload, nil
}

func loadErhuaYinyuanLayout(path string) (erhuaYinyuanLayout, error) {
	var payload erhuaYinyuanLayout
	data, err := os.ReadFile(path)
	if err != nil {
		return payload, err
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return payload, err
	}
	if payload.FormatVersion != 1 || len(payload.YinyuanIDToKey) == 0 {
		return payload, errors.New("Yinyuan layout has an invalid schema or no mappings")
	}
	return payload, nil
}

func indexErhuaSoundProjection(bundle erhuaSoundProjectionBundle, layout erhuaYinyuanLayout) (erhuaSoundProjectionIndex, error) {
	index := erhuaSoundProjectionIndex{
		keyClassByID:       map[string]erhuaSoundKeyClass{},
		keyClassByCarrier:  map[string]erhuaSoundKeyClass{},
		soundByID:          map[string]erhuaSoundUnit{},
		soundByFamilyTone:  map[string]erhuaSoundUnit{},
		surfaceClassByID:   map[string]erhuaSurfaceProjection{},
		layoutKeyByYinyuan: layout.YinyuanIDToKey,
	}
	for _, item := range bundle.KeyClasses {
		if item.KeyClassID == "" || item.CarrierYinyuanID == "" || !validToneGrade(item.ToneGrade) {
			return index, errors.New("erhua key class has an empty or invalid field")
		}
		if _, ok := index.keyClassByID[item.KeyClassID]; ok {
			return index, fmt.Errorf("duplicate erhua key class %s", item.KeyClassID)
		}
		if _, ok := index.keyClassByCarrier[item.CarrierYinyuanID]; ok {
			return index, fmt.Errorf("duplicate erhua carrier Yinyuan ID %s", item.CarrierYinyuanID)
		}
		if key := layout.YinyuanIDToKey[item.CarrierYinyuanID]; len([]rune(key)) != 1 {
			return index, fmt.Errorf("erhua key class %s references unmapped carrier %s", item.KeyClassID, item.CarrierYinyuanID)
		}
		index.keyClassByID[item.KeyClassID] = item
		index.keyClassByCarrier[item.CarrierYinyuanID] = item
	}
	soundsPerKeyClass := map[string]int{}
	seenSoundIDs := map[string]struct{}{}
	for _, item := range bundle.SoundUnits {
		if item.SoundUnitID == "" || item.QualityFamily == "" || item.RepresentativeIPA == "" || !validToneGrade(item.ToneGrade) {
			return index, errors.New("erhua sound unit has an empty or invalid field")
		}
		if _, ok := seenSoundIDs[item.SoundUnitID]; ok {
			return index, fmt.Errorf("duplicate erhua sound unit %s", item.SoundUnitID)
		}
		if _, clashesWithKeyClass := index.keyClassByID[item.SoundUnitID]; clashesWithKeyClass {
			return index, fmt.Errorf("erhua sound unit %s must not reuse a key-class ID", item.SoundUnitID)
		}
		if _, clashesWithCarrier := index.keyClassByCarrier[item.SoundUnitID]; clashesWithCarrier {
			return index, fmt.Errorf("erhua sound unit %s must not reuse a carrier Yinyuan ID", item.SoundUnitID)
		}
		seenSoundIDs[item.SoundUnitID] = struct{}{}
		keyClass, ok := index.keyClassByID[item.KeyClassID]
		if !ok || keyClass.ToneGrade != item.ToneGrade {
			return index, fmt.Errorf("erhua sound unit %s has an invalid key-class projection", item.SoundUnitID)
		}
		switch item.AdmissionStatus {
		case "runtime_pilot":
			index.pilotSoundUnits++
		case "research_only":
			index.researchSoundUnits++
		default:
			return index, fmt.Errorf("erhua sound unit %s has unsupported admission status %q", item.SoundUnitID, item.AdmissionStatus)
		}
		familyTone := item.QualityFamily + "\x00" + item.ToneGrade
		if _, ok := index.soundByFamilyTone[familyTone]; ok {
			return index, fmt.Errorf("duplicate erhua sound family/tone %s/%s", item.QualityFamily, item.ToneGrade)
		}
		index.soundByFamilyTone[familyTone] = item
		index.soundByID[item.SoundUnitID] = item
		soundsPerKeyClass[item.KeyClassID]++
	}
	for keyClassID := range index.keyClassByID {
		if soundsPerKeyClass[keyClassID] < 2 {
			return index, fmt.Errorf("erhua key class %s does not demonstrate many-to-one sound projection", keyClassID)
		}
	}
	for _, item := range bundle.SurfaceClasses {
		if item.SurfaceClass == "" || item.SoundFamily == "" || len(item.RhoticFinalPositions) == 0 {
			return index, errors.New("erhua surface class has an empty or invalid field")
		}
		if _, ok := index.surfaceClassByID[item.SurfaceClass]; ok {
			return index, fmt.Errorf("duplicate erhua surface class %s", item.SurfaceClass)
		}
		switch item.RuntimeStatus {
		case "pilot", "research_only":
		default:
			return index, fmt.Errorf("erhua surface class %s has unsupported runtime status %q", item.SurfaceClass, item.RuntimeStatus)
		}
		positionSet := map[int]struct{}{}
		for _, position := range item.RhoticFinalPositions {
			if position < 1 || position > 3 {
				return index, fmt.Errorf("erhua surface class %s has invalid final position %d", item.SurfaceClass, position)
			}
			if _, ok := positionSet[position]; ok {
				return index, fmt.Errorf("erhua surface class %s repeats final position %d", item.SurfaceClass, position)
			}
			positionSet[position] = struct{}{}
		}
		for positionText, allowedIDs := range item.RetainedPositionYinyuanIDs {
			position, err := strconv.Atoi(positionText)
			if err != nil || position < 1 || position > 3 || len(allowedIDs) == 0 {
				return index, fmt.Errorf("erhua surface class %s has invalid retained position %q", item.SurfaceClass, positionText)
			}
			if _, rhotic := positionSet[position]; rhotic {
				return index, fmt.Errorf("erhua surface class %s marks position %d both retained and rhotic", item.SurfaceClass, position)
			}
			for _, id := range allowedIDs {
				if len([]rune(layout.YinyuanIDToKey[id])) != 1 {
					return index, fmt.Errorf("erhua surface class %s references unmapped retained Yinyuan ID %s", item.SurfaceClass, id)
				}
			}
		}
		for _, tone := range []string{"high", "mid", "low"} {
			sound, ok := index.soundByFamilyTone[item.SoundFamily+"\x00"+tone]
			if !ok {
				return index, fmt.Errorf("erhua surface class %s lacks %s sound unit", item.SurfaceClass, tone)
			}
			if item.RuntimeStatus == "pilot" && sound.AdmissionStatus != "runtime_pilot" {
				return index, fmt.Errorf("pilot erhua surface class %s references research-only sound unit %s", item.SurfaceClass, sound.SoundUnitID)
			}
		}
		index.surfaceClassByID[item.SurfaceClass] = item
	}
	return index, nil
}

func (index erhuaSoundProjectionIndex) validateRouteLayout(record erhuaAliasRecord) error {
	for routeName, route := range record.Routes {
		for mode, code := range route.Codes {
			var projected strings.Builder
			for _, id := range code.YinyuanIDs {
				key, ok := index.layoutKeyByYinyuan[id]
				if !ok || len([]rune(key)) != 1 {
					return fmt.Errorf("%s has unmapped %s/%s Yinyuan ID %s", record.RecordID, routeName, mode, id)
				}
				projected.WriteString(key)
			}
			if projected.String() != code.LayoutKeyCode {
				return fmt.Errorf("%s %s/%s layout code %q does not match ID projection %q", record.RecordID, routeName, mode, code.LayoutKeyCode, projected.String())
			}
		}
	}
	return nil
}

func (index erhuaSoundProjectionIndex) projectFusedRoute(record erhuaAliasRecord) (erhuaProjectedRoute, error) {
	route := record.Routes["fused_erhua"]
	surfaceClass, ok := index.surfaceClassByID[route.SurfaceClass]
	if !ok {
		return erhuaProjectedRoute{}, fmt.Errorf("%s references unknown fused surface class %q", record.RecordID, route.SurfaceClass)
	}
	if surfaceClass.RuntimeStatus != "pilot" {
		return erhuaProjectedRoute{}, fmt.Errorf("%s references non-pilot fused surface class %s", record.RecordID, route.SurfaceClass)
	}
	if len(route.AttachedSyllableYinyuanIDs) != 4 {
		return erhuaProjectedRoute{}, fmt.Errorf("%s fused route must have one initial plus three final positions", record.RecordID)
	}
	full := route.Codes["full"].YinyuanIDs
	if len(full) < 4 || !equalStrings(full[len(full)-4:], route.AttachedSyllableYinyuanIDs) {
		return erhuaProjectedRoute{}, fmt.Errorf("%s fused full code does not end in its attached-syllable tuple", record.RecordID)
	}
	result := erhuaProjectedRoute{SoundUnitIDs: append([]string(nil), route.AttachedSyllableYinyuanIDs...)}
	rhoticPositions := map[int]struct{}{}
	for _, position := range surfaceClass.RhoticFinalPositions {
		rhoticPositions[position] = struct{}{}
		carrierID := route.AttachedSyllableYinyuanIDs[position]
		keyClass, ok := index.keyClassByCarrier[carrierID]
		if !ok {
			return erhuaProjectedRoute{}, fmt.Errorf("%s fused position %d does not use an erhua key carrier", record.RecordID, position)
		}
		sound := index.soundByFamilyTone[surfaceClass.SoundFamily+"\x00"+keyClass.ToneGrade]
		if sound.AdmissionStatus != "runtime_pilot" {
			return erhuaProjectedRoute{}, fmt.Errorf("%s fused position %d would export research-only sound %s", record.RecordID, position, sound.SoundUnitID)
		}
		result.SoundUnitIDs[position] = sound.SoundUnitID
	}
	for position := 1; position <= 3; position++ {
		if _, rhotic := rhoticPositions[position]; rhotic {
			continue
		}
		allowed := surfaceClass.RetainedPositionYinyuanIDs[strconv.Itoa(position)]
		if !containsExact(allowed, route.AttachedSyllableYinyuanIDs[position]) {
			return erhuaProjectedRoute{}, fmt.Errorf("%s fused retained position %d has unexpected Yinyuan ID %s", record.RecordID, position, route.AttachedSyllableYinyuanIDs[position])
		}
	}
	projection, err := index.describeSoundKeyProjection(result.SoundUnitIDs)
	if err != nil {
		return erhuaProjectedRoute{}, fmt.Errorf("%s: %w", record.RecordID, err)
	}
	result.KeyProjection = projection
	return result, nil
}

func (index erhuaSoundProjectionIndex) describeSoundKeyProjection(ids []string) (string, error) {
	parts := make([]string, 0, len(ids))
	for _, id := range ids {
		if sound, ok := index.soundByID[id]; ok {
			keyClass := index.keyClassByID[sound.KeyClassID]
			key := index.layoutKeyByYinyuan[keyClass.CarrierYinyuanID]
			if key == "" {
				return "", fmt.Errorf("sound unit %s has no physical-key projection", id)
			}
			parts = append(parts, fmt.Sprintf("%s→%s→%s(%s)", id, keyClass.KeyClassID, keyClass.CarrierYinyuanID, key))
			continue
		}
		key := index.layoutKeyByYinyuan[id]
		if key == "" {
			return "", fmt.Errorf("retained Yinyuan ID %s has no physical-key projection", id)
		}
		parts = append(parts, fmt.Sprintf("%s→%s", id, key))
	}
	return strings.Join(parts, "；"), nil
}

func validToneGrade(value string) bool {
	return value == "high" || value == "mid" || value == "low"
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

func containsExact(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
