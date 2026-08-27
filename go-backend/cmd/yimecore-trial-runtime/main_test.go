package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestResolveOptionsRequiresCompleteIndependentTrialPackage(t *testing.T) {
	root := t.TempDir()
	broker := filepath.Join(root, "runtime", "YimeBroker.exe")
	state := filepath.Join(root, "state")
	for _, path := range []string{
		broker,
		filepath.Join(root, "package", "indexes", "full.yidx"),
		filepath.Join(root, "package", "indexes", "variable.yidx"),
		filepath.Join(root, "package", "indexes", "shorthand.yidx"),
		filepath.Join(root, "package", "data", "yime_pinyin_codes.tsv"),
	} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("test"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	resolved, err := resolveOptions(options{
		installRoot: filepath.Join(root, "package"), brokerPath: broker,
		stateRoot: state, pipeName: defaultPipeName, noToolbar: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if resolved.brokerPath != broker || resolved.stateRoot != state {
		t.Fatalf("custom durable runtime paths changed: %+v", resolved)
	}
	if err := os.Remove(filepath.Join(root, "package", "indexes", "shorthand.yidx")); err != nil {
		t.Fatal(err)
	}
	if _, err := resolveOptions(resolved); err == nil {
		t.Fatal("incomplete three-mode package was accepted")
	}
}

func TestDesktopToolsUsesDedicatedNativeWindowsExecutable(t *testing.T) {
	root := filepath.Join(`C:\trial package`)
	if got := desktopToolsPath(root); got != filepath.Join(root, "bin", "YimeCoreDesktopTools.exe") {
		t.Fatalf("desktop tools path=%q", got)
	}
	if got := trainerPath(root); got != filepath.Join(root, "bin", "YimeCoreTrainer.exe") {
		t.Fatalf("trainer path=%q", got)
	}
	if got := toolCenterPath(root); got != filepath.Join(root, "bin", "YimeCoreToolCenter.exe") {
		t.Fatalf("Tool Center path=%q", got)
	}
	config := options{installRoot: root, stateRoot: `C:\trial state`}
	arguments := desktopToolsArguments(config)
	for _, expected := range []string{
		trainerPath(root), toolCenterPath(root), filepath.Join(root, "data"), config.stateRoot, "-Experimental",
	} {
		if !slices.Contains(arguments, expected) {
			t.Fatalf("Desktop Tools arguments lack %q: %v", expected, arguments)
		}
	}
}

func TestBrokerArgumentsPinMultiIndexDurabilityAndTransactionalControl(t *testing.T) {
	config := options{
		installRoot: `C:\trial package`, brokerPath: `C:\runtime\YimeBroker.exe`,
		stateRoot: `C:\user state`, pipeName: defaultPipeName,
	}
	arguments := brokerArguments(config)
	for _, expected := range []string{
		"-index-root", filepath.Join(config.installRoot, "indexes"),
		"-default-mode", "variable",
		"-named-pipe", defaultPipeName,
		"-user-model-snapshot", filepath.Join(config.stateRoot, "user-model", "user-model.json"),
		"-user-model-journal", filepath.Join(config.stateRoot, "user-model", "user-model.journal"),
		"-user-model-source-id", modelSourceID,
		"-index-control-manifest", filepath.Join(config.stateRoot, "index-control", "request.json"),
		"-index-control-status", filepath.Join(config.stateRoot, "index-control", "status.json"),
	} {
		if !slices.Contains(arguments, expected) {
			t.Fatalf("Broker arguments lack %q: %v", expected, arguments)
		}
	}
}

func TestRuntimeStatusRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime-status.json")
	want := runtimeStatus{SchemaVersion: statusSchema, State: "running", RuntimePID: 11, BrokerPID: 22, Restarts: 3}
	writeRuntimeStatus(path, want)
	got, err := readRuntimeStatus(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("status mismatch: got %+v want %+v", got, want)
	}
}
