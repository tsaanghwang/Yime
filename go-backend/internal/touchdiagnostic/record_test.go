package touchdiagnostic

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const validRecord = "{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"win32\":5}\n"

func TestRecorderStrictFilteringAndIndependentStreams(t *testing.T) {
	dir := t.TempDir()
	r := OpenRecorder(dir, nil)
	a, b := r.Stream(), r.Stream()
	a.Write([]byte("{\"stage\":\"broker-auth\","))
	b.Write([]byte("PRIVATE正文组码候选\n"))
	a.Write([]byte("\"reason\":\"identity-mismatch\",\"win32\":5}\n"))
	invalid := []string{
		"{\"stage\":\"broker-auth\",\"reason\":\"PRIVATE\"}",
		"{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"text\":\"PRIVATE\"}",
		"{\"stage\":\"broker-auth\",\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\"}",
		"{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"win32\":null}",
		"{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"win32\":4294967296}",
		strings.Repeat("PRIVATE", 10000),
	}
	for _, line := range invalid {
		b.Write([]byte(line + "\n"))
	}
	b.Write([]byte("{\"stage\":\"broker-auth\"")) // incomplete EOF
	r.Close()
	records, err := ReadRecent(dir)
	if err != nil || len(records) != 1 || *records[0].Win32 != 5 {
		t.Fatalf("records: %v %v", records, err)
	}
	data, err := os.ReadFile(filepath.Join(dir, r.Health().Run))
	if err != nil || bytes.Contains(data, []byte("PRIVATE")) {
		t.Fatal("private output persisted", err)
	}
}
func TestRecorderLimitsAndOwnedRetention(t *testing.T) {
	dir := t.TempDir()
	r := OpenRecorder(dir, nil)
	stream := r.Stream()
	for i := 0; i < MaxRecords+20; i++ {
		stream.Write([]byte(validRecord))
	}
	deadline := time.Now().Add(10 * time.Second)
	for r.Health().Saved < MaxRecords && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	r.Close()
	if h := r.Health(); h.State != "limit" || h.Saved != MaxRecords {
		t.Fatal(h)
	}
	info, err := os.Stat(filepath.Join(dir, r.Health().Run))
	if err != nil || info.Size() > MaxFile {
		t.Fatal("unbounded file", err)
	}
	unrelated := filepath.Join(dir, "leave-me.txt")
	if err = os.WriteFile(unrelated, []byte("evidence"), 0600); err != nil {
		t.Fatal(err)
	}
	var newest string
	for i := 0; i < MaxRuns+3; i++ {
		next := OpenRecorder(dir, nil)
		if next.Health().State != "ready" {
			t.Fatal(next.Health())
		}
		newest = next.Health().Run
		next.Close()
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != MaxRuns || names[len(names)-1] != newest {
		t.Fatal(names, err)
	}
	if _, err = os.Stat(unrelated); err != nil {
		t.Fatal("unrelated file removed")
	}
}
func TestRecorderRealWriteFailureAndSlowDiskCannotBlockStream(t *testing.T) {
	r := OpenRecorder(t.TempDir(), nil)
	if err := r.file.Close(); err != nil {
		t.Fatal(err)
	} // real OS write failure, not an in-memory sink
	stream := r.Stream()
	n, err := stream.Write([]byte(validRecord))
	if err != nil || n != len(validRecord) {
		t.Fatal("stopped draining", err)
	}
	r.Close()
	if h := r.Health(); h.State != "failed" || h.Saved != 0 || h.Diagnostic.Reason != "storage-write-failed" {
		t.Fatal(h)
	}
	stream.Write(bytes.Repeat([]byte("PRIVATE"), 100000))
	if r.Health().State != "failed" {
		t.Fatal("failure cleared")
	}
	// A worker deliberately not scheduled models a stalled disk. Enqueue and
	// Health must still finish and retain at most MaxRecords, without disk IO.
	blocked := &Recorder{health: Health{State: "ready"}, changed: make(chan struct{}, 1), queue: make(chan Diagnostic, MaxRecords), done: make(chan struct{})}
	done := make(chan struct{})
	go func() {
		for i := 0; i < MaxRecords+100; i++ {
			blocked.Stream().Write([]byte(validRecord))
		}
		_ = blocked.Health()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("slow storage blocked stderr")
	}
	if len(blocked.queue) != MaxRecords || blocked.Health().State != "limit" {
		t.Fatal("queue not bounded")
	}
	started := time.Now()
	blocked.Close()
	if time.Since(started) > 3*time.Second || blocked.Health().State != "failed" || blocked.Health().Diagnostic.Reason != "storage-close-pending" {
		t.Fatal("close was not bounded")
	}
}
func TestRecorderExactLineBoundaryAndHealth(t *testing.T) {
	line := strings.TrimSuffix(validRecord, "\n")
	line += strings.Repeat(" ", MaxLine-len(line))
	if _, ok := DecodeLine([]byte(line)); !ok {
		t.Fatal("exact boundary rejected")
	}
	if _, ok := DecodeLine([]byte(line + " ")); ok {
		t.Fatal("oversize accepted")
	}
	var output bytes.Buffer
	h := Health{State: "failed", Saved: 0}
	if err := WriteHealth(&output, h); err != nil {
		t.Fatal(err)
	}
	output.WriteString("{\"state\":\"failed\",\"run\":\"PRIVATE\",\"saved\":0}\n")
	var got []Health
	ReadHealth(&output, func(h Health) { got = append(got, h) })
	if len(got) != 1 || got[0].State != "failed" {
		raw, _ := json.Marshal(got)
		t.Fatal(string(raw))
	}
}
