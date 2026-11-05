//go:build windows && (amd64 || arm64)

package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"github.com/tsaanghwang/Yime/go-backend/internal/touchdiagnostic"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestRuntimeInstalledDiagnosticHelper(t *testing.T) {
	if os.Getenv("YIME_DIAGNOSTIC_TEST_CHILD") == "" {
		return
	}
	line, err := bufio.NewReaderSize(os.Stdin, 1024).ReadBytes('\n')
	var h touchdiagnostic.Health
	if err != nil || len(line) > 1024 || json.Unmarshal(line, &h) != nil || !h.Valid() {
		os.Exit(21)
	}
	fmt.Fprintln(os.Stdout, h.State)
	// Fragmented real stderr, oversized private text, duplicate keys, then more
	// than the per-run limit and the capacity of an OS pipe after a disk failure.
	fmt.Fprint(os.Stderr, "{\"stage\":\"broker-auth\",")
	fmt.Fprintln(os.Stderr, "\"reason\":\"identity-mismatch\",\"win32\":5}")
	fmt.Fprintln(os.Stderr, strings.Repeat("PRIVATE正文候选组码", 20000))
	fmt.Fprintln(os.Stderr, "{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"text\":\"PRIVATE\"}")
	fmt.Fprintln(os.Stderr, "{\"stage\":\"broker-auth\",\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\"}")
	for i := 0; i < 80; i++ {
		fmt.Fprintln(os.Stderr, "{\"stage\":\"tip-completion\",\"reason\":\"operation-failed\",\"hresult\":2147500037}")
	}
	fmt.Fprintln(os.Stderr, strings.Repeat("PRIVATE", 20000))
	os.Exit(0)
}

func TestRuntimeInstalledDiagnosticPipeToDiskAndFailure(t *testing.T) {
	for _, mode := range []string{"normal", "open-failure", "write-after-close"} {
		t.Run(mode, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), "diagnostics")
			if mode == "open-failure" {
				if err := os.WriteFile(dir, []byte("occupied"), 0600); err != nil {
					t.Fatal(err)
				}
			}
			recorder := touchdiagnostic.OpenRecorder(dir, nil)
			defer recorder.Close()
			if mode == "write-after-close" {
				recorder.Close()
			}
			initial := recorder.Health().State
			job, err := createChildProcessJob()
			if err != nil {
				t.Fatal(err)
			}
			var once sync.Once
			var mu sync.Mutex
			stop := func() { once.Do(func() { mu.Lock(); defer mu.Unlock(); _ = job.Close() }) }
			defer stop()
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			t.Setenv("YIME_DIAGNOSTIC_TEST_CHILD", "1")
			exe, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			child, err := startDesktopDiagnosticChild(installedStart(job, &mu, stop), recorder, ctx, exe, []string{"-test.run=^TestRuntimeInstalledDiagnosticHelper$"}, t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			defer child.Stop()
			go forwardDiagnosticHealth(ctx, recorder, child.Input())
			state := make(chan string, 1)
			go func() {
				reader := bufio.NewReader(child.Output())
				line, _ := reader.ReadString('\n')
				state <- strings.TrimSpace(line)
				_, _ = io.Copy(io.Discard, reader)
			}()
			select {
			case got := <-state:
				if got != initial {
					t.Fatalf("GUI stdin status %q != %q", got, initial)
				}
			case <-ctx.Done():
				t.Fatal("status pipe blocked")
			}
			done := make(chan error, 1)
			go func() { done <- child.Wait() }()
			select {
			case err = <-done:
				if err != nil {
					t.Fatal(err)
				}
			case <-ctx.Done():
				t.Fatal("stderr stopped draining after storage failure")
			}
			if mode == "normal" {
				deadline := time.Now().Add(10 * time.Second)
				for recorder.Health().Saved < touchdiagnostic.MaxRecords && time.Now().Before(deadline) {
					time.Sleep(time.Millisecond)
				}
			}
			recorder.Close()
			h := recorder.Health()
			if mode != "normal" {
				if h.State != "failed" || h.Saved != 0 {
					t.Fatal("false save", h)
				}
				return
			}
			if h.State != "limit" || h.Saved != touchdiagnostic.MaxRecords {
				t.Fatal(h)
			}
			records, err := touchdiagnostic.ReadRecent(dir)
			if err != nil || len(records) != touchdiagnostic.MaxRecords || records[0].Win32 == nil || *records[0].Win32 != 5 {
				t.Fatal("diagnostic cannot be retrieved", err)
			}
			data, err := os.ReadFile(filepath.Join(dir, h.Run))
			if err != nil || len(data) > touchdiagnostic.MaxFile || strings.Contains(string(data), "PRIVATE") || strings.Contains(string(data), "正文") {
				t.Fatal("size/privacy violation", err)
			}
		})
	}
}
