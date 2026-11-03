package main

// nativeMachineMatches rejects emulated processes and unsupported architectures.
func nativeMachineMatches(arch string, apiOK bool, processMachine, nativeMachine uint16) bool {
	if !apiOK || processMachine != 0 {
		return false
	}
	switch arch {
	case "amd64":
		return nativeMachine == 0x8664
	case "arm64":
		return nativeMachine == 0xaa64
	default:
		return false
	}
}
