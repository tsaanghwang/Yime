//go:build windows

package main

import "testing"

func TestToolHubButtonsFormAlignedTwoColumnGrid(t *testing.T) {
	boxes := toolHubButtonRects(620, toolHubMinimumClientHeight(10), 10)
	if len(boxes) != 10 {
		t.Fatalf("expected ten tool buttons, got %d", len(boxes))
	}
	if boxes[0].Left != 16 || boxes[1].Right != 604 {
		t.Fatalf("button grid must align with both content edges: %#v", boxes[:2])
	}
	leftWidth := boxes[0].Right - boxes[0].Left
	rightWidth := boxes[1].Right - boxes[1].Left
	if leftWidth != rightWidth {
		t.Fatalf("columns must be symmetric: left=%d right=%d", leftWidth, rightWidth)
	}
	for index := 2; index < len(boxes); index++ {
		if boxes[index].Left != boxes[index%2].Left || boxes[index].Right != boxes[index%2].Right {
			t.Fatalf("button %d is not column-aligned: %#v", index, boxes[index])
		}
	}
}

func TestToolHubButtonsExpandAndStayVerticallyCentered(t *testing.T) {
	compact := toolHubButtonRects(620, toolHubMinimumClientHeight(10), 10)
	expanded := toolHubButtonRects(820, toolHubMinimumClientHeight(10)+120, 10)
	if expanded[0].Right-expanded[0].Left <= compact[0].Right-compact[0].Left {
		t.Fatal("buttons should expand with the window width")
	}
	if expanded[0].Top <= compact[0].Top {
		t.Fatal("button grid should remain vertically centered in a taller window")
	}
	if expanded[len(expanded)-1].Bottom >= toolHubMinimumClientHeight(10)+120 {
		t.Fatal("expanded grid must stay inside the client area")
	}
}

func TestToolHubOddEntryCountKeepsLastButtonInLeftColumn(t *testing.T) {
	boxes := toolHubButtonRects(620, toolHubMinimumClientHeight(9), 9)
	if len(boxes) != 9 || boxes[8].Left != boxes[0].Left {
		t.Fatalf("odd final entry should occupy the left column: %#v", boxes)
	}
}
