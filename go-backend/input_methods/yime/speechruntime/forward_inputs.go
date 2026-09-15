package speechruntime

import (
	"encoding/hex"
	"errors"
	"strings"
)

// expectedForwardInputs independently pins the complete v1 formal-source
// closure. This must stay identical to the offline validator's SOURCE_PATHS;
// a future scope change needs a reviewed update, never a receipt-supplied list.
var expectedForwardInputs = map[string]string{
	"review":                  "docs/project/connected_speech/third_tone_stage5b_review.tsv",
	"decisions":               "docs/project/connected_speech/third_tone_stage5b_decisions.tsv",
	"rule_sources":            "docs/project/connected_speech/third_tone_stage5b_sources.tsv",
	"scope":                   "docs/project/connected_speech/third_tone_sandhi_scope.tsv",
	"phrase_pronunciations":   "internal_data/phrase_pinyin/phrase_pinyin.txt",
	"canonical_inventory":     "internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json",
	"canonical_decomposition": "internal_data/yime_syllable_decomposition.tsv",
	"packaged_decomposition":  "go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv",
	"canonical_layout":        "internal_data/manual_key_layout.json",
	"packaged_layout":         "go-backend/input_methods/yime/data/yime_yinyuan_layout.json",
	"semantic_initials":       "syllable/yinyuan/zaoyin_yinyuan_enhanced.json",
	"semantic_musical":        "syllable/yinyuan/yueyin_yinyuan_enhanced.json",
	"canonical_symbols":       "internal_data/key_to_symbol.json",
	"initial_codepoints":      "syllable/yinyuan/shouyin_codepoint.json",
	"initial_analysis":        "syllable/pianyin/zaoyin_pianyin.json",
	"musical_attributes":      "syllable/yinyuan/variables_of_attributes.json",
	"pianyin_sequence":        "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json",
	"marked_finals":           "syllable/yinyuan/ganyin.json",
	"neutral_exceptions":      "internal_data/pinyin_source_db/neutral_tone_encoding_exceptions.json",
	"formal_pipeline":         "syllable/analysis/syllable_encoding_pipeline.py",
	"formal_splitter":         "syllable/analysis/syllable_splitter.py",
	"formal_encoder":          "syllable/codec/yinjie_encoder.py",
	"formal_initial_encoder":  "syllable/analysis/shouyin_encoder.py",
	"formal_initial_source":   "syllable/analysis/zaoyin_pianyin_source.py",
	"formal_musical_encoder":  "syllable/analysis/ganyin_encoder.py",
	"formal_musical_mapper":   "syllable/analysis/yueyin_mapper.py",
	"formal_id_chain":         "yime/utils/yinyuan_id_chain.py",
	"validator":               "tools/lexicon/validate_connected_speech_forward.py",
	"formal_import_01":        "syllable/__init__.py",
	"formal_import_02":        "syllable/analysis/__init__.py",
	"formal_import_03":        "syllable/analysis/ganyin_categorizer.py",
	"formal_import_04":        "syllable/analysis/ganyin_yinyuan_slots.py",
	"formal_import_05":        "syllable/analysis/segment_split.py",
	"formal_import_06":        "syllable/analysis/syllable.py",
	"formal_import_07":        "syllable/analysis/syllable_analyzer.py",
	"formal_import_08":        "syllable/analysis/syllable_categorizer.py",
	"formal_import_09":        "syllable/codec/__init__.py",
	"formal_import_10":        "syllable/codec/input_shorthand/__init__.py",
	"formal_import_11":        "syllable/codec/input_shorthand/tone_omission.py",
	"formal_import_12":        "syllable/codec/model_full_code/__init__.py",
	"formal_import_13":        "syllable/codec/model_full_code/structure.py",
	"formal_import_14":        "syllable/codec/neutral_tone_encoding.py",
	"formal_import_15":        "syllable/codec/paths.py",
	"formal_import_16":        "syllable/codec/variable_length_yinyuan/__init__.py",
	"formal_import_17":        "syllable/codec/variable_length_yinyuan/transform.py",
	"formal_import_18":        "syllable/codec/yinjie.py",
	"formal_import_19":        "syllable/codec/yinjie_api_manifest.py",
	"formal_import_20":        "syllable/codec/yinjie_decoder.py",
	"formal_import_21":        "yime/__init__.py",
	"formal_import_22":        "yime/utils/__init__.py",
	"formal_import_23":        "yime/utils/backup.py",
	"formal_import_24":        "yime/utils/charfilter.py",
	"formal_import_25":        "yime/utils/marked_pinyin.py",
	"formal_import_26":        "yime/utils/pinyin_normalizer.py",
	"formal_import_27":        "yime/utils/pinyin_zhuyin.py",
	"formal_import_28":        "yime/utils/reverse_key_value_pairs.py",
}

func canonicalForwardDigest(value string) bool {
	if len(value) != 64 || value != strings.ToLower(value) {
		return false
	}
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == 32
}

func validateForwardInputs(receipt ForwardReceipt) error {
	if len(receipt.InputSHA256) != len(expectedForwardInputs) || len(receipt.Inputs) != len(expectedForwardInputs) {
		return errors.New("forward source input closure incomplete")
	}
	seenRoles := make(map[string]bool, len(expectedForwardInputs))
	seenPaths := make(map[string]bool, len(expectedForwardInputs))
	for _, input := range receipt.Inputs {
		expectedPath, ok := expectedForwardInputs[input.Role]
		if !ok || input.Path != expectedPath || seenRoles[input.Role] || seenPaths[input.Path] {
			return errors.New("forward source role/path set mismatch")
		}
		if !canonicalForwardDigest(input.SHA256) {
			return errors.New("forward source digest must be lowercase SHA-256")
		}
		mapDigest, ok := receipt.InputSHA256[input.Path]
		if !ok || !canonicalForwardDigest(mapDigest) || mapDigest != input.SHA256 {
			return errors.New("forward source input map/array mismatch")
		}
		seenRoles[input.Role] = true
		seenPaths[input.Path] = true
	}
	// Length and one-to-one checks above require every fixed role. Still check
	// every map key explicitly so undeclared paths can never escape rehashing.
	for path, digest := range receipt.InputSHA256 {
		if !seenPaths[path] || !canonicalForwardDigest(digest) {
			return errors.New("forward source undeclared input or invalid digest")
		}
	}
	return nil
}
