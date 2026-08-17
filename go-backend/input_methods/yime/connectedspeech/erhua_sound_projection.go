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
	LayoutKey        string `json:"layout_key"`
}

type erhuaFeatures struct {
	Rhotic    bool `json:"rhotic"`
	Nasalized bool `json:"nasalized"`
}

type erhuaSoundUnit struct {
	SoundUnitID       string        `json:"sound_unit_id"`
	BaseYinyuanID     string        `json:"base_yinyuan_id"`
	Features          erhuaFeatures `json:"features"`
	QualityFamily     string        `json:"quality_family"`
	ToneGrade         string        `json:"tone_grade"`
	RepresentativeIPA string        `json:"representative_ipa"`
	KeyClassID        string        `json:"key_class_id"`
	AdmissionStatus   string        `json:"admission_status"`
}

type erhuaSoundProjectionBundle struct {
	SchemaVersion  int                  `json:"schema_version"`
	RuntimeEnabled bool                 `json:"runtime_enabled"`
	KeyClasses     []erhuaSoundKeyClass `json:"key_classes"`
	SoundUnits     []erhuaSoundUnit     `json:"sound_units"`
}

type erhuaYinyuanLayout struct {
	FormatVersion  int               `json:"format_version"`
	YinyuanIDToKey map[string]string `json:"yinyuan_id_to_key"`
}

type erhuaSoundProjectionIndex struct {
	keyClassByID        map[string]erhuaSoundKeyClass
	soundByID           map[string]erhuaSoundUnit
	soundByFeature      map[string]erhuaSoundUnit
	layoutKeyByYinyuan  map[string]string
	layoutKeyByKeyClass map[string]string
	pilotSoundUnits     int
	researchSoundUnits  int
	sharedKeyClasses    int
	dedicatedKeyClasses int
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
	if payload.SchemaVersion != 2 || len(payload.KeyClasses) == 0 || len(payload.SoundUnits) == 0 {
		return payload, errors.New("erhua Yinyuan-feature projection has an invalid schema or no records")
	}
	if payload.RuntimeEnabled {
		return payload, errors.New("erhua Yinyuan-feature projection is a derivation source and must remain runtime-disabled")
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

func featureProjectionKey(base string, features erhuaFeatures) string {
	return fmt.Sprintf("%s\x00rhotic=%t\x00nasalized=%t", base, features.Rhotic, features.Nasalized)
}

func indexErhuaSoundProjection(bundle erhuaSoundProjectionBundle, layout erhuaYinyuanLayout) (erhuaSoundProjectionIndex, error) {
	index := erhuaSoundProjectionIndex{
		keyClassByID: map[string]erhuaSoundKeyClass{}, soundByID: map[string]erhuaSoundUnit{}, soundByFeature: map[string]erhuaSoundUnit{},
		layoutKeyByYinyuan: layout.YinyuanIDToKey, layoutKeyByKeyClass: map[string]string{},
	}
	baseLayoutKeys := map[string]struct{}{}
	for _, key := range layout.YinyuanIDToKey {
		baseLayoutKeys[key] = struct{}{}
	}
	dedicatedLayoutKeys := map[string]struct{}{}
	for _, item := range bundle.KeyClasses {
		if item.KeyClassID == "" || !validToneGrade(item.ToneGrade) {
			return index, errors.New("erhua key class has an empty or invalid field")
		}
		hasCarrier, hasDedicatedKey := item.CarrierYinyuanID != "", item.LayoutKey != ""
		if hasCarrier == hasDedicatedKey {
			return index, fmt.Errorf("erhua key class %s must declare exactly one carrier or dedicated layout key", item.KeyClassID)
		}
		if _, ok := index.keyClassByID[item.KeyClassID]; ok {
			return index, fmt.Errorf("duplicate erhua key class %s", item.KeyClassID)
		}
		key := item.LayoutKey
		if hasCarrier {
			key = layout.YinyuanIDToKey[item.CarrierYinyuanID]
			if len([]rune(key)) != 1 {
				return index, fmt.Errorf("erhua key class %s references unmapped carrier %s", item.KeyClassID, item.CarrierYinyuanID)
			}
			index.sharedKeyClasses++
		} else {
			if len([]rune(key)) != 1 {
				return index, fmt.Errorf("erhua key class %s has an invalid dedicated layout key", item.KeyClassID)
			}
			if _, exists := baseLayoutKeys[key]; exists {
				return index, fmt.Errorf("erhua key class %s dedicated key %q collides with the base layout", item.KeyClassID, key)
			}
			if _, exists := dedicatedLayoutKeys[key]; exists {
				return index, fmt.Errorf("duplicate dedicated erhua layout key %q", key)
			}
			dedicatedLayoutKeys[key] = struct{}{}
			index.dedicatedKeyClasses++
		}
		index.keyClassByID[item.KeyClassID] = item
		index.layoutKeyByKeyClass[item.KeyClassID] = key
	}
	for _, item := range bundle.SoundUnits {
		if item.SoundUnitID == "" || item.BaseYinyuanID == "" || item.QualityFamily == "" || item.RepresentativeIPA == "" || !validToneGrade(item.ToneGrade) || !item.Features.Rhotic {
			return index, errors.New("erhua derived Yinyuan has an empty or invalid field")
		}
		if _, ok := index.soundByID[item.SoundUnitID]; ok {
			return index, fmt.Errorf("duplicate erhua derived Yinyuan ID %s", item.SoundUnitID)
		}
		keyClass, ok := index.keyClassByID[item.KeyClassID]
		if !ok || keyClass.ToneGrade != item.ToneGrade {
			return index, fmt.Errorf("erhua derived Yinyuan %s has an invalid key-class projection", item.SoundUnitID)
		}
		featureKey := featureProjectionKey(item.BaseYinyuanID, item.Features)
		if _, ok := index.soundByFeature[featureKey]; ok {
			return index, fmt.Errorf("duplicate erhua base-feature projection %s", item.BaseYinyuanID)
		}
		switch item.AdmissionStatus {
		case "runtime_pilot":
			index.pilotSoundUnits++
		case "research_only":
			index.researchSoundUnits++
		default:
			return index, fmt.Errorf("erhua derived Yinyuan %s has unsupported admission status %q", item.SoundUnitID, item.AdmissionStatus)
		}
		index.soundByFeature[featureKey] = item
		index.soundByID[item.SoundUnitID] = item
	}
	return index, nil
}

func (index erhuaSoundProjectionIndex) validateRouteLayout(record erhuaAliasRecord) error {
	for routeName, route := range record.Routes {
		for mode, code := range route.Codes {
			var projected strings.Builder
			for _, id := range code.YinyuanIDs {
				key, ok := index.layoutKeyForID(id)
				if !ok {
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
	if route.Status != "available" || len(route.AttachedSyllableYinyuanIDs) != 4 {
		return erhuaProjectedRoute{}, fmt.Errorf("%s has no available four-position feature-derived route", record.RecordID)
	}
	for _, rewrite := range route.FeatureRewrites {
		if rewrite.Position < 1 || rewrite.Position > 3 {
			return erhuaProjectedRoute{}, fmt.Errorf("%s has invalid feature rewrite position %d", record.RecordID, rewrite.Position)
		}
		sound, ok := index.soundByFeature[featureProjectionKey(rewrite.BaseYinyuanID, rewrite.Features)]
		if !ok || sound.AdmissionStatus != "runtime_pilot" {
			return erhuaProjectedRoute{}, fmt.Errorf("%s has no admitted derived Yinyuan for %s plus features", record.RecordID, rewrite.BaseYinyuanID)
		}
		if route.AttachedSyllableYinyuanIDs[rewrite.Position] != sound.SoundUnitID {
			return erhuaProjectedRoute{}, fmt.Errorf("%s feature rewrite position %d did not produce %s", record.RecordID, rewrite.Position, sound.SoundUnitID)
		}
	}
	result := erhuaProjectedRoute{SoundUnitIDs: append([]string(nil), route.AttachedSyllableYinyuanIDs...)}
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
			key := index.layoutKeyByKeyClass[keyClass.KeyClassID]
			if key == "" {
				return "", fmt.Errorf("derived Yinyuan %s has no physical-key projection", id)
			}
			parts = append(parts, fmt.Sprintf("%s+rhotic=%t+nasalized=%t→%s→%s(%s)", sound.BaseYinyuanID, sound.Features.Rhotic, sound.Features.Nasalized, sound.SoundUnitID, keyClass.KeyClassID, key))
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

func (index erhuaSoundProjectionIndex) layoutKeyForID(id string) (string, bool) {
	if sound, ok := index.soundByID[id]; ok {
		key := index.layoutKeyByKeyClass[sound.KeyClassID]
		return key, len([]rune(key)) == 1
	}
	key := index.layoutKeyByYinyuan[id]
	return key, len([]rune(key)) == 1
}

func validToneGrade(value string) bool { return value == "high" || value == "mid" || value == "low" }

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		if left[i] != right[i] {
			return false
		}
	}
	return true
}

func (index erhuaSoundProjectionIndex) toneGradeForID(id string) (string, error) {
	if sound, ok := index.soundByID[id]; ok {
		return sound.ToneGrade, nil
	}
	if len(id) != 3 || id[0] != 'M' {
		return "", fmt.Errorf("%s is not a tonal musical Yinyuan ID", id)
	}
	ordinal, err := strconv.Atoi(id[1:])
	if err != nil || ordinal < 1 {
		return "", fmt.Errorf("%s is not a tonal musical Yinyuan ID", id)
	}
	return []string{"high", "mid", "low"}[(ordinal-1)%3], nil
}

func (index erhuaSoundProjectionIndex) qualityFamilyForID(id string) (string, bool) {
	if sound, ok := index.soundByID[id]; ok {
		return "R:" + sound.QualityFamily, true
	}
	if len(id) != 3 || id[0] != 'M' {
		return "", false
	}
	ordinal, err := strconv.Atoi(id[1:])
	if err != nil || ordinal < 1 {
		return "", false
	}
	return fmt.Sprintf("M:%02d", (ordinal-1)/3), true
}
