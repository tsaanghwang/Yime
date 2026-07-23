package yime

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const rimeRuntimeLockName = "rime_runtime.lock.json"

type rimeRuntimeLock struct {
	SchemaVersion  int               `json:"schema_version"`
	Source         string            `json:"source"`
	LibrimeVersion string            `json:"librime_version"`
	LibrimeCommit  string            `json:"librime_commit"`
	Platform       string            `json:"platform"`
	Files          map[string]string `json:"files"`
}

func verifyPinnedRimeRuntime(dllPath string) (rimeRuntimeLock, error) {
	runtimeDir := filepath.Dir(dllPath)
	lockPath := filepath.Join(runtimeDir, rimeRuntimeLockName)
	data, err := os.ReadFile(lockPath)
	if err != nil {
		return rimeRuntimeLock{}, fmt.Errorf("read %s: %w", lockPath, err)
	}

	var lock rimeRuntimeLock
	if err := json.Unmarshal(data, &lock); err != nil {
		return rimeRuntimeLock{}, fmt.Errorf("parse %s: %w", lockPath, err)
	}
	if lock.SchemaVersion != 1 {
		return rimeRuntimeLock{}, fmt.Errorf("unsupported Rime runtime lock schema %d", lock.SchemaVersion)
	}
	if strings.TrimSpace(lock.Source) == "" ||
		strings.TrimSpace(lock.LibrimeVersion) == "" ||
		strings.TrimSpace(lock.LibrimeCommit) == "" ||
		strings.TrimSpace(lock.Platform) == "" {
		return rimeRuntimeLock{}, fmt.Errorf("Rime runtime lock has incomplete provenance")
	}

	required := []string{"rime.dll", "rime_deployer.exe", "rime_dict_manager.exe"}
	if len(lock.Files) != len(required) {
		return rimeRuntimeLock{}, fmt.Errorf("Rime runtime lock must declare exactly %d files", len(required))
	}
	for _, name := range required {
		expected := strings.TrimSpace(lock.Files[name])
		if expected == "" {
			return rimeRuntimeLock{}, fmt.Errorf("Rime runtime lock is missing %s", name)
		}
		path := filepath.Join(runtimeDir, name)
		content, err := os.ReadFile(path)
		if err != nil {
			return rimeRuntimeLock{}, fmt.Errorf("read pinned %s: %w", name, err)
		}
		sum := sha256.Sum256(content)
		actual := hex.EncodeToString(sum[:])
		if !strings.EqualFold(actual, expected) {
			return rimeRuntimeLock{}, fmt.Errorf("Rime runtime hash mismatch for %s: expected %s, got %s", name, expected, actual)
		}
		if name == "rime.dll" && !bytes.Contains(content, []byte(lock.LibrimeVersion)) {
			return rimeRuntimeLock{}, fmt.Errorf("rime.dll does not identify locked librime version %s", lock.LibrimeVersion)
		}
	}
	return lock, nil
}
