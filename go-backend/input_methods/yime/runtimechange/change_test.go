package runtimechange

import (
	"os"
	"path/filepath"
	"sync"
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
	if read.Revision != written.Revision || read.LexiconRevision != written.LexiconRevision || read.RedeployRevision != written.RedeployRevision {
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
	if read.Revision != second.Revision || read.SettingsRevision != first.SettingsRevision || read.LexiconRevision != second.LexiconRevision || read.RedeployRevision != second.RedeployRevision {
		t.Fatalf("expected latest marker %#v, got %#v", second, read)
	}
}

func TestConcurrentNotificationsPreserveEveryScope(t *testing.T) {
	userDir := t.TempDir()
	var wait sync.WaitGroup
	for i := 0; i < 20; i++ {
		wait.Add(2)
		go func() {
			defer wait.Done()
			if _, err := Notify(userDir, ScopeSettings, false); err != nil {
				t.Errorf("settings notification failed: %v", err)
			}
		}()
		go func() {
			defer wait.Done()
			if _, err := Notify(userDir, ScopeLexicon, true); err != nil {
				t.Errorf("lexicon notification failed: %v", err)
			}
		}()
	}
	wait.Wait()
	event, err := Read(userDir)
	if err != nil {
		t.Fatal(err)
	}
	if event.SettingsRevision == 0 || event.LexiconRevision == 0 || event.RedeployRevision == 0 {
		t.Fatalf("concurrent notifications lost a scope: %#v", event)
	}
}

func TestNotifyRecoversCorruptMarker(t *testing.T) {
	userDir := t.TempDir()
	if err := os.WriteFile(Path(userDir), []byte("{"), 0o644); err != nil {
		t.Fatal(err)
	}
	written, err := Notify(userDir, ScopeSettings, false)
	if err != nil {
		t.Fatal(err)
	}
	read, err := Read(userDir)
	if err != nil {
		t.Fatal(err)
	}
	if read.SettingsRevision != written.SettingsRevision || read.SettingsRevision == 0 {
		t.Fatalf("corrupt marker recovery lost the notification: wrote %#v read %#v", written, read)
	}
	if _, err := os.Stat(filepath.Join(userDir, FileName+".corrupt")); err != nil {
		t.Fatalf("expected corrupt marker backup: %v", err)
	}
}

func TestReadMigratesLegacySingleScopeMarker(t *testing.T) {
	userDir := t.TempDir()
	legacy := []byte(`{"revision":42,"scope":"lexicon","requires_redeploy":true}`)
	if err := os.WriteFile(Path(userDir), legacy, 0o644); err != nil {
		t.Fatal(err)
	}
	event, err := Read(userDir)
	if err != nil {
		t.Fatal(err)
	}
	if event.LexiconRevision != 42 || event.RedeployRevision != 42 {
		t.Fatalf("legacy marker was not migrated: %#v", event)
	}
}
