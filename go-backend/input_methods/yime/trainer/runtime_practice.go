package trainer

import (
	"container/heap"
	"fmt"
	"math/rand"
	"path/filepath"
	"sort"
	"strings"
	"unicode"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

const (
	practiceItemsPerGroup = 5
	wordHighFrequencyPool = 500
	componentPoolPerSize  = 5000
	sentenceCandidatePool = 5000
)

type RuntimePracticeItem struct {
	Text                  string
	FullCode              string
	Weight                int
	Parts                 []RuntimePracticePart
	NumericPinyin         string
	MarkedPinyin          string
	HasSharedCodeReadings bool
}

type RuntimePracticePart struct {
	Text     string
	FullCode string
	Weight   int
}

type RuntimePracticeSet struct {
	WordsBySyllableCount map[int][]RuntimePracticeItem
	Sentences            []RuntimePracticeItem
}

type runtimeSyllablePronunciation struct {
	Numeric string
	Marked  string
}

func appendUniqueRuntimePronunciation(values []runtimeSyllablePronunciation, value runtimeSyllablePronunciation) []runtimeSyllablePronunciation {
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

func sortRuntimePronunciations(values []runtimeSyllablePronunciation) {
	sort.Slice(values, func(i, j int) bool {
		return values[i].Numeric < values[j].Numeric
	})
}

type weightedEntryHeap []systemlexicon.Entry

func (values weightedEntryHeap) Len() int { return len(values) }
func (values weightedEntryHeap) Less(i, j int) bool {
	if values[i].Weight != values[j].Weight {
		return values[i].Weight < values[j].Weight
	}
	if values[i].Text != values[j].Text {
		return values[i].Text > values[j].Text
	}
	return values[i].Code > values[j].Code
}
func (values weightedEntryHeap) Swap(i, j int) { values[i], values[j] = values[j], values[i] }
func (values *weightedEntryHeap) Push(value any) {
	*values = append(*values, value.(systemlexicon.Entry))
}
func (values *weightedEntryHeap) Pop() any {
	old := *values
	value := old[len(old)-1]
	*values = old[:len(old)-1]
	return value
}

func pushTopEntry(values *weightedEntryHeap, entry systemlexicon.Entry, limit int) {
	if values.Len() < limit {
		heap.Push(values, entry)
		return
	}
	root := (*values)[0]
	if entry.Weight < root.Weight ||
		(entry.Weight == root.Weight && (entry.Text > root.Text || (entry.Text == root.Text && entry.Code >= root.Code))) {
		return
	}
	heap.Pop(values)
	heap.Push(values, entry)
}

func entriesDescending(values weightedEntryHeap) []systemlexicon.Entry {
	result := append([]systemlexicon.Entry(nil), values...)
	sort.Slice(result, func(i, j int) bool {
		if result[i].Weight != result[j].Weight {
			return result[i].Weight > result[j].Weight
		}
		if result[i].Text != result[j].Text {
			return result[i].Text < result[j].Text
		}
		return result[i].Code < result[j].Code
	})
	return result
}

func (resolver *Resolver) SelectRuntimePracticeSet(rng *rand.Rand) (RuntimePracticeSet, error) {
	if resolver == nil {
		return RuntimePracticeSet{}, fmt.Errorf("练习解析器未初始化")
	}
	if rng == nil {
		return RuntimePracticeSet{}, fmt.Errorf("运行库抽题需要随机源")
	}
	path := filepath.Join(resolver.runtimeDataDir, "yime_full.dict.yaml")
	wordPools := map[int]*weightedEntryHeap{}
	componentPools := map[int]*weightedEntryHeap{}
	for count := 1; count <= 4; count++ {
		wordPool := &weightedEntryHeap{}
		componentPool := &weightedEntryHeap{}
		heap.Init(wordPool)
		heap.Init(componentPool)
		wordPools[count] = wordPool
		componentPools[count] = componentPool
	}
	sentencePool := &weightedEntryHeap{}
	heap.Init(sentencePool)
	err := systemlexicon.VisitDictFile(path, func(entry systemlexicon.Entry) error {
		count, ok := eligibleRuntimeText(entry)
		if !ok || !resolver.runtimeCodeSupported(entry.Code) {
			return nil
		}
		switch {
		case count >= 1 && count <= 4:
			pushTopEntry(wordPools[count], entry, wordHighFrequencyPool)
			pushTopEntry(componentPools[count], entry, componentPoolPerSize)
		case count >= 5 && count <= 12:
			pushTopEntry(sentencePool, entry, sentenceCandidatePool)
		}
		return nil
	})
	if err != nil {
		return RuntimePracticeSet{}, err
	}

	result := RuntimePracticeSet{WordsBySyllableCount: map[int][]RuntimePracticeItem{}}
	for _, count := range []int{2, 3, 4, 1} {
		selected := sampleUniqueEntries(entriesDescending(*wordPools[count]), practiceItemsPerGroup, rng)
		if len(selected) != practiceItemsPerGroup {
			return RuntimePracticeSet{}, fmt.Errorf("运行库高频部分只有 %d 个可用的%d音节字词", len(selected), count)
		}
		for _, entry := range selected {
			item, itemErr := resolver.runtimePracticeItem(entry, nil)
			if itemErr != nil {
				return RuntimePracticeSet{}, itemErr
			}
			result.WordsBySyllableCount[count] = append(result.WordsBySyllableCount[count], item)
		}
	}

	components := map[string]RuntimePracticePart{}
	for count := 1; count <= 4; count++ {
		for _, entry := range entriesDescending(*componentPools[count]) {
			key := componentKey(entry.Text, entry.Code)
			if _, exists := components[key]; !exists {
				components[key] = RuntimePracticePart{
					Text: entry.Text, FullCode: strings.Join(strings.Fields(entry.Code), " "), Weight: entry.Weight,
				}
			}
		}
	}
	composable := make([]RuntimePracticeItem, 0, 256)
	seenSentence := map[string]bool{}
	for _, entry := range entriesDescending(*sentencePool) {
		if seenSentence[entry.Text] {
			continue
		}
		parts, ok := compositionParts(entry, components)
		if !ok {
			continue
		}
		seenSentence[entry.Text] = true
		item, itemErr := resolver.runtimePracticeItem(entry, parts)
		if itemErr != nil {
			return RuntimePracticeSet{}, itemErr
		}
		composable = append(composable, item)
	}
	if len(composable) < practiceItemsPerGroup {
		return RuntimePracticeSet{}, fmt.Errorf("运行库高频部分只有 %d 个可动态组句的短句", len(composable))
	}
	rng.Shuffle(len(composable), func(i, j int) { composable[i], composable[j] = composable[j], composable[i] })
	result.Sentences = append(result.Sentences, composable[:practiceItemsPerGroup]...)
	return result, nil
}

func (resolver *Resolver) runtimePracticeItem(entry systemlexicon.Entry, parts []RuntimePracticePart) (RuntimePracticeItem, error) {
	numeric, marked, shared, err := resolver.runtimePronunciation(entry.Code)
	if err != nil {
		return RuntimePracticeItem{}, fmt.Errorf("运行库条目 %s: %w", entry.Text, err)
	}
	return RuntimePracticeItem{
		Text: entry.Text, FullCode: strings.Join(strings.Fields(entry.Code), " "), Weight: entry.Weight,
		Parts: append([]RuntimePracticePart(nil), parts...), NumericPinyin: numeric, MarkedPinyin: marked,
		HasSharedCodeReadings: shared,
	}, nil
}

func (resolver *Resolver) runtimePronunciation(fullCode string) (numeric string, marked string, shared bool, err error) {
	var numericParts, markedParts []string
	for _, token := range strings.Fields(fullCode) {
		readings := resolver.fullCodePronunciations[token]
		if len(readings) == 0 {
			return "", "", false, fmt.Errorf("正式音节编码表中找不到等长码 %q 的规范读音", token)
		}
		numericOptions := make([]string, 0, len(readings))
		markedOptions := make([]string, 0, len(readings))
		for _, reading := range readings {
			numericOptions = append(numericOptions, reading.Numeric)
			markedOptions = append(markedOptions, reading.Marked)
		}
		if len(readings) > 1 {
			shared = true
		}
		numericParts = append(numericParts, strings.Join(numericOptions, "/"))
		markedParts = append(markedParts, strings.Join(markedOptions, "/"))
	}
	if len(numericParts) == 0 {
		return "", "", false, fmt.Errorf("正式音节码序列为空")
	}
	return strings.Join(numericParts, " "), strings.Join(markedParts, " "), shared, nil
}

func (resolver *Resolver) runtimeCodeSupported(code string) bool {
	if resolver == nil || len(resolver.fullCodeMap) == 0 {
		return false
	}
	for _, token := range strings.Fields(code) {
		if _, exists := resolver.fullCodeMap[token]; !exists {
			return false
		}
	}
	return true
}

func eligibleRuntimeText(entry systemlexicon.Entry) (int, bool) {
	tokens := strings.Fields(entry.Code)
	runes := []rune(strings.TrimSpace(entry.Text))
	if entry.Weight <= 0 || len(tokens) == 0 || len(tokens) != len(runes) {
		return 0, false
	}
	for _, char := range runes {
		if !unicode.Is(unicode.Han, char) {
			return 0, false
		}
	}
	return len(tokens), true
}

func sampleUniqueEntries(entries []systemlexicon.Entry, count int, rng *rand.Rand) []systemlexicon.Entry {
	rng.Shuffle(len(entries), func(i, j int) { entries[i], entries[j] = entries[j], entries[i] })
	result := make([]systemlexicon.Entry, 0, count)
	seen := map[string]bool{}
	for _, entry := range entries {
		if seen[entry.Text] {
			continue
		}
		seen[entry.Text] = true
		result = append(result, entry)
		if len(result) == count {
			break
		}
	}
	return result
}

func componentKey(text, code string) string {
	return text + "\x00" + strings.Join(strings.Fields(code), " ")
}

func compositionParts(entry systemlexicon.Entry, components map[string]RuntimePracticePart) ([]RuntimePracticePart, bool) {
	runes := []rune(entry.Text)
	tokens := strings.Fields(entry.Code)
	if len(runes) != len(tokens) || len(runes) < 5 {
		return nil, false
	}
	dp := make([][]RuntimePracticePart, len(runes)+1)
	dp[0] = []RuntimePracticePart{}
	for end := 1; end <= len(runes); end++ {
		startAt := end - 4
		if startAt < 0 {
			startAt = 0
		}
		for start := startAt; start < end; start++ {
			if dp[start] == nil {
				continue
			}
			text := string(runes[start:end])
			code := strings.Join(tokens[start:end], " ")
			part, exists := components[componentKey(text, code)]
			if !exists || part.Weight <= 0 {
				continue
			}
			dp[end] = append(append([]RuntimePracticePart(nil), dp[start]...), part)
			break
		}
	}
	parts := dp[len(runes)]
	if len(parts) < 2 || len(parts) > 6 {
		return nil, false
	}
	singleCharacterParts := 0
	hasMultiSyllablePart := false
	for _, part := range parts {
		if len([]rune(part.Text)) >= 2 {
			hasMultiSyllablePart = true
		} else {
			singleCharacterParts++
		}
	}
	if !hasMultiSyllablePart || singleCharacterParts > 2 {
		return nil, false
	}
	return parts, true
}

func runtimePronunciationDetail(item RuntimePracticeItem) string {
	detail := "标准拼音：" + item.MarkedPinyin + "（" + item.NumericPinyin + "）"
	if item.HasSharedCodeReadings {
		detail += "；斜线两侧为共用同一音节码的规范读音"
	}
	return detail
}

func runtimePartLabels(parts []RuntimePracticePart) []string {
	labels := make([]string, 0, len(parts))
	for _, part := range parts {
		labels = append(labels, part.Text)
	}
	return labels
}

func (resolver *Resolver) ResolveWordPracticeGroups(set RuntimePracticeSet, mode reverselookup.Mode) ([]ExerciseGroup, error) {
	definitions := []struct {
		count int
		id    string
		title string
	}{
		{2, "words-two", "双音词语"},
		{3, "words-three", "三音词语"},
		{4, "words-four", "四音词语"},
		{1, "words-one", "单音节字"},
	}
	groups := make([]ExerciseGroup, 0, len(definitions))
	for _, definition := range definitions {
		items := set.WordsBySyllableCount[definition.count]
		if len(items) != practiceItemsPerGroup {
			return nil, fmt.Errorf("%s需要 %d 题，当前为 %d 题", definition.title, practiceItemsPerGroup, len(items))
		}
		group := ExerciseGroup{ID: definition.id, Category: "word-length", Title: definition.title}
		for _, item := range items {
			expected, err := resolver.convertFullRuntimeCode(item.FullCode, mode)
			if err != nil {
				return nil, fmt.Errorf("字词 %s: %w", item.Text, err)
			}
			answerUnits, err := resolver.answerUnitsForFullCode(item.FullCode, mode)
			if err != nil {
				return nil, fmt.Errorf("字词 %s: %w", item.Text, err)
			}
			group.Exercises = append(group.Exercises, Exercise{
				ID:          "word:" + item.Text + ":" + item.FullCode + ":" + string(mode),
				SectionType: SectionWordPractice, SectionTitle: "字词练习",
				Instruction: "根据字词读音连续敲入完整编码，按 Enter 确认。",
				Prompt:      item.Text,
				Detail: fmt.Sprintf("%s；%s · %d 个音节 · 本次从系统运行库高频部分随机抽取",
					runtimePronunciationDetail(item), definition.title, definition.count),
				Expected: expected, AnswerLabel: "完整编码",
				MarkedPinyin: item.MarkedPinyin, NumericPinyin: item.NumericPinyin,
				AnswerUnits:  answerUnits,
				LearningTags: []string{"word:" + item.Text, fmt.Sprintf("word-length:%d", definition.count), "mode:" + string(mode)},
			})
		}
		groups = append(groups, group)
	}
	return groups, nil
}

func (resolver *Resolver) ResolveSentencePractice(set RuntimePracticeSet, mode reverselookup.Mode) ([]Exercise, error) {
	if len(set.Sentences) != practiceItemsPerGroup {
		return nil, fmt.Errorf("短句练习需要 %d 题，当前为 %d 题", practiceItemsPerGroup, len(set.Sentences))
	}
	exercises := make([]Exercise, 0, len(set.Sentences))
	for _, item := range set.Sentences {
		expected, err := resolver.convertFullRuntimeCode(item.FullCode, mode)
		if err != nil {
			return nil, fmt.Errorf("短句 %s: %w", item.Text, err)
		}
		answerUnits, err := resolver.answerUnitsForFullCode(item.FullCode, mode)
		if err != nil {
			return nil, fmt.Errorf("短句 %s: %w", item.Text, err)
		}
		exercises = append(exercises, Exercise{
			ID:          "sentence:" + item.Text + ":" + item.FullCode + ":" + string(mode),
			SectionType: SectionSentencePractice, SectionTitle: "短句练习",
			Instruction: "输入由系统运行库高频部件动态组成的短句完整编码，按 Enter 确认。",
			Prompt:      item.Text,
			Detail:      runtimePronunciationDetail(item) + "；动态组句：" + strings.Join(runtimePartLabels(item.Parts), " + "),
			Expected:    expected, AnswerLabel: "完整编码",
			MarkedPinyin: item.MarkedPinyin, NumericPinyin: item.NumericPinyin,
			AnswerUnits:  answerUnits,
			LearningTags: []string{"sentence", fmt.Sprintf("sentence-length:%d", len(strings.Fields(item.FullCode))), "mode:" + string(mode)},
		})
	}
	return exercises, nil
}

func (resolver *Resolver) answerUnitsForFullCode(fullCode string, mode reverselookup.Mode) ([]AnswerUnit, error) {
	var units []AnswerUnit
	for index, token := range strings.Fields(fullCode) {
		readings := resolver.fullCodePronunciations[token]
		if len(readings) == 0 {
			return nil, fmt.Errorf("正式音节编码表中找不到等长码 %q", token)
		}
		row, exists := resolver.decomposition[readings[0].Numeric]
		if !exists || row.Status != "ok" {
			return nil, fmt.Errorf("找不到等长码 %q 的正式音节分解", token)
		}
		for _, reading := range readings[1:] {
			aliasRow, aliasExists := resolver.decomposition[reading.Numeric]
			if !aliasExists || aliasRow.IDs != row.IDs {
				return nil, fmt.Errorf("共码读音 %s 与 %s 的四音元分解不一致", readings[0].Numeric, reading.Numeric)
			}
		}
		rowUnits, err := resolver.answerUnitsForRow(row, mode, index+1)
		if err != nil {
			return nil, err
		}
		units = append(units, rowUnits...)
	}
	return units, nil
}

func (resolver *Resolver) convertFullRuntimeCode(fullCode string, mode reverselookup.Mode) (string, error) {
	var result strings.Builder
	for _, token := range strings.Fields(fullCode) {
		record, exists := resolver.fullCodeMap[token]
		if !exists {
			return "", fmt.Errorf("正式音节编码表中找不到等长码 %q", token)
		}
		result.WriteString(codeRecordForMode(record, mode))
	}
	return result.String(), nil
}
