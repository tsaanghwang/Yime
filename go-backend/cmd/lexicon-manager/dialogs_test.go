//go:build windows

package main

import (
	"strconv"
	"testing"
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
