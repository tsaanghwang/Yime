package touchdiagnostic

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func recorderChildCommand(mode, dir string) *exec.Cmd {
	command := exec.Command(os.Args[0], "-test.run=^TestRecorderProcessHelper$")
	command.Env = append(os.Environ(), "YIME_DIAGNOSTIC_TEST_MODE="+mode, "YIME_DIAGNOSTIC_TEST_DIRECTORY="+dir)
	return command
}

func startRecorderLockChild(t *testing.T, mode, dir string) func() {
	t.Helper()
	command := recorderChildCommand(mode, dir)
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	command.Stderr = &stderr
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	stopped := false
	t.Cleanup(func() {
		input.Close()
		if !stopped {
			command.Process.Kill()
			command.Wait()
		}
	})
	ready := make(chan string, 1)
	go func() {
		line, _ := bufio.NewReader(output).ReadString('\n')
		ready <- line
	}()
	select {
	case line := <-ready:
		if line != "ready\n" {
			t.Fatalf("child did not hold expected lock: %q", line)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("child lock handshake timed out")
	}
	return func() {
		t.Helper()
		if stopped {
			return
		}
		if err := command.Process.Kill(); err != nil {
			t.Fatal(err)
		}
		err := command.Wait()
		stopped = true
		if err == nil {
			t.Fatal("expected abrupt termination of disposable lock owner", stderr.String())
		}
	}
}

func TestRecorderProcessLockIsNonblockingAndCrashReleasesIt(t *testing.T) {
	dir := t.TempDir()
	stop := startRecorderLockChild(t, "directory", dir)
	opened := make(chan *Recorder, 1)
	go func() { opened <- retentionOpen(dir, retentionTime(), 0) }()
	var r *Recorder
	select {
	case r = <-opened:
	case <-time.After(time.Second):
		t.Fatal("directory lock waited instead of returning busy")
	}
	retentionWrite(t, r, 3)
	r.Close()
	if h := r.Health(); h.State != "failed" || h.Diagnostic.Reason != "storage-busy" || h.Run != "" || h.Saved != 0 {
		t.Fatal(h)
	}
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrStorageBusy) {
		t.Fatal("reader ignored process lock", err)
	}
	stop()
	r = retentionOpen(dir, retentionTime(), 0)
	r.Close()
	if h := r.Health(); h.State != "ready" || h.Run == "" {
		t.Fatal("crashed owner left a permanent lock", h)
	}
}

func TestRecorderProcessCrashLeavesIncompleteAndCanBeRetainedOut(t *testing.T) {
	dir := t.TempDir()
	stop := startRecorderLockChild(t, "partial", dir)
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrStorageBusy) {
		t.Fatal("reader entered an unfinished write", err)
	}
	stop()
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrIncompleteRun) {
		t.Fatal("crashed write appeared synchronized", err)
	}
	old := retentionName(retentionTime(), 0)
	for i := 0; i < MaxRuns; i++ {
		r := retentionOpen(dir, retentionTime(), byte(i))
		r.Close()
		if r.Health().State != "ready" {
			t.Fatal(r.Health())
		}
	}
	if _, err := os.Stat(filepath.Join(dir, old)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("abandoned run was not eligible for retention", err)
	}
	if _, err := os.Stat(activeRecordPath(dir, old)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("abandoned marker was not removed with its run", err)
	}
	if records, err := readRecent(dir, retentionTime, readRecordFile); err != nil || len(records) != 0 {
		t.Fatal(records, err)
	}
}

func TestRecorderLogicalIdentitySurvivesProcessBoundaries(t *testing.T) {
	dir := t.TempDir()
	first := retentionOpen(dir, retentionTime(), 255)
	first.Close()
	if first.Health().State != "ready" {
		t.Fatal(first.Health())
	}
	output, err := recorderChildCommand("record", dir).CombinedOutput()
	if err != nil {
		t.Fatalf("record subprocess: %v %s", err, output)
	}
	second := strings.TrimSpace(string(output))
	stamp, err := recordTime(second)
	if err != nil || !stamp.Equal(retentionTime().Add(time.Nanosecond)) {
		t.Fatal("process-local identity ordering", second, err)
	}
	third := retentionOpen(dir, retentionTime(), 0)
	third.Close()
	stamp, err = recordTime(third.Health().Run)
	if third.Health().State != "ready" || err != nil || !stamp.Equal(retentionTime().Add(2*time.Nanosecond)) {
		t.Fatal(third.Health(), err)
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != 3 || names[0] != first.Health().Run || names[1] != second || names[2] != third.Health().Run {
		t.Fatal(names, err)
	}
}

func TestRecorderActiveProcessIsNotPruned(t *testing.T) {
	dir := t.TempDir()
	stop := startRecorderLockChild(t, "active", dir)
	for i := 0; i < MaxRuns+3; i++ {
		r := retentionOpen(dir, retentionTime(), byte(i))
		r.Close()
		if r.Health().State != "ready" {
			t.Fatal(r.Health())
		}
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != MaxRuns || names[0] != retentionName(retentionTime(), 0) {
		t.Fatal("live process lost its run", names, err)
	}
	records, err := readRecent(dir, retentionTime, readRecordFile)
	if err != nil || len(records) != 1 || records[0].Win32 == nil || *records[0].Win32 != 123 {
		t.Fatal("live process snapshot failed", records, err)
	}
	stop()
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrIncompleteRun) {
		t.Fatal("terminated process was reported cleanly closed", err)
	}
}

// This helper only opens temporary diagnostic files. It never starts a product,
// installed host, registration tool, or an input request.
func TestRecorderProcessHelper(t *testing.T) {
	mode := os.Getenv("YIME_DIAGNOSTIC_TEST_MODE")
	if mode == "" {
		return
	}
	dir := os.Getenv("YIME_DIAGNOSTIC_TEST_DIRECTORY")
	if mode == "record" {
		r := retentionOpen(dir, retentionTime().Add(-time.Hour), 0)
		r.Close()
		if r.Health().State != "ready" {
			fmt.Fprintln(os.Stderr, r.Health())
			os.Exit(2)
		}
		fmt.Fprintln(os.Stdout, r.Health().Run)
		os.Exit(0)
	}
	if mode == "active" {
		r := retentionOpen(dir, retentionTime(), 0)
		defer r.Close()
		retentionWrite(t, r, 123)
		retentionWait(t, r, 1, false)
		fmt.Fprintln(os.Stdout, "ready")
		var signal [1]byte
		io.ReadFull(os.Stdin, signal[:])
		os.Exit(3)
	}
	var r *Recorder
	if mode == "partial" {
		r = retentionOpen(dir, retentionTime(), 0)
		if r.Health().State != "ready" {
			fmt.Fprintln(os.Stderr, r.Health())
			os.Exit(2)
		}
		defer r.Close()
	} else if mode != "directory" && mode != "orphan" {
		os.Exit(2)
	}
	lock, err := lockRecordDirectory(dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	defer lock.Close()
	if mode == "orphan" {
		marker, err := lockRecordPath(activeRecordPath(dir, retentionName(retentionTime(), 0)), recordLockCreateNew)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		defer marker.Close()
		if err := marker.Sync(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
	}
	if r != nil {
		if _, err := r.file.Write([]byte("{\"stage\":\"broker-auth\"")); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
	}
	fmt.Fprintln(os.Stdout, "ready")
	var signal [1]byte
	io.ReadFull(os.Stdin, signal[:])
	os.Exit(3) // The parent normally kills this process without running defers.
}
