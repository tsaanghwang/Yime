//go:build windows

package main

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	runtimeMutexPrefix                = `Local\YimeCoreTrialRuntime.v1.`
	runtimeStopPrefix                 = `Local\YimeCoreTrialRuntime.Stop.v1.`
	waitObject0                       = 0
	waitTimeout                       = 258
	errorAlreadyExists                = 183
	eventModifyState                  = 0x0002
	synchronize                       = 0x00100000
	processSync                       = 0x00100000
	createNoWindow                    = 0x08000000
	createUnicodeEnvironment          = 0x00000400
	extendedStartupInfoPresent        = 0x00080000
	startfUseStdHandles               = 0x00000100
	startfUseShowWindow               = 0x00000001
	procThreadAttributeHandleList     = 0x00020002
	procThreadAttributeJobList        = 0x0002000D
	duplicateSameAccess               = 0x00000002
	jobObjectExtendedLimitInformation = 9
	jobObjectLimitKillOnJobClose      = 0x00002000
)

var (
	kernel32Runtime          = syscall.NewLazyDLL("kernel32.dll")
	procCreateMutexW         = kernel32Runtime.NewProc("CreateMutexW")
	procCreateEventW         = kernel32Runtime.NewProc("CreateEventW")
	procOpenEventW           = kernel32Runtime.NewProc("OpenEventW")
	procSetEvent             = kernel32Runtime.NewProc("SetEvent")
	procWaitForSingle        = kernel32Runtime.NewProc("WaitForSingleObject")
	procOpenProcess          = kernel32Runtime.NewProc("OpenProcess")
	procCreateJob            = kernel32Runtime.NewProc("CreateJobObjectW")
	procSetJobInfo           = kernel32Runtime.NewProc("SetInformationJobObject")
	procInitializeAttributes = kernel32Runtime.NewProc("InitializeProcThreadAttributeList")
	procUpdateAttribute      = kernel32Runtime.NewProc("UpdateProcThreadAttribute")
	procDeleteAttributes     = kernel32Runtime.NewProc("DeleteProcThreadAttributeList")
	procCloseHandle          = kernel32Runtime.NewProc("CloseHandle")
)

type runtimeHandle struct{ value uintptr }

type startupInfoEx struct {
	syscall.StartupInfo
	attributeList unsafe.Pointer
}

type runtimeProcess struct {
	pid    int
	handle syscall.Handle
	mu     sync.Mutex
}

func createChildProcessJob() (*runtimeHandle, error) {
	handle, _, callErr := procCreateJob.Call(0, 0)
	if handle == 0 {
		return nil, fmt.Errorf("CreateJobObjectW failed: %w", callErr)
	}
	if err := setKillOnJobClose(handle); err != nil {
		procCloseHandle.Call(handle)
		return nil, err
	}
	return &runtimeHandle{value: handle}, nil
}

func startProcessInJob(path string, arguments []string, output *os.File, job *runtimeHandle) (*runtimeProcess, error) {
	if output == nil || job == nil || job.value == 0 {
		return nil, errors.New("process output and runtime job are required")
	}
	input, err := os.OpenFile(os.DevNull, os.O_RDONLY, 0)
	if err != nil {
		return nil, err
	}
	defer input.Close()
	stdin, err := duplicateInheritableHandle(syscall.Handle(input.Fd()))
	if err != nil {
		return nil, err
	}
	defer syscall.CloseHandle(stdin)
	stdout, err := duplicateInheritableHandle(syscall.Handle(output.Fd()))
	if err != nil {
		return nil, err
	}
	defer syscall.CloseHandle(stdout)

	attributeList, attributeStorage, err := newProcessAttributeList(2)
	if err != nil {
		return nil, err
	}
	defer procDeleteAttributes.Call(uintptr(attributeList))
	handles := []syscall.Handle{stdin, stdout}
	if err := updateProcessAttribute(attributeList, procThreadAttributeHandleList,
		unsafe.Pointer(&handles[0]), uintptr(len(handles))*unsafe.Sizeof(handles[0])); err != nil {
		return nil, err
	}
	jobHandle := job.value
	if err := updateProcessAttribute(attributeList, procThreadAttributeJobList,
		unsafe.Pointer(&jobHandle), unsafe.Sizeof(jobHandle)); err != nil {
		return nil, err
	}

	application, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	commandParts := make([]string, 0, len(arguments)+1)
	commandParts = append(commandParts, syscall.EscapeArg(path))
	for _, argument := range arguments {
		commandParts = append(commandParts, syscall.EscapeArg(argument))
	}
	commandLine, err := syscall.UTF16FromString(strings.Join(commandParts, " "))
	if err != nil {
		return nil, err
	}
	startup := startupInfoEx{attributeList: attributeList}
	startup.Cb = uint32(unsafe.Sizeof(startup))
	startup.Flags = startfUseStdHandles | startfUseShowWindow
	startup.StdInput = stdin
	startup.StdOutput = stdout
	startup.StdErr = stdout
	var processInfo syscall.ProcessInformation
	err = syscall.CreateProcess(application, &commandLine[0], nil, nil, true,
		createNoWindow|createUnicodeEnvironment|extendedStartupInfoPresent,
		nil, nil, &startup.StartupInfo, &processInfo)
	if err != nil {
		return nil, err
	}
	runtime.KeepAlive(attributeStorage)
	runtime.KeepAlive(handles)
	runtime.KeepAlive(jobHandle)
	syscall.CloseHandle(processInfo.Thread)
	_ = attributeStorage
	return &runtimeProcess{pid: int(processInfo.ProcessId), handle: processInfo.Process}, nil
}

func duplicateInheritableHandle(source syscall.Handle) (syscall.Handle, error) {
	current, err := syscall.GetCurrentProcess()
	if err != nil {
		return 0, err
	}
	var duplicate syscall.Handle
	if err := syscall.DuplicateHandle(current, source, current, &duplicate, 0, true, duplicateSameAccess); err != nil {
		return 0, err
	}
	return duplicate, nil
}

func newProcessAttributeList(count uintptr) (unsafe.Pointer, []byte, error) {
	var size uintptr
	procInitializeAttributes.Call(0, count, 0, uintptr(unsafe.Pointer(&size)))
	if size == 0 {
		return nil, nil, errors.New("InitializeProcThreadAttributeList did not report a size")
	}
	storage := make([]byte, size)
	list := unsafe.Pointer(&storage[0])
	initialized, _, callErr := procInitializeAttributes.Call(uintptr(list), count, 0, uintptr(unsafe.Pointer(&size)))
	if initialized == 0 {
		return nil, nil, fmt.Errorf("InitializeProcThreadAttributeList failed: %w", callErr)
	}
	return list, storage, nil
}

func updateProcessAttribute(list unsafe.Pointer, attribute uintptr, value unsafe.Pointer, size uintptr) error {
	updated, _, callErr := procUpdateAttribute.Call(
		uintptr(list), 0, attribute, uintptr(value), size, 0, 0,
	)
	if updated == 0 {
		return fmt.Errorf("UpdateProcThreadAttribute failed: %w", callErr)
	}
	return nil
}

func (p *runtimeProcess) PID() int {
	if p == nil {
		return 0
	}
	return p.pid
}

func (p *runtimeProcess) Kill() error {
	if p == nil {
		return nil
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.handle == 0 {
		return nil
	}
	return syscall.TerminateProcess(p.handle, 1)
}

func (p *runtimeProcess) Wait() error {
	if p == nil {
		return nil
	}
	p.mu.Lock()
	handle := p.handle
	p.mu.Unlock()
	if handle == 0 {
		return nil
	}
	defer func() {
		p.mu.Lock()
		if p.handle == handle {
			syscall.CloseHandle(p.handle)
			p.handle = 0
		}
		p.mu.Unlock()
	}()
	status, err := syscall.WaitForSingleObject(handle, syscall.INFINITE)
	if err != nil || status != syscall.WAIT_OBJECT_0 {
		return fmt.Errorf("wait for process %d failed: status=%d err=%w", p.pid, status, err)
	}
	var exitCode uint32
	if err := syscall.GetExitCodeProcess(handle, &exitCode); err != nil {
		return err
	}
	if exitCode != 0 {
		return fmt.Errorf("process %d exited with code %d", p.pid, exitCode)
	}
	return nil
}

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

func runtimeObjectName(prefix, pipeName string) string {
	hash := sha256.Sum256([]byte(pipeName))
	return fmt.Sprintf("%s%x", prefix, hash[:8])
}
