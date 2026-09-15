//go:build !windows

package processmemory

import "fmt"

type Snapshot struct {
	WorkingSetBytes uint64 `json:"working_set_bytes"`
	PrivateBytes    uint64 `json:"private_bytes"`
}

func Current() (Snapshot, error) {
	return Snapshot{}, fmt.Errorf("process memory snapshot is not implemented on this platform")
}

func PID(pid int) (Snapshot, error) {
	return Snapshot{}, fmt.Errorf("process memory snapshot for PID %d is not implemented on this platform", pid)
}
