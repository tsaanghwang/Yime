//go:build !amd64 && !arm64

package touchbroker

import "testing"

func TestNewProductionRejectsUnsupportedArchitecture(t *testing.T) {
	s, err := NewProduction(t.TempDir(), t.TempDir())
	if s != nil || err == nil || err.Error() != "unsupported dedicated broker architecture" {
		t.Fatalf("unsupported process did not fail before resource selection: service=%v error=%v", s, err)
	}
}
