package tsffrontend

func nativeMachineMatches(arch string, process, native uint16) bool {
	if process != 0 {
		return false
	}
	switch arch {
	case "amd64":
		return native == 0x8664
	case "arm64":
		return native == 0xaa64
	default:
		return false
	}
}
