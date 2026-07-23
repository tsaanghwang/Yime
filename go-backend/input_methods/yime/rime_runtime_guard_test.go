package yime

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVerifyPinnedRimeRuntimeAcceptsMatchingFiles(t *testing.T) {
	dir := t.TempDir()
	writeTestRimeRuntime(t, dir)
	lock, err := verifyPinnedRimeRuntime(filepath.Join(dir, "rime.dll"))
	if err != nil {
		t.Fatal(err)
	}
	if lock.LibrimeVersion != "1.17.0" || lock.LibrimeCommit != "33e7814" {
		t.Fatalf("unexpected lock: %#v", lock)
	}
}

func TestVerifyPinnedRimeRuntimeRejectsHashMismatch(t *testing.T) {
	dir := t.TempDir()
	writeTestRimeRuntime(t, dir)
	if err := os.WriteFile(filepath.Join(dir, "rime_deployer.exe"), []byte("changed"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := verifyPinnedRimeRuntime(filepath.Join(dir, "rime.dll")); err == nil || !strings.Contains(err.Error(), "hash mismatch") {
		t.Fatalf("expected hash mismatch, got %v", err)
	}
}

func writeTestRimeRuntime(t *testing.T, dir string) {
	t.Helper()
	files := map[string][]byte{
		"rime.dll":              []byte("test librime 1.17.0 runtime"),
		"rime_deployer.exe":     []byte("deployer"),
		"rime_dict_manager.exe": []byte("dict manager"),
	}
	hashes := make(map[string]string, len(files))
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), content, 0o644); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(content)
		hashes[name] = hex.EncodeToString(sum[:])
	}
	lock := rimeRuntimeLock{
		SchemaVersion:  1,
		Source:         "https://example.invalid/librime/1.17.0",
		LibrimeVersion: "1.17.0",
		LibrimeCommit:  "33e7814",
		Platform:       "Windows-msvc-x64",
		Files:          hashes,
	}
	data, err := json.Marshal(lock)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, rimeRuntimeLockName), data, 0o644); err != nil {
		t.Fatal(err)
	}
}
