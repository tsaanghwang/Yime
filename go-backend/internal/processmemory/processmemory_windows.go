//go:build windows

// Package processmemory reports current-process memory for matched experiment
// evidence without adding a third-party dependency.
package processmemory

import (
	"fmt"
	"syscall"
	"unsafe"
)

type Snapshot struct {
	WorkingSetBytes uint64 `json:"working_set_bytes"`
	PrivateBytes    uint64 `json:"private_bytes"`
}

type processMemoryCountersEx struct {
	CB                         uint32
	PageFaultCount             uint32
	PeakWorkingSetSize         uintptr
	WorkingSetSize             uintptr
	QuotaPeakPagedPoolUsage    uintptr
	QuotaPagedPoolUsage        uintptr
	QuotaPeakNonPagedPoolUsage uintptr
	QuotaNonPagedPoolUsage     uintptr
	PagefileUsage              uintptr
	PeakPagefileUsage          uintptr
	PrivateUsage               uintptr
}

var (
	kernel32             = syscall.NewLazyDLL("kernel32.dll")
	getCurrentProcess    = kernel32.NewProc("GetCurrentProcess")
	psapi                = syscall.NewLazyDLL("psapi.dll")
	getProcessMemoryInfo = psapi.NewProc("GetProcessMemoryInfo")
)

func Current() (Snapshot, error) {
	handle, _, _ := getCurrentProcess.Call()
	return snapshot(handle)
}

func PID(pid int) (Snapshot, error) {
	if pid <= 0 {
		return Snapshot{}, fmt.Errorf("invalid process ID %d", pid)
	}
	handle, err := syscall.OpenProcess(0x0400|0x0010, false, uint32(pid))
	if err != nil {
		return Snapshot{}, fmt.Errorf("OpenProcess failed: %w", err)
	}
	defer syscall.CloseHandle(handle)
	return snapshot(uintptr(handle))
}

func snapshot(handle uintptr) (Snapshot, error) {
	var counters processMemoryCountersEx
	counters.CB = uint32(unsafe.Sizeof(counters))
	result, _, callErr := getProcessMemoryInfo.Call(
		handle,
		uintptr(unsafe.Pointer(&counters)),
		uintptr(counters.CB),
	)
	if result == 0 {
		return Snapshot{}, fmt.Errorf("GetProcessMemoryInfo failed: %w", callErr)
	}
	return Snapshot{WorkingSetBytes: uint64(counters.WorkingSetSize), PrivateBytes: uint64(counters.PrivateUsage)}, nil
}
