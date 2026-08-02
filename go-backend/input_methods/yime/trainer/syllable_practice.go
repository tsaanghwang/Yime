package trainer

import (
	"fmt"
	"sort"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/layoutdesigner"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/syllableinspector"
)

func (resolver *Resolver) ResolveSyllablePracticeGroups(mode reverselookup.Mode) ([]ExerciseGroup, error) {
	if resolver == nil {
		return nil, fmt.Errorf("练习解析器未初始化")
	}
	byShouyin := map[string][]Exercise{}
	for _, row := range resolver.decomposition {
		if row.Status == "canonical-only" {
			continue
		}
		if row.Status != "ok" {
			return nil, fmt.Errorf("音节 %s 的编码对照状态异常：%s", row.PinyinTone, row.Status)
		}
		record, exists := resolver.codeMap[row.PinyinTone]
		if !exists {
			return nil, fmt.Errorf("编码对照表中的音节 %s 无法读取", row.PinyinTone)
		}
		expected, err := resolver.projectSyllableIDs(row.IDs, mode)
		if err != nil {
			return nil, fmt.Errorf("音节 %s: %w", row.PinyinTone, err)
		}
		fromTable := codeRecordForMode(record, mode)
		if fromTable != expected {
			return nil, fmt.Errorf("音节 %s 的当前布局推导码 %q 与编码对照表 %q 不一致", row.PinyinTone, expected, fromTable)
		}
		segments, err := resolver.segmentsForRow(row)
		if err != nil {
			return nil, fmt.Errorf("音节 %s: %w", row.PinyinTone, err)
		}
		parts := [4]string{}
		for index := range row.IDs {
			parts[index] = fmt.Sprintf("%s（%s）", row.Names[index], row.IDs[index])
		}
		detail := fmt.Sprintf("首音分析：%s → %s\r\n干音分析：%s → %s + %s + %s\r\n完整音元拼音：%s + %s + %s + %s",
			row.ShouyinLabel, parts[0],
			row.GanyinLabel, parts[1], parts[2], parts[3],
			row.Names[0], row.Names[1], row.Names[2], row.Names[3])
		answerUnits, err := resolver.answerUnitsForRow(row, mode, 1)
		if err != nil {
			return nil, fmt.Errorf("音节 %s: %w", row.PinyinTone, err)
		}
		byShouyin[row.IDs[0]] = append(byShouyin[row.IDs[0]], Exercise{
			ID:            "syllable:" + row.PinyinTone + ":" + string(mode),
			SectionType:   SectionSyllablePractice,
			SectionTitle:  "编码练习",
			Instruction:   "先看首音与干音的两段分析，再敲入所选输入方案的完整音元拼音编码。",
			Prompt:        fmt.Sprintf("%s（%s）", row.MarkedPinyin, row.PinyinTone),
			Detail:        detail,
			Expected:      expected,
			AnswerLabel:   "完整编码",
			MarkedPinyin:  row.MarkedPinyin,
			NumericPinyin: row.PinyinTone,
			Segments:      segments,
			AnswerUnits:   answerUnits,
			LearningTags:  []string{"syllable:" + row.PinyinTone, "shouyin:" + row.IDs[0], "mode:" + string(mode)},
		})
	}

	result := make([]ExerciseGroup, 0, 24)
	for _, id := range layoutdesigner.ExpectedIDs() {
		if !strings.HasPrefix(id, "N") {
			continue
		}
		entry, ok := resolver.catalog.Lookup(id)
		if !ok || entry.Category != "shouyin" {
			return nil, fmt.Errorf("编码练习缺少首音目录项 %s", id)
		}
		exercises := byShouyin[id]
		if len(exercises) == 0 {
			return nil, fmt.Errorf("首音 %s 没有现存音节", id)
		}
		sort.Slice(exercises, func(i, j int) bool {
			return exercises[i].NumericPinyin < exercises[j].NumericPinyin
		})
		result = append(result, ExerciseGroup{
			ID:          "syllables-" + strings.ToLower(id),
			Category:    "shouyin",
			Title:       fmt.Sprintf("%s · %s", id, entry.DisplayName),
			Description: "按首音段和干音段分别分析后合成完整编码",
			Exercises:   exercises,
		})
		delete(byShouyin, id)
	}
	if len(byShouyin) != 0 {
		return nil, fmt.Errorf("编码练习出现首音目录外的分组")
	}
	return result, nil
}

func (resolver *Resolver) projectSyllableIDs(ids [4]string, mode reverselookup.Mode) (string, error) {
	indices, err := resolver.projectedSyllableIndices(ids, mode)
	if err != nil {
		return "", err
	}
	var result strings.Builder
	for _, index := range indices {
		key := resolver.layout.Projection[ids[index]]
		if key == "" {
			return "", fmt.Errorf("当前布局缺少音元 %s", ids[index])
		}
		result.WriteString(key)
	}
	return result.String(), nil
}

func (resolver *Resolver) projectedSyllableIndices(ids [4]string, mode reverselookup.Mode) ([]int, error) {
	indices := []int{0}
	for index := 1; index < len(ids); index++ {
		if index == 1 || ids[index] != ids[index-1] {
			indices = append(indices, index)
		}
	}
	if mode == reverselookup.ModeFull {
		return []int{0, 1, 2, 3}, nil
	}
	if mode == reverselookup.ModeShorthand && len(indices) == 4 {
		entries := make([]Yinyuan, 0, 3)
		for _, id := range ids[1:] {
			entry, ok := resolver.catalog.Lookup(id)
			if !ok {
				return nil, fmt.Errorf("找不到音元 %s", id)
			}
			entries = append(entries, entry)
		}
		if entries[0].QualityGroup == entries[1].QualityGroup && entries[1].QualityGroup == entries[2].QualityGroup &&
			((entries[0].ToneGrade == "high" && entries[1].ToneGrade == "mid" && entries[2].ToneGrade == "low") ||
				(entries[0].ToneGrade == "low" && entries[1].ToneGrade == "mid" && entries[2].ToneGrade == "high")) {
			return []int{0, 1, 3}, nil
		}
	}
	return indices, nil
}

func (resolver *Resolver) answerUnitsForRow(row syllableinspector.Row, mode reverselookup.Mode, syllable int) ([]AnswerUnit, error) {
	segments, err := resolver.segmentsForRow(row)
	if err != nil {
		return nil, err
	}
	indices, err := resolver.projectedSyllableIndices(row.IDs, mode)
	if err != nil {
		return nil, err
	}
	units := make([]AnswerUnit, 0, len(indices))
	for _, index := range indices {
		segment := segments[index]
		units = append(units, AnswerUnit{
			ExpectedKey: segment.Key, Syllable: syllable, Position: segment.Position,
			YinyuanID: segment.ID, DisplayName: segment.DisplayName,
		})
	}
	return units, nil
}

func (resolver *Resolver) answerUnitsForPinyin(syllables []string, mode reverselookup.Mode) ([]AnswerUnit, error) {
	var units []AnswerUnit
	for index, pinyin := range syllables {
		row, exists := resolver.decomposition[strings.TrimSpace(pinyin)]
		if !exists || row.Status != "ok" {
			return nil, fmt.Errorf("标准拼音分解表中找不到正式音节 %s", pinyin)
		}
		rowUnits, err := resolver.answerUnitsForRow(row, mode, index+1)
		if err != nil {
			return nil, err
		}
		units = append(units, rowUnits...)
	}
	return units, nil
}

func codeRecordForMode(record reverselookup.CodeRecord, mode reverselookup.Mode) string {
	switch mode {
	case reverselookup.ModeFull:
		return record.Full
	case reverselookup.ModeShorthand:
		return record.Shorthand
	default:
		return record.Variable
	}
}
