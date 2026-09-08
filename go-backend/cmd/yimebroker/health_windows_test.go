//go:build windows

package main

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/engineapi"
	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
)

func openHealthWiringPipe(t *testing.T, name string) *os.File {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		file, err := os.OpenFile(name, os.O_RDWR, 0)
		if err == nil {
			return file
		}
		if time.Now().After(deadline) {
			t.Fatalf("open owned test pipe %s: %v", name, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestBrokerHealthWiringDoesNotSpendInputQuotaOrOpenEngine(t *testing.T) {
	base := fmt.Sprintf(`\\.\pipe\YimeBroker-health-wiring-%d`, os.Getpid())
	var factories atomic.Int32
	dispatcher, err := yimebroker.NewDispatcher(func() (engineapi.Engine, error) {
		factories.Add(1)
		return nil, fmt.Errorf("health must not open an engine")
	}, yimebroker.Config{MaxSessions: 1, MaxSessionsPerClient: 1})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- serveBrokerPipe(ctx, dispatcher, yimebroker.NamedPipeConfig{Name: base, MaxConnections: 1, MaxConnectionsPerClient: 1}, base+".health-v1")
	}()
	ordinary := openHealthWiringPipe(t, base)
	defer ordinary.Close()
	// The only input connection slot is occupied for the entire health exchange.
	for n := 1; n <= 2; n++ {
		probe := openHealthWiringPipe(t, base+".health-v1")
		request := make([]byte, 48)
		copy(request, "YIMEH01\x00")
		binary.LittleEndian.PutUint32(request[8:], 1)
		request[16] = byte(n)
		if _, err := probe.Write(request); err != nil {
			probe.Close()
			t.Fatal(err)
		}
		response, err := io.ReadAll(io.LimitReader(probe, 81))
		probe.Close()
		if err != nil || len(response) != 80 || string(response[:8]) != "YIMER01\x00" || binary.LittleEndian.Uint32(response[12:]) != 1 || response[16] != byte(n) {
			t.Fatalf("health wiring did not report bound listener: response=%x err=%v", response, err)
		}
	}
	if factories.Load() != 0 {
		t.Fatal("health entered the input engine factory")
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("listener/health shutdown did not drain an idle owned input connection")
	}
	if file, err := os.OpenFile(base+".health-v1", os.O_RDWR, 0); err == nil {
		file.Close()
		t.Fatal("health outlived the input listener")
	}
}

func TestBrokerHealthPreclaimPreventsMainListenerStart(t *testing.T) {
	base := fmt.Sprintf(`\\.\pipe\YimeBroker-health-preclaim-wiring-%d`, os.Getpid())
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	owner, err := yimebroker.StartHealthServer(ctx, yimebroker.HealthConfig{Name: base, Role: yimebroker.HealthRoleBroker, Snapshot: func() yimebroker.HealthSnapshot {
		return yimebroker.HealthSnapshot{State: yimebroker.HealthStateStarting}
	}})
	if err != nil {
		t.Fatal(err)
	}
	defer owner.Close()
	dispatcher, _ := yimebroker.NewDispatcher(func() (engineapi.Engine, error) { return nil, nil }, yimebroker.Config{})
	if err := serveBrokerPipe(ctx, dispatcher, yimebroker.NamedPipeConfig{Name: base}, base+".health-v1"); err == nil {
		t.Fatal("health preclaim was ignored")
	}
	if file, err := os.OpenFile(base, os.O_RDWR, 0); err == nil {
		file.Close()
		t.Fatal("ordinary listener started after health preclaim")
	}
}
