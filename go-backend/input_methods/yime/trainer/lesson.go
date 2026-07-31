// Package trainer loads Yime typing lessons and resolves their exercises
// against the active, generated Yime layout data.
package trainer

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/syllableinspector"
)

const SchemaVersion = "1.2"

const (
	SectionKeymap            = "keymap"
	SectionSyllableAssociate = "syllable_association"
	SectionSyllableContrast  = "syllable_contrast"
	SectionCommonWords       = "common_words"
)

// Lesson is the stable, data-only course contract migrated from the original
// standalone Python prototype.
type Lesson struct {
	SchemaVersion string    `json:"schema_version"`
	ID            string    `json:"id"`
	Title         string    `json:"title"`
	Description   string    `json:"description,omitempty"`
	Tags          []string  `json:"tags,omitempty"`
	Sections      []Section `json:"sections"`

	baseDir string
}

type Section struct {
	ID          string `json:"id"`
	Type        string `json:"type"`
	Title       string `json:"title"`
	Instruction string `json:"instruction,omitempty"`
	Items       []Item `json:"items"`
}

type Item struct {
	Prompt         string   `json:"prompt,omitempty"`
	YinyuanID      string   `json:"yinyuan_id,omitempty"`
	ReferenceLabel string   `json:"reference_label,omitempty"`
	ReferenceValue string   `json:"reference_value,omitempty"`
	Syllable       string   `json:"syllable,omitempty"`
	Hanzi          string   `json:"hanzi,omitempty"`
	Contrast       []string `json:"contrast,omitempty"`
	Text           string   `json:"text,omitempty"`
	Syllables      []string `json:"syllables,omitempty"`
	FrequencyTier  string   `json:"frequency_tier,omitempty"`
	Notes          string   `json:"notes,omitempty"`
	Audio          string   `json:"audio,omitempty"`
}

// Exercise is one runtime-ready item. Expected always comes from the active
// layout/code table, except for a keymap item whose key is itself read from the
// active layout profile.
type Exercise struct {
	SectionType   string
	SectionTitle  string
	Instruction   string
	Prompt        string
	Detail        string
	Expected      string
	AnswerLabel   string
	MarkedPinyin  string
	Segments      []Segment
	AudioPath     string
	AudioDeclared bool
}

// Segment is one structural position in a canonical four-Yinyuan syllable.
// Key is resolved from the active layout and is never stored in lesson data.
type Segment struct {
	Position          string
	ID                string
	Notation          string
	DisplayName       string
	RepresentativeIPA string
	Key               string
	AudioPath         string
}

type Resolver struct {
	codeMap       map[string]reverselookup.CodeRecord
	layout        layoutdesigner.Profile
	catalog       Catalog
	decomposition map[string]syllableinspector.Row
}

func Load(path string) (Lesson, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return Lesson{}, err
	}
	var lesson Lesson
	if err := json.Unmarshal(payload, &lesson); err != nil {
		return Lesson{}, fmt.Errorf("课程 JSON 格式错误: %w", err)
	}
	if err := lesson.Validate(); err != nil {
		return Lesson{}, err
	}
	lesson.baseDir = filepath.Dir(path)
	return lesson, nil
}

func (lesson Lesson) Validate() error {
	if lesson.SchemaVersion != SchemaVersion {
		return fmt.Errorf("不支持课程格式 %q，当前需要 %s", lesson.SchemaVersion, SchemaVersion)
	}
	if strings.TrimSpace(lesson.ID) == "" || strings.TrimSpace(lesson.Title) == "" {
		return fmt.Errorf("课程必须包含 id 和 title")
	}
	if len(lesson.Sections) == 0 {
		return fmt.Errorf("课程必须至少包含一个分段")
	}
	sectionIDs := map[string]bool{}
	for sectionIndex, section := range lesson.Sections {
		context := fmt.Sprintf("分段 %d", sectionIndex+1)
		if strings.TrimSpace(section.ID) == "" || strings.TrimSpace(section.Title) == "" {
			return fmt.Errorf("%s 必须包含 id 和 title", context)
		}
		if sectionIDs[section.ID] {
			return fmt.Errorf("分段 id 重复：%s", section.ID)
		}
		sectionIDs[section.ID] = true
		if len(section.Items) == 0 {
			return fmt.Errorf("%s 必须至少包含一道题", context)
		}
		for itemIndex, item := range section.Items {
			itemContext := fmt.Sprintf("%s第 %d 题", context, itemIndex+1)
			if err := validateOptionalRelativePath(item.Audio); err != nil {
				return fmt.Errorf("%s 的 audio 无效: %w", itemContext, err)
			}
			switch section.Type {
			case SectionKeymap:
				if strings.TrimSpace(item.YinyuanID) == "" {
					return fmt.Errorf("%s 缺少 yinyuan_id", itemContext)
				}
			case SectionSyllableAssociate, SectionSyllableContrast:
				if !reverselookup.ValidateNumericTonePinyin(item.Syllable) {
					return fmt.Errorf("%s 的 syllable 不是数字标调拼音：%s", itemContext, item.Syllable)
				}
			case SectionCommonWords:
				if strings.TrimSpace(item.Text) == "" || len(item.Syllables) == 0 {
					return fmt.Errorf("%s 必须包含 text 和 syllables", itemContext)
				}
				if reverselookup.PhraseSyllableCount(item.Text) != len(item.Syllables) {
					return fmt.Errorf("%s 的字数和音节数不一致", itemContext)
				}
				for _, syllable := range item.Syllables {
					if !reverselookup.ValidateNumericTonePinyin(syllable) {
						return fmt.Errorf("%s 包含无效数字标调拼音：%s", itemContext, syllable)
					}
				}
			default:
				return fmt.Errorf("%s 使用未知题型：%s", context, section.Type)
			}
		}
	}
	return nil
}

func NewResolver(dataDir string) (*Resolver, error) {
	codeMap, err := reverselookup.LoadSharedCodeMap(dataDir)
	if err != nil {
		return nil, err
	}
	layout, err := layoutdesigner.LoadProfile(filepath.Join(dataDir, layoutdesigner.ProfileFileName))
	if err != nil {
		return nil, fmt.Errorf("读取当前音元布局: %w", err)
	}
	catalog, err := LoadCatalog(filepath.Join(dataDir, "trainer", CatalogFileName))
	if err != nil {
		return nil, fmt.Errorf("读取音元教学语义目录: %w", err)
	}
	inventory, err := syllableinspector.Load(dataDir)
	if err != nil {
		return nil, fmt.Errorf("读取标准拼音音节分解: %w", err)
	}
	decomposition := make(map[string]syllableinspector.Row, len(inventory.Rows))
	for _, row := range inventory.Rows {
		decomposition[row.PinyinTone] = row
	}
	return &Resolver{codeMap: codeMap, layout: layout, catalog: catalog, decomposition: decomposition}, nil
}

func (resolver *Resolver) Resolve(lesson Lesson, mode reverselookup.Mode) ([]Exercise, error) {
	if resolver == nil {
		return nil, fmt.Errorf("练习解析器未初始化")
	}
	var exercises []Exercise
	for _, section := range lesson.Sections {
		for _, item := range section.Items {
			exercise, err := resolver.resolveItem(lesson, section, item, mode)
			if err != nil {
				return nil, fmt.Errorf("%s/%s: %w", section.Title, item.Prompt, err)
			}
			exercises = append(exercises, exercise)
		}
	}
	return exercises, nil
}

func (resolver *Resolver) resolveItem(lesson Lesson, section Section, item Item, mode reverselookup.Mode) (Exercise, error) {
	exercise := Exercise{
		SectionType:   section.Type,
		SectionTitle:  section.Title,
		Instruction:   section.Instruction,
		Prompt:        strings.TrimSpace(item.Prompt),
		AnswerLabel:   "目标编码",
		AudioDeclared: strings.TrimSpace(item.Audio) != "",
		AudioPath:     existingOptionalAudioPath(lesson.baseDir, item.Audio),
	}
	switch section.Type {
	case SectionKeymap:
		entry, exists := resolver.catalog.Lookup(item.YinyuanID)
		if !exists {
			return Exercise{}, fmt.Errorf("音元语义目录中找不到 %s", item.YinyuanID)
		}
		key := resolver.layout.Projection[item.YinyuanID]
		if key == "" {
			return Exercise{}, fmt.Errorf("当前布局中找不到音元 %s", item.YinyuanID)
		}
		if exercise.Prompt == "" {
			exercise.Prompt = entry.DisplayName
		}
		exercise.Detail = fmt.Sprintf("%s · %s", item.YinyuanID, entry.DisplayName)
		if entry.RepresentativeIPA != "" {
			exercise.Detail += " · 代表音值 [" + entry.RepresentativeIPA + "]"
		}
		exercise.Expected = key
		exercise.AnswerLabel = "目标键位"
		if exercise.AudioPath == "" {
			exercise.AudioDeclared = exercise.AudioDeclared || strings.TrimSpace(entry.Audio) != ""
			exercise.AudioPath = resolver.catalog.AudioPath(entry)
		}
	case SectionSyllableAssociate:
		if err := resolver.resolveSyllableAssociation(&exercise, item, mode); err != nil {
			return Exercise{}, err
		}
	case SectionSyllableContrast:
		code, _, err := reverselookup.EncodeNumericTonePinyin(resolver.codeMap, item.Syllable, mode)
		if err != nil {
			return Exercise{}, err
		}
		if exercise.Prompt == "" {
			exercise.Prompt = item.Syllable
		}
		detailParts := []string{"音节：" + item.Syllable}
		if item.Hanzi != "" {
			detailParts = append(detailParts, "例字："+item.Hanzi)
		}
		if len(item.Contrast) > 0 {
			detailParts = append(detailParts, "对照："+strings.Join(item.Contrast, "、"))
		}
		exercise.Detail = strings.Join(detailParts, "    ")
		exercise.Expected = code
	case SectionCommonWords:
		pinyin := strings.Join(item.Syllables, " ")
		code, _, err := reverselookup.EncodeNumericTonePinyin(resolver.codeMap, pinyin, mode)
		if err != nil {
			return Exercise{}, err
		}
		if exercise.Prompt == "" {
			exercise.Prompt = item.Text
		}
		exercise.Detail = item.Text + "    拼音：" + pinyin
		if item.Notes != "" {
			exercise.Detail += "    提示：" + item.Notes
		}
		exercise.Expected = code
	}
	return exercise, nil
}

func (resolver *Resolver) resolveSyllableAssociation(exercise *Exercise, item Item, mode reverselookup.Mode) error {
	row, ok := resolver.decomposition[strings.TrimSpace(item.Syllable)]
	if !ok {
		return fmt.Errorf("标准拼音分解表中找不到音节 %s", item.Syllable)
	}
	code, _, err := reverselookup.EncodeNumericTonePinyin(resolver.codeMap, item.Syllable, mode)
	if err != nil {
		return err
	}
	exercise.MarkedPinyin = row.MarkedPinyin
	if exercise.Prompt == "" {
		exercise.Prompt = row.MarkedPinyin
		if item.Hanzi != "" {
			exercise.Prompt += "（" + item.Hanzi + "）"
		}
	}
	positions := []string{"首音", "呼音", "主音", "末音"}
	parts := make([]string, 0, len(row.IDs))
	notations := make([]string, 0, len(row.IDs))
	for index, id := range row.IDs {
		entry, exists := resolver.catalog.Lookup(id)
		if !exists {
			return fmt.Errorf("音元语义目录中找不到 %s", id)
		}
		key := resolver.layout.Projection[id]
		if key == "" {
			return fmt.Errorf("当前布局中找不到音元 %s", id)
		}
		segment := Segment{
			Position:          positions[index],
			ID:                id,
			Notation:          row.Names[index],
			DisplayName:       entry.DisplayName,
			RepresentativeIPA: entry.RepresentativeIPA,
			Key:               key,
			AudioPath:         resolver.catalog.AudioPath(entry),
		}
		exercise.Segments = append(exercise.Segments, segment)
		notations = append(notations, row.Names[index])
		label := positions[index] + " " + id + " " + entry.DisplayName
		if entry.RepresentativeIPA != "" {
			label += " [" + entry.RepresentativeIPA + "]"
		}
		parts = append(parts, label)
	}
	exercise.Detail = "标准拼音：" + row.MarkedPinyin + "（" + row.PinyinTone + "）"
	if item.Hanzi != "" {
		exercise.Detail += "    例字：" + item.Hanzi
	}
	exercise.Detail += "\r\n音元拼音：" + strings.Join(notations, " + ")
	exercise.Detail += "\r\n结构分解：" + strings.Join(parts, "  →  ")
	exercise.Expected = code
	return nil
}

func Evaluate(input, expected string) bool {
	return strings.TrimSpace(input) == expected
}
