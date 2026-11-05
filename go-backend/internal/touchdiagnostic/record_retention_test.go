package touchdiagnostic

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func retentionTime() time.Time {
	return time.Date(2026, time.November, 5, 8, 2, 19, 622669600, time.UTC)
}

func retentionName(stamp time.Time, nonce uint64) string {
	return fmt.Sprintf("run-%s-%016x.jsonl", strings.ReplaceAll(stamp.Format(recordTimeLayout), ".", ""), nonce)
}

func retentionOpen(dir string, now time.Time, nonce byte) *Recorder {
	return openRecorder(dir, nil, func() time.Time { return now }, bytes.NewReader(bytes.Repeat([]byte{nonce}, 8)))
}

func retentionWrite(t *testing.T, r *Recorder, code int) {
	t.Helper()
	line := fmt.Sprintf("{\"stage\":\"broker-auth\",\"reason\":\"identity-mismatch\",\"win32\":%d}\n", code)
	if n, err := r.Stream().Write([]byte(line)); err != nil || n != len(line) {
		t.Fatal("stderr stopped draining", n, err)
	}
}

func retentionWait(t *testing.T, r *Recorder, saved int, failed bool) {
	t.Helper()
	deadline := time.NewTimer(10 * time.Second)
	defer deadline.Stop()
	for {
		h := r.Health()
		if failed && h.State == "failed" || !failed && h.Saved == saved {
			return
		}
		if !failed && h.State == "failed" {
			t.Fatal(h)
		}
		select {
		case <-r.Changed():
		case <-deadline.C:
			t.Fatal("disk worker did not reach expected state", h)
		}
	}
}

func retentionFixture(t *testing.T, dir string, count int) []string {
	t.Helper()
	var names []string
	for i := 0; i < count; i++ {
		name := retentionName(retentionTime().Add(time.Duration(i)*time.Nanosecond), uint64(i))
		if err := os.WriteFile(filepath.Join(dir, name), []byte(validRecord), 0600); err != nil {
			t.Fatal(err)
		}
		names = append(names, name)
	}
	return names
}

func TestRecorderLogicalTimeRetentionAndRecent(t *testing.T) {
	for _, regress := range []bool{false, true} {
		t.Run(fmt.Sprintf("clock-regresses-%v", regress), func(t *testing.T) {
			dir := t.TempDir()
			unrelated := filepath.Join(dir, "leave-me.txt")
			if err := os.WriteFile(unrelated, []byte("evidence"), 0600); err != nil {
				t.Fatal(err)
			}
			directory := filepath.Join(dir, retentionName(retentionTime(), 0))
			if err := os.Mkdir(directory, 0700); err != nil {
				t.Fatal(err)
			}
			var created []string
			for i := 0; i < MaxRuns+3; i++ {
				now := retentionTime()
				if regress {
					now = now.Add(-time.Duration(i) * time.Second)
				}
				r := retentionOpen(dir, now, byte(255-i))
				if h := r.Health(); h.State != "ready" {
					r.Close()
					t.Fatal(h)
				}
				name := r.Health().Run
				stamp, err := recordTime(name)
				if err != nil || !stamp.Equal(retentionTime().Add(time.Duration(i)*time.Nanosecond)) {
					r.Close()
					t.Fatalf("logical timestamp %d: %s %v", i, name, err)
				}
				retentionWrite(t, r, i)
				r.Close()
				if h := r.Health(); h.State != "ready" || h.Saved != 1 {
					t.Fatal(h)
				}
				created = append(created, name)
			}
			names, err := recordFiles(dir)
			if err != nil || len(names) != MaxRuns {
				t.Fatal(names, err)
			}
			want := created[len(created)-MaxRuns:]
			for i := range names {
				if names[i] != want[i] {
					t.Fatalf("retained run %d: got %s want %s", i, names[i], want[i])
				}
			}
			records, err := readRecent(dir, retentionTime, readRecordFile)
			if err != nil || len(records) != MaxRuns {
				t.Fatal(records, err)
			}
			for i, record := range records {
				if record.Win32 == nil || *record.Win32 != uint32(i+3) {
					t.Fatalf("recent record %d: %+v", i, record)
				}
			}
			if raw, err := os.ReadFile(unrelated); err != nil || string(raw) != "evidence" {
				t.Fatal("unrelated file changed", err)
			}
			if info, err := os.Stat(directory); err != nil || !info.IsDir() {
				t.Fatal("run-shaped directory removed", err)
			}
		})
	}
}

func TestRecorderLegacyTimestampTiesPrecedeNewRuns(t *testing.T) {
	dir := t.TempDir()
	for _, nonce := range []uint64{^uint64(0), 0} {
		if err := os.WriteFile(filepath.Join(dir, retentionName(retentionTime(), nonce)), []byte(validRecord), 0600); err != nil {
			t.Fatal(err)
		}
	}
	r := retentionOpen(dir, retentionTime(), 0)
	retentionWrite(t, r, 99)
	r.Close()
	if h := r.Health(); h.State != "ready" || h.Saved != 1 {
		t.Fatal(h)
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != 3 || names[2] != r.Health().Run {
		t.Fatal(names, err)
	}
	stamp, err := recordTime(names[2])
	if err != nil || !stamp.Equal(retentionTime().Add(time.Nanosecond)) {
		t.Fatal(stamp, err)
	}
	records, err := readRecent(dir, retentionTime, readRecordFile)
	if err != nil || len(records) != 3 || records[2].Win32 == nil || *records[2].Win32 != 99 {
		t.Fatal(records, err)
	}
}

func TestRecorderAllocationFailurePreservesHistory(t *testing.T) {
	for _, mode := range []string{"invalid-date", "future", "overflow", "invalid-clock", "nonce", "create"} {
		t.Run(mode, func(t *testing.T) {
			dir := t.TempDir()
			names := retentionFixture(t, dir, MaxRuns)
			now := retentionTime().Add(time.Hour)
			var random io.Reader = bytes.NewReader(make([]byte, 8))
			badName := ""
			switch mode {
			case "invalid-date":
				badName = "run-20261305T080219622669600Z-0000000000000000.jsonl"
			case "future":
				badName = retentionName(now.Add(maxRecordFuture+time.Nanosecond), 0)
			case "overflow":
				now = time.Date(9999, time.December, 31, 23, 59, 59, 999999999, time.UTC)
				badName = retentionName(now, 0)
			case "invalid-clock":
				now = time.Date(10000, time.January, 1, 0, 0, 0, 0, time.UTC)
			case "nonce":
				random = bytes.NewReader(nil)
			case "create":
				if err := os.Mkdir(filepath.Join(dir, retentionName(now, 0)), 0700); err != nil {
					t.Fatal(err)
				}
			}
			if badName != "" {
				if err := os.WriteFile(filepath.Join(dir, badName), []byte(validRecord), 0600); err != nil {
					t.Fatal(err)
				}
				names = append(names, badName)
			}
			r := openRecorder(dir, nil, func() time.Time { return now }, random)
			retentionWrite(t, r, 8)
			r.Close()
			if h := r.Health(); h.State != "failed" || h.Saved != 0 || h.Run != "" || h.Diagnostic.Reason != "storage-open-failed" {
				t.Fatal(h)
			}
			for _, name := range names {
				if raw, err := os.ReadFile(filepath.Join(dir, name)); err != nil || string(raw) != validRecord {
					t.Fatal("failed allocation changed prior evidence", name, err)
				}
			}
			if mode == "invalid-date" || mode == "future" {
				if _, err := readRecent(dir, func() time.Time { return now }, readRecordFile); err == nil {
					t.Fatal("reader accepted invalid run clock")
				}
			}
		})
	}
}

func TestRecorderActiveRunsSurviveRetentionAndAllowSnapshot(t *testing.T) {
	dir := t.TempDir()
	active := retentionOpen(dir, retentionTime(), 255)
	t.Cleanup(active.Close)
	retentionWrite(t, active, 101)
	retentionWait(t, active, 1, false)
	var closedRuns []string
	for i := 0; i < MaxRuns+3; i++ {
		r := retentionOpen(dir, retentionTime(), byte(i))
		r.Close()
		if r.Health().State != "ready" {
			t.Fatal(r.Health())
		}
		closedRuns = append(closedRuns, r.Health().Run)
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != MaxRuns || names[0] != active.Health().Run {
		t.Fatal("active oldest run was removed", names, err)
	}
	records, err := readRecent(dir, retentionTime, readRecordFile)
	if err != nil || len(records) != 1 || records[0].Win32 == nil || *records[0].Win32 != 101 {
		t.Fatal("active synchronized snapshot unavailable", records, err)
	}
	retentionWrite(t, active, 102)
	retentionWait(t, active, 2, false)
	active.Close()
	records, err = readRecent(dir, retentionTime, readRecordFile)
	if err != nil || len(records) != 2 || *records[1].Win32 != 102 {
		t.Fatal(records, err)
	}
	// The active-run exception ends after that owner closes. The next Open
	// discards its old identity and restores the exact newest-16 contract.
	last := retentionOpen(dir, retentionTime(), 254)
	last.Close()
	if last.Health().State != "ready" {
		t.Fatal(last.Health())
	}
	closedRuns = append(closedRuns, last.Health().Run)
	names, err = recordFiles(dir)
	if err != nil || len(names) != MaxRuns {
		t.Fatal(names, err)
	}
	for i, want := range closedRuns[len(closedRuns)-MaxRuns:] {
		if names[i] != want {
			t.Fatal("closed-owner retention did not return to newest runs", names)
		}
	}
}

func TestRecorderAllActiveCapacityReportsBusyWithoutDeletion(t *testing.T) {
	dir := t.TempDir()
	var recorders []*Recorder
	for i := 0; i < MaxRuns; i++ {
		r := retentionOpen(dir, retentionTime(), byte(i))
		if r.Health().State != "ready" {
			r.Close()
			t.Fatal(r.Health())
		}
		recorders = append(recorders, r)
		t.Cleanup(r.Close)
	}
	r := retentionOpen(dir, retentionTime(), 255)
	retentionWrite(t, r, 7)
	r.Close()
	if h := r.Health(); h.State != "failed" || h.Diagnostic.Reason != "storage-busy" || h.Run != "" {
		t.Fatal(h)
	}
	names, err := recordFiles(dir)
	if err != nil || len(names) != MaxRuns {
		t.Fatal(names, err)
	}
	for i, prior := range recorders {
		if names[i] != prior.Health().Run {
			t.Fatal("active history changed", i, names)
		}
	}
}

func TestRecorderReaderHoldsDirectoryLockThroughRead(t *testing.T) {
	dir := t.TempDir()
	names := retentionFixture(t, dir, MaxRuns)
	entered, release := make(chan struct{}), make(chan struct{})
	result := make(chan error, 1)
	go func() {
		first := true
		_, err := readRecent(dir, retentionTime, func(path string) ([]byte, error) {
			if first {
				first = false
				close(entered)
				<-release
			}
			return readRecordFile(path)
		})
		result <- err
	}()
	select {
	case <-entered:
	case <-time.After(10 * time.Second):
		t.Fatal("reader did not reach file IO")
	}
	r := retentionOpen(dir, retentionTime(), 255)
	r.Close()
	close(release)
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	if h := r.Health(); h.State != "failed" || h.Diagnostic.Reason != "storage-busy" {
		t.Fatal(h)
	}
	for _, name := range names {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Fatal("cleanup interleaved with snapshot", name, err)
		}
	}
}

func TestRecorderWriteContentionAndPartialLegacyAreExplicit(t *testing.T) {
	dir := t.TempDir()
	r := retentionOpen(dir, retentionTime(), 0)
	retentionWrite(t, r, 1)
	retentionWait(t, r, 1, false)
	lock, err := lockRecordDirectory(dir)
	if err != nil {
		t.Fatal(err)
	}
	retentionWrite(t, r, 2)
	retentionWait(t, r, 0, true)
	if err := lock.Close(); err != nil {
		t.Fatal(err)
	}
	retentionWrite(t, r, 3)
	r.Close()
	if h := r.Health(); h.Diagnostic.Reason != "storage-busy" || h.Saved != 1 {
		t.Fatal(h)
	}
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrIncompleteRun) {
		t.Fatal("abandoned marker appeared complete", err)
	}
	if raw, err := os.ReadFile(filepath.Join(dir, r.Health().Run)); err != nil || bytes.Count(raw, []byte{'\n'}) != 1 || bytes.Contains(raw, []byte("\"win32\":2")) || bytes.Contains(raw, []byte("\"win32\":3")) {
		t.Fatal("busy write was retried or later data was saved", string(raw), err)
	}
	legacy := t.TempDir()
	if err := os.WriteFile(filepath.Join(legacy, retentionName(retentionTime(), 0)), []byte(strings.TrimSuffix(validRecord, "\n")), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readRecent(legacy, retentionTime, readRecordFile); !errors.Is(err, ErrIncompleteRun) {
		t.Fatal("unterminated legacy line appeared complete", err)
	}
}

func TestRecorderCloseContentionLeavesIncompleteMarker(t *testing.T) {
	dir := t.TempDir()
	r := retentionOpen(dir, retentionTime(), 0)
	retentionWrite(t, r, 1)
	retentionWait(t, r, 1, false)
	lock, err := lockRecordDirectory(dir)
	if err != nil {
		t.Fatal(err)
	}
	r.Close()
	if err := lock.Close(); err != nil {
		t.Fatal(err)
	}
	if h := r.Health(); h.State != "failed" || h.Diagnostic.Reason != "storage-busy" || h.Saved != 1 {
		t.Fatal(h)
	}
	if _, err := readRecent(dir, retentionTime, readRecordFile); !errors.Is(err, ErrIncompleteRun) {
		t.Fatal("contended close claimed a completed run", err)
	}
}
