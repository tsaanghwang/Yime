//go:build windows && (amd64 || arm64)

package main

import "testing"

func TestOwnDemoRepeatedInactivePollKeepsRebindGesture(t *testing.T) {
	a := touchUIFixture(t)
	a.stopDemoSession("inactive")
	a.previewTouches[42] = &previewGesture{action: "reset"}
	a.stopDemoSession("still inactive")
	if a.previewTouches[42] == nil {
		t.Fatal("inactive timer cancelled explicit rebind press")
	}
}
