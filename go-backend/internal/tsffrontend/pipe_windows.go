//go:build windows && amd64

package tsffrontend

import (
	"bytes"
	"errors"
	"fmt"
	"sync"
	"syscall"
	"unsafe"
)

var kernel = syscall.NewLazyDLL("kernel32.dll")
var eventCreate = kernel.NewProc("CreateEventW")
var overlappedResult = kernel.NewProc("GetOverlappedResult")
var cancelIO = kernel.NewProc("CancelIoEx")
var serverPID = kernel.NewProc("GetNamedPipeServerProcessId")

type pipeTransport struct {
	mu     sync.Mutex
	handle syscall.Handle
	closed bool
}

func Dial(pid, thread uint32, window uint64) (*Client, error) {
	var processMachine, nativeMachine uint16
	current, _ := syscall.GetCurrentProcess()
	valid, _, _ := kernel.NewProc("IsWow64Process2").Call(uintptr(current), uintptr(unsafe.Pointer(&processMachine)), uintptr(unsafe.Pointer(&nativeMachine)))
	if valid == 0 || processMachine != 0 || nativeMachine != 0x8664 {
		return nil, errors.New("requires native x64 Windows")
	}
	if pid == 0 || thread == 0 {
		return nil, errors.New("missing target process/thread")
	}
	name, _ := syscall.UTF16PtrFromString(fmt.Sprintf(`\\.\pipe\Yime18u.Frontend.v1.%d.%d`, pid, thread))
	h, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OVERLAPPED|0x00100000|0x00010000, 0)
	if err != nil {
		return nil, fmt.Errorf("active 18u TSF endpoint unavailable; select matching input profile: %w", err)
	}
	var actual uint32
	ok, _, _ := serverPID.Call(uintptr(h), uintptr(unsafe.Pointer(&actual)))
	if ok == 0 || actual != pid {
		syscall.CloseHandle(h)
		return nil, errors.New("TSF server process mismatch")
	}
	return Bind(&pipeTransport{handle: h}, window)
}
func (p *pipeTransport) transfer(buffer []byte, write bool) (uint32, error) {
	event, _, err := eventCreate.Call(0, 1, 0, 0)
	if event == 0 {
		return 0, err
	}
	defer syscall.CloseHandle(syscall.Handle(event))
	operation := syscall.Overlapped{HEvent: syscall.Handle(event)}
	var n uint32
	if write {
		err = syscall.WriteFile(p.handle, buffer, &n, &operation)
	} else {
		err = syscall.ReadFile(p.handle, buffer, &n, &operation)
	}
	if err != nil && err != syscall.ERROR_IO_PENDING {
		return 0, err
	}
	if err == syscall.ERROR_IO_PENDING {
		status, e := syscall.WaitForSingleObject(operation.HEvent, 5000)
		if e != nil || status != syscall.WAIT_OBJECT_0 {
			cancelIO.Call(uintptr(p.handle), uintptr(unsafe.Pointer(&operation)))
			overlappedResult.Call(uintptr(p.handle), uintptr(unsafe.Pointer(&operation)), uintptr(unsafe.Pointer(&n)), 1)
			return 0, errors.New("TSF pipe timeout; outcome unknown")
		}
		ok, _, e := overlappedResult.Call(uintptr(p.handle), uintptr(unsafe.Pointer(&operation)), uintptr(unsafe.Pointer(&n)), 0)
		if ok == 0 {
			return 0, e
		}
	}
	return n, nil
}
func (p *pipeTransport) Exchange(request []byte) ([]byte, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		return nil, errors.New("TSF pipe closed")
	}
	n, err := p.transfer(request, true)
	if err != nil {
		return nil, err
	}
	if int(n) != len(request) {
		return nil, errors.New("partial TSF request; no replay")
	}
	var response []byte
	for len(response) < 4096 {
		buffer := make([]byte, 4096-len(response))
		n, err = p.transfer(buffer, false)
		if err != nil {
			return nil, err
		}
		if n == 0 {
			return nil, errors.New("TSF disconnected")
		}
		response = append(response, buffer[:n]...)
		if i := bytes.IndexByte(response, '\n'); i >= 0 {
			if i != len(response)-1 {
				return nil, errors.New("extra TSF output")
			}
			return response[:i], nil
		}
	}
	return nil, errors.New("TSF response frame limit")
}
func (p *pipeTransport) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		return nil
	}
	p.closed = true
	return syscall.CloseHandle(p.handle)
}
