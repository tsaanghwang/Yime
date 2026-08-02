package trainer

import (
	"fmt"
	"math/rand"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

func TestCandidateSimulatorPreservesDigitsAndShiftOrdinals(t *testing.T) {
	simulator := NewCandidateSimulator([]string{"一", "二", "三", "四"}, 3)
	if selected, ok := simulator.PressDigit(2, false); ok || selected != "" || simulator.Composition != "2" {
		t.Fatalf("bare digit did not remain composition: %#v selected=%q", simulator, selected)
	}
	if selected, ok := simulator.PressDigit(2, true); !ok || selected != "二" {
		t.Fatalf("Shift+2 selection failed: %#v selected=%q", simulator, selected)
	}
	if !simulator.NextPage() || simulator.Page != 1 {
		t.Fatal("candidate simulation did not page forward")
	}
	if selected, ok := simulator.PressDigit(1, true); !ok || selected != "四" {
		t.Fatalf("paged Shift+1 selection failed: %#v selected=%q", simulator, selected)
	}
	if !simulator.PreviousPage() {
		t.Fatal("candidate simulation did not page backward")
	}
	simulator.SetCompositionSegments([]string{"边做边", "是"})
	simulator.Candidates = []string{"是", "试"}
	if !simulator.SelectCompositionSegment(1, 2) || simulator.SelectedSegment != 1 || simulator.Committed != "" {
		t.Fatalf("segment correction state failed: %#v", simulator)
	}
	if committed, ok := simulator.PressDigit(2, true); !ok || committed != "边做边试" || simulator.SelectedSegment != -1 {
		t.Fatalf("corrected full-sentence commit failed: %#v committed=%q", simulator, committed)
	}
}

func TestCandidatePracticeUsesIsolatedRuntimeSetAndShiftAwareLabels(t *testing.T) {
	resolver, err := NewResolver(repositoryDataDir(t))
	if err != nil {
		t.Fatal(err)
	}
	set, err := resolver.SelectRuntimePracticeSet(rand.New(rand.NewSource(20260802)))
	if err != nil {
		t.Fatal(err)
	}
	for _, mode := range []reverselookup.Mode{reverselookup.ModeVariable, reverselookup.ModeFull, reverselookup.ModeShorthand} {
		exercises, resolveErr := resolver.ResolveCandidatePractice(set, mode)
		if resolveErr != nil {
			t.Fatal(resolveErr)
		}
		if len(exercises) != practiceItemsPerGroup {
			t.Fatalf("mode %s candidate exercises=%d", mode, len(exercises))
		}
		for index, exercise := range exercises {
			if !strings.Contains(exercise.Detail, fmt.Sprintf("⇧%d %s", index+1, exercise.Prompt)) ||
				strings.Contains(exercise.Detail, " 1 "+exercise.Prompt) ||
				!strings.HasSuffix(exercise.Expected, shiftedCandidateKeys[index]) {
				t.Fatalf("mode %s exercise %d violates Shift ordinal contract: %#v", mode, index, exercise)
			}
			var answer strings.Builder
			for _, unit := range exercise.AnswerUnits {
				answer.WriteString(unit.ExpectedKey)
			}
			if answer.String() != exercise.Expected || exercise.AnswerUnits[len(exercise.AnswerUnits)-1].Position != "候选选择" {
				t.Fatalf("mode %s candidate units do not explain the answer: %#v", mode, exercise)
			}
		}
	}
}

func TestCandidateWorkflowSimulationPassesThreeHostProfiles(t *testing.T) {
	for _, host := range []string{"x64 Notepad", "Codex IDE", "x86 SysWOW64 charmap"} {
		result := RunCandidateHostSimulation(host)
		if result.Host != host || !result.BareDigitComposes || !result.ShiftOrdinalSelects || !result.PagingWorks || !result.SegmentCorrectionCommits {
			t.Fatalf("host simulation failed: %#v", result)
		}
	}
}
