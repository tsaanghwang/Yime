package trainer

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

const (
	CompositionSegmentShouyin = "shouyin"
	CompositionSegmentGanyin  = "ganyin"
)

type GanyinToneGroup struct {
	Tone        int
	Title       string
	TonePattern string
	Exercises   []Exercise
}

type GanyinRhymeGroup struct {
	ID           string
	Title        string
	MainQuality  string
	FinalQuality string
	ToneGroups   []GanyinToneGroup
}

type rhymeQualityPair struct {
	main  string
	final string
}

// The order follows the prototype's 19 rhyme-quality relations with the [m]
// relation deliberately omitted. The actual members and target keys are not
// stored here: they are derived from the active syllable decomposition and
// imported layout on every load.
var practicedRhymeQualityPairs = []rhymeQualityPair{
	{main: "i", final: "i"},
	{main: "u", final: "u"},
	{main: "ü", final: "ü"},
	{main: "a", final: "a"},
	{main: "o", final: "o"},
	{main: "e/ê", final: "e/ê"},
	{main: "舌尖i", final: "舌尖i"},
	{main: "er", final: "er"},
	{main: "n", final: "n"},
	{main: "ng", final: "ng"},
	{main: "a", final: "i"},
	{main: "a", final: "u"},
	{main: "e/ê", final: "i"},
	{main: "o", final: "u"},
	{main: "a", final: "n"},
	{main: "e/ê", final: "n"},
	{main: "a", final: "ng"},
	{main: "o", final: "ng"},
}

var ganyinTonePatterns = map[int]string{
	1: "高高高",
	2: "低中高",
	3: "低低低",
	4: "高中低",
}

type ganyinCandidate struct {
	ids    [3]string
	labels map[string]bool
}

func (resolver *Resolver) ResolveShouyinCompositionGroups() ([]ExerciseGroup, error) {
	groups, err := resolver.ResolveKeymapGroups()
	if err != nil {
		return nil, err
	}
	result := make([]ExerciseGroup, 0, 6)
	for _, group := range groups {
		if group.Category == GroupCategoryZaoyin {
			result = append(result, group)
		}
	}
	if len(result) != 6 {
		return nil, fmt.Errorf("音节构成的首音练习需要六组，当前得到 %d 组", len(result))
	}
	return result, nil
}

func (resolver *Resolver) ResolveGanyinCompositionGroups() ([]GanyinRhymeGroup, error) {
	if resolver == nil {
		return nil, fmt.Errorf("练习解析器未初始化")
	}
	observed := map[rhymeQualityPair]map[int]map[string]*ganyinCandidate{}
	for _, row := range resolver.decomposition {
		tone, ok := ganyinTone(row.GanyinLabel)
		if !ok {
			continue
		}
		mainEntry, mainOK := resolver.catalog.Lookup(row.IDs[2])
		finalEntry, finalOK := resolver.catalog.Lookup(row.IDs[3])
		if !mainOK || !finalOK || mainEntry.Category != "yueyin" || finalEntry.Category != "yueyin" {
			return nil, fmt.Errorf("干音 %s 的韵音 ID 无法解析: %s %s", row.GanyinLabel, row.IDs[2], row.IDs[3])
		}
		pair := rhymeQualityPair{main: mainEntry.QualityGroup, final: finalEntry.QualityGroup}
		if pair.main == "m" && pair.final == "m" {
			continue
		}
		byTone := observed[pair]
		if byTone == nil {
			byTone = map[int]map[string]*ganyinCandidate{}
			observed[pair] = byTone
		}
		bySequence := byTone[tone]
		if bySequence == nil {
			bySequence = map[string]*ganyinCandidate{}
			byTone[tone] = bySequence
		}
		ids := [3]string{row.IDs[1], row.IDs[2], row.IDs[3]}
		sequenceKey := strings.Join(ids[:], " ")
		candidate := bySequence[sequenceKey]
		if candidate == nil {
			candidate = &ganyinCandidate{ids: ids, labels: map[string]bool{}}
			bySequence[sequenceKey] = candidate
		}
		candidate.labels[row.GanyinLabel] = true
	}

	result := make([]GanyinRhymeGroup, 0, len(practicedRhymeQualityPairs))
	declared := map[rhymeQualityPair]bool{}
	for index, pair := range practicedRhymeQualityPairs {
		declared[pair] = true
		byTone := observed[pair]
		if len(byTone) == 0 {
			return nil, fmt.Errorf("干音韵音分类 [%s+%s] 没有当前音节分解实例", pair.main, pair.final)
		}
		group := GanyinRhymeGroup{
			ID:           fmt.Sprintf("rhyme-%02d", index+1),
			Title:        fmt.Sprintf("[%s+%s]类", pair.main, pair.final),
			MainQuality:  pair.main,
			FinalQuality: pair.final,
		}
		for tone := 1; tone <= 4; tone++ {
			bySequence := byTone[tone]
			if len(bySequence) == 0 {
				continue
			}
			toneGroup := GanyinToneGroup{
				Tone:        tone,
				Title:       ganyinTonePatterns[tone],
				TonePattern: ganyinTonePatterns[tone],
			}
			sequenceKeys := make([]string, 0, len(bySequence))
			for key := range bySequence {
				sequenceKeys = append(sequenceKeys, key)
			}
			sort.Slice(sequenceKeys, func(i, j int) bool {
				left := shortestGanyinLabel(bySequence[sequenceKeys[i]].labels)
				right := shortestGanyinLabel(bySequence[sequenceKeys[j]].labels)
				if len([]rune(left)) != len([]rune(right)) {
					return len([]rune(left)) < len([]rune(right))
				}
				return left < right
			})
			for _, key := range sequenceKeys {
				candidate := bySequence[key]
				labels := make([]string, 0, len(candidate.labels))
				for label := range candidate.labels {
					labels = append(labels, label)
				}
				sort.Slice(labels, func(i, j int) bool {
					if len([]rune(labels[i])) != len([]rune(labels[j])) {
						return len([]rune(labels[i])) < len([]rune(labels[j]))
					}
					return labels[i] < labels[j]
				})
				prompt := "干音 " + strings.Join(labels, " / ")
				formCondition := ""
				huyinEntry, _ := resolver.catalog.Lookup(candidate.ids[0])
				if pair.main == "o" && pair.final == "ng" && huyinEntry.QualityGroup == "u" {
					prompt = fmt.Sprintf("干音 ong%d（与首音相拼时） / ueng%d（独立成音节时，对应 weng%d）", tone, tone, tone)
					formCondition = " · 形式条件：与首音相拼用 ong；独立成音节用 ueng，音节拼写为 weng"
				}
				var expected strings.Builder
				for _, id := range candidate.ids {
					key := resolver.layout.Projection[id]
					if key == "" {
						return nil, fmt.Errorf("当前布局中找不到干音音元 %s", id)
					}
					expected.WriteString(key)
				}
				toneGroup.Exercises = append(toneGroup.Exercises, Exercise{
					SectionType:  SectionSyllableComposition,
					SectionTitle: "分段练习",
					Instruction:  "根据干音提示，敲入呼音、主音、末音三个音元在当前布局中的物理键。",
					Prompt:       prompt,
					Detail: fmt.Sprintf("韵音音质：[%s+%s] · 调型：%s · 音元：%s",
						pair.main, pair.final, ganyinTonePatterns[tone], strings.Join(candidate.ids[:], " ")) + formCondition,
					Expected:    expected.String(),
					AnswerLabel: "目标键位",
				})
			}
			group.ToneGroups = append(group.ToneGroups, toneGroup)
		}
		result = append(result, group)
		delete(observed, pair)
	}
	for pair := range observed {
		if !declared[pair] {
			return nil, fmt.Errorf("当前音节分解表出现未登记的干音韵音分类 [%s+%s]", pair.main, pair.final)
		}
	}
	return result, nil
}

func ganyinTone(label string) (int, bool) {
	label = strings.TrimSpace(label)
	if len(label) < 2 {
		return 0, false
	}
	tone, err := strconv.Atoi(label[len(label)-1:])
	return tone, err == nil && tone >= 1 && tone <= 4
}

func shortestGanyinLabel(labels map[string]bool) string {
	result := ""
	for label := range labels {
		if result == "" || len([]rune(label)) < len([]rune(result)) ||
			(len([]rune(label)) == len([]rune(result)) && label < result) {
			result = label
		}
	}
	return result
}
