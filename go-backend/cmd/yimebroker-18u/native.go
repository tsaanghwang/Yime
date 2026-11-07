package main

import "fmt"

func requireBrokerPlatform(goos, goarch string) error {
	if goos != "windows" || (goarch != "amd64" && goarch != "arm64") {
		return fmt.Errorf("dedicated broker requires Windows x64 or ARM64")
	}
	return nil
}

// IsWow64Process2 reports zero for a non-emulated process. The host machine
// must also match this binary: a nonzero process machine is never accepted.
func validateNativeArchitecture(goarch string, machine, native uint16, queryErr error) error {
	if queryErr != nil {
		return queryErr
	}
	var expected uint16
	switch goarch {
	case "amd64":
		expected = 0x8664
	case "arm64":
		expected = 0xaa64
	default:
		return fmt.Errorf("unsupported dedicated broker architecture %q", goarch)
	}
	if machine != 0 || native != expected {
		return fmt.Errorf("dedicated broker requires native Windows %s, not emulation or another architecture", goarch)
	}
	return nil
}
