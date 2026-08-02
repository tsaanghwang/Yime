package trainer

import (
	"math/rand"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/systemlexicon"
)

func TestCompositionPartsRequiresRuntimeComponentsWithMatchingCodes(t *testing.T) {
	entry := systemlexicon.Entry{Text: "我们爱中国", Code: "wo men ai zhong guo", Weight: 100}
	components := map[string]bool{
		componentKey("我们爱", "wo men ai"): true,
		componentKey("中国", "zhong guo"):  true,
	}
	parts, ok := compositionParts(entry, components)
	if !ok || strings.Join(parts, "+") != "我们爱+中国" {
		t.Fatalf("compositionParts=%#v ok=%v", parts, ok)
	}
	delete(components, componentKey("中国", "zhong guo"))
	components[componentKey("中国", "wrong code")] = true
	if _, ok := compositionParts(entry, components); ok {
		t.Fatal("text-only match incorrectly passed dynamic composition check")
	}
}

func TestRuntimePracticeSelectsCompleteHighFrequencyGroupsAndComposableSentences(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	set, err := resolver.SelectRuntimePracticeSet(rand.New(rand.NewSource(20260801)))
	if err != nil {
		t.Fatal(err)
	}
	for _, count := range []int{2, 3, 4, 1} {
		items := set.WordsBySyllableCount[count]
		if len(items) != practiceItemsPerGroup {
			t.Fatalf("%d-syllable items=%d want %d", count, len(items), practiceItemsPerGroup)
		}
		seen := map[string]bool{}
		for _, item := range items {
			if seen[item.Text] || len(strings.Fields(item.FullCode)) != count {
				t.Fatalf("invalid %d-syllable item %#v", count, item)
			}
			seen[item.Text] = true
		}
	}
	if len(set.Sentences) != practiceItemsPerGroup {
		t.Fatalf("sentences=%d want %d", len(set.Sentences), practiceItemsPerGroup)
	}
	for _, sentence := range set.Sentences {
		if len(sentence.Parts) < 2 || strings.Join(sentence.Parts, "") != sentence.Text {
			t.Fatalf("sentence is not backed by a complete composition path: %#v", sentence)
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
				if exercise.SectionType != SectionWordPractice || strings.TrimSpace(exercise.Expected) == "" {
					t.Fatalf("mode %s invalid word exercise %#v", mode, exercise)
				}
			}
		}
		sentences, err := resolver.ResolveSentencePractice(set, mode)
		if err != nil {
			t.Fatalf("mode %s sentences: %v", mode, err)
		}
		if len(sentences) != practiceItemsPerGroup {
			t.Fatalf("mode %s sentences=%d", mode, len(sentences))
		}
	}
}
