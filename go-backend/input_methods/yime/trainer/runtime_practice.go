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
	Text     string
	FullCode string
	Weight   int
	Parts    []string
}

type RuntimePracticeSet struct {
	WordsBySyllableCount map[int][]RuntimePracticeItem
	Sentences            []RuntimePracticeItem
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
			result.WordsBySyllableCount[count] = append(result.WordsBySyllableCount[count], RuntimePracticeItem{
				Text: entry.Text, FullCode: entry.Code, Weight: entry.Weight,
			})
		}
	}

	components := map[string]bool{}
	for count := 1; count <= 4; count++ {
		for _, entry := range entriesDescending(*componentPools[count]) {
			components[componentKey(entry.Text, entry.Code)] = true
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
		composable = append(composable, RuntimePracticeItem{
			Text: entry.Text, FullCode: entry.Code, Weight: entry.Weight, Parts: parts,
		})
	}
	if len(composable) < practiceItemsPerGroup {
		return RuntimePracticeSet{}, fmt.Errorf("运行库高频部分只有 %d 个可动态组句的短句", len(composable))
	}
	rng.Shuffle(len(composable), func(i, j int) { composable[i], composable[j] = composable[j], composable[i] })
	result.Sentences = append(result.Sentences, composable[:practiceItemsPerGroup]...)
	return result, nil
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

func compositionParts(entry systemlexicon.Entry, components map[string]bool) ([]string, bool) {
	runes := []rune(entry.Text)
	tokens := strings.Fields(entry.Code)
	if len(runes) != len(tokens) || len(runes) < 5 {
		return nil, false
	}
	dp := make([][]string, len(runes)+1)
	dp[0] = []string{}
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
			if !components[componentKey(text, code)] {
				continue
			}
			dp[end] = append(append([]string(nil), dp[start]...), text)
			break
		}
	}
	return dp[len(runes)], len(dp[len(runes)]) >= 2
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
			group.Exercises = append(group.Exercises, Exercise{
				SectionType: SectionWordPractice, SectionTitle: "字词练习",
				Instruction: "根据字词读音连续敲入完整编码，按 Enter 确认。",
				Prompt:      item.Text, Detail: fmt.Sprintf("%s · %d 个音节 · 本次从系统运行库高频部分随机抽取", definition.title, definition.count),
				Expected: expected, AnswerLabel: "完整编码",
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
		exercises = append(exercises, Exercise{
			SectionType: SectionSentencePractice, SectionTitle: "短句练习",
			Instruction: "输入由系统运行库高频部件动态组成的短句完整编码，按 Enter 确认。",
			Prompt:      item.Text, Detail: "动态组句：" + strings.Join(item.Parts, " + "),
			Expected: expected, AnswerLabel: "完整编码",
		})
	}
	return exercises, nil
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
