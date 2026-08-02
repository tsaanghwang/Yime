package trainer

import (
	"fmt"
	"strings"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/reverselookup"
)

var shiftedCandidateKeys = []string{"!", "@", "#", "$", "%", "^", "&", "*", "("}

type CandidateSimulator struct {
	Composition     string
	Candidates      []string
	PageSize        int
	Page            int
	SelectedSegment int
	Segments        []string
	Committed       string
}

type CandidateHostSimulationResult struct {
	Host                     string
	BareDigitComposes        bool
	ShiftOrdinalSelects      bool
	PagingWorks              bool
	SegmentCorrectionCommits bool
}

func NewCandidateSimulator(candidates []string, pageSize int) *CandidateSimulator {
	if pageSize <= 0 || pageSize > 9 {
		pageSize = 9
	}
	return &CandidateSimulator{Candidates: append([]string(nil), candidates...), PageSize: pageSize, SelectedSegment: -1}
}

// PressDigit preserves Yime's fixed input contract: an unshifted digit is
// always appended to composition; only Shift+1 through Shift+9 selects.
func (simulator *CandidateSimulator) PressDigit(digit int, shift bool) (string, bool) {
	if simulator == nil || digit < 1 || digit > 9 {
		return "", false
	}
	if !shift {
		simulator.Composition += fmt.Sprintf("%d", digit)
		return "", false
	}
	index := simulator.Page*simulator.PageSize + digit - 1
	if index < 0 || index >= len(simulator.Candidates) || digit > simulator.PageSize {
		return "", false
	}
	selected := simulator.Candidates[index]
	if simulator.SelectedSegment >= 0 && simulator.SelectedSegment < len(simulator.Segments) {
		simulator.Segments[simulator.SelectedSegment] = selected
		simulator.Committed = strings.Join(simulator.Segments, "")
		simulator.SelectedSegment = -1
	} else {
		simulator.Committed = selected
	}
	return simulator.Committed, true
}

func (simulator *CandidateSimulator) NextPage() bool {
	if simulator == nil || (simulator.Page+1)*simulator.PageSize >= len(simulator.Candidates) {
		return false
	}
	simulator.Page++
	return true
}

func (simulator *CandidateSimulator) PreviousPage() bool {
	if simulator == nil || simulator.Page == 0 {
		return false
	}
	simulator.Page--
	return true
}

func (simulator *CandidateSimulator) SelectCompositionSegment(index, count int) bool {
	if simulator == nil || index < 0 || index >= count {
		return false
	}
	simulator.SelectedSegment = index
	simulator.Committed = ""
	return true
}

func (simulator *CandidateSimulator) SetCompositionSegments(parts []string) {
	if simulator == nil {
		return
	}
	simulator.Segments = append([]string(nil), parts...)
	simulator.Committed = strings.Join(simulator.Segments, "")
	simulator.SelectedSegment = -1
}

func (resolver *Resolver) ResolveCandidatePractice(set RuntimePracticeSet, mode reverselookup.Mode) ([]Exercise, error) {
	if len(set.Sentences) < practiceItemsPerGroup {
		return nil, fmt.Errorf("候选实战需要 %d 个隔离模拟句，当前只有 %d 个", practiceItemsPerGroup, len(set.Sentences))
	}
	exercises := make([]Exercise, 0, practiceItemsPerGroup)
	for index := 0; index < practiceItemsPerGroup; index++ {
		item := set.Sentences[index]
		code, err := resolver.convertFullRuntimeCode(item.FullCode, mode)
		if err != nil {
			return nil, err
		}
		ordinal := index + 1
		distractors := make([]string, 0, practiceItemsPerGroup-1)
		for offset := 1; offset < practiceItemsPerGroup; offset++ {
			distractors = append(distractors, set.Sentences[(index+offset)%practiceItemsPerGroup].Text)
		}
		candidates := make([]string, 0, practiceItemsPerGroup)
		candidates = append(candidates, distractors[:ordinal-1]...)
		candidates = append(candidates, item.Text)
		candidates = append(candidates, distractors[ordinal-1:]...)
		labels := make([]string, 0, len(candidates))
		for candidateIndex, candidate := range candidates {
			labels = append(labels, fmt.Sprintf("⇧%d %s", candidateIndex+1, candidate))
		}
		candidateDisplay := strings.Join(labels[:3], "    ") + "\r\n" + strings.Join(labels[3:], "    ")
		units, err := resolver.answerUnitsForFullCode(item.FullCode, mode)
		if err != nil {
			return nil, err
		}
		units = append(units, AnswerUnit{ExpectedKey: shiftedCandidateKeys[ordinal-1], Position: "候选选择", DisplayName: fmt.Sprintf("⇧%d", ordinal)})
		exercises = append(exercises, Exercise{
			ID:           fmt.Sprintf("candidate:%s:%s:%d:%s", item.Text, item.FullCode, ordinal, mode),
			SectionType:  SectionCandidatePractice,
			SectionTitle: "候选实战",
			Instruction:  "先连续输入完整编码，再按候选标签使用 Shift+数字；裸数字始终仍是组成键。",
			Prompt:       item.Text,
			Detail: runtimePronunciationDetail(item) + "\r\n隔离模拟候选：" + candidateDisplay +
				"\r\n模拟器另行验证翻页、句中分段改选及改选后整句提交；本题不连接 PIME/Rime。",
			Expected:      code + shiftedCandidateKeys[ordinal-1],
			AnswerLabel:   fmt.Sprintf("完整编码 + ⇧%d", ordinal),
			MarkedPinyin:  item.MarkedPinyin,
			NumericPinyin: item.NumericPinyin,
			AnswerUnits:   units,
			LearningTags:  []string{"candidate-selection", fmt.Sprintf("candidate-ordinal:%d", ordinal), "mode:" + string(mode)},
		})
	}
	return exercises, nil
}

func RunCandidateHostSimulation(host string) CandidateHostSimulationResult {
	result := CandidateHostSimulationResult{Host: host}
	simulator := NewCandidateSimulator([]string{"候选一", "候选二", "候选三", "候选四"}, 3)
	simulator.PressDigit(1, false)
	result.BareDigitComposes = simulator.Composition == "1" && simulator.Committed == ""
	selected, ok := simulator.PressDigit(2, true)
	result.ShiftOrdinalSelects = ok && selected == "候选二"
	result.PagingWorks = simulator.NextPage() && simulator.Page == 1 && simulator.PreviousPage() && simulator.Page == 0
	simulator.SetCompositionSegments([]string{"边做边", "是"})
	simulator.Candidates = []string{"是", "试"}
	if simulator.SelectCompositionSegment(1, 2) {
		committed, selectedOK := simulator.PressDigit(2, true)
		result.SegmentCorrectionCommits = selectedOK && committed == "边做边试"
	}
	return result
}
