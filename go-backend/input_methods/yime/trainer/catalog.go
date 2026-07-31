package trainer

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
)

const (
	CatalogFileName      = "yinyuan_catalog.json"
	CatalogFormatVersion = 1
)

// Catalog is the semantic layer between canonical Yinyuan IDs and lessons.
// Physical keys remain owned by yime_yinyuan_layout.json.
type Catalog struct {
	FormatVersion int       `json:"format_version"`
	Description   string    `json:"description,omitempty"`
	Entries       []Yinyuan `json:"entries"`

	baseDir string
	byID    map[string]Yinyuan
}

// Yinyuan describes one stable Yinyuan ID without assigning it a physical
// key. Audio is an optional path relative to the catalog directory.
type Yinyuan struct {
	ID                   string `json:"id"`
	Category             string `json:"category"`
	StructuralClass      string `json:"structural_class,omitempty"`
	ReferenceLabel       string `json:"reference_label,omitempty"`
	QualityGroup         string `json:"quality_group,omitempty"`
	ToneGrade            string `json:"tone_grade,omitempty"`
	DisplayName          string `json:"display_name"`
	RepresentativeIPA    string `json:"representative_ipa,omitempty"`
	CoveredPianyinLevels []int  `json:"covered_pianyin_levels,omitempty"`
	Audio                string `json:"audio,omitempty"`
}

func LoadCatalog(path string) (Catalog, error) {
	payload, err := os.ReadFile(path)
	if err != nil {
		return Catalog{}, err
	}
	var catalog Catalog
	if err := json.Unmarshal(payload, &catalog); err != nil {
		return Catalog{}, fmt.Errorf("音元语义目录 JSON 格式错误: %w", err)
	}
	catalog.baseDir = filepath.Dir(path)
	if err := catalog.Validate(); err != nil {
		return Catalog{}, err
	}
	catalog.index()
	return catalog, nil
}

func (catalog Catalog) Validate() error {
	if catalog.FormatVersion != CatalogFormatVersion {
		return fmt.Errorf("不支持音元语义目录格式 %d，当前需要 %d", catalog.FormatVersion, CatalogFormatVersion)
	}
	expected := map[string]bool{}
	for _, id := range layoutdesigner.ExpectedIDs() {
		expected[id] = true
	}
	seen := map[string]bool{}
	for index, entry := range catalog.Entries {
		context := fmt.Sprintf("音元目录第 %d 项", index+1)
		if !expected[entry.ID] {
			return fmt.Errorf("%s 使用未知 ID %q", context, entry.ID)
		}
		if seen[entry.ID] {
			return fmt.Errorf("音元目录 ID 重复：%s", entry.ID)
		}
		seen[entry.ID] = true
		delete(expected, entry.ID)
		if strings.TrimSpace(entry.DisplayName) == "" {
			return fmt.Errorf("%s 缺少 display_name", context)
		}
		if err := validateOptionalRelativePath(entry.Audio); err != nil {
			return fmt.Errorf("%s 的 audio 无效: %w", context, err)
		}
		switch entry.Category {
		case "shouyin":
			if !strings.HasPrefix(entry.ID, "N") || (entry.StructuralClass != "real" && entry.StructuralClass != "virtual") {
				return fmt.Errorf("%s 的首音类别或 ID 无效", context)
			}
			if strings.TrimSpace(entry.ReferenceLabel) == "" {
				return fmt.Errorf("%s 缺少首音 reference_label", context)
			}
		case "yueyin":
			if !strings.HasPrefix(entry.ID, "M") || strings.TrimSpace(entry.QualityGroup) == "" {
				return fmt.Errorf("%s 的乐音类别、ID 或音质组无效", context)
			}
			wantLevels := map[string][]int{
				"high": {5},
				"mid":  {4},
				"low":  {3, 2, 1},
			}[entry.ToneGrade]
			if wantLevels == nil || !reflect.DeepEqual(entry.CoveredPianyinLevels, wantLevels) {
				return fmt.Errorf("%s 的调级或五度片音映射无效", context)
			}
		default:
			return fmt.Errorf("%s 使用未知 category %q", context, entry.Category)
		}
	}
	if len(expected) > 0 {
		var missing []string
		for _, id := range layoutdesigner.ExpectedIDs() {
			if expected[id] {
				missing = append(missing, id)
			}
		}
		return fmt.Errorf("音元语义目录不完整，缺少：%s", strings.Join(missing, " "))
	}
	return nil
}

func (catalog *Catalog) index() {
	catalog.byID = make(map[string]Yinyuan, len(catalog.Entries))
	for _, entry := range catalog.Entries {
		catalog.byID[entry.ID] = entry
	}
}

func (catalog Catalog) Lookup(id string) (Yinyuan, bool) {
	entry, ok := catalog.byID[id]
	return entry, ok
}

func (catalog Catalog) AudioPath(entry Yinyuan) string {
	return existingOptionalAudioPath(catalog.baseDir, entry.Audio)
}

func validateOptionalRelativePath(value string) error {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	if filepath.IsAbs(value) {
		return fmt.Errorf("必须使用相对路径")
	}
	clean := filepath.Clean(value)
	if clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return fmt.Errorf("不得离开课程目录")
	}
	return nil
}

func existingOptionalAudioPath(baseDir, value string) string {
	if validateOptionalRelativePath(value) != nil || strings.TrimSpace(value) == "" {
		return ""
	}
	path := filepath.Join(baseDir, filepath.Clean(value))
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return ""
	}
	return path
}
