//go:build !windows

package diagnostics

func processRunning(name string) bool {
	_ = name
	return false
}
