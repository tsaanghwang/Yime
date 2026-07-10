package runtimechange

import (
	"testing"
)

func TestNotifyRoundTrip(t *testing.T) {
	userDir := t.TempDir()
	written, err := Notify(userDir, ScopeLexicon, true)
	if err != nil {
		t.Fatal(err)
	}
	read, err := Read(userDir)
	if err != nil {
		t.Fatal(err)
	}
	if read != written {
		t.Fatalf("round trip mismatch: wrote %#v read %#v", written, read)
	}
	if read.Revision <= 0 {
		t.Fatalf("expected positive revision, got %d", read.Revision)
	}
}

func TestNotifyReplacesMarkerWithIncreasingRevision(t *testing.T) {
	userDir := t.TempDir()
	first, err := Notify(userDir, ScopeSettings, false)
	if err != nil {
		t.Fatal(err)
	}
	second, err := Notify(userDir, ScopeLexicon, true)
	if err != nil {
		t.Fatal(err)
	}
	if second.Revision <= first.Revision {
		t.Fatalf("expected increasing revisions, first=%d second=%d", first.Revision, second.Revision)
	}
	read, err := Read(userDir)
	if err != nil {
		t.Fatal(err)
	}
	if read != second {
		t.Fatalf("expected latest marker %#v, got %#v", second, read)
	}
}
