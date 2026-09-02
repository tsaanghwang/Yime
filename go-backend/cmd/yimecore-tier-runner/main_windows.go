//go:build windows

// Command yimecore-tier-runner runs one benchmark in a Windows Job Object
// with a host-normalized CPU hard cap and a fixed processor affinity. It is a
// repeatable resource-pressure harness, not a claim to emulate a particular
// processor microarchitecture, cache hierarchy, storage device or RAM speed.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"syscall"
	"time"
	"unsafe"
)

const (
	jobObjectExtendedLimitInformation  = 9
	jobObjectCpuRateControlInformation = 15
	jobObjectLimitKillOnJobClose       = 0x00002000
	jobObjectCpuRateControlEnable      = 0x1
	jobObjectCpuRateControlHardCap     = 0x4
	processTerminate                   = 0x0001
	processSetQuota                    = 0x0100
	processSetInformation              = 0x0200
	processQueryLimitedInformation     = 0x1000
	synchronize                        = 0x00100000
	belowNormalPriorityClass           = 0x00004000
)

var (
	kernel32                    = syscall.NewLazyDLL("kernel32.dll")
	procCreateJobObjectW        = kernel32.NewProc("CreateJobObjectW")
	procSetInformationJobObject = kernel32.NewProc("SetInformationJobObject")
	procAssignProcessToJob      = kernel32.NewProc("AssignProcessToJobObject")
	procOpenProcess             = kernel32.NewProc("OpenProcess")
	procCloseHandle             = kernel32.NewProc("CloseHandle")
	procSetProcessAffinityMask  = kernel32.NewProc("SetProcessAffinityMask")
	procSetPriorityClass        = kernel32.NewProc("SetPriorityClass")
)

type ioCounters struct {
	ReadOperationCount  uint64
	WriteOperationCount uint64
	OtherOperationCount uint64
	ReadTransferCount   uint64
	WriteTransferCount  uint64
	OtherTransferCount  uint64
}

type basicLimitInformation struct {
	PerProcessUserTimeLimit int64
	PerJobUserTimeLimit     int64
	LimitFlags              uint32
	MinimumWorkingSetSize   uintptr
	MaximumWorkingSetSize   uintptr
	ActiveProcessLimit      uint32
	Affinity                uintptr
	PriorityClass           uint32
	SchedulingClass         uint32
}

type extendedLimitInformation struct {
	BasicLimitInformation basicLimitInformation
	IoInfo                ioCounters
	ProcessMemoryLimit    uintptr
	JobMemoryLimit        uintptr
	PeakProcessMemoryUsed uintptr
	PeakJobMemoryUsed     uintptr
}

type cpuRateControlInformation struct {
	ControlFlags uint32
	CpuRate      uint32
}

type evidence struct {
	ToolVersion          string   `json:"tool_version"`
	GeneratedAt          string   `json:"generated_at"`
	LogicalProcessors    int      `json:"logical_processors"`
	RequestedCorePercent float64  `json:"requested_single_core_percent"`
	JobCpuRate           uint32   `json:"job_cpu_rate_per_10000_total_host"`
	AffinityMask         string   `json:"affinity_mask"`
	Priority             string   `json:"priority"`
	Command              string   `json:"command"`
	Arguments            []string `json:"arguments"`
	ExitCode             int      `json:"exit_code"`
	ElapsedNS            int64    `json:"elapsed_ns"`
}

func main() {
	corePercent := flag.Float64("core-percent", 100, "CPU budget as a percentage of one logical processor")
	affinity := flag.Uint64("affinity-mask", 1, "process affinity mask")
	priority := flag.String("priority", "below-normal", "normal or below-normal")
	evidencePath := flag.String("evidence", "", "optional runner evidence JSON path")
	flag.Parse()
	args := flag.Args()
	if len(args) == 0 || *corePercent <= 0 || *corePercent > 100 || *affinity == 0 {
		fail(errors.New("usage: yimecore-tier-runner [flags] command [arguments]; core-percent must be in (0,100]"))
	}
	if *priority != "normal" && *priority != "below-normal" {
		fail(errors.New("priority must be normal or below-normal"))
	}

	logicalProcessors := runtime.NumCPU()
	cpuRate := uint32((*corePercent / 100) * 10000 / float64(logicalProcessors))
	if cpuRate < 1 {
		cpuRate = 1
	}

	job, err := createJob(cpuRate)
	if err != nil {
		fail(err)
	}
	defer procCloseHandle.Call(job)

	command := exec.Command(args[0], args[1:]...)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	started := time.Now()
	if err := command.Start(); err != nil {
		fail(err)
	}
	process, _, openErr := procOpenProcess.Call(
		processTerminate|processSetQuota|processSetInformation|processQueryLimitedInformation|synchronize,
		0, uintptr(uint32(command.Process.Pid)),
	)
	if process == 0 {
		_ = command.Process.Kill()
		_ = command.Wait()
		fail(fmt.Errorf("OpenProcess failed: %w", openErr))
	}
	defer procCloseHandle.Call(process)
	if assigned, _, callErr := procAssignProcessToJob.Call(job, process); assigned == 0 {
		_ = command.Process.Kill()
		_ = command.Wait()
		fail(fmt.Errorf("AssignProcessToJobObject failed: %w", callErr))
	}
	if set, _, callErr := procSetProcessAffinityMask.Call(process, uintptr(*affinity)); set == 0 {
		_ = command.Process.Kill()
		_ = command.Wait()
		fail(fmt.Errorf("SetProcessAffinityMask failed: %w", callErr))
	}
	if *priority == "below-normal" {
		if set, _, callErr := procSetPriorityClass.Call(process, belowNormalPriorityClass); set == 0 {
			_ = command.Process.Kill()
			_ = command.Wait()
			fail(fmt.Errorf("SetPriorityClass failed: %w", callErr))
		}
	}

	waitErr := command.Wait()
	exitCode := 0
	if waitErr != nil {
		var exitErr *exec.ExitError
		if errors.As(waitErr, &exitErr) {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = 1
		}
	}
	report := evidence{
		ToolVersion: "yimecore-tier-runner-v1", GeneratedAt: time.Now().UTC().Format(time.RFC3339Nano),
		LogicalProcessors: logicalProcessors, RequestedCorePercent: *corePercent, JobCpuRate: cpuRate,
		AffinityMask: "0x" + strconv.FormatUint(*affinity, 16), Priority: *priority,
		Command: args[0], Arguments: args[1:], ExitCode: exitCode, ElapsedNS: time.Since(started).Nanoseconds(),
	}
	if *evidencePath != "" {
		data, marshalErr := json.MarshalIndent(report, "", "  ")
		if marshalErr != nil {
			fail(marshalErr)
		}
		data = append(data, '\n')
		if writeErr := os.WriteFile(*evidencePath, data, 0o644); writeErr != nil {
			fail(writeErr)
		}
	}
	if exitCode != 0 {
		os.Exit(exitCode)
	}
}

func createJob(cpuRate uint32) (uintptr, error) {
	handle, _, callErr := procCreateJobObjectW.Call(0, 0)
	if handle == 0 {
		return 0, fmt.Errorf("CreateJobObjectW failed: %w", callErr)
	}
	limits := extendedLimitInformation{}
	limits.BasicLimitInformation.LimitFlags = jobObjectLimitKillOnJobClose
	if err := setJobInformation(handle, jobObjectExtendedLimitInformation, unsafe.Pointer(&limits), unsafe.Sizeof(limits)); err != nil {
		procCloseHandle.Call(handle)
		return 0, err
	}
	cpu := cpuRateControlInformation{ControlFlags: jobObjectCpuRateControlEnable | jobObjectCpuRateControlHardCap, CpuRate: cpuRate}
	if err := setJobInformation(handle, jobObjectCpuRateControlInformation, unsafe.Pointer(&cpu), unsafe.Sizeof(cpu)); err != nil {
		procCloseHandle.Call(handle)
		return 0, err
	}
	return handle, nil
}

func setJobInformation(handle uintptr, class uintptr, information unsafe.Pointer, size uintptr) error {
	set, _, callErr := procSetInformationJobObject.Call(handle, class, uintptr(information), size)
	if set == 0 {
		return fmt.Errorf("SetInformationJobObject(%d) failed: %w", class, callErr)
	}
	return nil
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
