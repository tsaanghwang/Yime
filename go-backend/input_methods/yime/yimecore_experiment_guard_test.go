package yime

import (
	"os"
	"strings"
	"testing"
)

// The experimental Go core must remain parallel until the documented
// comparison gates pass. This source guard prevents an incidental factory
// switch from changing the production backend while E0 is still in progress.
func TestYimeCoreExperimentKeepsRimeAsDefaultBackend(t *testing.T) {
	source, err := os.ReadFile("yime.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(source), "var createRimeBackend = newNativeBackend") {
		t.Fatal("experimental YimeCore must not replace the production Rime backend factory")
	}
}
