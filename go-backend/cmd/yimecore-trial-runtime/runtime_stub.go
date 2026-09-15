//go:build !windows

package main

import (
	"errors"
	"os"
	"time"
)

type runtimeHandle struct{}
type runtimeProcess struct{}

func acquireRuntimeInstance(string) (*runtimeHandle, bool, error) {
	return nil, false, errors.New("trial runtime requires Windows")
}
func createRuntimeStopEvent(string) (*runtimeHandle, error) {
	return nil, errors.New("trial runtime requires Windows")
}
func createChildProcessJob() (*runtimeHandle, error) {
	return nil, errors.New("trial runtime requires Windows")
}
func signalRuntimeStop(string) error             { return errors.New("trial runtime requires Windows") }
func (h *runtimeHandle) Wait(time.Duration) bool { return false }
func (h *runtimeHandle) Close() error            { return nil }
func processRunning(int) bool                    { return false }
func startProcessInJob(string, []string, *os.File, *runtimeHandle) (*runtimeProcess, error) {
	return nil, errors.New("trial runtime requires Windows")
}
func (p *runtimeProcess) PID() int    { return 0 }
func (p *runtimeProcess) Kill() error { return nil }
func (p *runtimeProcess) Wait() error { return nil }
