package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRotatingLogWriterLimitsCurrentLogAndBackups(t *testing.T) {
	path := filepath.Join(t.TempDir(), "go_backend.log")
	w, err := newRotatingLogWriter(path, 10, 2)
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{"123456", "abcdef", "UVWXYZ", "latest"} {
		if _, err := w.Write([]byte(value)); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	assertFileContents(t, path, "latest")
	assertFileContents(t, path+".1", "UVWXYZ")
	assertFileContents(t, path+".2", "abcdef")
	if _, err := os.Stat(path + ".3"); !os.IsNotExist(err) {
		t.Fatalf("expected backups beyond the retention limit to be absent, got %v", err)
	}
}

func TestRotatingLogWriterAccountsForExistingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "go_backend.log")
	if err := os.WriteFile(path, []byte("existing"), 0o666); err != nil {
		t.Fatal(err)
	}
	w, err := newRotatingLogWriter(path, 10, 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("new")); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	assertFileContents(t, path, "new")
	assertFileContents(t, path+".1", "existing")
}

func TestRotatingLogWriterRejectsInvalidLimits(t *testing.T) {
	path := filepath.Join(t.TempDir(), "go_backend.log")
	if _, err := newRotatingLogWriter(path, 0, 1); err == nil {
		t.Fatal("expected zero max size to be rejected")
	}
	if _, err := newRotatingLogWriter(path, 10, -1); err == nil {
		t.Fatal("expected negative backup count to be rejected")
	}
}

func TestRotatingLogWriterRecoversAfterRotationFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "go_backend.log")
	w, err := newRotatingLogWriter(path, 10, 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("existing")); err != nil {
		t.Fatal(err)
	}

	blockedBackup := path + ".1"
	if err := os.Mkdir(blockedBackup, 0o777); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(blockedBackup, "keep"), []byte("occupied"), 0o666); err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("trigger")); err == nil {
		t.Fatal("expected rotation to fail while the backup path cannot be removed")
	}
	if _, err := w.Write([]byte("ok")); err != nil {
		t.Fatalf("writer did not recover after failed rotation: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	assertFileContents(t, path, "existingok")
}

func assertFileContents(t *testing.T, path, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := string(data); got != want {
		t.Fatalf("unexpected contents of %s: got %q, want %q", filepath.Base(path), got, want)
	}
}
