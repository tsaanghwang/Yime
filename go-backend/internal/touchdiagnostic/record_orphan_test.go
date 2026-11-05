package touchdiagnostic

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRecorderCrashBetweenMarkerAndDataReclaimsOnlyOrphan(t *testing.T) {
	dir := t.TempDir()
	name := retentionName(retentionTime(), 0)
	stop := startRecorderLockChild(t, "orphan", dir)
	if _, err := os.Stat(filepath.Join(dir, name)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("helper crossed the marker-before-data boundary", err)
	}
	stop()
	if info, err := os.Stat(activeRecordPath(dir, name)); err != nil || !info.Mode().IsRegular() || info.Size() != 0 {
		t.Fatal("crash marker was not preserved", err)
	}
	// Same clock and nonce deliberately reuse the orphan's name. Cleanup must
	// precede CREATE_NEW, while retaining the existing data-file safety rules.
	r := retentionOpen(dir, retentionTime(), 0)
	retentionWrite(t, r, 42)
	r.Close()
	if h := r.Health(); h.State != "ready" || h.Run != name || h.Saved != 1 {
		t.Fatal("orphan marker prevented a new run", h)
	}
	if _, err := os.Stat(activeRecordPath(dir, name)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("normal close left the reclaimed marker", err)
	}
	records, err := readRecent(dir, retentionTime, readRecordFile)
	if err != nil || len(records) != 1 || records[0].Win32 == nil || *records[0].Win32 != 42 {
		t.Fatal(records, err)
	}
}

func TestRecorderOrphanCleanupPreservesActiveUnknownAndDataMarkers(t *testing.T) {
	dir := t.TempDir()
	orphan := retentionName(retentionTime().Add(-time.Hour), 0)
	active := retentionName(retentionTime().Add(-2*time.Hour), 0)
	withData := retentionName(retentionTime().Add(-3*time.Hour), 0)
	nonempty := retentionName(retentionTime().Add(-4*time.Hour), 0)
	directoryMarker := retentionName(retentionTime().Add(-5*time.Hour), 0)
	directoryData := retentionName(retentionTime().Add(-6*time.Hour), 0)
	for _, name := range []string{orphan, withData, directoryData} {
		if err := os.WriteFile(activeRecordPath(dir, name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, withData), []byte(validRecord), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, directoryData), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(activeRecordPath(dir, directoryMarker), 0700); err != nil {
		t.Fatal(err)
	}
	unknown := map[string]string{
		nonempty + ".active": "evidence",
		"leave-me.active":    "evidence",
		"run-20261305T080219622669600Z-0000000000000000.jsonl.active": "",
		orphan + ".active.backup":                                     "evidence",
	}
	for name, contents := range unknown {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
	owner, err := lockRecordPath(activeRecordPath(dir, active), recordLockCreateNew)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { owner.Close() })
	r := retentionOpen(dir, retentionTime(), 255)
	r.Close()
	if r.Health().State != "ready" {
		t.Fatal(r.Health())
	}
	if _, err := os.Stat(activeRecordPath(dir, orphan)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("unlocked orphan marker was not reclaimed", err)
	}
	if _, err := os.Stat(activeRecordPath(dir, active)); err != nil {
		t.Fatal("live marker removed", err)
	}
	probe, err := lockRecordPath(activeRecordPath(dir, active), recordLockExisting)
	if probe != nil {
		probe.Close()
	}
	if !errors.Is(err, ErrStorageBusy) {
		t.Fatal("live marker ownership changed", err)
	}
	for _, name := range []string{withData, directoryData} {
		if _, err := os.Stat(activeRecordPath(dir, name)); err != nil {
			t.Fatal("marker with a data path removed", name, err)
		}
	}
	if raw, err := os.ReadFile(filepath.Join(dir, withData)); err != nil || string(raw) != validRecord {
		t.Fatal("existing data changed", err)
	}
	if info, err := os.Stat(activeRecordPath(dir, directoryMarker)); err != nil || !info.IsDir() {
		t.Fatal("directory marker changed", err)
	}
	for name, contents := range unknown {
		if raw, err := os.ReadFile(filepath.Join(dir, name)); err != nil || string(raw) != contents {
			t.Fatal("unknown marker changed", name, err)
		}
	}
}
