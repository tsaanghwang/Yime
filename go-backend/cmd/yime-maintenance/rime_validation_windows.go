//go:build windows

package main

import (
	"errors"
	"syscall"
	"unsafe"
)

func processStarted(process syscall.Handle) (uint64, error) {
	var created, exited, kernelTime, userTime syscall.Filetime
	if err := syscall.GetProcessTimes(process, &created, &exited, &kernelTime, &userTime); err != nil {
		return 0, err
	}
	return uint64(created.HighDateTime)<<32 | uint64(created.LowDateTime), nil
}

func requireLiveProcess(process syscall.Handle) error {
	state, err := syscall.WaitForSingleObject(process, 0)
	if err != nil {
		return err
	}
	if state != syscall.WAIT_TIMEOUT {
		return errors.New("ordinary installation caller is no longer running")
	}
	return nil
}

func holdOrdinaryCaller(pid uint, started uint64, sid, image string) (syscall.Handle, error) {
	if pid == 0 || uint64(pid) > uint64(^uint32(0)) || started == 0 {
		return 0, errors.New("incomplete ordinary caller binding")
	}
	process, err := syscall.OpenProcess(0x1000|syscall.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return 0, err
	}
	keep := false
	defer func() {
		if !keep {
			syscall.CloseHandle(process)
		}
	}()
	if err = requireLiveProcess(process); err != nil {
		return 0, err
	}
	actual := ordinaryCallerIdentity{}
	if actual.started, err = processStarted(process); err != nil {
		return 0, err
	}
	if actual.sid, actual.elevated, err = processIdentity(process); err != nil {
		return 0, err
	}
	buffer := make([]uint16, 32768)
	size := uint32(len(buffer))
	ok, _, err := kernel.NewProc("QueryFullProcessImageNameW").Call(uintptr(process), 0, uintptr(unsafe.Pointer(&buffer[0])), uintptr(unsafe.Pointer(&size)))
	if ok == 0 {
		return 0, err
	}
	actual.image = syscall.UTF16ToString(buffer[:size])
	// ShellExecuteEx elevates the same package executable. The elevated helper
	// stays there while its child PowerShell executes from the protected stage.
	// That executable and its ancestors are already held by maintain().
	if err = validateOrdinaryCaller(actual, started, sid, image); err != nil {
		return 0, err
	}
	keep = true
	return process, nil
}
