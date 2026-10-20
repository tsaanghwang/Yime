package keyboardlab

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/tsaanghwang/Yime/go-backend/internal/asciicodemode"
)

// Small explicit test dictionaries exercise the real index loader. They are not
// a substitute for the separately gated complete-corpus acceptance run.
func runtimeFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	layoutDir := filepath.Join(root, "prototypes", "touch-terminal", "data")
	dataDir := filepath.Join(root, "isolated-data")
	for _, p := range []string{layoutDir, dataDir} {
		if err := os.MkdirAll(p, 0700); err != nil {
			t.Fatal(err)
		}
	}
	layout, _ := json.Marshal(map[string]string{"layoutId": codemode.LayoutProjectionSHA256})
	if err := os.WriteFile(filepath.Join(layoutDir, "physical-layout.json"), layout, 0600); err != nil {
		t.Fatal(err)
	}
	manifest := dataManifest{SchemaVersion: 1, LayoutProjectionSHA256: codemode.LayoutProjectionSHA256, InputPolicy: inputPolicy, Scope: "immutable_source_runtime_experiment", DisabledYinyuanIDs: []string{}, DictionarySHA256: map[string]string{}}
	for _, mode := range modes {
		name := "yime_" + mode + ".dict.yaml"
		body := []byte("---\nname: explicit_runtime_test_fixture\nversion: '1'\n...\n测试\ta\t100\n")
		if err := os.WriteFile(filepath.Join(dataDir, name), body, 0600); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(body)
		manifest.DictionarySHA256[name] = hex.EncodeToString(sum[:])
	}
	body, _ := json.Marshal(manifest)
	if err := os.WriteFile(filepath.Join(dataDir, "ascii_keyboard_manifest.json"), body, 0600); err != nil {
		t.Fatal(err)
	}
	return root, dataDir
}

func TestRuntimeOwnsThreeModesAndClosesBeforeIndexCleanup(t *testing.T) {
	root, dataDir := runtimeFixture(t)
	r, err := OpenRuntime(root, dataDir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = r.Close() })
	for _, mode := range modes {
		s := directState(t, r.Sessions.Open(mode, r.LayoutID), 200)
		s = directState(t, r.Sessions.Dispatch(Event{SessionID: s.SessionID, EventID: "type", Type: "input", Code: "a"}), 200)
		if s.State.Candidates[0].Text != "测试" {
			t.Fatal("real indexed candidate missing")
		}
		s = directState(t, r.Sessions.Dispatch(Event{SessionID: s.SessionID, EventID: "select", BaseRevision: s.Revision, Type: "select", CandidateID: s.State.Candidates[0].ID}), 200)
		if s.Commit != "测试" || r.Builds[mode].IndexedRecords != 1 {
			t.Fatal("mode data or selection lost")
		}
	}
	indexRoot := r.indexRoot
	if err := r.Close(); err != nil {
		t.Fatal(err)
	}
	if err := r.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(indexRoot); !os.IsNotExist(err) {
		t.Fatalf("temporary indexes remain: %v", err)
	}
	if r.Sessions.Open("full", r.LayoutID).Status != 410 {
		t.Fatal("session accessed unmapped index")
	}
}

func TestRuntimeRejectsDictionaryTamperingAndMissingDataWithoutFallback(t *testing.T) {
	root, dataDir := runtimeFixture(t)
	p := filepath.Join(dataDir, "yime_full.dict.yaml")
	f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		t.Fatal(err)
	}
	_, err = f.WriteString("篡改\tb\t100\n")
	if closeErr := f.Close(); err != nil || closeErr != nil {
		t.Fatalf("write: %v / %v", err, closeErr)
	}
	if r, err := OpenRuntime(root, dataDir); err == nil {
		_ = r.Close()
		t.Fatal("modified dictionary accepted")
	}
	if r, err := OpenRuntime(root, ""); err == nil {
		_ = r.Close()
		t.Fatal("found data outside explicit default root")
	}
}
