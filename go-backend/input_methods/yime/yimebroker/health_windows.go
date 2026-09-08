//go:build windows

package yimebroker

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var procHealthPeekNamedPipe = kernel32.NewProc("PeekNamedPipe")

// HealthServer owns an independent endpoint, anchor and two connection slots.
// It never opens a Dispatcher session or consumes the ordinary pipe's quota.
type HealthServer struct {
	cancel context.CancelFunc
	done   chan struct{}
	err    error // published by closing done; read only after that close
}

func StartHealthServer(ctx context.Context, config HealthConfig) (*HealthServer, error) {
	if ctx == nil {
		return nil, errors.New("health server context is required")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	name, err := HealthPipeName(config.Name, config.Role)
	if err != nil {
		return nil, err
	}
	if config.Snapshot == nil {
		return nil, errors.New("health snapshot callback is required")
	}
	pid, creation, sid, err := healthCurrentIdentity()
	if err != nil {
		return nil, err
	}
	security, err := newPipeSecurity()
	if err != nil {
		return nil, fmt.Errorf("create health pipe security: %w", err)
	}
	anchor, anchorClient, err := createPipeAnchor(name, healthConnections+1, &security.attributes)
	if err != nil {
		security.close()
		return nil, err
	}
	serverCtx, cancel := context.WithCancel(ctx)
	server := &HealthServer{cancel: cancel, done: make(chan struct{})}
	go func() {
		defer close(server.done)
		defer security.close()
		defer syscall.CloseHandle(anchor)
		defer syscall.CloseHandle(anchorClient)
		server.err = server.serve(serverCtx, name, config, security, pid, creation, sid)
	}()
	return server, nil
}

// Close cancels accepts and all connection I/O, then waits for every worker.
// Concurrent and repeated calls are safe. Snapshot's prompt-return contract
// applies during shutdown as well; there is no detached callback goroutine.
func (s *HealthServer) Close() error {
	if s == nil {
		return nil
	}
	s.cancel()
	<-s.done
	return s.err
}

func (s *HealthServer) serve(ctx context.Context, name string, config HealthConfig, security *pipeSecurity, pid uint32, creation uint64, sid string) error {
	slots := make(chan struct{}, healthConnections)
	var workers sync.WaitGroup
	// Unexpected accept failures must cancel existing workers before draining.
	defer workers.Wait()
	defer s.cancel()
	for {
		select {
		case <-ctx.Done():
			return nil
		case slots <- struct{}{}:
		}
		handle, err := createPipe(name, healthConnections+1, false, &security.attributes)
		if err != nil {
			<-slots
			return err
		}
		if err := connectPipe(ctx, handle); err != nil {
			_ = syscall.CloseHandle(handle)
			<-slots
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("accept health pipe: %w", err)
		}
		deadline := time.Now().Add(healthIOBudget)
		client, err := trustedClientFromPipe(handle)
		if err != nil || !healthClientSameSID(client, sid) {
			_ = syscall.CloseHandle(handle)
			<-slots
			continue
		}
		file := os.NewFile(uintptr(handle), name)
		if file == nil {
			_ = syscall.CloseHandle(handle)
			<-slots
			return errors.New("wrap health pipe handle")
		}
		workers.Add(1)
		go func() {
			defer workers.Done()
			defer func() { <-slots }()
			serveHealthFile(ctx, file, config, pid, creation, deadline)
		}()
	}
}

func healthClientSameSID(client TrustedClient, sid string) bool {
	prefix := "windows:" + sid + ":pid:"
	if sid == "" || !strings.HasPrefix(client.ID, prefix) {
		return false
	}
	pid, err := strconv.ParseUint(strings.TrimPrefix(client.ID, prefix), 10, 32)
	return err == nil && pid != 0
}

func healthCurrentIdentity() (uint32, uint64, string, error) {
	process, err := syscall.GetCurrentProcess()
	if err != nil {
		return 0, 0, "", err
	}
	var created, exited, kernel, userTime syscall.Filetime
	if err := syscall.GetProcessTimes(process, &created, &exited, &kernel, &userTime); err != nil {
		return 0, 0, "", fmt.Errorf("read health server creation time: %w", err)
	}
	var token syscall.Token
	if err := syscall.OpenProcessToken(process, tokenQuery, &token); err != nil {
		return 0, 0, "", err
	}
	defer token.Close()
	user, err := token.GetTokenUser()
	if err != nil {
		return 0, 0, "", err
	}
	sid, err := user.User.Sid.String()
	if err != nil {
		return 0, 0, "", err
	}
	pid := uint32(os.Getpid())
	creation := uint64(created.HighDateTime)<<32 | uint64(created.LowDateTime)
	if pid == 0 || creation == 0 || sid == "" {
		return 0, 0, "", errors.New("health server identity is incomplete")
	}
	return pid, creation, sid, nil
}

func serveHealthFile(ctx context.Context, file *os.File, config HealthConfig, pid uint32, creation uint64, deadline time.Time) {
	stopped := make(chan struct{})
	watcherDone := make(chan struct{})
	go func() {
		defer close(watcherDone)
		select {
		case <-ctx.Done():
			_ = file.Close()
		case <-stopped:
		}
	}()
	defer func() {
		close(stopped)
		_ = file.Close()
		<-watcherDone
		// A faulty memory callback must not take down the owning process.
		_ = recover()
	}()
	if err := file.SetDeadline(deadline); err != nil {
		return
	}
	var request [healthRequestSize]byte
	if _, err := io.ReadFull(file, request[:]); err != nil {
		return
	}
	nonce, err := decodeHealthRequest(request[:], config.Role)
	if err != nil || ctx.Err() != nil || !time.Now().Before(deadline) {
		return
	}
	if ok := healthNoBufferedInput(file); !ok {
		return
	}
	snapshot := config.Snapshot()
	response, err := encodeHealthResponse(config.Role, nonce, snapshot, pid, creation)
	if err != nil || ctx.Err() != nil || !time.Now().Before(deadline) || !healthNoBufferedInput(file) {
		return
	}
	// One frame per connection. Byte pipes have no request half-close: this
	// rejects already buffered excess bytes, not arbitrary future input. Any
	// late bytes are discarded when the single response connection is closed.
	_, _ = file.Write(response[:])
}

func healthNoBufferedInput(file *os.File) bool {
	raw, err := file.SyscallConn()
	if err != nil {
		return false
	}
	clear := false
	// Control retains the handle against the concurrent cancellation Close.
	err = raw.Control(func(handle uintptr) {
		var available uint32
		ok, _, _ := procHealthPeekNamedPipe.Call(handle, 0, 0, 0, uintptr(unsafe.Pointer(&available)), 0)
		clear = ok != 0 && available == 0
	})
	return err == nil && clear
}
