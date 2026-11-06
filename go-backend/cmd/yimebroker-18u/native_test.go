package main

import (
	"errors"
	"testing"
)

func TestBrokerPlatform(t *testing.T) {
	for _, tc := range []struct {
		goos, goarch string
		want         bool
	}{
		{"windows", "amd64", true},
		{"windows", "arm64", true},
		{"windows", "386", false},
		{"windows", "arm", false},
		{"windows", "", false},
		{"linux", "amd64", false},
		{"linux", "arm64", false},
		{"darwin", "arm64", false},
	} {
		t.Run(tc.goos+"/"+tc.goarch, func(t *testing.T) {
			if got := requireBrokerPlatform(tc.goos, tc.goarch) == nil; got != tc.want {
				t.Fatalf("accepted = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestNativeArchitectureIdentity(t *testing.T) {
	for _, tc := range []struct {
		name, arch      string
		machine, native uint16
		queryErr        error
		want            bool
	}{
		{"native-x64", "amd64", 0, 0x8664, nil, true},
		{"native-arm64", "arm64", 0, 0xaa64, nil, true},
		{"x64-on-arm64", "amd64", 0x8664, 0xaa64, nil, false},
		{"x64-mismatched-host", "amd64", 0, 0xaa64, nil, false},
		{"arm64-mismatched-host", "arm64", 0, 0x8664, nil, false},
		{"x86-on-x64", "amd64", 0x014c, 0x8664, nil, false},
		{"x86-on-arm64", "arm64", 0x014c, 0xaa64, nil, false},
		{"arm-emulation", "arm64", 0x01c4, 0xaa64, nil, false},
		{"nonzero-matching-process", "arm64", 0xaa64, 0xaa64, nil, false},
		{"unknown-host", "arm64", 0, 0, nil, false},
		{"unsupported-binary", "386", 0, 0x8664, nil, false},
		{"query-unavailable", "arm64", 0, 0xaa64, errors.New("query unavailable"), false},
		{"query-failed", "amd64", 0, 0x8664, errors.New("query failed"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := validateNativeArchitecture(tc.arch, tc.machine, tc.native, tc.queryErr) == nil; got != tc.want {
				t.Fatalf("accepted = %v, want %v", got, tc.want)
			}
		})
	}
}
