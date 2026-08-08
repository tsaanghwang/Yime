// Package connectedspeech provides the offline-only validation and audit
// boundary for proposed connected-speech input aliases. It deliberately has
// no dependency on a Rime session, PIME, user data, or dictionary writers.
package connectedspeech

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
)

const (
	SchemaVersion = 1
	ToolVersion   = "connected-speech-audit-v1"
)

type YinyuanTuple [4]string

func (tuple *YinyuanTuple) UnmarshalJSON(data []byte) error {
	var values []string
	if err := json.Unmarshal(data, &values); err != nil {
		return err
	}
	if len(values) != 4 {
		return fmt.Errorf("四音元元组必须恰有 4 项，实际为 %d", len(values))
	}
	copy(tuple[:], values)
	return nil
}

type YinyuanSequence []YinyuanTuple

type SourceObservation struct {
	ObservationID       string  `json:"observation_id"`
	SourcePolicy        string  `json:"source_policy"`
	SourceLocator       string  `json:"source_locator"`
	SourceSHA256        string  `json:"source_sha256"`
	TextRaw             string  `json:"text_raw"`
	ReadingRaw          string  `json:"reading_raw"`
	TextCorrected       *string `json:"text_corrected,omitempty"`
	ReadingCorrected    *string `json:"reading_corrected,omitempty"`
	TranscriptionStatus string  `json:"transcription_status"`
	Note                string  `json:"note,omitempty"`
}

type Rewrite struct {
	SyllableIndex int      `json:"syllable_index"`
	Position      string   `json:"position"`
	FromID        string   `json:"from_id"`
	ToID          string   `json:"to_id"`
	Attributes    []string `json:"attributes"`
}

type Record struct {
	SchemaVersion           int                 `json:"schema_version"`
	RulesetVersion          string              `json:"ruleset_version"`
	RecordID                string              `json:"record_id"`
	RecordRevision          int                 `json:"record_revision"`
	Text                    string              `json:"text"`
	CanonicalPinyin         string              `json:"canonical_pinyin"`
	Phenomenon              string              `json:"phenomenon"`
	Scope                   string              `json:"scope"`
	CandidateTextPolicy     string              `json:"candidate_text_policy"`
	TranscriptionStatus     string              `json:"transcription_status,omitempty"`
	AdjudicationStatus      string              `json:"adjudication_status"`
	RuntimeEnabled          bool                `json:"runtime_enabled"`
	RuleID                  string              `json:"rule_id,omitempty"`
	UnderlyingTone          *int                `json:"underlying_tone,omitempty"`
	ErhuaStatus             string              `json:"erhua_status,omitempty"`
	AttachmentSyllableIndex *int                `json:"attachment_syllable_index,omitempty"`
	ErCharacterIndex        *int                `json:"er_character_index,omitempty"`
	ErhuaClass              *string             `json:"erhua_class,omitempty"`
	SourceObservations      []SourceObservation `json:"source_observations"`
	CompatibilityReading    *string             `json:"compatibility_reading,omitempty"`
	SurfaceReading          *string             `json:"surface_reading,omitempty"`
	CanonicalYinyuanIDs     YinyuanSequence     `json:"canonical_yinyuan_ids"`
	CompatibilityYinyuanIDs *YinyuanSequence    `json:"compatibility_yinyuan_ids,omitempty"`
	SurfaceYinyuanIDs       *YinyuanSequence    `json:"surface_yinyuan_ids,omitempty"`
	Rewrites                []Rewrite           `json:"rewrites,omitempty"`
	Note                    string              `json:"note,omitempty"`
}

// Switches exist only in an offline trial manifest. They never alter a record
// and default to false through Go's zero value.
type Switches struct {
	Enabled                  bool `json:"connected_speech.enabled"`
	ToneSandhi               bool `json:"connected_speech.tone_sandhi"`
	NeutralToneSurface       bool `json:"connected_speech.neutral_tone_surface"`
	ErhuaSuffixCompatibility bool `json:"connected_speech.erhua_suffix_compatibility"`
	ErhuaFused               bool `json:"connected_speech.erhua_fused"`
	ParticleAllomorphy       bool `json:"connected_speech.particle_allomorphy"`
	Assimilation             bool `json:"connected_speech.assimilation"`
	Dissimilation            bool `json:"connected_speech.dissimilation"`
}

func LoadRecords(path string) ([]Record, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取语流音变记录 %s: %w", path, err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var records []Record
	if err := decoder.Decode(&records); err != nil {
		return nil, fmt.Errorf("解析语流音变记录 %s: %w", path, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err == nil {
		return nil, fmt.Errorf("解析语流音变记录 %s: JSON 数组后存在第二个值", path)
	} else if !errorsIsEOF(err) {
		return nil, fmt.Errorf("解析语流音变记录 %s: JSON 数组后存在无效内容: %w", path, err)
	}
	return records, nil
}

// ValidateSchemaDocument protects the checked-in v1 contract itself. Record
// validation remains implemented in Go so the audit tool stays dependency-free
// and can run offline on the build machine.
func ValidateSchemaDocument(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("读取记录 Schema %s: %w", path, err)
	}
	var document struct {
		Schema     string                     `json:"$schema"`
		ID         string                     `json:"$id"`
		Type       string                     `json:"type"`
		Required   []string                   `json:"required"`
		Properties map[string]json.RawMessage `json:"properties"`
		Defs       map[string]json.RawMessage `json:"$defs"`
	}
	if err := json.Unmarshal(data, &document); err != nil {
		return fmt.Errorf("解析记录 Schema %s: %w", path, err)
	}
	if document.Schema != "https://json-schema.org/draft/2020-12/schema" {
		return fmt.Errorf("记录 Schema 必须使用 JSON Schema Draft 2020-12")
	}
	if !strings.HasSuffix(document.ID, "connected-speech-record-v1.json") || document.Type != "object" {
		return fmt.Errorf("记录 Schema 的 $id 或顶层类型不符合 v1 契约")
	}
	required := map[string]bool{}
	for _, name := range document.Required {
		required[name] = true
	}
	for _, name := range []string{"schema_version", "ruleset_version", "record_id", "text", "canonical_pinyin", "adjudication_status", "runtime_enabled", "source_observations", "canonical_yinyuan_ids"} {
		if !required[name] || document.Properties[name] == nil {
			return fmt.Errorf("记录 Schema 缺少必要契约字段 %s", name)
		}
	}
	if document.Defs["syllableSequence"] == nil {
		return fmt.Errorf("记录 Schema 缺少 syllableSequence 定义")
	}
	return nil
}

func errorsIsEOF(err error) bool {
	return err == io.EOF
}
