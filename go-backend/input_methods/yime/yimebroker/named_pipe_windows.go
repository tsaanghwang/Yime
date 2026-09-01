//go:build windows

package yimebroker

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

const (
	pipeAccessDuplex          = 0x00000003
	fileFlagFirstPipeInstance = 0x00080000
	pipeRejectRemoteClients   = 0x00000008
	processQueryLimitedInfo   = 0x00001000
	tokenQuery                = 0x00000008
	securitySQOSPresent       = 0x00100000
	securityIdentification    = 0x00010000
	errorPipeConnected        = syscall.Errno(535)
	sddlRevision1             = 1
)

var (
	kernel32                                   = syscall.NewLazyDLL("kernel32.dll")
	advapi32                                   = syscall.NewLazyDLL("advapi32.dll")
	procCreateNamedPipeW                       = kernel32.NewProc("CreateNamedPipeW")
	procConnectNamedPipe                       = kernel32.NewProc("ConnectNamedPipe")
	procCreateEventW                           = kernel32.NewProc("CreateEventW")
	procGetOverlappedResult                    = kernel32.NewProc("GetOverlappedResult")
	procGetNamedPipeClientProcessID            = kernel32.NewProc("GetNamedPipeClientProcessId")
	procLocalFree                              = kernel32.NewProc("LocalFree")
	procConvertStringSecurityDescriptorToSDDLW = advapi32.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
)

// NamedPipeConfig configures the E6-A Windows transport. Client identity is
// always derived from the connected pipe handle, never from request JSON.
type NamedPipeConfig struct {
	Name                    string
	MaxConnections          int
	MaxConnectionsPerClient int
	OnConnectionError       func(error)
}

// ServeNamedPipe accepts independent byte-stream connections on a local-only,
// current-user pipe and serves the transport-neutral Broker line protocol.
func ServeNamedPipe(ctx context.Context, dispatcher *Dispatcher, config NamedPipeConfig) error {
	if dispatcher == nil {
		return errors.New("dispatcher is required")
	}
	if err := validatePipeConfig(&config); err != nil {
		return err
	}
	security, err := newPipeSecurity()
	if err != nil {
		return fmt.Errorf("create named pipe security: %w", err)
	}
	defer security.close()
	// Keep one unconnected first-instance handle for the server lifetime. The
	// accept loop may briefly have no pending client instance (for example when
	// MaxConnections is one); this anchor prevents a same-user process from
	// claiming the well-known pipe name during that gap.
	instanceLimit := config.MaxConnections + 1
	anchor, anchorClient, err := createPipeAnchor(config.Name, instanceLimit, &security.attributes)
	if err != nil {
		return err
	}
	defer syscall.CloseHandle(anchor)
	defer syscall.CloseHandle(anchorClient)

	limiter := newConnectionLimiter(config.MaxConnections, config.MaxConnectionsPerClient)
	globalSlots := make(chan struct{}, config.MaxConnections)
	var connections sync.WaitGroup
	defer connections.Wait()
	for {
		select {
		case globalSlots <- struct{}{}:
		case <-ctx.Done():
			return nil
		}
		releaseGlobal := func() { <-globalSlots }
		handle, createErr := createPipe(config.Name, instanceLimit, false, &security.attributes)
		if createErr != nil {
			releaseGlobal()
			return createErr
		}
		if connectErr := connectPipe(ctx, handle); connectErr != nil {
			_ = syscall.CloseHandle(handle)
			releaseGlobal()
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("accept named pipe connection: %w", connectErr)
		}
		client, identityErr := trustedClientFromPipe(handle)
		if identityErr != nil {
			_ = syscall.CloseHandle(handle)
			releaseGlobal()
			reportPipeError(config, fmt.Errorf("reject named pipe client: %w", identityErr))
			continue
		}
		release, accepted := limiter.acquire(client.ID)
		if !accepted {
			_ = syscall.CloseHandle(handle)
			releaseGlobal()
			reportPipeError(config, fmt.Errorf("reject named pipe client %q: connection quota exceeded", client.ID))
			continue
		}
		file := os.NewFile(uintptr(handle), config.Name)
		if file == nil {
			release()
			releaseGlobal()
			_ = syscall.CloseHandle(handle)
			return errors.New("wrap named pipe handle")
		}
		connections.Add(1)
		go func(file *os.File, client TrustedClient, release, releaseGlobal func()) {
			defer connections.Done()
			defer release()
			defer releaseGlobal()
			servePipeFile(ctx, file, dispatcher, client, config)
		}(file, client, release, releaseGlobal)
	}
}

func validatePipeConfig(config *NamedPipeConfig) error {
	const prefix = `\\.\pipe\`
	if !strings.HasPrefix(strings.ToLower(config.Name), prefix) {
		return fmt.Errorf("named pipe must use local path %q", prefix)
	}
	leaf := config.Name[len(prefix):]
	if len(leaf) == 0 || len(leaf) > 128 {
		return errors.New("named pipe leaf must contain 1-128 characters")
	}
	for _, character := range leaf {
		if !(character >= 'a' && character <= 'z') && !(character >= 'A' && character <= 'Z') && !(character >= '0' && character <= '9') && character != '.' && character != '_' && character != '-' {
			return errors.New("named pipe leaf may contain only ASCII letters, digits, dot, underscore and hyphen")
		}
	}
	if config.MaxConnections == 0 {
		config.MaxConnections = 64
	}
	if config.MaxConnectionsPerClient == 0 {
		config.MaxConnectionsPerClient = 8
	}
	if config.MaxConnections < 1 || config.MaxConnections > 254 || config.MaxConnectionsPerClient < 1 || config.MaxConnectionsPerClient > config.MaxConnections {
		return errors.New("invalid named pipe connection limits")
	}
	return nil
}

func createPipe(name string, maxInstances int, first bool, security *syscall.SecurityAttributes) (syscall.Handle, error) {
	namePointer, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return syscall.InvalidHandle, err
	}
	openMode := uintptr(pipeAccessDuplex | syscall.FILE_FLAG_OVERLAPPED)
	if first {
		openMode |= fileFlagFirstPipeInstance
	}
	handle, _, callErr := procCreateNamedPipeW.Call(
		uintptr(unsafe.Pointer(namePointer)), openMode, pipeRejectRemoteClients,
		uintptr(maxInstances), MaxMessageBytes+1, MaxMessageBytes+1, 5000,
		uintptr(unsafe.Pointer(security)),
	)
	if syscall.Handle(handle) == syscall.InvalidHandle {
		return syscall.InvalidHandle, fmt.Errorf("create named pipe %q: %w", name, callErr)
	}
	return syscall.Handle(handle), nil
}

func createPipeAnchor(name string, maxInstances int, security *syscall.SecurityAttributes) (syscall.Handle, syscall.Handle, error) {
	server, err := createPipe(name, maxInstances, true, security)
	if err != nil {
		return syscall.InvalidHandle, syscall.InvalidHandle, err
	}
	namePointer, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		syscall.CloseHandle(server)
		return syscall.InvalidHandle, syscall.InvalidHandle, err
	}
	client, err := syscall.CreateFile(
		namePointer,
		syscall.GENERIC_READ|syscall.GENERIC_WRITE,
		0,
		nil,
		syscall.OPEN_EXISTING,
		securitySQOSPresent|securityIdentification,
		0,
	)
	if err != nil {
		syscall.CloseHandle(server)
		return syscall.InvalidHandle, syscall.InvalidHandle, fmt.Errorf("connect named pipe anchor: %w", err)
	}
	return server, client, nil
}

func connectPipe(ctx context.Context, handle syscall.Handle) error {
	event, _, callErr := procCreateEventW.Call(0, 1, 0, 0)
	if event == 0 {
		return fmt.Errorf("create pipe accept event: %w", callErr)
	}
	defer syscall.CloseHandle(syscall.Handle(event))
	overlapped := syscall.Overlapped{HEvent: syscall.Handle(event)}
	connected, _, connectErr := procConnectNamedPipe.Call(uintptr(handle), uintptr(unsafe.Pointer(&overlapped)))
	if connected != 0 || connectErr == errorPipeConnected {
		return nil
	}
	if connectErr != syscall.ERROR_IO_PENDING {
		return connectErr
	}
	for {
		status, waitErr := syscall.WaitForSingleObject(syscall.Handle(event), 50)
		switch status {
		case syscall.WAIT_OBJECT_0:
			var transferred uint32
			ok, _, resultErr := procGetOverlappedResult.Call(uintptr(handle), uintptr(unsafe.Pointer(&overlapped)), uintptr(unsafe.Pointer(&transferred)), 0)
			if ok == 0 {
				return resultErr
			}
			return nil
		case syscall.WAIT_TIMEOUT:
			select {
			case <-ctx.Done():
				cancelAndDrainOverlapped(handle, &overlapped)
				return ctx.Err()
			default:
			}
		case syscall.WAIT_FAILED:
			cancelAndDrainOverlapped(handle, &overlapped)
			return waitErr
		default:
			cancelAndDrainOverlapped(handle, &overlapped)
			return fmt.Errorf("unexpected named pipe accept wait status %d", status)
		}
	}
}

// CancelIoEx is asynchronous. Drain the OVERLAPPED operation before returning
// so the kernel can no longer write to the caller's stack or signal a handle
// that the caller is about to close.
func cancelAndDrainOverlapped(handle syscall.Handle, overlapped *syscall.Overlapped) {
	_ = syscall.CancelIoEx(handle, overlapped)
	var transferred uint32
	_, _, _ = procGetOverlappedResult.Call(
		uintptr(handle),
		uintptr(unsafe.Pointer(overlapped)),
		uintptr(unsafe.Pointer(&transferred)),
		1,
	)
}

func trustedClientFromPipe(handle syscall.Handle) (TrustedClient, error) {
	var processID uint32
	ok, _, callErr := procGetNamedPipeClientProcessID.Call(uintptr(handle), uintptr(unsafe.Pointer(&processID)))
	if ok == 0 || processID == 0 {
		return TrustedClient{}, fmt.Errorf("read client process ID: %w", callErr)
	}
	process, err := syscall.OpenProcess(processQueryLimitedInfo, false, processID)
	if err != nil {
		return TrustedClient{}, fmt.Errorf("open client process %d: %w", processID, err)
	}
	defer syscall.CloseHandle(process)
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, tokenQuery, &token); err != nil {
		return TrustedClient{}, fmt.Errorf("open client token %d: %w", processID, err)
	}
	defer token.Close()
	user, err := token.GetTokenUser()
	if err != nil {
		return TrustedClient{}, fmt.Errorf("read client SID %d: %w", processID, err)
	}
	sid, err := user.User.Sid.String()
	if err != nil {
		return TrustedClient{}, fmt.Errorf("format client SID %d: %w", processID, err)
	}
	return TrustedClient{ID: fmt.Sprintf("windows:%s:pid:%d", sid, processID)}, nil
}

func servePipeFile(ctx context.Context, file *os.File, dispatcher *Dispatcher, client TrustedClient, config NamedPipeConfig) {
	closed := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = file.Close()
		case <-closed:
		}
	}()
	err := ServeLines(ctx, file, file, dispatcher, client)
	close(closed)
	_ = file.Close()
	if err != nil && ctx.Err() == nil && !errors.Is(err, syscall.ERROR_BROKEN_PIPE) {
		reportPipeError(config, err)
	}
}

func reportPipeError(config NamedPipeConfig, err error) {
	if config.OnConnectionError != nil {
		config.OnConnectionError(err)
	}
}

type pipeSecurity struct {
	descriptor uintptr
	attributes syscall.SecurityAttributes
}

func newPipeSecurity() (*pipeSecurity, error) {
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		return nil, err
	}
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, tokenQuery, &token); err != nil {
		return nil, err
	}
	defer token.Close()
	user, err := token.GetTokenUser()
	if err != nil {
		return nil, err
	}
	sid, err := user.User.Sid.String()
	if err != nil {
		return nil, err
	}
	sddl := fmt.Sprintf("D:P(D;;GA;;;NU)(A;;GA;;;SY)(A;;GA;;;%s)", sid)
	sddlPointer, err := syscall.UTF16PtrFromString(sddl)
	if err != nil {
		return nil, err
	}
	var descriptor uintptr
	ok, _, callErr := procConvertStringSecurityDescriptorToSDDLW.Call(
		uintptr(unsafe.Pointer(sddlPointer)), sddlRevision1, uintptr(unsafe.Pointer(&descriptor)), 0,
	)
	if ok == 0 {
		return nil, callErr
	}
	security := &pipeSecurity{descriptor: descriptor}
	security.attributes = syscall.SecurityAttributes{
		Length: uint32(unsafe.Sizeof(syscall.SecurityAttributes{})), SecurityDescriptor: descriptor,
	}
	return security, nil
}

func (s *pipeSecurity) close() {
	if s.descriptor != 0 {
		_, _, _ = procLocalFree.Call(s.descriptor)
		s.descriptor = 0
	}
}
