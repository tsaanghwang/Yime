package trainer

import (
	"crypto/sha256"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

func TestCompositionPartsRequiresRuntimeComponentsWithMatchingCodes(t *testing.T) {
	entry := systemlexicon.Entry{Text: "我们爱中国", Code: "wo men ai zhong guo", Weight: 100}
	components := map[string]RuntimePracticePart{
		componentKey("我们爱", "wo men ai"): {Text: "我们爱", FullCode: "wo men ai", Weight: 80},
		componentKey("中国", "zhong guo"):  {Text: "中国", FullCode: "zhong guo", Weight: 90},
	}
	parts, ok := compositionParts(entry, components)
	if !ok || strings.Join(runtimePartLabels(parts), "+") != "我们爱+中国" {
		t.Fatalf("compositionParts=%#v ok=%v", parts, ok)
	}
	delete(components, componentKey("中国", "zhong guo"))
	components[componentKey("中国", "wrong code")] = RuntimePracticePart{Text: "中国", FullCode: "wrong code", Weight: 90}
	if _, ok := compositionParts(entry, components); ok {
		t.Fatal("text-only match incorrectly passed dynamic composition check")
	}
}

func TestCompositionPartsRejectsAllSingleCharacterPath(t *testing.T) {
	entry := systemlexicon.Entry{Text: "我们爱中国", Code: "wo men ai zhong guo", Weight: 100}
	components := map[string]RuntimePracticePart{}
	for index, text := range []string{"我", "们", "爱", "中", "国"} {
		code := strings.Fields(entry.Code)[index]
		components[componentKey(text, code)] = RuntimePracticePart{Text: text, FullCode: code, Weight: 100}
	}
	if _, ok := compositionParts(entry, components); ok {
		t.Fatal("an all-single-character path passed the sentence quality gate")
	}
}

func TestRuntimePronunciationPreservesSharedCodeReadings(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	numeric, marked, shared, err := resolver.runtimePronunciation("'rrr")
	if err != nil {
		t.Fatal(err)
	}
	if numeric != "e1/o1" || marked != "ē/ō" || !shared {
		t.Fatalf("shared-code pronunciation=(%q, %q, %v)", numeric, marked, shared)
	}

	sharedCodes := 0
	for _, readings := range resolver.fullCodePronunciations {
		if len(readings) > 1 {
			sharedCodes++
		}
		if len(readings) > 2 {
			t.Fatalf("unexpected pronunciation fan-out: %#v", readings)
		}
	}
	if sharedCodes != 9 {
		t.Fatalf("shared full codes=%d want 9", sharedCodes)
	}
}

func TestDuplicateTextKeepsOneExplicitSelectedPronunciation(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	entries := []systemlexicon.Entry{
		{Text: "行", Code: resolver.codeMap["xing2"].Full, Weight: 100},
		{Text: "行", Code: resolver.codeMap["hang2"].Full, Weight: 90},
		{Text: "试", Code: resolver.codeMap["shi4"].Full, Weight: 80},
	}
	selected := sampleUniqueEntries(entries, 2, rand.New(rand.NewSource(7)))
	if len(selected) != 2 || selected[0].Text == selected[1].Text {
		t.Fatalf("duplicate suppression failed: %#v", selected)
	}
	for _, entry := range selected {
		item, itemErr := resolver.runtimePracticeItem(entry, nil)
		if itemErr != nil {
			t.Fatal(itemErr)
		}
		if item.Text == "行" && (!strings.Contains(runtimePronunciationDetail(item), item.NumericPinyin) || item.NumericPinyin == "") {
			t.Fatalf("selected polyphonic entry lacks its explicit pronunciation: %#v", item)
		}
	}
}

func TestRuntimePracticeSelectsCompleteHighFrequencyGroupsAndComposableSentences(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	dictPath := filepath.Join(resolver.runtimeDataDir, "yime_full.dict.yaml")
	before := digestFile(t, dictPath)
	set, err := resolver.SelectRuntimePracticeSet(rand.New(rand.NewSource(20260801)))
	if err != nil {
		t.Fatal(err)
	}
	if after := digestFile(t, dictPath); after != before {
		t.Fatalf("runtime practice modified the source dictionary: before=%x after=%x", before, after)
	}
	for _, count := range []int{2, 3, 4, 1} {
		items := set.WordsBySyllableCount[count]
		if len(items) != practiceItemsPerGroup {
			t.Fatalf("%d-syllable items=%d want %d", count, len(items), practiceItemsPerGroup)
		}
		seen := map[string]bool{}
		for _, item := range items {
			if seen[item.Text] || len(strings.Fields(item.FullCode)) != count ||
				len(strings.Fields(item.NumericPinyin)) != count || len(strings.Fields(item.MarkedPinyin)) != count {
				t.Fatalf("invalid %d-syllable item %#v", count, item)
			}
			assertRecoverableRuntimePronunciation(t, resolver, item)
			seen[item.Text] = true
		}
	}
	if len(set.Sentences) != practiceItemsPerGroup {
		t.Fatalf("sentences=%d want %d", len(set.Sentences), practiceItemsPerGroup)
	}
	seenSentences := map[string]bool{}
	for _, sentence := range set.Sentences {
		if seenSentences[sentence.Text] || len(sentence.Parts) < 2 || len(sentence.Parts) > 6 ||
			strings.Join(runtimePartLabels(sentence.Parts), "") != sentence.Text {
			t.Fatalf("sentence is not backed by a complete composition path: %#v", sentence)
		}
		seenSentences[sentence.Text] = true
		assertRecoverableRuntimePronunciation(t, resolver, sentence)
		var partCode []string
		hasMultiSyllablePart := false
		singleCharacterParts := 0
		for _, part := range sentence.Parts {
			if part.Weight <= 0 {
				t.Fatalf("sentence has a non-positive-frequency component: %#v", sentence)
			}
			partCode = append(partCode, strings.Fields(part.FullCode)...)
			hasMultiSyllablePart = hasMultiSyllablePart || len([]rune(part.Text)) >= 2
			if len([]rune(part.Text)) == 1 {
				singleCharacterParts++
			}
		}
		if !hasMultiSyllablePart || singleCharacterParts > 2 || strings.Join(partCode, " ") != sentence.FullCode {
			t.Fatalf("sentence has a low-quality or code-incomplete path: %#v", sentence)
		}
	}

	wantWordTitles := []string{"双音词语", "三音词语", "四音词语", "单音节字"}
	for _, mode := range []reverselookup.Mode{
		reverselookup.ModeVariable,
		reverselookup.ModeFull,
		reverselookup.ModeShorthand,
	} {
		groups, err := resolver.ResolveWordPracticeGroups(set, mode)
		if err != nil {
			t.Fatalf("mode %s words: %v", mode, err)
		}
		if len(groups) != len(wantWordTitles) {
			t.Fatalf("mode %s groups=%d", mode, len(groups))
		}
		for index, group := range groups {
			if group.Title != wantWordTitles[index] || len(group.Exercises) != practiceItemsPerGroup {
				t.Fatalf("mode %s group %d=%#v", mode, index, group)
			}
			for _, exercise := range group.Exercises {
				if exercise.SectionType != SectionWordPractice || strings.TrimSpace(exercise.Expected) == "" ||
					strings.TrimSpace(exercise.MarkedPinyin) == "" || strings.TrimSpace(exercise.NumericPinyin) == "" ||
					!strings.Contains(exercise.Detail, "标准拼音：") {
					t.Fatalf("mode %s invalid word exercise %#v", mode, exercise)
				}
				item := runtimeItemByText(t, set.WordsBySyllableCount, exercise.Prompt)
				want, err := resolver.convertFullRuntimeCode(item.FullCode, mode)
				if err != nil || exercise.Expected != want || exercise.NumericPinyin != item.NumericPinyin {
					t.Fatalf("mode %s word answer is inconsistent: exercise=%#v item=%#v err=%v", mode, exercise, item, err)
				}
				assertAnswerUnitsMatch(t, exercise)
			}
		}
		sentences, err := resolver.ResolveSentencePractice(set, mode)
		if err != nil {
			t.Fatalf("mode %s sentences: %v", mode, err)
		}
		if len(sentences) != practiceItemsPerGroup {
			t.Fatalf("mode %s sentences=%d", mode, len(sentences))
		}
		for index, exercise := range sentences {
			item := set.Sentences[index]
			want, convertErr := resolver.convertFullRuntimeCode(item.FullCode, mode)
			if convertErr != nil || exercise.Prompt != item.Text || exercise.Expected != want ||
				exercise.NumericPinyin != item.NumericPinyin || !strings.Contains(exercise.Detail, "动态组句：") {
				t.Fatalf("mode %s sentence answer is inconsistent: exercise=%#v item=%#v err=%v", mode, exercise, item, convertErr)
			}
			assertAnswerUnitsMatch(t, exercise)
		}
	}
}

func assertAnswerUnitsMatch(t *testing.T, exercise Exercise) {
	t.Helper()
	var answer strings.Builder
	for _, unit := range exercise.AnswerUnits {
		answer.WriteString(unit.ExpectedKey)
		if unit.Syllable <= 0 || unit.Position == "" || unit.YinyuanID == "" {
			t.Fatalf("exercise has an untraceable answer unit: %#v", exercise)
		}
	}
	if answer.String() != exercise.Expected {
		t.Fatalf("answer units=%q expected=%q for %#v", answer.String(), exercise.Expected, exercise)
	}
}

func digestFile(t *testing.T, path string) [sha256.Size]byte {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		t.Fatal(err)
	}
	var result [sha256.Size]byte
	copy(result[:], hash.Sum(nil))
	return result
}

func assertRecoverableRuntimePronunciation(t *testing.T, resolver *Resolver, item RuntimePracticeItem) {
	t.Helper()
	numeric, marked, shared, err := resolver.runtimePronunciation(item.FullCode)
	if err != nil {
		t.Fatal(err)
	}
	if numeric != item.NumericPinyin || marked != item.MarkedPinyin || shared != item.HasSharedCodeReadings {
		t.Fatalf("pronunciation is not recoverable for %#v: got (%q, %q, %v)", item, numeric, marked, shared)
	}
}

func runtimeItemByText(t *testing.T, groups map[int][]RuntimePracticeItem, text string) RuntimePracticeItem {
	t.Helper()
	for _, items := range groups {
		for _, item := range items {
			if item.Text == text {
				return item
			}
		}
	}
	t.Fatalf("runtime item %q not found", text)
	return RuntimePracticeItem{}
}
