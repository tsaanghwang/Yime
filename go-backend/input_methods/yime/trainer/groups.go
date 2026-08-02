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

const (
	GroupCatalogFileName      = "yinyuan_groups.json"
	GroupCatalogFormatVersion = 1
	GroupCategoryZaoyin       = "zaoyin"
	GroupCategoryYueyin       = "yueyin"
)

type GroupCategory struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

// YinyuanGroup records pedagogical grouping only. Physical keys are always
// resolved from the active imported layout and must never be stored here.
type YinyuanGroup struct {
	ID          string   `json:"id"`
	Category    string   `json:"category"`
	Title       string   `json:"title"`
	Description string   `json:"description,omitempty"`
	YinyuanIDs  []string `json:"yinyuan_ids"`
}

type GroupCatalog struct {
	FormatVersion int             `json:"format_version"`
	Description   string          `json:"description,omitempty"`
	Categories    []GroupCategory `json:"categories"`
	Groups        []YinyuanGroup  `json:"groups"`
}

type ExerciseGroup struct {
	ID          string
	Category    string
	Title       string
	Description string
	Exercises   []Exercise
}

func LoadGroupCatalog(path string, catalog Catalog) (GroupCatalog, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return GroupCatalog{}, err
	}
	var groups GroupCatalog
	if err := json.Unmarshal(payload, &groups); err != nil {
		return GroupCatalog{}, fmt.Errorf("音元练习分组 JSON 格式错误: %w", err)
	}
	if err := groups.Validate(catalog); err != nil {
		return GroupCatalog{}, err
	}
	return groups, nil
}

func (groups GroupCatalog) Validate(catalog Catalog) error {
	if groups.FormatVersion != GroupCatalogFormatVersion {
		return fmt.Errorf("不支持音元练习分组格式 %d，当前需要 %d", groups.FormatVersion, GroupCatalogFormatVersion)
	}
	categoryTitles := map[string]string{}
	for _, category := range groups.Categories {
		if strings.TrimSpace(category.ID) == "" || strings.TrimSpace(category.Title) == "" {
			return fmt.Errorf("音元练习类别必须包含 id 和 title")
		}
		if _, exists := categoryTitles[category.ID]; exists {
			return fmt.Errorf("音元练习类别重复：%s", category.ID)
		}
		categoryTitles[category.ID] = category.Title
	}
	for _, required := range []string{GroupCategoryZaoyin, GroupCategoryYueyin} {
		if categoryTitles[required] == "" {
			return fmt.Errorf("音元练习分组缺少类别：%s", required)
		}
	}

	expected := map[string]bool{}
	for _, id := range layoutdesigner.ExpectedIDs() {
		expected[id] = true
	}
	seenGroups := map[string]bool{}
	seenIDs := map[string]string{}
	for index, group := range groups.Groups {
		context := fmt.Sprintf("音元练习第 %d 组", index+1)
		if strings.TrimSpace(group.ID) == "" || strings.TrimSpace(group.Title) == "" {
			return fmt.Errorf("%s 必须包含 id 和 title", context)
		}
		if seenGroups[group.ID] {
			return fmt.Errorf("音元练习组重复：%s", group.ID)
		}
		seenGroups[group.ID] = true
		if categoryTitles[group.Category] == "" {
			return fmt.Errorf("%s 使用未知类别 %q", context, group.Category)
		}
		if len(group.YinyuanIDs) == 0 {
			return fmt.Errorf("%s 没有音元成员", context)
		}
		for _, id := range group.YinyuanIDs {
			entry, exists := catalog.Lookup(id)
			if !exists || !expected[id] {
				return fmt.Errorf("%s 使用未知音元 %s", context, id)
			}
			if previous := seenIDs[id]; previous != "" {
				return fmt.Errorf("音元 %s 同时出现在 %s 和 %s", id, previous, group.ID)
			}
			if group.Category == GroupCategoryZaoyin && entry.Category != "shouyin" {
				return fmt.Errorf("%s 的噪音组包含非首音 %s", context, id)
			}
			if group.Category == GroupCategoryYueyin && entry.Category != "yueyin" {
				return fmt.Errorf("%s 的乐音组包含非乐音 %s", context, id)
			}
			seenIDs[id] = group.ID
			delete(expected, id)
		}
	}
	if len(expected) > 0 {
		var missing []string
		for _, id := range layoutdesigner.ExpectedIDs() {
			if expected[id] {
				missing = append(missing, id)
			}
		}
		return fmt.Errorf("音元练习分组不完整，缺少：%s", strings.Join(missing, " "))
	}
	return nil
}

func (resolver *Resolver) ResolveKeymapGroups() ([]ExerciseGroup, error) {
	if resolver == nil {
		return nil, fmt.Errorf("练习解析器未初始化")
	}
	lesson := Lesson{baseDir: filepath.Dir(resolver.catalog.baseDir)}
	result := make([]ExerciseGroup, 0, len(resolver.groups.Groups))
	for _, group := range resolver.groups.Groups {
		instruction := "按当前导入布局练习本组音元与物理键的对应关系。"
		if strings.TrimSpace(group.Description) != "" {
			instruction = strings.TrimSpace(group.Description) + "；" + instruction
		}
		section := Section{
			ID:          group.ID,
			Type:        SectionKeymap,
			Title:       group.Title,
			Instruction: instruction,
		}
		resolved := ExerciseGroup{
			ID: group.ID, Category: group.Category, Title: group.Title,
			Description: group.Description,
		}
		for _, id := range group.YinyuanIDs {
			exercise, err := resolver.resolveItem(lesson, section, Item{YinyuanID: id}, reverselookup.ModeVariable)
			if err != nil {
				return nil, fmt.Errorf("%s/%s: %w", group.Title, id, err)
			}
			resolved.Exercises = append(resolved.Exercises, exercise)
		}
		result = append(result, resolved)
	}
	return result, nil
}

// KeymapGroupCategories returns the declared display order for the linked
// category/group selectors. Callers receive a copy and cannot mutate the
// resolver's validated grouping catalog.
func (resolver *Resolver) KeymapGroupCategories() []GroupCategory {
	if resolver == nil {
		return nil
	}
	return append([]GroupCategory(nil), resolver.groups.Categories...)
}

func (groups GroupCatalog) CategoryTitle(id string) string {
	for _, category := range groups.Categories {
		if category.ID == id {
			return category.Title
		}
	}
	return id
}
