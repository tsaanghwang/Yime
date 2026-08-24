//go:build windows

package main

import (
	"crypto/sha256"
	"fmt"
	"os/exec"
	"syscall"
	"time"
	"unsafe"
)

const (
	runtimeMutexPrefix = `Local\YimeCoreTrialRuntime.v1.`
	runtimeStopPrefix  = `Local\YimeCoreTrialRuntime.Stop.v1.`
	waitObject0        = 0
	waitTimeout        = 258
	errorAlreadyExists = 183
	eventModifyState   = 0x0002
	synchronize        = 0x00100000
	processSync        = 0x00100000
	createNoWindow     = 0x08000000
)

var (
	kernel32Runtime   = syscall.NewLazyDLL("kernel32.dll")
	procCreateMutexW  = kernel32Runtime.NewProc("CreateMutexW")
	procCreateEventW  = kernel32Runtime.NewProc("CreateEventW")
	procOpenEventW    = kernel32Runtime.NewProc("OpenEventW")
	procSetEvent      = kernel32Runtime.NewProc("SetEvent")
	procWaitForSingle = kernel32Runtime.NewProc("WaitForSingleObject")
	procOpenProcess   = kernel32Runtime.NewProc("OpenProcess")
	procCloseHandle   = kernel32Runtime.NewProc("CloseHandle")
)

type runtimeHandle struct{ value uintptr }

func acquireRuntimeInstance(pipeName string) (*runtimeHandle, bool, error) {
	name, _ := syscall.UTF16PtrFromString(runtimeObjectName(runtimeMutexPrefix, pipeName))
	handle, _, callErr := procCreateMutexW.Call(0, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return nil, false, fmt.Errorf("CreateMutexW failed: %w", callErr)
	}
	already := callErr == syscall.Errno(errorAlreadyExists)
	return &runtimeHandle{value: handle}, already, nil
}

func createRuntimeStopEvent(pipeName string) (*runtimeHandle, error) {
	name, _ := syscall.UTF16PtrFromString(runtimeObjectName(runtimeStopPrefix, pipeName))
	handle, _, callErr := procCreateEventW.Call(0, 1, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return nil, fmt.Errorf("CreateEventW failed: %w", callErr)
	}
	return &runtimeHandle{value: handle}, nil
}

func signalRuntimeStop(pipeName string) error {
	name, _ := syscall.UTF16PtrFromString(runtimeObjectName(runtimeStopPrefix, pipeName))
	handle, _, callErr := procOpenEventW.Call(eventModifyState|synchronize, 0, uintptr(unsafe.Pointer(name)))
	if handle == 0 {
		return fmt.Errorf("OpenEventW failed: %w", callErr)
	}
	defer procCloseHandle.Call(handle)
	result, _, callErr := procSetEvent.Call(handle)
	if result == 0 {
		return fmt.Errorf("SetEvent failed: %w", callErr)
	}
	return nil
}

func (h *runtimeHandle) Wait(timeout time.Duration) bool {
	if h == nil || h.value == 0 {
		return false
	}
	milliseconds := uintptr(timeout / time.Millisecond)
	result, _, _ := procWaitForSingle.Call(h.value, milliseconds)
	return result == waitObject0
}

func (h *runtimeHandle) Close() error {
	if h == nil || h.value == 0 {
		return nil
	}
	procCloseHandle.Call(h.value)
	h.value = 0
	return nil
}

func processRunning(pid int) bool {
	if pid <= 0 {
		return false
	}
	handle, _, _ := procOpenProcess.Call(processSync, 0, uintptr(pid))
	if handle == 0 {
		return false
	}
	defer procCloseHandle.Call(handle)
	result, _, _ := procWaitForSingle.Call(handle, 0)
	return result == waitTimeout
}

func configureChildProcess(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
}

func runtimeObjectName(prefix, pipeName string) string {
	hash := sha256.Sum256([]byte(pipeName))
	return fmt.Sprintf("%s%x", prefix, hash[:8])
}
