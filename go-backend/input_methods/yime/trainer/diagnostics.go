package trainer

import (
	"fmt"
	"strings"
)

const (
	ErrorNone         = "none"
	ErrorSubstitution = "substitution"
	ErrorMissing      = "missing"
	ErrorExtra        = "extra"
)

// Diagnosis is a mode-aware edit alignment between the submitted physical
// key sequence and the projected answer units of an exercise.
type Diagnosis struct {
	Correct       bool
	ErrorCount    int
	Kind          string
	Unit          AnswerUnit
	ActualKey     string
	Expected      string
	Actual        string
	ExpectedIndex int
}

func Diagnose(exercise Exercise, input string) Diagnosis {
	expected := []rune(exercise.Expected)
	actual := []rune(strings.TrimSpace(input))
	units := exercise.AnswerUnits
	if len(units) != len(expected) {
		units = make([]AnswerUnit, len(expected))
		for index, key := range expected {
			units[index] = AnswerUnit{ExpectedKey: string(key), Position: "编码位置"}
		}
	}
	dp := suffixEditDistance(expected, actual)
	diagnosis := Diagnosis{Correct: dp[0][0] == 0, ErrorCount: dp[0][0], Kind: ErrorNone, Expected: string(expected), Actual: string(actual)}
	if diagnosis.Correct {
		return diagnosis
	}
	i, j := 0, 0
	for i < len(expected) || j < len(actual) {
		if i < len(expected) && j < len(actual) && expected[i] == actual[j] {
			i++
			j++
			continue
		}
		diagnosis.ExpectedIndex = i
		if i < len(units) {
			diagnosis.Unit = units[i]
		} else if len(units) > 0 {
			diagnosis.Unit = units[len(units)-1]
		}
		switch {
		case i < len(expected) && j < len(actual) && dp[i][j] == 1+dp[i+1][j+1]:
			diagnosis.Kind = ErrorSubstitution
			diagnosis.ActualKey = string(actual[j])
		case i < len(expected) && dp[i][j] == 1+dp[i+1][j]:
			diagnosis.Kind = ErrorMissing
		case j < len(actual):
			diagnosis.Kind = ErrorExtra
			diagnosis.ActualKey = string(actual[j])
		}
		return diagnosis
	}
	return diagnosis
}

func suffixEditDistance(expected, actual []rune) [][]int {
	dp := make([][]int, len(expected)+1)
	for i := range dp {
		dp[i] = make([]int, len(actual)+1)
	}
	for i := len(expected); i >= 0; i-- {
		for j := len(actual); j >= 0; j-- {
			switch {
			case i == len(expected):
				dp[i][j] = len(actual) - j
			case j == len(actual):
				dp[i][j] = len(expected) - i
			case expected[i] == actual[j]:
				dp[i][j] = dp[i+1][j+1]
			default:
				dp[i][j] = 1 + minInt(dp[i+1][j+1], dp[i+1][j], dp[i][j+1])
			}
		}
	}
	return dp
}

func minInt(values ...int) int {
	result := values[0]
	for _, value := range values[1:] {
		if value < result {
			result = value
		}
	}
	return result
}

func (diagnosis Diagnosis) location() string {
	parts := []string{}
	if diagnosis.Unit.Syllable > 0 {
		parts = append(parts, fmt.Sprintf("第%d个音节", diagnosis.Unit.Syllable))
	}
	if diagnosis.Unit.Position != "" {
		parts = append(parts, diagnosis.Unit.Position)
	}
	if len(parts) == 0 {
		return fmt.Sprintf("第%d个编码位置", diagnosis.ExpectedIndex+1)
	}
	return strings.Join(parts, "的")
}

func (diagnosis Diagnosis) Summary() string {
	if diagnosis.Correct {
		return "正确。"
	}
	location := diagnosis.location()
	expectedKey := diagnosis.Unit.ExpectedKey
	if expectedKey == "" && diagnosis.ExpectedIndex < len([]rune(diagnosis.Expected)) {
		expectedKey = string([]rune(diagnosis.Expected)[diagnosis.ExpectedIndex])
	}
	switch diagnosis.Kind {
	case ErrorMissing:
		return fmt.Sprintf("%s漏键，应输入 %s。共发现 %d 处差异。", location, expectedKey, diagnosis.ErrorCount)
	case ErrorExtra:
		return fmt.Sprintf("%s之前多输入了 %s。共发现 %d 处差异。", location, diagnosis.ActualKey, diagnosis.ErrorCount)
	default:
		return fmt.Sprintf("%s输入成了 %s，应为 %s。共发现 %d 处差异。", location, diagnosis.ActualKey, expectedKey, diagnosis.ErrorCount)
	}
}

// Hint returns the three progressive teaching hints required by the trainer:
// syllable location, canonical Yinyuan, then the complete answer.
func (diagnosis Diagnosis) Hint(level int) string {
	if diagnosis.Correct {
		return "本题已经正确。"
	}
	switch level {
	case 1:
		if diagnosis.Unit.Syllable > 0 {
			return fmt.Sprintf("错误位于第 %d 个音节。", diagnosis.Unit.Syllable)
		}
		return fmt.Sprintf("错误位于第 %d 个编码位置。", diagnosis.ExpectedIndex+1)
	case 2:
		if diagnosis.Unit.YinyuanID != "" {
			return fmt.Sprintf("错误音元：%s %s（%s），目标键 %s。", diagnosis.Unit.Position, diagnosis.Unit.YinyuanID, diagnosis.Unit.DisplayName, diagnosis.Unit.ExpectedKey)
		}
		return diagnosis.Summary()
	default:
		return "完整答案：" + diagnosis.Expected
	}
}
