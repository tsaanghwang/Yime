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
)

const SchemaVersion = "1.1"

const (
	SectionKeymap           = "keymap"
	SectionSyllableContrast = "syllable_contrast"
	SectionCommonWords      = "common_words"
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
}

// Exercise is one runtime-ready item. Expected always comes from the active
// layout/code table, except for a keymap item whose key is itself read from the
// active layout profile.
type Exercise struct {
	SectionType  string
	SectionTitle string
	Instruction  string
	Prompt       string
	Detail       string
	Expected     string
}

type Resolver struct {
	codeMap map[string]reverselookup.CodeRecord
	layout  layoutdesigner.Profile
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
			switch section.Type {
			case SectionKeymap:
				if strings.TrimSpace(item.YinyuanID) == "" {
					return fmt.Errorf("%s 缺少 yinyuan_id", itemContext)
				}
			case SectionSyllableContrast:
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
	return &Resolver{codeMap: codeMap, layout: layout}, nil
}

func (resolver *Resolver) Resolve(lesson Lesson, mode reverselookup.Mode) ([]Exercise, error) {
	if resolver == nil {
		return nil, fmt.Errorf("练习解析器未初始化")
	}
	var exercises []Exercise
	for _, section := range lesson.Sections {
		for _, item := range section.Items {
			exercise, err := resolver.resolveItem(section, item, mode)
			if err != nil {
				return nil, fmt.Errorf("%s/%s: %w", section.Title, item.Prompt, err)
			}
			exercises = append(exercises, exercise)
		}
	}
	return exercises, nil
}

func (resolver *Resolver) resolveItem(section Section, item Item, mode reverselookup.Mode) (Exercise, error) {
	exercise := Exercise{
		SectionType:  section.Type,
		SectionTitle: section.Title,
		Instruction:  section.Instruction,
		Prompt:       strings.TrimSpace(item.Prompt),
	}
	switch section.Type {
	case SectionKeymap:
		key := resolver.layout.Projection[item.YinyuanID]
		if key == "" {
			return Exercise{}, fmt.Errorf("当前布局中找不到音元 %s", item.YinyuanID)
		}
		if exercise.Prompt == "" {
			exercise.Prompt = layoutdesigner.DescribeID(item.YinyuanID)
		}
		exercise.Detail = fmt.Sprintf("%s · %s", item.YinyuanID, layoutdesigner.DescribeID(item.YinyuanID))
		exercise.Expected = key
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

func Evaluate(input, expected string) bool {
	return strings.TrimSpace(input) == expected
}
