//go:build windows

package yimebroker

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

var healthFixtureSequence atomic.Uint64

func healthFixtureBase() string {
	return fmt.Sprintf(`\\.\pipe\YimeBroker-health-test-%d-%d`, os.Getpid(), healthFixtureSequence.Add(1))
}

func startHealthFixture(t *testing.T, role HealthRole, snapshot func() HealthSnapshot) (string, *HealthServer) {
	t.Helper()
	base := healthFixtureBase()
	server, err := StartHealthServer(context.Background(), HealthConfig{Name: base, Role: role, Snapshot: snapshot})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := server.Close(); err != nil {
			t.Error(err)
		}
	})
	name, err := HealthPipeName(base, role)
	if err != nil {
		t.Fatal(err)
	}
	return name, server
}

func healthOpenUntil(name string, until time.Time) (*os.File, error) {
	ptr, err := syscall.UTF16PtrFromString(name)
	if err != nil {
		return nil, err
	}
	for {
		handle, err := syscall.CreateFile(ptr, syscall.GENERIC_READ|syscall.GENERIC_WRITE, 0, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_OVERLAPPED|securitySQOSPresent|securityIdentification, 0)
		if err == nil {
			file := os.NewFile(uintptr(handle), name)
			if err := file.SetDeadline(time.Now().Add(4 * time.Second)); err != nil {
				file.Close()
				return nil, err
			}
			return file, nil
		}
		if time.Now().After(until) {
			return nil, err
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func healthOpen(t *testing.T, name string) *os.File {
	t.Helper()
	file, err := healthOpenUntil(name, time.Now().Add(3*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = file.Close() })
	return file
}

func healthReadToClose(t *testing.T, file *os.File) []byte {
	t.Helper()
	got, err := io.ReadAll(io.LimitReader(file, healthResponseSize+1))
	if err != nil {
		t.Fatalf("read health reply/EOF: %v (%d bytes)", err, len(got))
	}
	return got
}

func healthExchange(t *testing.T, name string, request []byte) []byte {
	t.Helper()
	file := healthOpen(t, name)
	if _, err := file.Write(request); err != nil {
		t.Fatal(err)
	}
	got := healthReadToClose(t, file)
	_ = file.Close()
	return got
}

func TestHealthNativeNonceIdentityAndStates(t *testing.T) {
	pid, creation, _, err := healthCurrentIdentity()
	if err != nil {
		t.Fatal(err)
	}
	for _, role := range []HealthRole{HealthRoleBroker, HealthRoleRuntime} {
		for _, state := range []HealthState{HealthStateServing, HealthStateStarting, HealthStateStopping} {
			t.Run(fmt.Sprintf("role%d-state%d", role, state), func(t *testing.T) {
				snapshot := HealthSnapshot{State: state}
				if role == HealthRoleRuntime && state == HealthStateServing {
					snapshot.BrokerPID = pid
					snapshot.BrokerCreationFiletime = creation
				}
				name, _ := startHealthFixture(t, role, func() HealthSnapshot { return snapshot })
				for _, seed := range []byte{1, 117} {
					request := healthTestRequest(role, seed)
					got := healthExchange(t, name, request)
					nonce, err := decodeHealthRequest(request, role)
					if err != nil {
						t.Fatal(err)
					}
					want, err := encodeHealthResponse(role, nonce, snapshot, pid, creation)
					if err != nil || string(got) != string(want[:]) {
						t.Fatalf("nonce/native identity/state mismatch %x %v", got, err)
					}
				}
			})
		}
	}
}

func TestHealthNativeRejectsMalformedAndInvalidSnapshot(t *testing.T) {
	var calls atomic.Int32
	name, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot { calls.Add(1); return HealthSnapshot{State: HealthStateServing} })
	valid := healthTestRequest(HealthRoleBroker, 2)
	invalid := [][]byte{healthTestRequest(HealthRoleRuntime, 2), append(append([]byte{}, valid...), valid...)}
	for _, index := range []int{0, 7, 12, 15} {
		frame := append([]byte{}, valid...)
		frame[index] ^= 1
		invalid = append(invalid, frame)
	}
	zero := append([]byte{}, valid...)
	clear(zero[16:])
	invalid = append(invalid, zero)
	for index, request := range invalid {
		if got := healthExchange(t, name, request); len(got) != 0 {
			t.Fatalf("invalid request %d replied %x", index, got)
		}
	}
	if calls.Load() != 0 {
		t.Fatal("malformed request reached memory callback")
	}
	for _, snapshot := range []HealthSnapshot{{State: 0}, {State: 4}, {State: 1, BrokerPID: 9}, {State: 1, BrokerCreationFiletime: 8}, {State: 1, BrokerPID: 9, BrokerCreationFiletime: 8}} {
		badName, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot { return snapshot })
		if got := healthExchange(t, badName, valid); len(got) != 0 {
			t.Fatal("invalid Broker snapshot produced response")
		}
	}
	badName, _ := startHealthFixture(t, HealthRoleRuntime, func() HealthSnapshot { return HealthSnapshot{State: HealthStateServing} })
	if got := healthExchange(t, badName, healthTestRequest(HealthRoleRuntime, 2)); len(got) != 0 {
		t.Fatal("serving Runtime with no child responded")
	}
	panicName, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot { panic("fixture") })
	if got := healthExchange(t, panicName, valid); len(got) != 0 {
		t.Fatal("panicking callback responded")
	}
}

func TestHealthNativeTotalBudgetAndSlotRecovery(t *testing.T) {
	name, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot { return HealthSnapshot{State: HealthStateServing} })
	first := healthOpen(t, name)
	second := healthOpen(t, name)
	started := time.Now()
	if third, err := healthOpenUntil(name, time.Now().Add(100*time.Millisecond)); err == nil {
		third.Close()
		t.Fatal("third connection bypassed independent two-slot cap")
	}
	if _, err := first.Write(healthTestRequest(HealthRoleBroker, 1)[:19]); err != nil {
		t.Fatal(err)
	}
	if got := healthReadToClose(t, first); len(got) != 0 {
		t.Fatal("short request replied")
	}
	if got := healthReadToClose(t, second); len(got) != 0 {
		t.Fatal("idle connection replied")
	}
	if elapsed := time.Since(started); elapsed < 800*time.Millisecond || elapsed > 2300*time.Millisecond {
		t.Fatalf("unexpected shared read budget: %s", elapsed)
	}
	if got := healthExchange(t, name, healthTestRequest(HealthRoleBroker, 5)); len(got) != healthResponseSize {
		t.Fatal("timed-out slots not reclaimed")
	}

	// Delayed first-half input and synchronous callback share one original
	// deadline. Resetting the deadline for either phase would wrongly reply.
	budgetName, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot {
		time.Sleep(600 * time.Millisecond)
		return HealthSnapshot{State: HealthStateServing}
	})
	file := healthOpen(t, budgetName)
	request := healthTestRequest(HealthRoleBroker, 8)
	if _, err := file.Write(request[:24]); err != nil {
		t.Fatal(err)
	}
	time.Sleep(600 * time.Millisecond)
	if _, err := file.Write(request[24:]); err != nil {
		t.Fatal(err)
	}
	if got := healthReadToClose(t, file); len(got) != 0 {
		t.Fatal("response escaped original total I/O deadline")
	}
}

func TestHealthNativeSingleFrameAndCallbackDrain(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	var calls atomic.Int32
	name, server := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot {
		calls.Add(1)
		once.Do(func() { close(entered) })
		<-release
		return HealthSnapshot{State: HealthStateServing}
	})
	file := healthOpen(t, name)
	if _, err := file.Write(healthTestRequest(HealthRoleBroker, 4)); err != nil {
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		close(release)
		t.Fatal("callback not reached")
	}
	// A second frame arriving while the callback runs is rejected and cannot
	// become another dispatch. Close also waits for the synchronous callback.
	if _, err := file.Write(healthTestRequest(HealthRoleBroker, 9)); err != nil {
		close(release)
		t.Fatal(err)
	}
	closed := make(chan error, 1)
	go func() { closed <- server.Close() }()
	select {
	case <-closed:
		close(release)
		t.Fatal("Close abandoned callback")
	case <-time.After(50 * time.Millisecond):
	}
	close(release)
	select {
	case err := <-closed:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("Close failed to drain callback")
	}
	if got := healthReadToClose(t, file); len(got) != 0 {
		t.Fatal("cancelled/extra request replied")
	}
	if calls.Load() != 1 {
		t.Fatalf("processed %d frames", calls.Load())
	}

	plainName, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot { return HealthSnapshot{State: HealthStateServing} })
	plain := healthOpen(t, plainName)
	if _, err := plain.Write(healthTestRequest(HealthRoleBroker, 5)); err != nil {
		t.Fatal(err)
	}
	var response [healthResponseSize]byte
	if _, err := io.ReadFull(plain, response[:]); err != nil {
		t.Fatal(err)
	}
	_, _ = plain.Write(healthTestRequest(HealthRoleBroker, 6))
	if got := healthReadToClose(t, plain); len(got) != 0 {
		t.Fatal("late frame produced second reply")
	}
}

func TestHealthNativeBufferedLateFrameRejectedWithoutCancellation(t *testing.T) {
	entered := make(chan struct{})
	release := make(chan struct{})
	var calls atomic.Int32
	name, _ := startHealthFixture(t, HealthRoleBroker, func() HealthSnapshot {
		calls.Add(1)
		close(entered)
		<-release
		return HealthSnapshot{State: HealthStateServing}
	})
	file := healthOpen(t, name)
	if _, err := file.Write(healthTestRequest(HealthRoleBroker, 11)); err != nil {
		close(release)
		t.Fatal(err)
	}
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		close(release)
		t.Fatal("callback did not start")
	}
	if _, err := file.Write([]byte{1}); err != nil {
		close(release)
		t.Fatal(err)
	}
	close(release)
	if got := healthReadToClose(t, file); len(got) != 0 {
		t.Fatal("buffered trailing byte accepted after callback")
	}
	if calls.Load() != 1 {
		t.Fatal("late input reached an additional callback")
	}
}

func TestHealthNativePreclaimAnchorCancel(t *testing.T) {
	base := healthFixtureBase()
	name, _ := HealthPipeName(base, HealthRoleBroker)
	security, err := newPipeSecurity()
	if err != nil {
		t.Fatal(err)
	}
	defer security.close()
	claim, err := createPipe(name, 3, true, &security.attributes)
	if err != nil {
		t.Fatal(err)
	}
	config := HealthConfig{Name: base, Role: HealthRoleBroker, Snapshot: func() HealthSnapshot { return HealthSnapshot{State: HealthStateServing} }}
	if server, err := StartHealthServer(context.Background(), config); err == nil {
		server.Close()
		syscall.CloseHandle(claim)
		t.Fatal("preclaimed health endpoint accepted")
	}
	_ = syscall.CloseHandle(claim)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	server, err := StartHealthServer(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	first := healthOpen(t, name)
	second := healthOpen(t, name)
	if claim, err := createPipe(name, 3, true, &security.attributes); err == nil {
		syscall.CloseHandle(claim)
		t.Fatal("saturated service lost first-instance anchor")
	}
	start := time.Now()
	cancel()
	if err := server.Close(); err != nil {
		t.Fatal(err)
	}
	if time.Since(start) > time.Second {
		t.Fatal("cancellation did not close active I/O")
	}
	for _, file := range []*os.File{first, second} {
		if got := healthReadToClose(t, file); len(got) != 0 {
			t.Fatal("idle cancelled client replied")
		}
		file.Close()
	}
	if err := server.Close(); err != nil {
		t.Fatal(err)
	}
	if claim, err := createPipe(name, 3, true, &security.attributes); err != nil {
		t.Fatalf("closed server retained anchor: %v", err)
	} else {
		syscall.CloseHandle(claim)
	}
}

func TestHealthNativeSeparateOrdinaryQuota(t *testing.T) {
	base := healthFixtureBase()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	dispatcher := newMemoryDispatcher(t, Config{})
	go func() {
		done <- ServeNamedPipe(ctx, dispatcher, NamedPipeConfig{Name: base, MaxConnections: 1, MaxConnectionsPerClient: 1})
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Error(err)
			}
		case <-time.After(3 * time.Second):
			t.Error("ordinary fixture did not close")
		}
	})
	ordinary := openTestPipe(t, base)
	defer ordinary.Close()
	server, err := StartHealthServer(ctx, HealthConfig{Name: base, Role: HealthRoleBroker, Snapshot: func() HealthSnapshot { return HealthSnapshot{State: HealthStateServing} }})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	name, _ := HealthPipeName(base, HealthRoleBroker)
	if got := healthExchange(t, name, healthTestRequest(HealthRoleBroker, 1)); len(got) != healthResponseSize {
		t.Fatal("ordinary quota blocked health exchange")
	}
	first := healthOpen(t, name)
	defer first.Close()
	second := healthOpen(t, name)
	defer second.Close()
	response := exchangePipeRequest(t, ordinary, `{"version":1,"sequence":1,"operation":"open"}`)
	if response.Error != nil || response.SessionID == "" {
		t.Fatal("health slots affected ordinary Dispatcher")
	}
	_ = first.Close()
	_ = second.Close()
	response = exchangePipeRequest(t, ordinary, `{"version":1,"sequence":2,"session_id":"`+response.SessionID+`","operation":"reset"}`)
	if response.Error != nil {
		t.Fatal("health cleanup destroyed ordinary session")
	}
}

func TestHealthStartAndSIDValidation(t *testing.T) {
	config := HealthConfig{Name: healthFixtureBase(), Role: HealthRoleBroker, Snapshot: func() HealthSnapshot { return HealthSnapshot{State: 1} }}
	if _, err := StartHealthServer(nil, config); err == nil {
		t.Fatal("nil context accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := StartHealthServer(ctx, config); err == nil {
		t.Fatal("cancelled context accepted")
	}
	config.Snapshot = nil
	if _, err := StartHealthServer(context.Background(), config); err == nil {
		t.Fatal("nil snapshot accepted")
	}
	_, _, sid, err := healthCurrentIdentity()
	if err != nil {
		t.Fatal(err)
	}
	if !healthClientSameSID(TrustedClient{ID: "windows:" + sid + ":pid:123"}, sid) {
		t.Fatal("same SID rejected")
	}
	for _, identity := range []string{"", "windows:S-1-5-18:pid:123", "windows:" + sid + "-suffix:pid:123", "windows:" + sid + ":pid:0", "windows:" + sid + ":pid:-1", "windows:" + sid + ":pid:4294967296", "windows:" + sid + ":pid:123:extra"} {
		if healthClientSameSID(TrustedClient{ID: identity}, sid) {
			t.Fatalf("foreign/malformed trusted identity accepted: %q", identity)
		}
	}
}

// TestHealthInteropServer is an opt-in, bounded wire fixture for the independent
// C# client. Its related PID is a fixture assertion, not parentage evidence.
func TestHealthInteropServer(t *testing.T) {
	if os.Getenv("YIME_HEALTH_INTEROP") != "1" {
		t.Skip("explicit interop fixture only")
	}
	base := os.Getenv("YIME_HEALTH_INTEROP_BASE")
	const basePrefix = `\\.\pipe\YimeBroker-health-interop-`
	if !strings.HasPrefix(base, basePrefix) || len(base) < len(basePrefix)+16 {
		t.Fatal("explicit random interop pipe base required")
	}
	roleValue, err := strconv.ParseUint(os.Getenv("YIME_HEALTH_INTEROP_ROLE"), 10, 32)
	if err != nil {
		t.Fatal(err)
	}
	role := HealthRole(roleValue)
	name, err := HealthPipeName(base, role)
	if err != nil {
		t.Fatal(err)
	}
	readyPath := os.Getenv("YIME_HEALTH_INTEROP_READY")
	if !filepath.IsAbs(readyPath) || !strings.HasPrefix(filepath.Base(readyPath), "health-interop-ready-") || filepath.Ext(readyPath) != ".json" {
		t.Fatal("explicit new interop ready path required")
	}
	snapshot := HealthSnapshot{State: HealthStateServing}
	if role == HealthRoleRuntime {
		child, err := strconv.ParseUint(os.Getenv("YIME_HEALTH_INTEROP_BROKER_PID"), 10, 32)
		if err != nil {
			t.Fatal(err)
		}
		created, err := strconv.ParseUint(os.Getenv("YIME_HEALTH_INTEROP_BROKER_CREATION"), 10, 64)
		if err != nil {
			t.Fatal(err)
		}
		snapshot.BrokerPID = uint32(child)
		snapshot.BrokerCreationFiletime = created
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	server, err := StartHealthServer(ctx, HealthConfig{Name: base, Role: role, Snapshot: func() HealthSnapshot { return snapshot }})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	pid, creation, _, err := healthCurrentIdentity()
	if err != nil {
		t.Fatal(err)
	}
	ready, err := os.OpenFile(readyPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		t.Fatal(err)
	}
	err = json.NewEncoder(ready).Encode(map[string]any{"pipe_name": name, "role": role, "pid": pid, "creation_filetime": creation, "broker_pid": snapshot.BrokerPID, "broker_creation_filetime": snapshot.BrokerCreationFiletime, "wire_fixture_only": true, "parentage_verified": false})
	closeErr := ready.Close()
	if err != nil {
		t.Fatal(err)
	}
	if closeErr != nil {
		t.Fatal(closeErr)
	}
	<-ctx.Done()
}
