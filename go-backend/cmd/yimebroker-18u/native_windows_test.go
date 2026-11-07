//go:build windows && (amd64 || arm64)

package main

import (
	"errors"
	"flag"
	"os"
	"runtime"
	"strconv"
	"testing"
)

// Calls the production Windows API gate without launching a broker, a TIP or a
// host. Run natively on both architectures, and as amd64 on ARM64 for rejection.
func TestNativeArchitectureCurrentProcess(t *testing.T) {
	machine, native, e := queryNativeArchitecture()
	if e != nil {
		t.Fatal(e)
	}
	wantNative := machine == 0 && ((runtime.GOARCH == "amd64" && native == 0x8664) || (runtime.GOARCH == "arm64" && native == 0xaa64))
	if e = requireNativeArchitecture(); (e == nil) != wantNative {
		t.Fatalf("GOARCH=%s process=%#x native=%#x: gate error = %v, native = %v", runtime.GOARCH, machine, native, e, wantNative)
	}
	t.Logf("GOARCH=%s process=%#x native=%#x accepted=%v", runtime.GOARCH, machine, native, e == nil)
}

// A missing descriptor makes NewProduction fail before any pipe is opened.
// This exercises run's platform gate and production initialization together.
func TestBrokerRunReachesProductionInitialization(t *testing.T) {
	machine, native, e := queryNativeArchitecture()
	if e != nil {
		t.Fatal(e)
	}
	wantNative := machine == 0 && ((runtime.GOARCH == "amd64" && native == 0x8664) || (runtime.GOARCH == "arm64" && native == 0xaa64))
	oldArgs, oldFlags := os.Args, flag.CommandLine
	t.Cleanup(func() { os.Args, flag.CommandLine = oldArgs, oldFlags })
	flag.CommandLine = flag.NewFlagSet("broker-production-init-test", flag.ContinueOnError)
	os.Args = []string{"broker-production-init-test", "--root", t.TempDir(), "--data-dir", t.TempDir(), "--pipe-name", `\\.\pipe\YimeBroker.18uTouch.v1.production-init-test`, "--tip-host-pid", strconv.Itoa(os.Getpid())}
	e = run()
	if wantNative {
		if !errors.Is(e, os.ErrNotExist) {
			t.Fatalf("native run did not reach NewProduction's missing-descriptor failure: %v", e)
		}
	} else {
		gateErr := requireNativeArchitecture()
		if gateErr == nil || e == nil || e.Error() != gateErr.Error() {
			t.Fatalf("non-native run did not fail at the native architecture gate: run=%v gate=%v", e, gateErr)
		}
	}
}
