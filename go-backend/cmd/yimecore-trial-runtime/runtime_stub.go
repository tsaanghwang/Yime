//go:build !windows

package main

import (
	"errors"
	"os/exec"
	"time"
)

type runtimeHandle struct{}

func acquireRuntimeInstance(string) (*runtimeHandle, bool, error) {
	return nil, false, errors.New("trial runtime requires Windows")
}
func createRuntimeStopEvent(string) (*runtimeHandle, error) {
	return nil, errors.New("trial runtime requires Windows")
}
func signalRuntimeStop(string) error             { return errors.New("trial runtime requires Windows") }
func (h *runtimeHandle) Wait(time.Duration) bool { return false }
func (h *runtimeHandle) Close() error            { return nil }
func processRunning(int) bool                    { return false }
func configureChildProcess(*exec.Cmd)            {}
