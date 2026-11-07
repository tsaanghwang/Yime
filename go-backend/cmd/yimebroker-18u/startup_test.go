package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/input_methods/yime/yimebroker"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchbroker"
)

func startupOptions() brokerOptions {
	return brokerOptions{root: "isolated-root", data: "isolated-data", pipe: `\\.\pipe\YimeBroker.18uTouch.v1.offline-startup`, pid: 0xfedcba98}
}

type startupOutput struct {
	bytes.Buffer
	events *[]string
}

func (out *startupOutput) Write(p []byte) (int, error) {
	*out.events = append(*out.events, "READY")
	return out.Buffer.Write(p)
}

func TestBrokerStartupReadyOrder(t *testing.T) {
	for _, arch := range []string{"amd64", "arm64"} {
		t.Run(arch, func(t *testing.T) {
			var events []string
			out := &startupOutput{events: &events}
			options := startupOptions()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			stopped := errors.New("listener stopped after READY")
			deps := brokerDependencies{
				ready:  out,
				native: func() error { events = append(events, "native"); return nil },
				production: func(root, data string) (*touchbroker.Service, error) {
					events = append(events, "production")
					if root != options.root || data != options.data {
						t.Fatal("resource paths changed")
					}
					return &touchbroker.Service{}, nil
				},
				serve: func(gotContext context.Context, config yimebroker.NamedPipeConfig, handler func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error {
					events = append(events, "listener")
					if gotContext != ctx || handler == nil || config.Name != options.pipe || config.ExpectedClientProcessID != uint32(options.pid) || config.MaxConnections != 2 || config.MaxConnectionsPerClient != 2 || !config.RequireSameLogon || config.OnListening == nil || config.OnStopped != nil || config.OnConnectionError != nil {
						t.Fatal("dedicated transport contract changed")
					}
					if out.Len() != 0 {
						t.Fatal("READY preceded the retained-listener callback")
					}
					// An empty stream exercises the bound service handler without
					// creating a session, loading data or touching any OS transport.
					if err := handler(ctx, strings.NewReader(""), io.Discard, yimebroker.TrustedClient{ID: "offline-startup-owner"}); err != nil {
						t.Fatal(err)
					}
					config.OnListening()
					events = append(events, "listener-return")
					return stopped
				},
			}
			if err := runBroker(ctx, options, "windows", arch, deps); err != stopped {
				t.Fatalf("listener error not preserved: %v", err)
			}
			if want := []string{"native", "production", "listener", "READY", "listener-return"}; !reflect.DeepEqual(events, want) {
				t.Fatalf("startup order = %v, want %v", events, want)
			}
			if out.String() != "READY yimebroker-18u\n" {
				t.Fatalf("READY must be emitted exactly once by the callback: %q", out.String())
			}
		})
	}
}

func TestBrokerStartupRejectsBeforeReady(t *testing.T) {
	for _, name := range []string{"unsupported-os", "unsupported-arch", "empty-pipe", "foreign-pipe", "bare-prefix", "zero-pid", "overflow-pid", "native-query", "production", "listener"} {
		t.Run(name, func(t *testing.T) {
			var events []string
			var out bytes.Buffer
			options := startupOptions()
			goos, goarch := "windows", "arm64"
			failure := errors.New(name)
			var want []string
			deps := brokerDependencies{
				ready: &out,
				native: func() error {
					events = append(events, "native")
					if name == "native-query" {
						return failure
					}
					return nil
				},
				production: func(string, string) (*touchbroker.Service, error) {
					events = append(events, "production")
					if name == "production" {
						return nil, failure
					}
					return &touchbroker.Service{}, nil
				},
				serve: func(context.Context, yimebroker.NamedPipeConfig, func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error {
					events = append(events, "listener")
					return failure
				},
			}
			switch name {
			case "unsupported-os":
				goos = "linux"
			case "unsupported-arch":
				goarch = "386"
			case "empty-pipe":
				options.pipe = ""
			case "foreign-pipe":
				options.pipe = `\\.\pipe\YimeBroker.standard`
			case "bare-prefix":
				options.pipe = `\\.\pipe\YimeBroker.18uTouch.v1.`
			case "zero-pid":
				options.pid = 0
			case "overflow-pid":
				options.pid = 1 << 32
			case "native-query":
				want = []string{"native"}
			case "production":
				want = []string{"native", "production"}
			case "listener":
				want = []string{"native", "production", "listener"}
			}
			err := runBroker(context.Background(), options, goos, goarch, deps)
			if err == nil || (want != nil && err != failure) {
				t.Fatalf("startup refusal not propagated: %v", err)
			}
			if !reflect.DeepEqual(events, want) || out.Len() != 0 {
				t.Fatalf("failed startup continued or reported READY: events=%v want=%v output=%q", events, want, out.String())
			}
		})
	}
}

// The existing architecture unit test owns the exhaustive identity matrix.
// Here representative observations must also stop the startup pipeline before
// construction/listening, while both original native contracts can reach READY.
func TestBrokerStartupNativeIdentity(t *testing.T) {
	queryError := errors.New("IsWow64Process2 unavailable")
	for _, tc := range []struct {
		name, arch      string
		process, native uint16
		queryErr        error
		accepted        bool
	}{
		{"native-x64", "amd64", 0, 0x8664, nil, true},
		{"native-arm64", "arm64", 0, 0xaa64, nil, true},
		{"x64-emulated-on-arm64", "amd64", 0x8664, 0xaa64, nil, false},
		{"x64-foreign-native", "amd64", 0, 0xaa64, nil, false},
		{"arm64-foreign-native", "arm64", 0, 0x8664, nil, false},
		{"nonzero-matching-process", "arm64", 0xaa64, 0xaa64, nil, false},
		{"query-failed", "arm64", 0, 0xaa64, queryError, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			constructed, listened := false, false
			deps := brokerDependencies{
				ready:  &out,
				native: func() error { return validateNativeArchitecture(tc.arch, tc.process, tc.native, tc.queryErr) },
				production: func(string, string) (*touchbroker.Service, error) {
					constructed = true
					return &touchbroker.Service{}, nil
				},
				serve: func(_ context.Context, config yimebroker.NamedPipeConfig, _ func(context.Context, io.Reader, io.Writer, yimebroker.TrustedClient) error) error {
					listened = true
					config.OnListening()
					return nil
				},
			}
			err := runBroker(context.Background(), startupOptions(), "windows", tc.arch, deps)
			wantOutput := ""
			if tc.accepted {
				wantOutput = "READY yimebroker-18u\n"
			}
			if (err == nil) != tc.accepted || constructed != tc.accepted || listened != tc.accepted || out.String() != wantOutput {
				t.Fatalf("native gate did not control startup: error=%v constructed=%v listened=%v output=%q", err, constructed, listened, out.String())
			}
			if tc.queryErr != nil && !errors.Is(err, tc.queryErr) {
				t.Fatal("native query error was replaced", err)
			}
		})
	}
}
