//go:build windows

package yimebroker

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"
)

func TestServeNamedPipeHandlesConcurrentConnectionsAndRejectsIdentityFields(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	pipeName := fmt.Sprintf(`\\.\pipe\YimeBroker-test-%d`, os.Getpid())
	ctx, cancel := context.WithCancel(context.Background())
	serverDone := make(chan error, 1)
	go func() {
		serverDone <- ServeNamedPipe(ctx, dispatcher, NamedPipeConfig{
			Name: pipeName, MaxConnections: 4, MaxConnectionsPerClient: 4,
		})
	}()

	first := openTestPipe(t, pipeName)
	defer first.Close()
	second := openTestPipe(t, pipeName)
	defer second.Close()
	firstResponse := exchangePipeRequest(t, first, `{"version":1,"sequence":1,"operation":"open"}`)
	secondResponse := exchangePipeRequest(t, second, `{"version":1,"sequence":1,"operation":"open"}`)
	if firstResponse.Error != nil || secondResponse.Error != nil || firstResponse.SessionID == "" || secondResponse.SessionID == "" || firstResponse.SessionID == secondResponse.SessionID {
		t.Fatalf("unexpected open responses: first=%+v second=%+v", firstResponse, secondResponse)
	}
	spoofed := exchangePipeRequest(t, first, `{"version":1,"sequence":2,"session_id":"`+firstResponse.SessionID+`","operation":"reset","client_id":"spoofed"}`)
	if spoofed.Error == nil || spoofed.Error.Code != CodeInvalidRequest {
		t.Fatalf("request identity field was not rejected: %+v", spoofed)
	}

	_ = first.Close()
	_ = second.Close()
	cancel()
	select {
	case err := <-serverDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("named pipe server did not stop after context cancellation")
	}
}

func TestValidateNamedPipeRejectsRemoteAndUnboundedNames(t *testing.T) {
	for _, name := range []string{`\\server\pipe\YimeBroker`, `\\.\pipe\`, `\\.\pipe\YimeBroker\nested`, `\\.\pipe\Yime Broker`} {
		config := NamedPipeConfig{Name: name}
		if err := validatePipeConfig(&config); err == nil {
			t.Fatalf("invalid pipe name accepted: %q", name)
		}
	}
}

func TestServeNamedPipeWaitsAtGlobalConnectionLimit(t *testing.T) {
	dispatcher := newMemoryDispatcher(t, Config{})
	pipeName := fmt.Sprintf(`\\.\pipe\YimeBroker-limit-test-%d`, os.Getpid())
	ctx, cancel := context.WithCancel(context.Background())
	serverDone := make(chan error, 1)
	go func() {
		serverDone <- ServeNamedPipe(ctx, dispatcher, NamedPipeConfig{
			Name: pipeName, MaxConnections: 2, MaxConnectionsPerClient: 2,
		})
	}()
	first := openTestPipe(t, pipeName)
	second := openTestPipe(t, pipeName)
	thirdResult := make(chan *os.File, 1)
	thirdError := make(chan error, 1)
	go func() {
		file, err := openPipeUntil(pipeName, time.Now().Add(3*time.Second))
		if err != nil {
			thirdError <- err
			return
		}
		thirdResult <- file
	}()
	select {
	case err := <-serverDone:
		t.Fatalf("server exited at connection limit: %v", err)
	case file := <-thirdResult:
		_ = file.Close()
		t.Fatal("third connection bypassed global limit")
	case err := <-thirdError:
		t.Fatal(err)
	case <-time.After(100 * time.Millisecond):
	}
	_ = first.Close()
	var third *os.File
	select {
	case third = <-thirdResult:
	case err := <-thirdError:
		t.Fatal(err)
	case <-time.After(3 * time.Second):
		t.Fatal("released global connection slot was not reused")
	}
	response := exchangePipeRequest(t, third, `{"version":1,"sequence":1,"operation":"open"}`)
	if response.Error != nil {
		t.Fatalf("third connection failed after slot release: %+v", response)
	}
	_ = third.Close()
	_ = second.Close()
	cancel()
	select {
	case err := <-serverDone:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("limited named pipe server did not stop")
	}
}

func openTestPipe(t *testing.T, name string) *os.File {
	t.Helper()
	file, err := openPipeUntil(name, time.Now().Add(3*time.Second))
	if err != nil {
		t.Fatalf("open named pipe: %v", err)
	}
	return file
}

func openPipeUntil(name string, deadline time.Time) (*os.File, error) {
	for {
		file, err := os.OpenFile(name, os.O_RDWR, 0)
		if err == nil {
			return file, nil
		}
		if time.Now().After(deadline) {
			return nil, err
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func exchangePipeRequest(t *testing.T, file *os.File, request string) Response {
	t.Helper()
	if _, err := fmt.Fprintln(file, request); err != nil {
		t.Fatal(err)
	}
	line, err := bufio.NewReader(file).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	var response Response
	if err := json.Unmarshal([]byte(strings.TrimSpace(line)), &response); err != nil {
		t.Fatal(err)
	}
	return response
}
