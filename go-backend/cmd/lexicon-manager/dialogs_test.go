//go:build windows

package main

import (
	"strconv"
	"testing"

	"github.com/EasyIME/pime-go/input_methods/yime/reverselookup"
)

func TestAdjustWeightValue(t *testing.T) {
	tests := []struct {
		name      string
		current   string
		step      string
		direction int
		want      string
		wantErr   bool
	}{
		{name: "add", current: "10", step: "3", direction: 1, want: "13"},
		{name: "subtract", current: "10", step: "3", direction: -1, want: "7"},
		{name: "blank defaults", direction: 1, want: "1"},
		{name: "zero step", current: "10", step: "0", direction: -1, want: "10"},
		{name: "invalid current", current: "x", step: "1", direction: 1, wantErr: true},
		{name: "negative step", current: "10", step: "-1", direction: 1, wantErr: true},
		{name: "invalid direction", current: "10", step: "1", direction: 0, wantErr: true},
		{name: "positive overflow", current: strconv.Itoa(int(^uint(0) >> 1)), step: "1", direction: 1, wantErr: true},
		{name: "negative overflow", current: strconv.Itoa(-int(^uint(0)>>1) - 1), step: "1", direction: -1, wantErr: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := adjustWeightValue(test.current, test.step, test.direction)
			if test.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("adjustWeightValue returned error: %v", err)
			}
			if got != test.want {
				t.Fatalf("adjustWeightValue = %q, want %q", got, test.want)
			}
		})
	}
}

func TestCenteredButtonRectsCentersGroupAndPreservesGaps(t *testing.T) {
	buttons := centeredButtonRects(16, 504, 216, 28, 10, []int32{88, 96, 88})
	if len(buttons) != 3 {
		t.Fatalf("expected 3 buttons, got %d", len(buttons))
	}
	leftSpace := buttons[0].Left - 16
	rightSpace := 504 - buttons[len(buttons)-1].Right
	if leftSpace != rightSpace {
		t.Fatalf("button group is not centered: left=%d right=%d", leftSpace, rightSpace)
	}
	for index := 1; index < len(buttons); index++ {
		if buttons[index].Left-buttons[index-1].Right != 10 {
			t.Fatalf("unexpected gap between buttons %d and %d", index-1, index)
		}
	}
}

func TestWeightAdjustmentRectsFillContentRow(t *testing.T) {
	minus, step, plus := weightAdjustmentRects(16, 504, 214, 28, 74, 10)
	if minus.Left != 16 || plus.Right != 504 {
		t.Fatalf("adjustment row does not fill content width: minus=%#v plus=%#v", minus, plus)
	}
	if step.Left-minus.Right != 10 || plus.Left-step.Right != 10 {
		t.Fatalf("adjustment row gaps are inconsistent: minus=%#v step=%#v plus=%#v", minus, step, plus)
	}
	if step.Right <= step.Left {
		t.Fatalf("step input has invalid width: %#v", step)
	}
}

func TestModeDisplayNameUsesChineseLabels(t *testing.T) {
	tests := []struct {
		mode reverselookup.Mode
		want string
	}{
		{mode: reverselookup.ModeVariable, want: "变长模式"},
		{mode: reverselookup.ModeFull, want: "等长模式"},
		{mode: reverselookup.ModeShorthand, want: "省键模式"},
		{mode: reverselookup.Mode("custom"), want: "custom"},
	}
	for _, test := range tests {
		if got := modeDisplayName(test.mode); got != test.want {
			t.Fatalf("modeDisplayName(%q) = %q, want %q", test.mode, got, test.want)
		}
	}
}

func TestNoticeTitleForFlags(t *testing.T) {
	tests := []struct {
		flags uintptr
		want  string
	}{
		{flags: 0x10, want: "操作失败"},
		{flags: 0x30, want: "提示"},
		{flags: 0x40, want: "操作完成"},
		{flags: 0, want: "词库管理"},
	}
	for _, test := range tests {
		if got := noticeTitleForFlags(test.flags); got != test.want {
			t.Fatalf("noticeTitleForFlags(%#x) = %q, want %q", test.flags, got, test.want)
		}
	}
}
