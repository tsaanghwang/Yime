//go:build windows

package yimebroker

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestDedicatedNamedPipeHandlerUsesActualSameLogonPeer(t *testing.T) {
	name := fmt.Sprintf(`\\.\pipe\YimeBroker-dedicated-peer-%d`, os.Getpid())
	ctx, cancel := context.WithCancel(context.Background())
	listening := make(chan struct{})
	done := make(chan error, 1)
	seen := make(chan TrustedClient, 1)
	rejected := make(chan error, 1)
	var file *os.File
	stopped := false
	// Also drain the listener on assertion failure, not only on the happy path.
	defer func() {
		if file != nil {
			_ = file.Close()
		}
		cancel()
		if !stopped {
			select {
			case e := <-done:
				if e != nil {
					t.Errorf("strict peer listener stop: %v", e)
				}
			case <-time.After(namedPipeTestTimeout):
				t.Error("strict peer listener failed to stop")
			}
		}
	}()
	go func() {
		done <- ServeNamedPipeHandler(ctx, NamedPipeConfig{Name: name, MaxConnections: 1, MaxConnectionsPerClient: 1, RequireSameLogon: true, ExpectedClientProcessID: uint32(os.Getpid()), OnListening: func() { close(listening) }, OnConnectionError: func(e error) {
			select {
			case rejected <- e:
			default:
			}
		}}, func(ctx context.Context, in io.Reader, out io.Writer, peer TrustedClient) error {
			seen <- peer
			_, e := out.Write([]byte("actual-os-peer\n"))
			return e
		})
	}()
	select {
	case <-listening:
	case e := <-done:
		stopped = true
		t.Fatalf("strict peer listener exited before readiness: %v", e)
	case <-time.After(namedPipeTestTimeout):
		t.Fatal("strict peer listener did not become ready")
	}
	file = openTestPipe(t, name)
	select {
	case peer := <-seen:
		if !strings.Contains(peer.ID, fmt.Sprintf(":pid:%d:", os.Getpid())) || !strings.Contains(peer.ID, ":logon:") || !strings.Contains(peer.ID, ":session:") {
			t.Fatal("strict peer response missing OS identity fields")
		}
	case e := <-rejected:
		t.Fatalf("strict peer transport rejected connection: %v", e)
	case e := <-done:
		stopped = true
		t.Fatalf("strict peer listener exited before authenticated handler: %v", e)
	case <-time.After(namedPipeTestTimeout):
		t.Fatal("strict peer handler not reached: no transport rejection or listener exit observed")
	}
}

func TestDedicatedNamedPipeWrongProcessHelper(t *testing.T) {
	name := os.Getenv("YIME_TEST_REJECTED_PIPE")
	if name == "" {
		return // Only exercised by the explicitly spawned test subprocess.
	}
	file, e := openPipeUntil(name, time.Now().Add(namedPipeTestTimeout))
	if e != nil {
		t.Fatal(e)
	}
	defer file.Close()
	var b [1]byte
	n, e := file.Read(b[:])
	if n != 0 || e == nil {
		t.Fatal("unauthorized process received data")
	}
}
func TestDedicatedNamedPipeRejectsOtherActualProcess(t *testing.T) {
	name := fmt.Sprintf(`\\.\pipe\YimeBroker-dedicated-reject-%d`, os.Getpid())
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	listening := make(chan struct{})
	done := make(chan error, 1)
	rejected := make(chan error, 1)
	go func() {
		done <- ServeNamedPipeHandler(ctx, NamedPipeConfig{Name: name, MaxConnections: 1, MaxConnectionsPerClient: 1, RequireSameLogon: true, ExpectedClientProcessID: uint32(os.Getpid()), OnListening: func() { close(listening) }, OnConnectionError: func(e error) {
			select {
			case rejected <- e:
			default:
			}
		}}, func(context.Context, io.Reader, io.Writer, TrustedClient) error {
			return fmt.Errorf("wrong process reached handler")
		})
	}()
	waitTestPipeListening(t, listening, done)
	exe, e := os.Executable()
	if e != nil {
		t.Fatal(e)
	}
	childCtx, stop := context.WithTimeout(context.Background(), namedPipeTestTimeout)
	defer stop()
	cmd := exec.CommandContext(childCtx, exe, "-test.run=^TestDedicatedNamedPipeWrongProcessHelper$")
	cmd.Env = append(os.Environ(), "YIME_TEST_REJECTED_PIPE="+name)
	if e = cmd.Run(); e != nil {
		t.Fatal("rejected peer helper failed", e)
	}
	select {
	case e = <-rejected:
		if !strings.Contains(e.Error(), "not bootstrap TIP host") {
			t.Fatal("wrong rejection reason", e)
		}
	case <-time.After(namedPipeTestTimeout):
		t.Fatal("no OS process rejection")
	}
	cancel()
	select {
	case e = <-done:
		if e != nil {
			t.Fatal(e)
		}
	case <-time.After(namedPipeTestTimeout):
		t.Fatal("listener failed to stop")
	}
}
