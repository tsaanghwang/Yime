package main

import "testing"

func TestNativeMachineMatches(t *testing.T) {
	cases := []struct {
		arch            string
		ok              bool
		process, native uint16
		want            bool
	}{
		{"amd64", true, 0, 0x8664, true}, {"arm64", true, 0, 0xaa64, true},
		{"amd64", true, 0, 0xaa64, false}, {"arm64", true, 0, 0x8664, false},
		{"amd64", true, 0x8664, 0xaa64, false}, {"arm64", true, 0x8664, 0xaa64, false},
		{"arm64", false, 0, 0xaa64, false}, {"386", true, 0, 0xaa64, false},
	}
	for _, c := range cases {
		if got := nativeMachineMatches(c.arch, c.ok, c.process, c.native); got != c.want {
			t.Errorf("%+v: got %v", c, got)
		}
	}
}
