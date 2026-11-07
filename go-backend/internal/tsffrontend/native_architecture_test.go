package tsffrontend

import "testing"

func TestNativeMachineRejectsEmulationAndForeignTIPArchitecture(t *testing.T) {
	for _, c := range []struct {
		arch            string
		process, native uint16
		want            bool
	}{
		{"amd64", 0, 0x8664, true}, {"arm64", 0, 0xaa64, true},
		{"amd64", 0x8664, 0xaa64, false}, {"amd64", 0, 0xaa64, false},
		{"arm64", 0, 0x8664, false}, {"arm64", 0xa641, 0xaa64, false},
		{"arm64", 0xa64e, 0xaa64, false}, {"arm64", 0, 0xa64e, false},
		{"386", 0x14c, 0xaa64, false}, {"386", 0, 0x14c, false},
		{"arm64", 0, 0, false}, {"", 0, 0xaa64, false},
	} {
		if got := nativeMachineMatches(c.arch, c.process, c.native); got != c.want {
			t.Errorf("%+v: got %v", c, got)
		}
	}
}
